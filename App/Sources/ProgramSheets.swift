// LIB-005: the two sheets of program export and import. Plain words, one decision per step, and nothing is written
// until the person presses the button that says so.
import SwiftUI
import Domain
import OperatorCore
import ProgramPackage

private func sizeText(_ bytes: Int64) -> String { ByteCountFormatter.string(fromByteCount: bytes, countStyle: .file) }

private struct ProgressRow: View {
    let work: ProgramWork
    let cancel: () -> Void

    var body: some View {
        if case .running(let progress) = work {
            HStack(spacing: Space.s4) {
                if let progress, progress.bytesTotal > 0 {
                    ProgressView(value: Double(progress.bytesDone), total: Double(progress.bytesTotal))
                        .accessibilityLabel("Progress")
                    Text("\(progress.filesDone) of \(progress.filesTotal) files").font(.wfCaption).foregroundStyle(Tok.muted)
                } else {
                    ProgressView().controlSize(.small)
                    Text("Working…").font(.wfCaption).foregroundStyle(Tok.muted)
                }
                Button("Cancel", action: cancel).keyboardShortcut(.cancelAction)
            }
        }
    }
}

struct ExportProgramSheet: View {
    let app: AppModel
    let workspace: WorkspaceModel
    @Bindable var model: ProgramTransferModel

    var body: some View {
        VStack(alignment: .leading, spacing: Space.s4) {
            Text("Export program").font(.title2.bold())
            Text("Saves one playlist, its songs and a copy of every picture and clip it uses as a single file you can carry to another Mac.")
                .font(.caption).foregroundStyle(.secondary)
            Picker("Playlist", selection: $model.exportPlaylistID) {
                ForEach(workspace.playlists) { Text($0.name).tag(Optional($0.id)) }
            }
            .disabled(model.exportWork.isRunning)
            .onChange(of: model.exportPlaylistID) { _, _ in model.planExport(app: app) }
            summary
            if case .failed(let message) = model.exportWork { Text(message).foregroundStyle(Tok.warning).font(.callout).textSelection(.enabled) }
            if case .done(let message) = model.exportWork { Text(message).font(.callout).textSelection(.enabled) }
            ProgressRow(work: model.exportWork) { model.cancelWork() }
            HStack {
                Spacer()
                if case .done = model.exportWork, let url = model.exportedURL {
                    Button("Show in Finder") { NSWorkspace.shared.activateFileViewerSelecting([url]) }
                }
                Button(model.exportWork.isRunning ? "Working…" : (doneOrFailed ? "Close" : "Cancel")) { model.closeExport(app: app) }
                    .keyboardShortcut(.cancelAction).disabled(model.exportWork.isRunning)
                if !doneOrFailed {
                    Button(exportTitle) { model.chooseDestinationAndExport(app: app) }
                        .keyboardShortcut(.defaultAction)
                        .disabled(model.exportPlan == nil || model.exportWork.isRunning || model.exportPlanning)
                }
            }
        }
        .padding(20).frame(width: 540)
    }

    private var doneOrFailed: Bool {
        switch model.exportWork { case .done, .failed: true; default: false }
    }

    private var exportTitle: String {
        (model.exportPlan?.missing.isEmpty ?? true) ? "Export…" : "Export without the missing files…"
    }

