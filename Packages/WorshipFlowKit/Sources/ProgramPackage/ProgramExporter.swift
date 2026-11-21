// LIB-005 item 2: exporting a playlist as a program package. `plan` reads the library and says what a package would contain
// (and what is missing); `write` builds the package in a temporary sibling folder and moves it into place.
import Foundation
import Domain
@_spi(ProgramPackage) import Persistence

public enum ProgramExporter {
    /// Reads the playlist and everything it needs, and says what a package would contain. Writes nothing.
    public static func plan(store: LibraryStore, playlistID: UUID, appVersion: String = "0.0.0") async throws -> ProgramExportPlan {
        guard let playlist = try await store.playlists().first(where: { $0.id == playlistID }) else {
            throw ProgramPackageError.playlistNotFound
        }
        let playlistItems = try await store.playlistItems(of: playlistID)
        var collector = MediaCollector()
        var references = ActionReferences()
        var warnings: [String] = []

        var presentations: [ProgramDocument.PresentationEntry] = []
        var seen: Set<UUID> = []
        for item in playlistItems where item.kind == .presentation && seen.insert(item.presentationID).inserted {
            if let entry = try await ProgramSnapshot.presentation(item.presentationID, in: store, collector: &collector, references: &references) {
                presentations.append(entry)
            }
        }

        // Looks that the slide actions select, then every custom theme those Looks and the presentations use.
        let allLooks = try await store.looks()
        let looks = allLooks.filter { Set(references.looks).contains($0.id) }
        if Set(references.looks).count > looks.count {
            warnings.append("A slide action selects a Look that is not in this library; it was left out.")
        }
        var themeIDs = Set(presentations.compactMap(\.themeID))
        for look in looks { for screen in look.screens.values { if let id = screen.themeID { themeIDs.insert(id) } } }
        let themes = try await store.themes().filter { themeIDs.contains($0.id) }.map {
            ProgramSnapshot.theme($0, collector: &collector)
        }

        // Media items that the slide actions play, with their files.
        let wanted = Set(references.assets)
        let assets = try await store.mediaAssets(kind: nil).filter { wanted.contains($0.id) }
        let assetEntries = assets.map { asset in
            ProgramDocument.AssetEntry(id: asset.id, name: asset.name, kind: asset.kind, duration: asset.duration,
                                       pixelWidth: asset.pixelWidth, pixelHeight: asset.pixelHeight, file: collector.reference(asset.path))
        }
        if wanted.count > assets.count { warnings.append("A slide action plays a media item that is not in this library; it was left out.") }
        if !references.notCarried.isEmpty {
            warnings.append("Slide actions use \(references.notCarried.sorted().joined(separator: ", ")), which a program does not carry: set them up again on the other Mac.")
        }

        let document = ProgramDocument(
            appVersion: appVersion, programID: playlist.id, playlist: .init(id: playlist.id, name: playlist.name),
            items: playlistItems.map(ProgramSnapshot.item), presentations: presentations, themes: themes,
            looks: looks.map(ProgramSnapshot.lookEntry), mediaAssets: assetEntries, media: collector.entries)
        return ProgramExportPlan(document: document, files: collector.files,
                                 missing: collector.missingNames.map { ProgramMissingMedia(name: $0) }, warnings: warnings)
    }

    /// Writes the package to `destination`: built in a temporary sibling folder and moved into place at the end. A failure or a
    /// cancel removes the temporary folder and leaves nothing at `destination`. An existing `destination` is refused unless
    /// `replaceExisting` (which the caller sets only after the person agreed to replace it).
    public static func write(_ plan: ProgramExportPlan, to destination: URL, replaceExisting: Bool = false,
                             hooks: ProgramExportHooks = .none, isCancelled: @Sendable () -> Bool = { false },
                             progress: @Sendable (ProgramProgress) -> Void = { _ in }) throws {
        let fm = FileManager.default
        let parent = destination.deletingLastPathComponent()
        var isFolder: ObjCBool = false
        guard fm.fileExists(atPath: parent.path, isDirectory: &isFolder), isFolder.boolValue else {
            throw ProgramPackageError.copyFailed("The folder \(parent.lastPathComponent) does not exist.")
        }
        if fm.fileExists(atPath: destination.path), !replaceExisting {
            throw ProgramPackageError.destinationExists(destination.lastPathComponent)
        }
        let temp = parent.appendingPathComponent(".\(destination.lastPathComponent).partial-\(UUID().uuidString)", isDirectory: true)
        var finished = false
        defer { if !finished { try? fm.removeItem(at: temp) } }
        try fm.createDirectory(at: temp.appendingPathComponent(ProgramFormat.mediaFolder), withIntermediateDirectories: true)

        let total = plan.totalBytes
        var done: Int64 = 0
        progress(ProgramProgress(bytesDone: 0, bytesTotal: total, filesDone: 0, filesTotal: plan.files.count))
        for (index, file) in plan.files.enumerated() {
            if isCancelled() { throw ProgramPackageError.cancelled }
            let target = temp.appendingPathComponent(file.packagePath)
            try copy(file, to: target, isCancelled: isCancelled) { piece in
                done += piece
                progress(ProgramProgress(bytesDone: done, bytesTotal: total, filesDone: index, filesTotal: plan.files.count))
            }
            progress(ProgramProgress(bytesDone: done, bytesTotal: total, filesDone: index + 1, filesTotal: plan.files.count))
            try hooks.afterFile?(index + 1)
        }
        if isCancelled() { throw ProgramPackageError.cancelled }

        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        try encoder.encode(plan.document).write(to: temp.appendingPathComponent(ProgramFormat.manifestName))
        try hooks.beforeMove?()
        if isCancelled() { throw ProgramPackageError.cancelled }

        if fm.fileExists(atPath: destination.path) {
            guard replaceExisting else { throw ProgramPackageError.destinationExists(destination.lastPathComponent) }
            _ = try fm.replaceItemAt(destination, withItemAt: temp)
        } else {
            try fm.moveItem(at: temp, to: destination)
        }
        finished = true
    }

    /// Clones where the file system allows, else copies in chunks. Either way a source that changed since the plan is refused.
    private static func copy(_ file: ProgramExportFile, to target: URL, isCancelled: () -> Bool, onBytes: (Int64) -> Void) throws {
        func unchanged() -> Bool {
            guard let now = ProgramFiles.statInfo(file.source.path) else { return false }
            return now.size == file.size && now.modified == file.modified
        }
        guard unchanged() else {
            throw ProgramPackageError.copyFailed("\(file.name) changed or went missing while the program was being exported.")
        }
        if ProgramFiles.clone(from: file.source, to: target) {
            guard unchanged() else {
                throw ProgramPackageError.copyFailed("\(file.name) changed while the program was being exported.")
            }
            onBytes(file.size)
            return
        }
        let digest = try ProgramFiles.chunkedCopy(from: file.source, to: target, isCancelled: isCancelled, onBytes: onBytes)
        guard digest == file.sha256 else {
            throw ProgramPackageError.copyFailed("\(file.name) changed while the program was being exported.")
        }
    }
}
