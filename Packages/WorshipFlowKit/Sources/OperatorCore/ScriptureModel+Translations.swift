// LIB-004c item 7: the Translations screen. Import a translation file (the LIB-004 JSON format) with progress and a plain result,
// ask before replacing one that is already there, remove one after asking. The app bundles no Bible text.
import Foundation
import Domain
import ScriptureEngine
import ScriptureStore

extension ScriptureModel {
    func setImportState(_ state: ScriptureImportState) {
        importState = state
        onImportState?(state)
    }

    /// Reads a translation file from disk and adds it to the library. A code that is already there is not touched until
    /// `confirmReplace()`. The file is read and checked off the main actor.
    public func importTranslation(from url: URL) async {
        let name = url.lastPathComponent
        setImportState(.running(done: 0, total: 0))
        let file: TranslationFile
        do {
            file = try await Task.detached(priority: .userInitiated) { () throws -> TranslationFile in
                let data = try Data(contentsOf: url)
                return try TranslationLoader.decode(from: data)
            }.value
        } catch let error as TranslationLoadError {
            setImportState(.failed("“\(name)” is not a WorshipFlow translation file. \(error.message) Translation files are JSON; the command-line importer (wf-bible-import) turns a USFM folder into one."))
            return
        } catch {
            setImportState(.failed("Could not read “\(name)”: \(error.localizedDescription)"))
            return
        }
        await runImport(file, replace: false)
    }

    func runImport(_ file: TranslationFile, replace: Bool) async {
        setImportState(.running(done: 0, total: 0))
        do {
            let result = try await store.importTranslation(file, replaceExisting: replace) { [weak self] progress in
                Task { @MainActor in
                    guard let self, case .running = self.importState else { return }
                    self.setImportState(.running(done: progress.versesDone, total: progress.versesTotal))
                }
            }
            pendingImport = nil
            await reloadTranslations()
            if primaryCode == nil { primaryCode = result.translation.code; await saveChoices() }
            let tail = result.report.messages.isEmpty ? "" : " " + result.report.messages.joined(separator: " ")
            let verb = result.replaced ? "Replaced" : "Imported"
            setImportState(.finished("\(verb) “\(result.translation.name)”: \(result.report.verseCount) verses.\(tail)"))
            await refreshAfterLibraryChange()
        } catch ScriptureStoreError.alreadyExists(let code) {
            pendingImport = file
            setImportState(.needsReplace(code: code, name: file.metadata.name))
        } catch {
            setImportState(.failed(Self.message(for: error)))
        }
    }

    /// Yes to "replace the translation that is already installed".
    public func confirmReplace() async {
        guard let file = pendingImport else { return }
        await runImport(file, replace: true)
    }

    public func cancelReplace() {
        pendingImport = nil
        setImportState(.idle)
    }

    public func dismissImportMessage() { if case .running = importState { return }; setImportState(.idle) }

    // MARK: Removing

    /// Asks to remove a translation. Nothing is removed until `confirmRemoval()`.
    public func requestRemoval(_ code: String) {
        guard let found = translation(code) else { return }
        pendingRemoval = PendingRemoval(code: found.code, name: found.name)
    }

    public func cancelRemoval() { pendingRemoval = nil }

    /// Removes the translation asked about. Playlist items that use it stay in the playlist and say it is not installed; a choice
    /// of this translation moves to one that is.
    public func confirmRemoval() async {
        guard let ask = pendingRemoval else { return }
        pendingRemoval = nil
        do { try await store.deleteTranslation(code: ask.code) } catch ScriptureStoreError.notFound { } catch {
            translationsError = Self.message(for: error)
            return
        }
        await reloadTranslations()
        if !installed(primaryCode) { primaryCode = translations.first(where: { $0.code != secondaryCode })?.code ?? translations.first?.code }
        if !installed(secondaryCode) || secondaryCode == primaryCode { secondaryCode = nil }
        await saveChoices()
        await refreshAfterLibraryChange()
    }

    private func refreshAfterLibraryChange() async {
        searchResults = []
        searchMessage = nil
        searchTruncated = false
    }
}
