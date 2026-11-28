// FIX-AC item C (LIB-004d): a translation file that comes inside the app is imported once, through the store's own import, into a library that
// has no translation with that id; never put back after the operator removes it; a library that has the id is left as it is; a damaged file is
// reported where translations are listed and does not stop anything. Invented verses only: no Bible text is in the repository.
import Testing
import Foundation
import Domain
import Persistence
import ScriptureEngine
import ScriptureStore
@testable import OperatorCore

@MainActor
@Suite struct FIXAC_BundledTranslationTests {
    /// A made-up translation whose id is "KJV", as the file the build carries is named.
    private func invented(name: String = "Invented bundled text", extra: Bool = false) -> TranslationFile {
        var file = TranslationFile(metadata: TranslationMetadata(
            id: "KJV", name: name, language: "en", abbreviation: "INV", copyright: "Invented for tests.",
            license: "none", isPublicDomain: true, versification: "KJV"), books: [:])
        file.setVerse("The invented lantern burned beside the invented door.", book: BookID("JHN"), chapter: 3, verse: 16)
        file.setVerse("A second invented line stands here.", book: BookID("JHN"), chapter: 3, verse: 17)
        if extra { file.setVerse("A third invented line.", book: BookID("JHN"), chapter: 3, verse: 18) }
        return file
    }

    private func folder(_ files: [String: Data]) throws -> URL {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("wf-fixac-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        for (name, data) in files { try data.write(to: url.appendingPathComponent(name)) }
        return url
    }

    private func launch(on store: LibraryStore) async -> ScriptureModel {
        let model = ScriptureModel(store: ScriptureStore(library: store), stateStore: store)
        await model.load()
        return model
    }

    @Test func theFirstLaunchImportsTheBundledFileAndSaysNothingAboutIt() async throws {
        let store = try LibraryStore.inMemory()
        let bundle = try folder(["KJV.json": try invented().encoded()])
        let model = await launch(on: store)
        #expect(model.translations.isEmpty)
        await model.offerBundledTranslations(in: bundle)
        #expect(model.translations.map(\.code) == ["KJV"])
        #expect(model.translations.first?.verseCount == 2)
        #expect(model.translations.first?.copyright == "Invented for tests.")      // the file's own text is what the list shows
        #expect(model.primaryCode == "KJV")
        #expect(model.importState == .idle, "no message, no alert for a quiet success")
    }

    @Test func theSecondLaunchDoesNotImportAgain() async throws {
        let store = try LibraryStore.inMemory()
        let bundle = try folder(["KJV.json": try invented().encoded()])
        await launch(on: store).offerBundledTranslations(in: bundle)
        // Same library, a new model: the next launch. A file that is no longer readable proves nothing was read again.
        try Data("not json".utf8).write(to: bundle.appendingPathComponent("KJV.json"))
        let second = await launch(on: store)
        await second.offerBundledTranslations(in: bundle)
        #expect(second.translations.map(\.code) == ["KJV"])
        #expect(second.importState == .idle, "an offered file is not even read the second time")
    }

    @Test func aRemovedTranslationIsNotPutBack() async throws {
        let store = try LibraryStore.inMemory()
        let bundle = try folder(["KJV.json": try invented().encoded()])
        let first = await launch(on: store)
        await first.offerBundledTranslations(in: bundle)
        first.requestRemoval("KJV")
        await first.confirmRemoval()
        #expect(first.translations.isEmpty)
        await first.offerBundledTranslations(in: bundle)
        #expect(first.translations.isEmpty)
        let next = await launch(on: store)
        await next.offerBundledTranslations(in: bundle)
        #expect(next.translations.isEmpty)
    }

    @Test func aLibraryThatAlreadyHasTheIdIsLeftExactlyAsItIs() async throws {
        let store = try LibraryStore.inMemory()
        let scriptureStore = ScriptureStore(library: store)
        _ = try await scriptureStore.importTranslation(invented(name: "The operator's own copy", extra: true), replaceExisting: false)
        let before = try await scriptureStore.translations()
        let bundle = try folder(["KJV.json": try invented().encoded()])
        let model = await launch(on: store)
        await model.offerBundledTranslations(in: bundle)
        #expect(model.translations == before)
        #expect(model.translations.first?.name == "The operator's own copy" && model.translations.first?.verseCount == 3)
        #expect(model.importState == .idle)
        // And removing it later does not bring the bundled one in.
        model.requestRemoval("KJV"); await model.confirmRemoval()
        await model.offerBundledTranslations(in: bundle)
        #expect(model.translations.isEmpty)
    }

    @Test func aDamagedBundledFileIsReportedWhereTranslationsAreListedAndChangesNothing() async throws {
        let store = try LibraryStore.inMemory()
        let bundle = try folder(["KJV.json": Data("{ this is not a translation".utf8)])
        let model = await launch(on: store)
        await model.offerBundledTranslations(in: bundle)
        #expect(model.translations.isEmpty)
        guard case .failed(let message) = model.importState else { Issue.record("\(model.importState)"); return }
        #expect(message.contains("KJV.json"))
        #expect(model.canStartImport, "the operator can still import a file of their own")
        // A good file in a later build is then taken.
        try invented().encoded().write(to: bundle.appendingPathComponent("KJV.json"))
        let next = await launch(on: store)
        await next.offerBundledTranslations(in: bundle)
        #expect(next.translations.map(\.code) == ["KJV"])
    }

    @Test func noBundledFileDoesNothing() async throws {
        let store = try LibraryStore.inMemory()
        let model = await launch(on: store)
        await model.offerBundledTranslations(in: nil)
        await model.offerBundledTranslations(in: FileManager.default.temporaryDirectory.appendingPathComponent("wf-fixac-missing-\(UUID().uuidString)"))
        await model.offerBundledTranslations(in: try folder([:]))
        #expect(model.translations.isEmpty && model.importState == .idle)
        #expect(try await store.state(for: ScriptureModel.bundledOfferedKey) == nil, "nothing is recorded when nothing was offered")
    }

    @Test func onlyJSONFilesAreOffered() async throws {
        let store = try LibraryStore.inMemory()
        let bundle = try folder(["KJV.json": try invented().encoded(), "notes.txt": Data("x".utf8), ".hidden.json": Data("x".utf8)])
        let model = await launch(on: store)
        await model.offerBundledTranslations(in: bundle)
        #expect(model.translations.map(\.code) == ["KJV"])
        #expect(model.importState == .idle)
    }
}
