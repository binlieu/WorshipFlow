// LIB-004c: invented fixtures for the scripture interface tests. Real book and chapter numbers, made-up words: none of this is
// scripture, and no Bible text is added to the repository. The Vietnamese lines carry stacked diacritics so the search tests
// have something to fold.
import Foundation
import Domain
import Persistence
import ScriptureEngine
import ScriptureStore
@testable import OperatorCore

enum L4C {
    /// John 3:1-18 in plain invented English, each verse long enough that one verse is more than a slide.
    static func englishVerse(_ n: Int) -> String {
        "Verse \(n): the quiet river carried a lantern past the old stone wall while the travellers counted the stars and sang a slow tune about home."
    }

    static func english(code: String = "en-test", name: String = "English test text") -> TranslationFile {
        var file = TranslationFile(metadata: TranslationMetadata(
            id: code, name: name, language: "en", abbreviation: "ENT", copyright: "Invented for tests. No rights reserved.",
            license: "none", isPublicDomain: true, versification: "KJV"), books: [:])
        for n in 1...18 { file.setVerse(englishVerse(n), book: BookID("JHN"), chapter: 3, verse: n) }
        file.setVerse("The lamp is lit. Nothing is missing.", book: BookID("PSA"), chapter: 23, verse: 1)
        file.setVerse("It rests the weary by the water.", book: BookID("PSA"), chapter: 23, verse: 2)
        file.setVerse("It leads along a quiet road.", book: BookID("PSA"), chapter: 23, verse: 3)
        file.setVerse("Short.", book: BookID("JHN"), chapter: 11, verse: 35)
        for n in 49...51 { file.setVerse("Exodus twelve, English verse \(n), invented.", book: BookID("EXO"), chapter: 12, verse: n) }
        return file
    }

    /// Vietnamese-looking invented text on the 1925 numbering. It has John 3:16 and 3:17 but not 3:18, and Exodus 12 stops at 50.
    static func vietnamese(code: String = "vi-test", name: String = "Vietnamese test text") -> TranslationFile {
        var file = TranslationFile(metadata: TranslationMetadata(
            id: code, name: name, language: "vi", abbreviation: "VIT", copyright: "Bản thử nghiệm, không phải kinh thánh.",
            license: "none", isPublicDomain: false, versification: "VI1925"), books: [:])
        file.setVerse("Người chăn dắt đàn chiên bên dòng nước bình an.", book: BookID("JHN"), chapter: 3, verse: 16)
        file.setVerse("Ngọn đèn thắp sáng suốt đêm dài, không ai bị bỏ lại.", book: BookID("JHN"), chapter: 3, verse: 17)
        file.setVerse("Câu thử nghiệm của Thi Thiên hai mươi ba.", book: BookID("PSA"), chapter: 23, verse: 1)
        for n in 49...50 { file.setVerse("Xuất Ai Cập mười hai, câu thử \(n).", book: BookID("EXO"), chapter: 12, verse: n) }
        return file
    }

    static func temp(_ name: String = "Library.sqlite") -> URL {
        FileManager.default.temporaryDirectory.appendingPathComponent("wf-l4c-\(UUID().uuidString)", isDirectory: true).appendingPathComponent(name)
    }

    @MainActor
    struct Rig {
        let store: LibraryStore
        let scriptureStore: ScriptureStore
        let workspace: WorkspaceModel
        let scripture: ScriptureModel
        let saveClock: ManualSaveClock
    }

    /// A workspace and a scripture model over one library. `install` lists the translation files to import first.
    @MainActor
    static func rig(install: [TranslationFile]? = nil, store existing: LibraryStore? = nil, theme: Theme = .fullScreen) async throws -> Rig {
        let store = try existing ?? LibraryStore.inMemory()
        let scriptureStore = ScriptureStore(library: store)
        for file in install ?? [english(), vietnamese()] { _ = try await scriptureStore.importTranslation(file, replaceExisting: true) }
        let saveClock = ManualSaveClock()
        let workspace = WorkspaceModel(store: store, clock: saveClock)
        await workspace.load()
        let scripture = ScriptureModel(store: scriptureStore, stateStore: store)
        scripture.themeProvider = { theme }
        scripture.connect(workspace)
        await scripture.load()
        return Rig(store: store, scriptureStore: scriptureStore, workspace: workspace, scripture: scripture, saveClock: saveClock)
    }
}
