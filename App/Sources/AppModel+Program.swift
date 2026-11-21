// LIB-005: the menu commands and file-open routes of program export and import, and the refresh after an import.
import AppKit
import ProgramPackage

extension AppModel {
    /// File > Export Program… and the playlist's menu.
    func openExportProgram(playlistID: UUID? = nil) {
        guard workspace != nil, libraryStore != nil else { return }
        ProgramTransferModel.shared.startExport(app: self, playlistID: playlistID)
    }

    /// File > Import Program…
    func openImportProgram() {
        guard workspace != nil, libraryStore != nil else { return }
        ProgramTransferModel.shared.chooseAndImport(app: self)
    }

    /// A `.worshipflowprogram` opened from Finder or dropped on the window. Anything else is ignored.
    func openProgramPackages(_ urls: [URL]) {
        guard let url = urls.first(where: { $0.pathExtension.lowercased() == ProgramFormat.fileExtension }) else { return }
        guard workspaceLoaded else {
            // Opened from Finder at launch: wait for the library to finish loading.
            Task { @MainActor in
                for _ in 0..<80 where !workspaceLoaded { try? await Task.sleep(for: .milliseconds(250)) }
                if workspaceLoaded { ProgramTransferModel.shared.beginImport(app: self, url: url) }
            }
            return
        }
        ProgramTransferModel.shared.beginImport(app: self, url: url)
    }

    /// The library was written behind the workspace's back: bring its lists, themes, Looks and media bin up to date.
    func libraryChangedByProgramImport(_ result: ProgramImportResult) async {
        await workspace?.reloadAfterProgramImport(selecting: result.playlistID, replaced: result.replacedPresentationIDs)
        if result.themesAdded > 0 || result.looksAdded > 0 { await settings?.reloadThemesAndLooksAfterProgramImport() }
        if result.mediaAssetsAdded > 0 { await media?.load() }
    }
}