    @ViewBuilder private var summary: some View {
        if model.exportPlanning {
            HStack { ProgressView().controlSize(.small); Text("Reading the playlist and its media…").font(.callout) }
        } else if let plan = model.exportPlan {
            VStack(alignment: .leading, spacing: 4) {
                Text("\(plan.itemCount) item\(plan.itemCount == 1 ? "" : "s") in the playlist, \(plan.presentationCount) presentation\(plan.presentationCount == 1 ? "" : "s")")
                Text("\(plan.files.count) media file\(plan.files.count == 1 ? "" : "s"), \(sizeText(plan.totalBytes)) in total (identical files are stored once)")
                if !plan.document.themes.isEmpty || !plan.document.looks.isEmpty {
                    Text("\(plan.document.themes.count) theme\(plan.document.themes.count == 1 ? "" : "s") and \(plan.document.looks.count) Look\(plan.document.looks.count == 1 ? "" : "s")")
                }
            }.font(.callout)
            if !plan.missing.isEmpty {
                VStack(alignment: .leading, spacing: 2) {
                    Label("\(plan.missing.count) file\(plan.missing.count == 1 ? " cannot" : "s cannot") be read and will not be included:", systemImage: "exclamationmark.triangle.fill")
                        .foregroundStyle(Tok.warning).font(.callout)
                    ForEach(plan.missing, id: \.name) { Text("• \($0.name)").font(.caption).foregroundStyle(.secondary) }
                    Text("They are recorded as missing in the program. Connect the drive and export again to include them.")
                        .font(.caption).foregroundStyle(.secondary)
                }
            }
            ForEach(plan.warnings, id: \.self) { Text($0).font(.caption).foregroundStyle(.secondary) }
        }
    }
}

struct ImportProgramSheet: View {
    let app: AppModel
    @Bindable var model: ProgramTransferModel

    var body: some View {
        VStack(alignment: .leading, spacing: Space.s4) {
            Text("Import program").font(.title2.bold())
            if let problem = model.importProblem {
                Text(problem).foregroundStyle(Tok.warning).textSelection(.enabled)
            } else if let summary = model.importSummary {
                ScrollView { details(summary).frame(maxWidth: .infinity, alignment: .leading) }.frame(maxHeight: 360)
            } else {
                HStack { ProgressView().controlSize(.small); Text("Reading the program…").font(.callout) }
            }
            if case .failed(let message) = model.importWork { Text(message).foregroundStyle(Tok.warning).font(.callout).textSelection(.enabled) }
            if case .done(let message) = model.importWork { Text(message).font(.callout).textSelection(.enabled) }
            ProgressRow(work: model.importWork) { model.cancelWork() }
            HStack {
                Spacer()
                Button(model.importWork.isRunning ? "Working…" : (finished ? "Close" : "Cancel")) { model.closeImport(app: app) }
                    .keyboardShortcut(.cancelAction).disabled(model.importWork.isRunning)
                if !finished, model.importProblem == nil {
                    Button(importTitle) { model.performImport(app: app) }
                        .keyboardShortcut(.defaultAction)
                        .disabled(model.importSummary == nil || model.importWork.isRunning || model.importSummary?.isNothingToImport == true)
                }
            }
        }
        .padding(20).frame(width: 560)
    }

    private var finished: Bool {
        switch model.importWork { case .done, .failed: true; default: false }
    }

    private var importTitle: String {
        guard let s = model.importSummary else { return "Import" }
        return s.hasConflicts ? "Import with this choice" : "Import"
    }

