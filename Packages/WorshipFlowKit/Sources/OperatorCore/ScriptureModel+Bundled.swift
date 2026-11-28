// FIX-AC item C (LIB-004d): a translation file that comes inside the app (the test build carries the King James Version) is imported once, by the
// store's own import, into a library that has no translation with that id. The repository holds no Bible text; this only reads a folder the build
// may or may not have. Foundation, Domain, ScriptureEngine and ScriptureStore only.
import Foundation
import Domain
import Persistence
import ScriptureEngine
import ScriptureStore

extension ScriptureModel {
    /// The library state that remembers which bundled files were already offered (a JSON list of lower-case file names without the extension).
    /// It lives in the library's own key/value state, beside the saved choices: no table, no migration.
    public static let bundledOfferedKey = "scripture.bundledOffered"

    /// Offers the `.json` files of `folder` once each. A file is read and imported only when the library has no translation with its id and the
    /// file was never offered before; it is then never offered again, so a translation the operator removes stays removed. A library that already
    /// has the id is left as it is. Reading, checking and writing all happen off the main actor; a quiet success changes nothing but the list.
    /// A failure is shown where the translations are listed. Nothing is recorded for a failure, so a corrected file is taken at the next launch.
    public func offerBundledTranslations(in folder: URL?) async {
        guard let folder, let stateStore else { return }
        let urls = await Task.detached(priority: .utility) { Self.bundledFiles(in: folder) }.value
        guard !urls.isEmpty else { return }
        var offered = await bundledOffered()
        let limit = Self.largestImportBytes
        for url in urls {
            let key = url.deletingPathExtension().lastPathComponent.lowercased()
            if offered.contains(key) { continue }
            let name = url.lastPathComponent
            do {
                let file = try await Task.detached(priority: .utility) { () throws -> TranslationFile in
                    let size = (try FileManager.default.attributesOfItem(atPath: url.path)[.size] as? NSNumber)?.intValue ?? 0
                    guard size <= limit else { throw BundledFileError.tooLarge(megabytes: (size + 1_048_575) / 1_048_576) }
                    return try TranslationLoader.decode(from: try Data(contentsOf: url))
                }.value
                let code = file.metadata.id.trimmingCharacters(in: .whitespacesAndNewlines)
                if translations.contains(where: { $0.code.caseInsensitiveCompare(code) == .orderedSame }) {
                    offered.insert(key)                              // the library has it: leave it, and do not offer again if it is removed later
                } else {
                    _ = try await store.importTranslation(file, replaceExisting: false)
                    offered.insert(key)
                    await reloadTranslations()
                    if primaryCode == nil { primaryCode = translations.first(where: { $0.code.caseInsensitiveCompare(code) == .orderedSame })?.code; await saveChoices() }
                }
                await saveBundledOffered(offered, to: stateStore)
            } catch ScriptureStoreError.alreadyExists {
                offered.insert(key)                                  // the operator imported it at the same moment
                await reloadTranslations()
                await saveBundledOffered(offered, to: stateStore)
            } catch {
                reportBundledFailure(name: name, error: error)
            }
        }
    }

    private enum BundledFileError: Error { case tooLarge(megabytes: Int) }

    private nonisolated static func bundledFiles(in folder: URL) -> [URL] {
        let items = (try? FileManager.default.contentsOfDirectory(at: folder, includingPropertiesForKeys: [.isRegularFileKey], options: [.skipsHiddenFiles])) ?? []
        return items.filter { $0.pathExtension.lowercased() == "json" && (try? $0.resourceValues(forKeys: [.isRegularFileKey]).isRegularFile) == true }
            .sorted { $0.lastPathComponent < $1.lastPathComponent }
    }

    private func bundledOffered() async -> Set<String> {
        guard let text = try? await stateStore?.state(for: Self.bundledOfferedKey), let data = text.data(using: .utf8),
              let list = try? JSONDecoder().decode([String].self, from: data) else { return [] }
        return Set(list)
    }

    private func saveBundledOffered(_ offered: Set<String>, to stateStore: LibraryStore) async {
        guard let data = try? JSONEncoder().encode(offered.sorted()), let text = String(data: data, encoding: .utf8) else { return }
        try? await stateStore.setState(text, for: Self.bundledOfferedKey)
    }

    private func reportBundledFailure(name: String, error: Error) {
        let detail: String
        switch error {
        case let known as TranslationLoadError: detail = "It is not a WorshipFlow translation file. \(known.message)"
        case BundledFileError.tooLarge(let megabytes): detail = "It is \(megabytes) MB, more than the \(Self.largestImportBytes / 1_048_576) MB WorshipFlow will import."
        default: detail = Self.message(for: error)
        }
        let message = "“\(name)”, which came with this build, could not be added. \(detail) You can still import a translation file of your own here."
        if canStartImport { setImportState(.failed(message)) } else { translationsError = message }
    }
}
