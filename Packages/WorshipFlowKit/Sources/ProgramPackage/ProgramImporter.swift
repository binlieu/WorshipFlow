// LIB-005 item 3: importing a program. Media is copied first into `Media/Imported/<program id>/` (and removed again if anything
// fails), then every row is written in one database transaction.
import Foundation
import GRDB
import Domain
@_spi(ProgramPackage) import Persistence

public enum ProgramImporter {
    /// What importing would do, with the default answer to conflicts. Reads only.
    public static func summarize(_ contents: ProgramPackageContents, into store: LibraryStore) async throws -> ProgramImportSummary {
        guard let folder = store.libraryFolder else { throw ProgramPackageError.noLibraryFolder }
        return try await ProgramImportPlanner.evaluate(contents, store: store, choice: .default, folder: folder).summary
    }

    /// Imports the program in one database transaction. A failure or a cancel leaves the library as it was and removes the
    /// media files this call copied.
    public static func apply(_ contents: ProgramPackageContents, into store: LibraryStore,
                             choice: ProgramConflictChoice = .default, live: ProgramLiveContext = .none,
                             hooks: ProgramImportHooks = .none,
                             isCancelled: @Sendable () -> Bool = { false },
                             progress: @Sendable (ProgramProgress) -> Void = { _ in }) async throws -> ProgramImportResult {
        guard let folder = store.libraryFolder else { throw ProgramPackageError.noLibraryFolder }
        let plan = try await ProgramImportPlanner.evaluate(contents, store: store, choice: choice, folder: folder, live: live)
        // FIX-G: room for the media (with a margin) before anything is copied.
        if plan.summary.mediaBytesToCopy > 0 {
            let free = hooks.freeSpace?(folder) ?? defaultFreeSpace(folder)
            let needed = plan.summary.mediaBytesToCopy + spaceMargin(forBytes: plan.summary.mediaBytesToCopy)
            if let free, free < needed { throw ProgramPackageError.notEnoughSpace(needed: needed, available: free) }
        }
        // FIX-G: before anything existing is replaced, the library is backed up; without a backup nothing is replaced.
        var backupURL: URL?
        if plan.replacesExisting {
            do { backupURL = try await store.backUp(beforeImportAt: (hooks.now ?? { Date() })()) }
            catch { throw ProgramPackageError.backupFailed(error.localizedDescription) }
        }
        var log = CopyLog()
        do {
            try copyMedia(plan, from: contents, into: folder, log: &log, hooks: hooks, isCancelled: isCancelled, progress: progress)
            if isCancelled() { throw ProgramPackageError.cancelled }
            try hooks.afterMediaCopied?()
            let inside = hooks.insideTransaction
            var result = try await store.programWrite { db, tools in
                let result = try ProgramImportWriter.write(plan, db: db, tools: tools)
                try inside?()
                return result
            }
            result.mediaFilesCopied = log.copied
            result.mediaFilesReused = log.reused
            result.backupURL = backupURL
            result.keptBecauseLive = plan.keptBecauseLive
            return result
        } catch {
            log.rollback()
            throw error
        }
    }

    // MARK: Space

    /// FIX-G: the room left over when checking free space: a tenth of what is copied, at least 64 MB.
    public static func spaceMargin(forBytes bytes: Int64) -> Int64 { max(bytes / 10, 64 * 1024 * 1024) }

    static func defaultFreeSpace(_ folder: URL) -> Int64? {
        let values = try? folder.resourceValues(forKeys: [.volumeAvailableCapacityForImportantUsageKey])
        return values?.volumeAvailableCapacityForImportantUsage
    }

    // MARK: Media

    struct CopyLog {
        var files: [URL] = []
        var directories: [URL] = []
        var copied = 0
        var reused = 0

        /// Removes what this import created: its files, then the folders it made (deepest first).
        func rollback() {
            let fm = FileManager.default
            for file in files { try? fm.removeItem(at: file) }
            for directory in directories.reversed() { try? fm.removeItem(at: directory) }
        }
    }

