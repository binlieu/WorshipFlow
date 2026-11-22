// LIB-004c (debug builds only): `UI_SNAPSHOT_SCRIPTURE=1` with the ui-snapshots hook runs the Scripture view in the real app
// against a temporary library: Command-J through the real menu, the empty state, two invented translation files imported through
// the model, a reference typed with real key events and Return, Go Live and Next from the keyboard, two translations side by side,
// a playlist item, a search. The only verses here are invented (not scripture). It writes pictures through the hook's `capture`.
#if DEBUG || WF_MEASURE
import AppKit
import Domain
import OperatorCore
import ScriptureEngine

extension AppModel {
    func runScriptureScenario(note: @MainActor (String) -> Void, capture: @MainActor (String) async -> Void,
                              key: @MainActor (UInt16, String, Bool, Bool) -> Void) async {
        guard let workspace, let scripture else { note("scripture: no models"); return }
        @MainActor func wait(_ seconds: Double, until condition: @MainActor () -> Bool) async -> Bool {
            let end = Date().addingTimeInterval(seconds)
            while Date() < end { if condition() { return true }; try? await Task.sleep(for: .milliseconds(100)) }
            return condition()
        }
        let codes: [Character: UInt16] = ["j": 38, "o": 31, "h": 4, "n": 45, " ": 49, "1": 18, "2": 19, "3": 20, "4": 21, "5": 23,
                                          "6": 22, "7": 26, "8": 28, "9": 25, "0": 29, "-": 27, ":": 41]
        @MainActor func type(_ text: String) async {
            for ch in text {
                let lower = Character(ch.lowercased())
                guard let code = codes[lower] else { continue }
                key(code, String(lower), false, ch.isUppercase || ch == ":")
                try? await Task.sleep(for: .milliseconds(60))
            }
        }

        // The pictures carry no operator content other than the sample song the hook already makes.
        // 0. Command-J through the real menu: the view opens, nothing is installed yet.
        workspace.setMode(.show)
        ui.scriptureOpen = false
        key(38, "j", true, false)
        _ = await wait(2) { ui.scriptureOpen }
        try? await Task.sleep(for: .milliseconds(800))
        note("scripture: Command-J -> view open \(ui.scriptureOpen) (expected true), nothing installed \(scripture.isEmpty) (expected true)")
        await capture("empty")

        // 1. Two invented translation files, through the model's import (the open panel only chooses the file).
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent("wf-scripture-run-\(UUID().uuidString)", isDirectory: true)
        try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: folder) }
        for file in Self.inventedTranslations() {
            let url = folder.appendingPathComponent("\(file.metadata.id).json")
            try? file.encoded().write(to: url)
            await scripture.importTranslation(from: url)
            note("scripture: imported \(file.metadata.id): \(scripture.importState)")
        }
        note("scripture: installed \(scripture.translations.map(\.code)) (expected invented-en, invented-vi), first \(scripture.primaryCode ?? "-")")
        ui.scriptureScreen = .translations
        try? await Task.sleep(for: .milliseconds(600))
        await capture("translations")

        // 2. A reference typed with real key events, Return, then Go Live and Next from the keyboard.
        ui.scriptureScreen = .reference
        ui.focusScripture += 1
        try? await Task.sleep(for: .milliseconds(900))
        await type("John 3:16-18")
        try? await Task.sleep(for: .milliseconds(300))
        note("scripture: field holds \"\(scripture.referenceText)\" (expected John 3:16-18)")
        key(36, "\r", false, false)
        _ = await wait(3) { scripture.passage != nil }
        try? await Task.sleep(for: .milliseconds(900))
        note("scripture: Return -> \(scripture.passage?.slides.count ?? 0) slides in preview \(workspace.show.previewDeck?.slides.count ?? 0), live deck is the passage: \(show.liveDeck?.presentationID == workspace.openScripture?.deckID) (expected false: preview only)")
        await capture("passage")
        key(36, "\r", false, false)                       // the grid has the keyboard now: Return is Go Live
        _ = await wait(3) { show.liveDeck?.presentationID == workspace.openScripture?.deckID }
        note("scripture: Return again -> passage live \(show.liveDeck?.presentationID == workspace.openScripture?.deckID), live slide \(show.liveIndex.map(String.init) ?? "-") (expected 0)")
        key(124, "\u{F703}", false, false)
        try? await Task.sleep(for: .milliseconds(500))
        note("scripture: Right arrow -> live slide \(show.liveIndex.map(String.init) ?? "-") (expected 1), position \(workspace.livePositionLine ?? "-")")

        // 3. Two translations: 3:18 exists in the first only, so its second side stays empty.
        await scripture.setSecondary("invented-vi")
        try? await Task.sleep(for: .milliseconds(700))
        note("scripture: with two translations \(scripture.passage?.contents.map { $0.secondary == nil ? "one side" : "two sides" } ?? []) (expected two, two, one side...)")
        await capture("two-translations")

        // 4. Keep it, and search.
        await scripture.addToPlaylist()
        note("scripture: playlist items \(workspace.playlistItems.map(\.title))")
        await scripture.setPrimary("invented-vi")
        await scripture.search("binh an")
        note("scripture: search 'binh an' -> \(scripture.searchResults.map(\.reference)) (expected one verse)")
        await scripture.setPrimary("invented-en")
        await scripture.setSecondary(nil)
    }

    /// Invented text under real references. None of it is scripture.
    static func inventedTranslations() -> [TranslationFile] {
        var en = TranslationFile(metadata: TranslationMetadata(id: "invented-en", name: "Invented English (not scripture)", language: "en", abbreviation: "INV",
                                                              copyright: "Made up for a screenshot. No rights reserved.", isPublicDomain: true, versification: "KJV"), books: [:])
        en.setVerse("The quiet river carried a lantern past the old stone wall while the travellers counted the stars and sang a slow tune about home.", book: BookID("JHN"), chapter: 3, verse: 16)
        en.setVerse("A small boat waited by the bridge, and nobody asked where it had come from.", book: BookID("JHN"), chapter: 3, verse: 17)
        en.setVerse("Morning arrived without any hurry. The bread was warm and the table was long.", book: BookID("JHN"), chapter: 3, verse: 18)
        var vi = TranslationFile(metadata: TranslationMetadata(id: "invented-vi", name: "Bản thử nghiệm (không phải kinh thánh)", language: "vi", abbreviation: "THU",
                                                              copyright: "Viết ra để chụp màn hình. Không giữ bản quyền.", isPublicDomain: true, versification: "VI1925"), books: [:])
        vi.setVerse("Dòng sông yên tĩnh mang theo ngọn đèn qua bức tường đá cũ, người lữ hành đếm sao và hát một điệu chậm về quê nhà bình an.", book: BookID("JHN"), chapter: 3, verse: 16)
        vi.setVerse("Chiếc thuyền nhỏ đợi bên cầu, và không ai hỏi nó từ đâu đến.", book: BookID("JHN"), chapter: 3, verse: 17)
        return [en, vi]
    }
}
#endif
