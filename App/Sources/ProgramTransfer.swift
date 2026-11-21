// LIB-005: the app side of exporting and importing a program. The rules and the file work are in `ProgramPackage`; this holds
// what the two sheets show, runs the work off the main thread and tells the workspace when the library changed.
import SwiftUI
import AppKit
import UniformTypeIdentifiers
import Domain
import OperatorCore
import Persistence
import ProgramPackage

/// Which sheet is open.
enum ProgramSheet: Identifiable, Equatable {
    case export, importing
    var id: Int { self == .export ? 0 : 1 }
}

/// A cancel request that the file work can poll from another thread.
final class ProgramCancelFlag: @unchecked Sendable {
    private let lock = NSLock()
    private var flag = false
    func cancel() { lock.lock(); flag = true; lock.unlock() }
    var isCancelled: Bool { lock.lock(); defer { lock.unlock() }; return flag }
}

/// Lets a progress callback from a worker thread reach the main actor about once per percent, not once per chunk.
final class ProgramProgressRelay: @unchecked Sendable {
    private let lock = NSLock()
    private var lastStep = -1
    let deliver: @Sendable (ProgramProgress) -> Void
    init(deliver: @escaping @Sendable (ProgramProgress) -> Void) { self.deliver = deliver }
    func report(_ p: ProgramProgress) {
        let step = p.bytesTotal > 0 ? Int(p.bytesDone * 100 / p.bytesTotal) : p.filesDone
        lock.lock()
        let fresh = step != lastStep || p.filesDone == p.filesTotal
        lastStep = step
        lock.unlock()
        if fresh { deliver(p) }
    }
}

enum ProgramWork: Equatable {
    case idle
    case running(ProgramProgress?)
    case done(String)
    case failed(String)
    var isRunning: Bool { if case .running = self { return true } else { return false } }
}

@MainActor
@Observable
final class ProgramTransferModel {
    static let shared = ProgramTransferModel()
    // Export
    var exportPlaylistID: UUID?
    private(set) var exportPlan: ProgramExportPlan?
    private(set) var exportPlanning = false
    private(set) var exportWork = ProgramWork.idle
    private(set) var exportedURL: URL?
    // Import
    private(set) var importURL: URL?
    private(set) var importContents: ProgramPackageContents?
    private(set) var importSummary: ProgramImportSummary?
    var importChoice = ProgramConflictChoice.default
    private(set) var importWork = ProgramWork.idle
    private(set) var importProblem: String?

    @ObservationIgnored private var cancel = ProgramCancelFlag()
    @ObservationIgnored private var planToken = 0

    // MARK: Export

    func startExport(app: AppModel, playlistID: UUID?) {
        guard let workspace = app.workspace, app.libraryStore != nil else { return }
        exportPlaylistID = playlistID ?? workspace.selectedPlaylistID ?? workspace.playlists.first?.id
        exportPlan = nil
        exportWork = .idle
        exportedURL = nil
        app.ui.programSheet = .export
        planExport(app: app)
    }

    func planExport(app: AppModel) {
        guard let store = app.libraryStore, let id = exportPlaylistID else { exportPlan = nil; return }
        planToken += 1
        let token = planToken
        exportPlanning = true
        exportPlan = nil
        let version = Self.appVersion
        Task { @MainActor in
            let plan = try? await ProgramExporter.plan(store: store, playlistID: id, appVersion: version)
            guard token == planToken else { return }
            exportPlanning = false
            exportPlan = plan
            if plan == nil { exportWork = .failed("The playlist could not be read.") }
        }
    }

    /// Asks where to save, then writes. The panel itself asks before replacing a file.
    func chooseDestinationAndExport(app: AppModel) {
        guard let plan = exportPlan, !exportWork.isRunning else { return }
        let panel = NSSavePanel()
        panel.allowedContentTypes = [UTType(filenameExtension: ProgramFormat.fileExtension, conformingTo: .package) ?? .package]
        panel.canCreateDirectories = true
        panel.nameFieldStringValue = Self.fileName(for: plan.document.playlist.name)
        panel.message = "Saves the program and a copy of its media as one file."
        guard panel.runModal() == .OK, var url = panel.url else { return }
        if url.pathExtension != ProgramFormat.fileExtension { url.appendPathExtension(ProgramFormat.fileExtension) }
        // The panel already asked about replacing an existing file.
        export(plan, to: url, replaceExisting: FileManager.default.fileExists(atPath: url.path))
    }