    private static func copyMedia(_ plan: ImportPlan, from contents: ProgramPackageContents, into folder: URL, log: inout CopyLog,
                                  hooks: ProgramImportHooks, isCancelled: @Sendable () -> Bool, progress: @Sendable (ProgramProgress) -> Void) throws {
        guard !plan.copies.isEmpty else { return }
        let fm = FileManager.default
        let total = plan.copies.reduce(Int64(0)) { $0.saturatingAdding(max(0, $1.entry.size ?? 0)) }
        var done: Int64 = 0
        var filesDone = 0
        progress(ProgramProgress(bytesDone: 0, bytesTotal: total, filesDone: 0, filesTotal: plan.copies.count))

        // Folders first: remember the ones that did not exist, so a failure can take them away again.
        var directory = folder
        for part in plan.programFolder.split(separator: "/") {
            directory.appendPathComponent(String(part), isDirectory: true)
            if !fm.fileExists(atPath: directory.path) {
                try fm.createDirectory(at: directory, withIntermediateDirectories: false)
                log.directories.append(directory)
            }
        }
        for (entry, local) in plan.copies {
            if isCancelled() { throw ProgramPackageError.cancelled }
            guard let sha = entry.sha256 else { continue }
            let target = folder.appendingPathComponent(local)
            let size = entry.size ?? 0
            if let info = ProgramFiles.lstatInfo(target) {
                // Something is there. The same bytes: use it. Anything else: refuse, never overwrite.
                guard info.isRegular, info.size == size, (try? ProgramFiles.sha256(of: target, isCancelled: isCancelled)) == sha else {
                    throw ProgramPackageError.mediaNameTaken(entry.name)
                }
                log.reused += 1
                done = done.saturatingAdding(max(0, size))
            } else {
                let partial = target.appendingPathExtension("partial")
                try? fm.removeItem(at: partial)
                log.files.append(partial)
                let source = contents.url.appendingPathComponent(entry.file)
                let digest = try ProgramFiles.chunkedCopy(from: source, to: partial, chunkSize: hooks.chunkSize ?? ProgramFiles.chunkSize,
                                                          limit: size, limitName: ProgramPathRules.safeName(entry.name), isCancelled: isCancelled) { piece in
                    hooks.onChunk?(piece)
                    done += piece
                    progress(ProgramProgress(bytesDone: done, bytesTotal: total, filesDone: filesDone, filesTotal: plan.copies.count))
                }
                guard digest == sha else { throw ProgramPackageError.mediaDamaged(ProgramPathRules.safeName(entry.name)) }
                try fm.moveItem(at: partial, to: target)
                log.files.removeAll { $0 == partial }
                log.files.append(target)
                log.copied += 1
            }
            filesDone += 1
            progress(ProgramProgress(bytesDone: done, bytesTotal: total, filesDone: filesDone, filesTotal: plan.copies.count))
        }
    }
}

