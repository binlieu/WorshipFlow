// SYS-002: extra coverage for the settings store (encoding stability, edge cases, v2 compatibility).
import Testing
import Foundation
import GRDB
import Domain
@testable import Persistence

@Suite struct SettingsStoreExtraTests {
    func storeURL() -> URL {
        FileManager.default.temporaryDirectory
            .appendingPathComponent("wf-tests-\(UUID().uuidString)", isDirectory: true)
            .appendingPathComponent("Library.sqlite")
    }
    func theme(_ name: String) -> Theme {
        Theme(id: UUID(), name: name, background: .image(path: "/a/b.png"), primary: Theme.fullScreen.primary, secondary: nil)
    }

    @Test func lookJSONUsesStringKeysAndSortedLayers() async throws {
        let screen = UUID(uuidString: "11111111-2222-3333-4444-555555555555")!
        let json = try SettingsJSON.encodeScreens([screen: ScreenLook(themeID: nil, visibleLayers: [.slide, .props, .background])])
        #expect(json == #"{"11111111-2222-3333-4444-555555555555":{"visibleLayers":["background","props","slide"]}}"#)
        #expect(try SettingsJSON.decodeScreens(json) == [screen: ScreenLook(themeID: nil, visibleLayers: [.slide, .props, .background])])
    }

    @Test func corruptLookJSONThrows() {
        #expect(throws: DecodingError.self) { try SettingsJSON.decodeScreens(#"{"nope":{"themeID":null,"visibleLayers":[]}}"#) }
        #expect(throws: DecodingError.self) { try SettingsJSON.decodeScreens(#"{"11111111-2222-3333-4444-555555555555":{"themeID":null,"visibleLayers":["x"]}}"#) }
    }

    @Test func themeNameIsTrimmedAndAllBackgroundsRoundTrip() async throws {
        let store = try LibraryStore.inMemory()
        for bg in [ThemeBackground.media, .color(ColorRGBA(red: 1, green: 0.5, blue: 0.25)), .image(path: "/x y/z.png"), .transparent] {
            var t = theme("  Padded  "); t.background = bg
            try await store.saveTheme(t)
            t.name = "Padded"
            #expect(try await store.themes() == [t])
            try await store.deleteTheme(id: t.id)
        }
    }

    @Test func themesSortIgnoringCaseAndDiacritics() async throws {
        let store = try LibraryStore.inMemory()
        let b = theme("bravo"), a = theme("Álpha"), c = theme("Charlie")
        for t in [c, b, a] { try await store.saveTheme(t) }
        #expect(try await store.themes().map(\.name) == ["Álpha", "bravo", "Charlie"])
    }

    @Test func deletingAThemeOnlyClearsPresentationsThatUsedIt() async throws {
        let store = try LibraryStore.inMemory()
        let lib = try await store.createLibrary(name: "L")
        let p1 = try await store.createPresentation(in: lib.id, title: "A", kind: .song)
        let p2 = try await store.createPresentation(in: lib.id, title: "B", kind: .song)
        let doomed = theme("Doomed"), kept = theme("Kept")
        try await store.saveTheme(doomed); try await store.saveTheme(kept)
        try await store.setTheme(doomed.id, forPresentation: p1.id)
        try await store.setTheme(kept.id, forPresentation: p2.id)
        try await store.deleteTheme(id: doomed.id)
        let after = try await store.presentations(in: lib.id)
        #expect(after.first { $0.id == p1.id }?.themeID == nil)
        #expect(after.first { $0.id == p2.id }?.themeID == kept.id)
    }

    @Test func builtInThemeIdsAreInvalidReferencesForSaveAndDelete() async throws {
        let store = try LibraryStore.inMemory()
        await #expect(throws: StoreError.invalidReference) { try await store.saveTheme(.lowerThird) }
        await #expect(throws: StoreError.invalidReference) { try await store.deleteTheme(id: Theme.fullScreen.id) }
        #expect(try await store.themes().isEmpty)
    }

    @Test func editingAPresentationKeepsItsTheme() async throws {
        let store = try LibraryStore.inMemory()
        let lib = try await store.createLibrary(name: "L")
        let p = try await store.createPresentation(in: lib.id, title: "A", kind: .song)
        try await store.setTheme(Theme.fullScreen.id, forPresentation: p.id)
        try await store.renamePresentation(id: p.id, to: "Renamed")
        try await store.replaceContent(of: p.id, with: Reflow.contents(primary: "Verse 1\na", secondary: nil, maxLines: 2))
        #expect(try await store.presentations(in: lib.id).first?.themeID == Theme.fullScreen.id)
    }

