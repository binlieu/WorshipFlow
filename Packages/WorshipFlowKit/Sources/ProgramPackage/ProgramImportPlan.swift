// LIB-005 item 3: deciding what an import does. `evaluate` compares the package with the library (reads only) and returns a plan:
// which presentations, themes, Looks and media items are new, already there or in conflict, what each choice does with them,
// where each media file will live, and what the playlist will be.
import Foundation
import GRDB
import Domain
@_spi(ProgramPackage) import Persistence

struct ImportPlan: Sendable {
    enum Action: Sendable { case skip, insert, replace, insertCopy }
    enum State: Sendable { case new, identical, conflict }

    struct PresentationPlan: Sendable {
        var state: State
        var action: Action
        var source: ProgramDocument.PresentationEntry
        /// What gets written (final ids, final title), for every action but `skip`.
        var written: ProgramDocument.PresentationEntry?
        /// The presentation id the playlist items must point at.
        var finalID: UUID
        /// Package arrangement id to the id it has in the library.
        var arrangementMap: [UUID: UUID]
    }

    struct ThemePlan: Sendable {
        var theme: Theme
        var state: State
        var action: Action
        var finalID: UUID
    }

    struct LookPlan: Sendable {
        var look: ProgramDocument.LookEntry
        var state: State
        var action: Action
        var finalID: UUID
        /// The Look's screens as this Mac's profile ids (FIX-G).
        var mapped: [UUID: ScreenLook] = [:]
    }

    struct ItemWrite: Sendable {
        var id: UUID
        var kind: PlaylistItemKind
        var presentationID: UUID?
        var arrangementID: UUID?
    }

    enum PlaylistAction: Sendable {
        case skip(existing: UUID)
        case insert(id: UUID, name: String)
        case replace(existing: UUID, name: String)
    }

    var libraryID: UUID?
    var presentations: [PresentationPlan] = []
    var themes: [ThemePlan] = []
    var looks: [LookPlan] = []
    var themeMap: [UUID: UUID] = [:]
    var lookMap: [UUID: UUID] = [:]
    var assetsToInsert: [ProgramDocument.AssetEntry] = []
    var playlistAction: PlaylistAction = .skip(existing: UUID())
    var playlistState: ProgramImportSummary.PlaylistState = .new
    var items: [ItemWrite] = []
    var warnings: [String] = []
    /// Titles of presentations kept beside the library's own because they are live (FIX-G).
    var keptBecauseLive: [String] = []
    /// True when this import replaces something that already exists (a presentation, theme, Look or the playlist).
    var replacesExisting: Bool {
        presentations.contains { $0.action == .replace } || themes.contains { $0.action == .replace }
            || looks.contains { $0.action == .replace } || { if case .replace = playlistAction { return true } else { return false } }()
    }
    /// Package path to the path the library stores: relative to the library's folder.
    var localPath: [String: String] = [:]
    /// Package files that have to be in the managed folder: entry and the stored (relative) path.
    var copies: [(entry: ProgramDocument.MediaEntry, local: String)] = []
    var programFolder = ""
    var summary: ProgramImportSummary
}

enum ProgramImportPlanner {
    static let importedSuffix = " (imported)"