enum ProgramImportWriter {
    static func write(_ plan: ImportPlan, db: Database, tools: ProgramWriteTools) throws -> ProgramImportResult {
        var result = ProgramImportResult()
        result.warnings = plan.warnings
        let now = Date()

        // The library the new presentations go into.
        let libraryID: String
        if let existing = plan.libraryID { libraryID = existing.uuidString }
        else {
            libraryID = UUID().uuidString
            try db.execute(sql: "INSERT INTO library (id, name, sortOrder, createdAt, updatedAt) VALUES (?, 'Library', 0, ?, ?)",
                           arguments: [libraryID, now, now])
        }

        for t in plan.themes where t.action != .skip {
            var theme = t.theme
            theme.id = t.finalID
            if t.action == .insertCopy { theme.name += ProgramImportPlanner.importedSuffix }
            result.themesAdded += 1
            if case .image(let path) = theme.background { theme.background = .image(path: plan.localPath[path] ?? path) }
            let name = theme.name.trimmingCharacters(in: .whitespacesAndNewlines)
            let definition = try tools.themeDefinition(theme)
            if t.action == .replace {
                try db.execute(sql: "UPDATE theme SET name = ?, nameFolded = ?, definition = ?, updatedAt = ? WHERE id = ?",
                               arguments: [name, SearchFolding.fold(name), definition, now, theme.id.uuidString])
            } else {
                try db.execute(sql: "INSERT INTO theme (id, name, nameFolded, definition, createdAt, updatedAt) VALUES (?, ?, ?, ?, ?, ?)",
                               arguments: [theme.id.uuidString, name, SearchFolding.fold(name), definition, now, now])
            }
        }

        for l in plan.looks where l.action != .skip {
            // The screens were mapped to this Mac's profiles when the plan was made.
            let screens = l.mapped.mapValues { ScreenLook(themeID: $0.themeID.map { plan.themeMap[$0] ?? $0 }, visibleLayers: $0.visibleLayers) }
            result.looksAdded += 1
            let name = l.look.name + (l.action == .insertCopy ? ProgramImportPlanner.importedSuffix : "")
            let json = try tools.lookScreens(screens)
            if l.action == .replace {
                try db.execute(sql: "UPDATE look SET name = ?, screens = ?, updatedAt = ? WHERE id = ?",
                               arguments: [name, json, now, l.finalID.uuidString])
            } else {
                try db.execute(sql: "INSERT INTO look (id, name, screens, createdAt, updatedAt) VALUES (?, ?, ?, ?, ?)",
                               arguments: [l.finalID.uuidString, name, json, now, now])
            }
        }

        // A package asset whose file is already in the bin under another id: slides that name the package's id are pointed at
        // the existing entry.
        var assetIDMap: [UUID: UUID] = [:]
        for asset in plan.assetsToInsert {
            let path = plan.localPath[asset.file] ?? asset.file
            if let existing = try String.fetchOne(db, sql: "SELECT id FROM mediaAsset WHERE path = ?", arguments: [path]) {
                if let id = UUID(uuidString: existing) { assetIDMap[asset.id] = id }
                result.warnings.append("The media item \(asset.name) uses a file that is already in the media bin under another entry; it was not added again.")
                continue
            }
            let name = asset.name.trimmingCharacters(in: .whitespacesAndNewlines)
            try db.execute(sql: """
                INSERT INTO mediaAsset (id, name, kind, path, bookmark, duration, pixelWidth, pixelHeight, addedAt, markIn, markOut)
                VALUES (?, ?, ?, ?, NULL, ?, ?, ?, ?, ?, ?)
                """, arguments: [asset.id.uuidString, name.isEmpty ? "Media" : name, asset.kind.rawValue, path, asset.duration,
                                 asset.pixelWidth, asset.pixelHeight, now, asset.markIn, asset.markOut])
            // SYS-015: the clip's markers come with it (their actions may name other clips; those are renamed below, once every clip is in).
            for (order, marker) in asset.markers.enumerated() {
                try db.execute(sql: """
                    INSERT OR IGNORE INTO mediaMarker (id, assetID, time, name, actions, sortOrder, createdAt, updatedAt) VALUES (?, ?, ?, ?, ?, ?, ?, ?)
                    """, arguments: [marker.id.uuidString, asset.id.uuidString, marker.time, marker.name, marker.actions.text, order, now, now])
            }
            result.mediaAssetsAdded += 1
        }

        // SYS-015: a marker's actions that play a clip the library already had under another id name that one.
        if !assetIDMap.isEmpty {
            for asset in plan.assetsToInsert where assetIDMap[asset.id] == nil {
                for marker in asset.markers {
                    let mapped = marker.actions.replacingUUIDs(assetIDMap)
                    if mapped != marker.actions {
                        try db.execute(sql: "UPDATE mediaMarker SET actions = ? WHERE id = ? AND assetID = ?", arguments: [mapped.text, marker.id.uuidString, asset.id.uuidString])
                    }
                }
            }
        }

        for p in plan.presentations {
            guard let entry = p.written else { continue }
            let id = entry.id.uuidString
            let themeID: String? = try entry.themeID.flatMap { theme -> String? in
                if Theme.builtIn.contains(where: { $0.id == theme }) { return theme.uuidString }
                return try Bool.fetchOne(db, sql: "SELECT EXISTS(SELECT 1 FROM theme WHERE id = ?)", arguments: [theme.uuidString]) == true
                    ? theme.uuidString : nil
            }
            switch p.action {
            case .replace:
                try db.execute(sql: "UPDATE presentation SET title = ?, kind = ?, themeID = ?, updatedAt = ? WHERE id = ?",
                               arguments: [entry.title, entry.kind.rawValue, themeID, now, id])
                try db.execute(sql: "DELETE FROM slide WHERE presentationID = ?", arguments: [id])
                try db.execute(sql: "DELETE FROM arrangement WHERE presentationID = ?", arguments: [id])
                try db.execute(sql: "DELETE FROM slideGroup WHERE presentationID = ?", arguments: [id])
                result.presentationsReplaced += 1
                result.replacedPresentationIDs.append(entry.id)
            case .insert, .insertCopy:
                try db.execute(sql: """
                    INSERT INTO presentation (id, libraryID, title, kind, titleFolded, bodyFolded, createdAt, updatedAt, themeID)
                    VALUES (?, ?, ?, ?, '', '', ?, ?, ?)
                    """, arguments: [id, libraryID, entry.title, entry.kind.rawValue, now, now, themeID])
                if p.action == .insert { result.presentationsAdded += 1 } else { result.presentationsKeptAsCopies += 1 }
            case .skip: continue
            }
            for (order, group) in entry.groups.enumerated() {
                try db.execute(sql: "INSERT INTO slideGroup (id, presentationID, name, sortOrder) VALUES (?, ?, ?, ?)",
                               arguments: [group.id.uuidString, id, group.name, order])
            }
            for (order, slide) in entry.slides.enumerated() {
                let own = slide.background.map { MediaSelection(assetID: assetIDMap[$0.assetID] ?? $0.assetID, kind: $0.kind, duration: $0.duration) }
                let objects = tools.slideObjects(slide.objects.map { object -> SlideObject in
                    // SYS-015: a video object names the bin entry the library already had for the same file, when there is one.
                    if case .video(var video) = object.content {
                        video.mediaID = assetIDMap[video.mediaID] ?? video.mediaID
                        var copy = object
                        copy.content = .video(video)
                        return copy
                    }
                    guard case .image(var image) = object.content else { return object }
                    image.path = plan.localPath[image.path] ?? image.path
                    var copy = object
                    copy.content = .image(image)
                    return copy
                })
                try db.execute(sql: """
                    INSERT INTO slide (id, presentationID, sortOrder, primaryText, secondaryText, notes, createdAt, updatedAt, groupID, objects, background, textFrames)
                    VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
                    """, arguments: [slide.id.uuidString, id, order, slide.primary, slide.secondary, slide.notes, now, now,
                                     slide.groupID?.uuidString, objects, tools.slideBackground(own), tools.slideTextFrames(slide.textFrames)])
                if let actions = slide.actions {
                    let mapped = assetIDMap.isEmpty ? actions : actions.replacingUUIDs(assetIDMap)
                    try db.execute(sql: "INSERT INTO cueSlideActions (slideID, definition, createdAt, updatedAt) VALUES (?, ?, ?, ?)",
                                   arguments: [slide.id.uuidString, mapped.text, now, now])
                }
            }
            for arrangement in entry.arrangements {
                try db.execute(sql: "INSERT INTO arrangement (id, presentationID, name, createdAt, updatedAt) VALUES (?, ?, ?, ?, ?)",
                               arguments: [arrangement.id.uuidString, id, arrangement.name, now, now])
                for (position, group) in arrangement.groupIDs.enumerated() {
                    try db.execute(sql: "INSERT INTO arrangementItem (arrangementID, position, groupID) VALUES (?, ?, ?)",
                                   arguments: [arrangement.id.uuidString, position, group.uuidString])
                }
            }
            try tools.reindex(db, presentationID: entry.id)
        }

        // The playlist.
        let playlistID: UUID
        switch plan.playlistAction {
        case .skip(let existing):
            playlistID = existing
        case .insert(let id, let name):
            playlistID = id
            try db.execute(sql: "INSERT INTO playlist (id, name, createdAt, updatedAt, serviceAt) VALUES (?, ?, ?, ?, ?)",
                           arguments: [id.uuidString, name, now, now, plan.playlistServiceAt])
        case .replace(let existing, let name):
            playlistID = existing
            try db.execute(sql: "UPDATE playlist SET name = ?, updatedAt = ?, serviceAt = ? WHERE id = ?",
                           arguments: [name, now, plan.playlistServiceAt, existing.uuidString])
            try db.execute(sql: "DELETE FROM playlistItem WHERE playlistID = ?", arguments: [existing.uuidString])
        }
        if case .skip = plan.playlistAction {} else {
            for (order, item) in plan.items.enumerated() {
                // FIX-T item 5 (M7): a media item or a loop names bin entries by id; an entry skipped above (the file was already in the bin under
                // another id) is replaced by the existing one, in this same transaction.
                let stored = item.kind.remappingAssets(assetIDMap).stored
                if item.kind.hasSlides, item.presentationID == nil { continue }
                try db.execute(sql: """
                    INSERT INTO playlistItem (id, playlistID, presentationID, sortOrder, createdAt, arrangementID, kind, payload)
                    VALUES (?, ?, ?, ?, ?, ?, ?, ?)
                    """, arguments: [item.id.uuidString, playlistID.uuidString, item.presentationID?.uuidString, order, now,
                                     item.arrangementID?.uuidString, stored.kind, stored.payload])
            }
        }
        result.playlistID = playlistID
        return result
    }
}

extension PlaylistItemKind {
    /// The same item with each bin entry id that `map` names replaced by its value. Everything else is kept as it is.
    func remappingAssets(_ map: [UUID: UUID]) -> PlaylistItemKind {
        guard !map.isEmpty else { return self }
        func spec(_ s: MediaItemSpec) -> MediaItemSpec { MediaItemSpec(assetID: map[s.assetID] ?? s.assetID, name: s.name, kind: s.kind) }
        switch self {
        case .media(let s): return .media(spec(s))
        case .announcements(let a): return .announcements(AnnouncementsSpec(label: a.label, items: a.items.map(spec), secondsPerPicture: a.secondsPerPicture))
        default: return self
        }
    }
}