    /// Writes `plan` to `url` off the main thread, with progress and Cancel.
    func export(_ plan: ProgramExportPlan, to url: URL, replaceExisting replace: Bool) {
        guard !exportWork.isRunning else { return }
        let flag = ProgramCancelFlag()
        cancel = flag
        exportWork = .running(nil)
        let destination = url
        let relay = ProgramProgressRelay { p in Task { @MainActor in
            if case .running = self.exportWork { self.exportWork = .running(p) }
        } }
        Task.detached {
            do {
                try ProgramExporter.write(plan, to: destination, replaceExisting: replace, isCancelled: { flag.isCancelled },
                                          progress: { relay.report($0) })
                await MainActor.run {
                    self.exportedURL = destination
                    self.exportWork = .done(Self.exportedMessage(plan, destination))
                }
            } catch {
                await MainActor.run { self.exportWork = .failed(error.localizedDescription) }
            }
        }
    }

    func cancelWork() { cancel.cancel() }

    func closeExport(app: AppModel) {
        guard !exportWork.isRunning else { return }
        app.ui.programSheet = nil
        exportPlan = nil
    }

    static func exportedMessage(_ plan: ProgramExportPlan, _ url: URL) -> String {
        let size = ByteCountFormatter.string(fromByteCount: plan.totalBytes, countStyle: .file)
        let missing = plan.missing.isEmpty ? "" : " \(plan.missing.count) missing file\(plan.missing.count == 1 ? " is" : "s are") recorded as missing."
        return "Saved \(url.lastPathComponent): \(plan.presentationCount) presentation\(plan.presentationCount == 1 ? "" : "s"), \(plan.files.count) media file\(plan.files.count == 1 ? "" : "s") (\(size)).\(missing)"
    }

    static func fileName(for playlist: String) -> String {
        let cleaned = playlist.components(separatedBy: CharacterSet(charactersIn: "/:\\")).joined(separator: "-")
            .trimmingCharacters(in: .whitespaces)
        return (cleaned.isEmpty ? "Program" : cleaned) + "." + ProgramFormat.fileExtension
    }

    static var appVersion: String { Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "0.0.0" }

    // MARK: Import

    /// The open panel, then the summary. A package may also come from Finder or a drop (`beginImport(url:)`).
    func chooseAndImport(app: AppModel) {
        let panel = NSOpenPanel()
        panel.canChooseFiles = true
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = false
        panel.message = "Choose a WorshipFlow program (.\(ProgramFormat.fileExtension))"
        guard panel.runModal() == .OK, let url = panel.url else { return }
        beginImport(app: app, url: url)
    }

    func beginImport(app: AppModel, url: URL) {
        guard app.libraryStore != nil, !importWork.isRunning else { return }
        importURL = url
        importContents = nil
        importSummary = nil
        importProblem = nil
        importWork = .idle
        importChoice = .default
        app.ui.programSheet = .importing
        guard let store = app.libraryStore else { return }
        Task { @MainActor in
            do {
                let contents = try await Task.detached { try ProgramPackageContents.open(url) }.value
                let summary = try await ProgramImporter.summarize(contents, into: store)
                importContents = contents
                importSummary = summary
            } catch {
                importProblem = error.localizedDescription
            }
        }
    }

    func performImport(app: AppModel) {
        guard let store = app.libraryStore, let contents = importContents, !importWork.isRunning else { return }
        let flag = ProgramCancelFlag()
        cancel = flag
        importWork = .running(nil)
        let choice = importChoice
        let relay = ProgramProgressRelay { p in Task { @MainActor in
            if case .running = self.importWork { self.importWork = .running(p) }
        } }
        Task { @MainActor in
            do {
                let result = try await ProgramImporter.apply(contents, into: store, choice: choice, isCancelled: { flag.isCancelled },
                                                             progress: { relay.report($0) })
                await app.libraryChangedByProgramImport(result)
                importWork = .done(Self.importedMessage(result))
            } catch {
                importWork = .failed(error.localizedDescription)
            }
        }
    }

    func closeImport(app: AppModel) {
        guard !importWork.isRunning else { return }
        app.ui.programSheet = nil
        importContents = nil
        importSummary = nil
        importProblem = nil
    }

    static func importedMessage(_ r: ProgramImportResult) -> String {
        var parts: [String] = []
        if r.presentationsAdded > 0 { parts.append("\(r.presentationsAdded) presentation\(r.presentationsAdded == 1 ? "" : "s") added") }
        if r.presentationsKeptAsCopies > 0 { parts.append("\(r.presentationsKeptAsCopies) kept as an \"(imported)\" copy") }
        if r.presentationsReplaced > 0 { parts.append("\(r.presentationsReplaced) replaced") }
        if r.mediaFilesCopied > 0 { parts.append("\(r.mediaFilesCopied) media file\(r.mediaFilesCopied == 1 ? "" : "s") copied") }
        if r.mediaFilesReused > 0 { parts.append("\(r.mediaFilesReused) already there") }
        return parts.isEmpty ? "Everything in this program was already in the library. Nothing changed." : "Imported: " + parts.joined(separator: ", ") + "."
    }
}