    static func evaluate(_ contents: ProgramPackageContents, store: LibraryStore, choice: ProgramConflictChoice,
                         folder: URL, live: ProgramLiveContext = .none) async throws -> ImportPlan {
        let doc = contents.document
        var plan = ImportPlan(summary: ProgramImportSummary(playlistName: doc.playlist.name, playlist: .new))
        let programFolder = "\(MediaPathPrefix.managed)\(doc.programID.uuidString)"
        plan.programFolder = programFolder

        // What the library already holds.
        struct Existing: Sendable {
            var libraryID: UUID?
            var presentationIDs: Set<UUID>
            var slideOwner: [String: String]
            var groupOwner: [String: String]
            var arrangementOwner: [String: String]
            var itemOwner: [String: String]
            var playlistIDs: Set<UUID>
            var scriptureCodes: Set<String>
        }
        let existing = try await store.programRead { db -> Existing in
            func map(_ sql: String) throws -> [String: String] {
                Dictionary(try Row.fetchAll(db, sql: sql).map { ($0[0] as String, $0[1] as String) }, uniquingKeysWith: { first, _ in first })
            }
            let codes: [String] = try db.tableExists("scriptureTranslation")
                ? try String.fetchAll(db, sql: "SELECT code FROM scriptureTranslation") : []
            return Existing(
                libraryID: try String.fetchOne(db, sql: "SELECT id FROM library ORDER BY sortOrder, rowid LIMIT 1").flatMap(UUID.init(uuidString:)),
                presentationIDs: Set(try String.fetchAll(db, sql: "SELECT id FROM presentation").compactMap(UUID.init(uuidString:))),
                slideOwner: try map("SELECT id, presentationID FROM slide"),
                groupOwner: try map("SELECT id, presentationID FROM slideGroup"),
                arrangementOwner: try map("SELECT id, presentationID FROM arrangement"),
                itemOwner: try map("SELECT id, playlistID FROM playlistItem"),
                playlistIDs: Set(try String.fetchAll(db, sql: "SELECT id FROM playlist").compactMap(UUID.init(uuidString:))),
                scriptureCodes: Set(codes.map { $0.lowercased() }))
        }
        plan.libraryID = existing.libraryID

        // Media: where each package path will live.
        let byFile = Dictionary(doc.media.map { ($0.file, $0) }, uniquingKeysWith: { first, _ in first })
        for entry in doc.media {
            if entry.status == .included, let sha = entry.sha256 {
                let ext = ProgramPathRules.safeExtension(of: entry.name)
                plan.localPath[entry.file] = "\(programFolder)/\(sha)" + (ext.isEmpty ? "" : ".\(ext)")
            } else {
                plan.localPath[entry.file] = "\(programFolder)/missing/\(ProgramPathRules.safeName(entry.name))"
            }
        }

        // Themes. Compared as the package would have written them, so a picture counts by its bytes, not where it is kept.
        var compare = MediaCollector()
        let libraryThemes = Dictionary(try await store.themes().map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        for theme in doc.themes {
            var themePlan = ImportPlan.ThemePlan(theme: theme, state: .new, action: .insert, finalID: theme.id)
            if let mine = libraryThemes[theme.id] {
                let same = try await ProgramSnapshot.theme(mine, collector: &compare) == theme
                themePlan.state = same ? .identical : .conflict
                switch (same, choice) {
                case (true, _), (false, .keepMine): themePlan.action = .skip
                case (false, .useImported):
                    if live.isShowLive, live.themeIDsInUse.contains(theme.id) {
                        themePlan.action = .insertCopy; themePlan.finalID = UUID()
                        plan.warnings.append("The theme \"\(theme.name)\" is in use on the live show, so it was not replaced: the imported version was kept beside it as \"\(theme.name)\(importedSuffix)\".")
                    } else { themePlan.action = .replace }
                case (false, .keepBoth): themePlan.action = .insertCopy; themePlan.finalID = UUID()
                }
                if themePlan.state == .conflict { plan.summary.conflictingThemes += 1 }
            } else { plan.summary.newThemes += 1 }
            if themePlan.finalID != theme.id { plan.themeMap[theme.id] = themePlan.finalID }
            plan.themes.append(themePlan)
        }

        // Looks.
        // FIX-G: a Look names screens by profile id, and profile ids belong to the Mac that wrote the package. They are compared and
        // written by role (audience, stage, broadcast).
        let profiles = try await store.screenProfiles()
        let libraryLooks = Dictionary(try await store.looks().map { ($0.id, ProgramSnapshot.lookEntry($0, profiles: profiles)) }, uniquingKeysWith: { first, _ in first })
        for look in doc.looks {
            var lookPlan = ImportPlan.LookPlan(look: look, state: .new, action: .insert, finalID: look.id)
            if let mine = libraryLooks[look.id] {
                let same = mine.name == look.name && roleKeyed(mine) == roleKeyed(look)
                lookPlan.state = same ? .identical : .conflict
                switch (same, choice) {
                case (true, _), (false, .keepMine): lookPlan.action = .skip
                case (false, .useImported):
                    if live.isShowLive, live.lookIDsInUse.contains(look.id) {
                        lookPlan.action = .insertCopy; lookPlan.finalID = UUID()
                        plan.warnings.append("The Look \"\(look.name)\" is in use on the live show, so it was not replaced: the imported version was kept beside it as \"\(look.name)\(importedSuffix)\".")
                    } else { lookPlan.action = .replace }
                case (false, .keepBoth): lookPlan.action = .insertCopy; lookPlan.finalID = UUID()
                }
                if lookPlan.state == .conflict { plan.summary.conflictingLooks += 1 }
            } else { plan.summary.newLooks += 1 }
            if lookPlan.finalID != look.id { plan.lookMap[look.id] = lookPlan.finalID }
            let mapped = mapScreens(look, profiles: profiles)
            lookPlan.mapped = mapped.screens
            if lookPlan.action != .skip {
                for role in mapped.unmapped {
                    plan.warnings.append("The Look \"\(look.name)\" has settings for \(role), but this Mac has no such screen set up, so those settings were left out.")
                }
            }
            plan.looks.append(lookPlan)
        }

        // Media bin entries that slide actions play.
        let libraryAssets = Set(try await store.mediaAssets(kind: nil).map(\.id))
        var wanted = doc.mediaAssets
        // FIX-G: a slide's own background whose bin item the package did not list gets one made from the slide's own entry.
        for background in doc.presentations.flatMap(\.slides).compactMap(\.background) where !wanted.contains(where: { $0.id == background.assetID }) {
            let name = byFile[background.file]?.name ?? ((background.file as NSString).lastPathComponent)
            wanted.append(.init(id: background.assetID, name: (name as NSString).deletingPathExtension, kind: background.kind,
                                duration: background.duration, pixelWidth: nil, pixelHeight: nil, file: background.file))
        }
        plan.assetsToInsert = wanted.filter { !libraryAssets.contains($0.id) }
        plan.summary.newMediaAssets = plan.assetsToInsert.count

        // Presentations.
        for entry in doc.presentations {
            var state = ImportPlan.State.new
            var libraryEntry: ProgramDocument.PresentationEntry?
            if existing.presentationIDs.contains(entry.id) {
                var refs = ActionReferences()
                libraryEntry = try await ProgramSnapshot.presentation(entry.id, in: store, collector: &compare, references: &refs)
                state = libraryEntry.map { ProgramSnapshot.contentKey($0) == ProgramSnapshot.contentKey(entry) } == true ? .identical : .conflict
            }
            var p = ImportPlan.PresentationPlan(state: state, action: .insert, source: entry, written: nil, finalID: entry.id, arrangementMap: [:])
            switch (state, choice) {
            case (.new, _): p.action = .insert
            case (.identical, _), (.conflict, .keepMine): p.action = .skip
            case (.conflict, .useImported):
                if live.livePresentationIDs.contains(entry.id) {
                    // FIX-G: a presentation that is on air is not replaced; both are kept for it and the operator is told.
                    p.action = .insertCopy
                    plan.keptBecauseLive.append(entry.title)
                    plan.warnings.append("\"\(entry.title)\" is live right now, so it was not replaced: the imported version was kept beside it as \"\(entry.title)\(importedSuffix)\".")
                } else { p.action = .replace }
            case (.conflict, .keepBoth): p.action = .insertCopy
            }
            switch p.action {
            case .skip:
                // The playlist keeps pointing at the library's own presentation; arrangements are matched by name.
                let mine = Dictionary(grouping: libraryEntry?.arrangements ?? [], by: \.name).compactMapValues(\.first)
                for arrangement in entry.arrangements { if let match = mine[arrangement.name] { p.arrangementMap[arrangement.id] = match.id } }
            case .insert, .replace, .insertCopy:
                let copy = p.action == .insertCopy
                let newID = copy ? UUID() : entry.id
                let owner = newID.uuidString
                func taken(_ ownerMap: [String: String], _ id: UUID) -> Bool {
                    if copy { return true }
                    if let other = ownerMap[id.uuidString] { return other != owner }
                    return false
                }
                var groupMap: [UUID: UUID] = [:]
                var written = entry
                written.id = newID
                if copy { written.title = entry.title + importedSuffix }
                written.groups = entry.groups.map { g in
                    let id = taken(existing.groupOwner, g.id) ? UUID() : g.id
                    groupMap[g.id] = id
                    return .init(id: id, name: g.name)
                }
                written.slides = entry.slides.map { s in
                    var s = s
                    s.id = taken(existing.slideOwner, s.id) ? UUID() : s.id
                    s.groupID = s.groupID.flatMap { groupMap[$0] ?? $0 }
                    if !plan.lookMap.isEmpty { s.actions = s.actions?.replacingUUIDs(plan.lookMap) }
                    return s
                }
                written.arrangements = entry.arrangements.map { a in
                    let id = taken(existing.arrangementOwner, a.id) ? UUID() : a.id
                    p.arrangementMap[a.id] = id
                    return .init(id: id, name: a.name, groupIDs: a.groupIDs.map { groupMap[$0] ?? $0 })
                }
                written.themeID = entry.themeID.map { plan.themeMap[$0] ?? $0 }
                p.written = written
                p.finalID = newID
            }
            switch state {
            case .new: plan.summary.newPresentations.append(entry.title)
            case .identical: plan.summary.alreadyPresent.append(entry.title)
            case .conflict: plan.summary.conflicting.append(entry.title)
            }
            plan.presentations.append(p)
        }

        // The playlist: what it would hold, then how that compares with the library's own.
        let byPresentation = Dictionary(plan.presentations.map { ($0.source.id, $0) }, uniquingKeysWith: { first, _ in first })
        var effective: [ProgramDocument.ItemEntry] = []
        for item in doc.items {
            var entry = item
            if item.kind == "presentation" {
                guard let id = item.presentationID, let p = byPresentation[id] else {
                    plan.warnings.append("A playlist item refers to a presentation that is not in the package; it was left out.")
                    continue
                }
                entry.presentationID = p.finalID
                entry.arrangementID = item.arrangementID.flatMap { p.arrangementMap[$0] }
            }
            effective.append(entry)
        }
        var playlistID = doc.playlist.id
        if existing.playlistIDs.contains(doc.playlist.id) {
            let mine = try await store.playlistItems(of: doc.playlist.id).map(ProgramSnapshot.item)
            let myName = try await store.playlists().first { $0.id == doc.playlist.id }?.name
            let same = mine == effective && myName == doc.playlist.name
            plan.playlistState = same ? .alreadyPresent : .conflicting
            switch (same, choice) {
            case (true, _), (false, .keepMine): plan.playlistAction = .skip(existing: playlistID)
            case (false, .useImported): plan.playlistAction = .replace(existing: playlistID, name: doc.playlist.name)
            case (false, .keepBoth):
                playlistID = UUID()
                plan.playlistAction = .insert(id: playlistID, name: doc.playlist.name + importedSuffix)
            }
        } else {
            plan.playlistState = .new
            plan.playlistAction = .insert(id: playlistID, name: doc.playlist.name)
        }
        plan.summary.playlist = plan.playlistState
        let freshItemIDs: Bool
        if case .insert(let id, _) = plan.playlistAction, id != doc.playlist.id { freshItemIDs = true } else { freshItemIDs = false }
        for entry in effective {
            guard let kind = ProgramSnapshot.kind(of: entry) else {
                plan.warnings.append("A playlist item of an unknown kind (\(entry.kind)) was left out.")
                continue
            }
            let owner = existing.itemOwner[entry.id.uuidString]
            let id = freshItemIDs || (owner != nil && owner != playlistID.uuidString) ? UUID() : entry.id
            plan.items.append(.init(id: id, kind: kind, presentationID: entry.presentationID, arrangementID: entry.arrangementID))
        }
        for entry in doc.items {
            if let scripture = entry.scripture, !scripture.translationCodes.allSatisfy({ existing.scriptureCodes.contains($0.lowercased()) }) {
                plan.summary.scriptureNotInstalled.append(scripture.label)
            }
        }

        plan.summary.slideActionKinds = actionKinds(plan.presentations)

        // Media that what is written refers to.
        var needed: [String] = []
        func need(_ path: String) { if !needed.contains(path) { needed.append(path) } }
        for p in plan.presentations {
            guard let written = p.written else { continue }
            for object in written.slides.flatMap(\.objects) { if case .image(let image) = object.content { need(image.path) } }
            for background in written.slides.compactMap(\.background) { need(background.file) }
        }
        for t in plan.themes where t.action != .skip { if case .image(let path) = t.theme.background { need(path) } }
        for a in plan.assetsToInsert { need(a.file) }
        var missing: [String] = []
        for path in needed {
            guard let entry = byFile[path] else { continue }
            guard entry.status == .included, let local = plan.localPath[path] else {
                if !missing.contains(entry.name) { missing.append(entry.name) }
                continue
            }
            plan.copies.append((entry, local))
            let target = folder.appendingPathComponent(local)
            if let info = ProgramFiles.lstatInfo(target), info.isRegular, info.size == entry.size {
                plan.summary.mediaFilesAlreadyThere += 1
            } else {
                plan.summary.mediaFilesToCopy += 1
                plan.summary.mediaBytesToCopy += entry.size ?? 0
            }
        }
        plan.summary.missingMedia = missing
        return plan
    }
}

extension ProgramImportPlanner {
    /// A Look's screens keyed by role (or, with no role recorded, by the profile id) with a number for repeats, so two Looks from
    /// different Macs can be compared.
    static func roleKeyed(_ look: ProgramDocument.LookEntry) -> [String: ProgramDocument.LookEntry.Screen] {
        var seen: [String: Int] = [:]
        var result: [String: ProgramDocument.LookEntry.Screen] = [:]
        for key in look.screens.keys.sorted() {
            let base = look.roles[key] ?? key
            let n = seen[base, default: 0]
            seen[base] = n + 1
            result["\(base)#\(n)"] = look.screens[key]
        }
        return result
    }