    @Test func lookOrderSurvivesEditingTheFirstLook() async throws {
        let store = try LibraryStore.inMemory()
        let a = Look(id: UUID(), name: "A"), b = Look(id: UUID(), name: "B")
        try await store.saveLook(a); try await store.saveLook(b)
        var edited = a; edited.name = "A2"; edited.screens = [UUID(): .standard]
        try await store.saveLook(edited)
        #expect(try await store.looks() == [edited, b])
        await #expect(throws: StoreError.invalidName) { try await store.saveLook(Look(id: UUID(), name: " ")) }
        await #expect(throws: StoreError.notFound) { try await store.deleteLook(id: UUID()) }
    }

    @Test func propOrderAndBookmarkReplacement() async throws {
        let store = try LibraryStore.inMemory()
        let frame = NormalizedRect(x: 0, y: 0, width: 1, height: 1)
        let p1 = Prop(id: UUID(), name: "One", imagePath: "/1.png", frame: frame)
        let p2 = Prop(id: UUID(), name: "Two", imagePath: "/2.png", frame: frame, opacity: 0.5, isOn: false)
        try await store.saveProp(p1, bookmark: Data([1])); try await store.saveProp(p2, bookmark: nil)
        var e = p1; e.name = "One!"
        try await store.saveProp(e, bookmark: Data([7]))
        #expect(try await store.props() == [e, p2])
        #expect(try await store.bookmark(forProp: p1.id) == Data([7]))
        #expect(try await store.bookmark(forProp: p2.id) == nil)
        await #expect(throws: StoreError.notFound) { try await store.deleteProp(id: UUID()) }
    }

    @Test func screenProfilesKeepDisplayIDsAndRejectDuplicates() async throws {
        let store = try LibraryStore.inMemory()
        let a = ScreenProfile(name: "Big", role: .audience, destination: .display(UInt32.max))
        let b = ScreenProfile(name: "Zero", role: .stage, destination: .display(0))
        try await store.saveScreenProfiles([a, b])
        #expect(try await store.screenProfiles() == [a, b])
        await #expect(throws: StoreError.invalidReference) { try await store.saveScreenProfiles([a, a]) }
        #expect(try await store.screenProfiles() == [a, b])          // a failed save changes nothing
        try await store.saveScreenProfiles([])
        #expect(try await store.screenProfiles().isEmpty)
    }

    @Test func mediaAssetValidationAndExistingAssetIsUnchanged() async throws {
        let store = try LibraryStore.inMemory()
        await #expect(throws: StoreError.invalidName) {
            _ = try await store.addMediaAsset(name: " ", kind: .image, path: "/a.png", bookmark: nil, duration: nil, pixelWidth: nil, pixelHeight: nil)
        }
        let first = try await store.addMediaAsset(name: "A", kind: .image, path: "/a.png", bookmark: Data([1]), duration: nil, pixelWidth: 4, pixelHeight: 3)
        let again = try await store.addMediaAsset(name: "Other", kind: .video, path: "/a.png", bookmark: nil, duration: 9, pixelWidth: 1, pixelHeight: 1)
        #expect(again == first)
        await #expect(throws: StoreError.notFound) { try await store.renameMediaAsset(id: UUID(), to: "x") }
        await #expect(throws: StoreError.invalidName) { try await store.renameMediaAsset(id: first.id, to: "") }
    }

    @Test func settingsPersistAcrossReopen() async throws {
        let url = storeURL()
        let store = try LibraryStore.open(at: url)
        let t = theme("Kept"); try await store.saveTheme(t)
        let asset = try await store.addMediaAsset(name: "M", kind: .audio, path: "/m.wav", bookmark: Data([5]), duration: 2, pixelWidth: nil, pixelHeight: nil)
        try store.close()
        let reopened = try LibraryStore.open(at: url)
        #expect(try await reopened.themes() == [t])
        #expect(try await reopened.mediaAssets(kind: nil) == [asset])
        try reopened.close()
    }

    /// A store opened only up to v2 keeps working for everything v2 offers, including creating presentations.
    @Test func v2StoreStillWorksWithoutThemeColumn() async throws {
        let url = storeURL()
        let old = try LibraryStore.open(at: url, migratingUpTo: "v2")
        #expect(try await old.appliedMigrations() == ["v1", "v2"])
        let lib = try await old.createLibrary(name: "L")
        let p = try await old.createPresentation(in: lib.id, title: "Song", kind: .song)
        try await old.renamePresentation(id: p.id, to: "Song 2")
        let list = try await old.createPlaylist(name: "Sunday")
        _ = try await old.addPresentation(p.id, to: list.id)
        #expect(try await old.playlistItems(of: list.id).map(\.title) == ["Song 2"])
        #expect(try await old.presentations(in: lib.id).first?.themeID == nil)
        try old.close()
    }
}