    @ViewBuilder private func details(_ s: ProgramImportSummary) -> some View {
        VStack(alignment: .leading, spacing: Space.s4) {
            Text("Playlist “\(s.playlistName)”: " + playlistWords(s.playlist)).font(.callout.bold())
            group("New in this library", s.newPresentations)
            group("Already in this library, unchanged", s.alreadyPresent)
            group("In this library with different content", s.conflicting)
            if s.newThemes + s.newLooks + s.newMediaAssets > 0 {
                Text("Also new: \(s.newThemes) theme\(s.newThemes == 1 ? "" : "s"), \(s.newLooks) Look\(s.newLooks == 1 ? "" : "s"), \(s.newMediaAssets) media bin item\(s.newMediaAssets == 1 ? "" : "s").")
                    .font(.callout)
            }
            if s.hasConflicts {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Where something has the same id but different content:").font(.callout.bold())
                    Picker("", selection: $model.importChoice) {
                        Text("Keep both (the imported copy is marked “(imported)”)").tag(ProgramConflictChoice.keepBoth)
                        Text("Keep mine").tag(ProgramConflictChoice.keepMine)
                        Text("Use the imported one (replaces mine)").tag(ProgramConflictChoice.useImported)
                    }.pickerStyle(.radioGroup).labelsHidden()
                    if model.importChoice == .useImported {
                        // FIX-G: what protects the replace.
                        Text("Before anything is replaced the whole library is copied to the Backups folder next to it. A presentation that is live right now, and a theme or Look the live show uses, are not replaced: both are kept.")
                            .font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                    }
                }
            }
            if s.mediaFilesToCopy > 0 || s.mediaFilesAlreadyThere > 0 {
                Text("Media: \(s.mediaFilesToCopy) file\(s.mediaFilesToCopy == 1 ? "" : "s") to copy (\(sizeText(s.mediaBytesToCopy)))" +
                     (s.mediaFilesAlreadyThere > 0 ? ", \(s.mediaFilesAlreadyThere) already here" : "") +
                     ". They are kept next to the library, so they go with it.").font(.callout)
            }
            if !s.slideActionKinds.isEmpty {
                // FIX-G: slide actions run things (media, Looks, ...) when a slide goes live; they are listed before anything is imported.
                VStack(alignment: .leading, spacing: 2) {
                    Text("Slide actions that come with these slides (they run when the slide goes live):").font(.callout)
                    ForEach(s.slideActionKinds.sorted { $0.key < $1.key }, id: \.key) { kind, count in
                        Text("• \(kind): \(count)").font(.caption).foregroundStyle(.secondary)
                    }
                }
            }
            if !s.missingMedia.isEmpty {
                VStack(alignment: .leading, spacing: 2) {
                    Label("Missing when the program was saved:", systemImage: "exclamationmark.triangle.fill").foregroundStyle(Tok.warning).font(.callout)
                    ForEach(s.missingMedia, id: \.self) { Text("• \($0)").font(.caption).foregroundStyle(.secondary) }
                }
            }
            if !s.scriptureNotInstalled.isEmpty {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Bible passages whose translation is not installed here (they import and show that until it is):").font(.callout)
                    ForEach(s.scriptureNotInstalled, id: \.self) { Text("• \($0)").font(.caption).foregroundStyle(.secondary) }
                }
            }
            if s.isNothingToImport { Text("Everything in this program is already in the library. Nothing to import.").font(.callout) }
        }
    }

    @ViewBuilder private func group(_ title: String, _ names: [String]) -> some View {
        if !names.isEmpty {
            VStack(alignment: .leading, spacing: 2) {
                Text("\(title) (\(names.count))").font(.callout.bold())
                ForEach(names, id: \.self) { Text("• \($0)").font(.caption).foregroundStyle(.secondary) }
            }
        }
    }

    private func playlistWords(_ state: ProgramImportSummary.PlaylistState) -> String {
        switch state {
        case .new: "new"
        case .alreadyPresent: "already in this library"
        case .conflicting: "in this library with different content"
        }
    }
}

/// LIB-005: attaches the export and import sheets to the workspace, and lets a program package be dropped on the window.
struct ProgramTransferModifier: ViewModifier {
    let app: AppModel
    let workspace: WorkspaceModel

    func body(content: Content) -> some View {
        content
            .sheet(item: Binding(get: { app.ui.programSheet }, set: { app.ui.programSheet = $0 })) { sheet in
                switch sheet {
                case .export: ExportProgramSheet(app: app, workspace: workspace, model: ProgramTransferModel.shared)
                case .importing: ImportProgramSheet(app: app, model: ProgramTransferModel.shared)
                }
            }
            .onDrop(of: [.fileURL], isTargeted: nil) { providers in
                guard let provider = providers.first(where: { $0.hasItemConformingToTypeIdentifier("public.file-url") }) else { return false }
                _ = provider.loadObject(ofClass: URL.self) { url, _ in
                    guard let url, url.pathExtension.lowercased() == ProgramFormat.fileExtension else { return }
                    Task { @MainActor in app.openProgramPackages([url]) }
                }
                return true
            }
    }
}