    /// The Look's screens as this Mac's profiles. A screen whose id is one of this Mac's profiles of the same role keeps it (so
    /// importing on the Mac that wrote the package changes nothing); the others go to this Mac's unused profile of the same role.
    /// Roles with no profile here come back as `unmapped` (a phrase for the operator); a screen with no recorded role is kept as written.
    static func mapScreens(_ look: ProgramDocument.LookEntry, profiles: [ScreenProfile]) -> (screens: [UUID: ScreenLook], unmapped: [String]) {
        var out: [UUID: ScreenLook] = [:]
        var unmapped: [String] = []
        var pending: [(UUID, String, ProgramDocument.LookEntry.Screen)] = []
        for key in look.screens.keys.sorted() {
            guard let id = UUID(uuidString: key), let screen = look.screens[key] else { continue }
            let role = look.roles[key]
            if let profile = profiles.first(where: { $0.id == id }), role == nil || role == profile.role.rawValue {
                out[id] = ScreenLook(themeID: screen.themeID, visibleLayers: Set(screen.visibleLayers.compactMap(LayerKind.init(rawValue:))))
            } else {
                pending.append((id, role ?? "", screen))
            }
        }
        for (id, role, screen) in pending {
            guard !role.isEmpty else {
                // A package that recorded no role (older, or a screen that was not one of its Mac's profiles): kept as it was written.
                out[id] = ScreenLook(themeID: screen.themeID, visibleLayers: Set(screen.visibleLayers.compactMap(LayerKind.init(rawValue:))))
                continue
            }
            if let target = profiles.first(where: { $0.role.rawValue == role && out[$0.id] == nil }) {
                out[target.id] = ScreenLook(themeID: screen.themeID, visibleLayers: Set(screen.visibleLayers.compactMap(LayerKind.init(rawValue:))))
            } else if !unmapped.contains("a \(role) screen") {
                unmapped.append("a \(role) screen")
            }
        }
        return (out, unmapped)
    }

    /// Slide actions by kind (`kind` field of each action), counted over presentations that will be written.
    static func actionKinds(_ presentations: [ImportPlan.PresentationPlan]) -> [String: Int] {
        var counts: [String: Int] = [:]
        for p in presentations where p.action != .skip {
            for slide in p.source.slides {
                guard case .object(let root)? = slide.actions, case .array(let list)? = root["actions"] else { continue }
                for action in list {
                    if case .object(let fields) = action, case .string(let kind)? = fields["kind"] { counts[kind, default: 0] += 1 }
                    else { counts["unknown", default: 0] += 1 }
                }
            }
        }
        return counts
    }
}

enum MediaPathPrefix {
    /// Imported media lives here, relative to the library's folder (see `MediaPathMapper` in Persistence).
    static let managed = "Media/Imported/"
}

extension ImportPlan.Action: Equatable {}
