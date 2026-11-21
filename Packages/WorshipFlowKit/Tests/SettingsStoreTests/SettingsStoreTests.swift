// SYS-002 acceptance tests: themes, Looks, props, screen profiles and media assets in SQLite (schema v3).
// Closes KI-016. Owned by the coordinator: do not modify.
import Testing
import Foundation
import Domain
@testable import Persistence

@Suite struct SettingsStoreTests {
    func storeURL() -> URL {
        FileManager.default.temporaryDirectory
            .appendingPathComponent("wf-tests-\(UUID().uuidString)", isDirectory: true)
            .appendingPathComponent("Library.sqlite")
    }
    func customTheme(_ name: String) -> Theme {
        var t = Theme.fullScreen
        t = Theme(id: UUID(), name: name, background: .color(ColorRGBA(red: 0.1, green: 0, blue: 0.2)), primary: t.primary, secondary: t.secondary)
        return t
    }

    @Test func schemaV3AddsSettingsTables() async throws {
        let store = try LibraryStore.inMemory()
        let tables = try await store.tableNames()
        for expected in ["theme", "look", "prop", "screenProfile", "mediaAsset"] { #expect(tables.contains(expected), "missing \(expected)") }
        #expect(try await store.appliedMigrations() == ["v1", "v2", "v3"])
    }

    @Test func v2RowsSurviveV3() async throws {
        let url = storeURL()
        let old = try LibraryStore.open(at: url, migratingUpTo: "v2")
        let lib = try await old.createLibrary(name: "Songs")
        let p = try await old.createPresentation(in: lib.id, title: "Amazing Grace", kind: .song)
        try await old.replaceContent(of: p.id, with: Reflow.contents(primary: "Verse 1\na\nb", secondary: nil, maxLines: 2))
        try old.close()
        let new = try LibraryStore.open(at: url)
        let after = try #require(try await new.presentations(in: lib.id).first)
        #expect(after.title == "Amazing Grace" && after.themeID == nil)
        #expect(try await new.groups(of: p.id).map(\.name) == ["Verse 1"])
        #expect(try await new.themes().isEmpty)
        try new.close()
    }

    // MARK: Themes

    @Test func themesRoundTripInNameOrder() async throws {
        let store = try LibraryStore.inMemory()
        let easter = customTheme("Easter"), advent = customTheme("Advent")
        try await store.saveTheme(easter)
        try await store.saveTheme(advent)
        #expect(try await store.themes() == [advent, easter])
        var edited = easter; edited.primary.style.fontSize = 140; edited.name = "Easter Sunday"
        try await store.saveTheme(edited)                       // same id: update, not a second row
        #expect(try await store.themes() == [advent, edited])
        try await store.deleteTheme(id: advent.id)
        #expect(try await store.themes() == [edited])
        await #expect(throws: StoreError.notFound) { try await store.deleteTheme(id: advent.id) }
    }

    /// Built-in themes live in code. They are never written to, or deleted from, the database.
    @Test func builtInThemesAreProtected() async throws {
        let store = try LibraryStore.inMemory()
        await #expect(throws: StoreError.self) { try await store.saveTheme(.fullScreen) }
        await #expect(throws: StoreError.self) { try await store.deleteTheme(id: Theme.lowerThird.id) }
        await #expect(throws: StoreError.invalidName) { try await store.saveTheme(customTheme("  ")) }
    }

    @Test func presentationThemeIsStoredAndClearedWhenThemeIsDeleted() async throws {
        let store = try LibraryStore.inMemory()
        let lib = try await store.createLibrary(name: "Songs")
        let p = try await store.createPresentation(in: lib.id, title: "Song", kind: .song)
        let theme = customTheme("Easter")
        try await store.saveTheme(theme)
        try await store.setTheme(theme.id, forPresentation: p.id)
        #expect(try await store.presentations(in: lib.id).first?.themeID == theme.id)
        try await store.setTheme(Theme.lowerThird.id, forPresentation: p.id)      // a built-in id is a valid reference
        #expect(try await store.presentations(in: lib.id).first?.themeID == Theme.lowerThird.id)
        try await store.setTheme(theme.id, forPresentation: p.id)
        try await store.deleteTheme(id: theme.id)
        #expect(try await store.presentations(in: lib.id).first?.themeID == nil)
        await #expect(throws: StoreError.self) { try await store.setTheme(UUID(), forPresentation: p.id) }
        await #expect(throws: StoreError.notFound) { try await store.setTheme(nil, forPresentation: UUID()) }
    }

    // MARK: Looks

    @Test func looksRoundTripAndKeepOrder() async throws {
        let store = try LibraryStore.inMemory()
        let screen = UUID()
        let worship = Look(id: UUID(), name: "Worship", screens: [screen: ScreenLook(themeID: Theme.lowerThird.id, visibleLayers: [.slide, .props])])
        let sermon = Look(id: UUID(), name: "Sermon", screens: [:])
        try await store.saveLook(worship)
        try await store.saveLook(sermon)
        #expect(try await store.looks() == [worship, sermon])           // creation order
        var renamed = worship; renamed.name = "Singing"
        try await store.saveLook(renamed)
        #expect(try await store.looks() == [renamed, sermon])
        try await store.deleteLook(id: sermon.id)
        #expect(try await store.looks().map(\.name) == ["Singing"])
    }

    // MARK: Props

    @Test func propsRoundTripWithBookmarks() async throws {
        let store = try LibraryStore.inMemory()
        let logo = Prop(id: UUID(), name: "Logo", imagePath: "/Users/x/logo.png",
                        frame: NormalizedRect(x: 0.86, y: 0.04, width: 0.1, height: 0.1), opacity: 0.9, isOn: true)
        let bookmark = Data([1, 2, 3, 4])
        try await store.saveProp(logo, bookmark: bookmark)
        #expect(try await store.props() == [logo])
        #expect(try await store.bookmark(forProp: logo.id) == bookmark)
        var off = logo; off.isOn = false
        try await store.saveProp(off, bookmark: nil)                    // nil keeps the stored bookmark
        #expect(try await store.props() == [off])
        #expect(try await store.bookmark(forProp: logo.id) == bookmark)
        try await store.deleteProp(id: logo.id)
        #expect(try await store.props().isEmpty)
        #expect(try await store.bookmark(forProp: logo.id) == nil)
    }

    // MARK: Screen profiles

    @Test func screenProfilesAreReplacedAsAnOrderedSet() async throws {
        let store = try LibraryStore.inMemory()
        #expect(try await store.screenProfiles().isEmpty)
        let a = ScreenProfile(id: UUID(), name: "Sanctuary", role: .audience, destination: .display(2), isEnabled: true)
        let b = ScreenProfile(id: UUID(), name: "Stage", role: .stage, destination: .window, isEnabled: true)
        let c = ScreenProfile(id: UUID(), name: "Stream", role: .broadcast, destination: .window, isEnabled: false)
        try await store.saveScreenProfiles([a, b, c])
        #expect(try await store.screenProfiles() == [a, b, c])
        try await store.saveScreenProfiles([c, a])                       // b removed, order changed
        #expect(try await store.screenProfiles() == [c, a])
    }

    // MARK: Media assets (MEDIA-01)

    @Test func mediaAssetsRoundTripAndFilterByKind() async throws {
        let store = try LibraryStore.inMemory()
        let loop = try await store.addMediaAsset(name: "Blue loop", kind: .video, path: "/Volumes/Media/loop.mov",
                                                 bookmark: Data([9]), duration: 20.02, pixelWidth: 1920, pixelHeight: 1080)
        let logo = try await store.addMediaAsset(name: "Logo", kind: .image, path: "/Volumes/Media/logo.png",
                                                 bookmark: nil, duration: nil, pixelWidth: 512, pixelHeight: 512)
        let bell = try await store.addMediaAsset(name: "Bell", kind: .audio, path: "/Volumes/Media/bell.wav",
                                                 bookmark: nil, duration: 3.5, pixelWidth: nil, pixelHeight: nil)
        #expect(try await store.mediaAssets(kind: nil).map(\.id) == [loop.id, logo.id, bell.id])    // order added
        #expect(try await store.mediaAssets(kind: .video) == [loop])
        #expect(loop.duration == 20.02 && loop.pixelWidth == 1920 && loop.bookmark == Data([9]))
        try await store.renameMediaAsset(id: logo.id, to: "Church logo")
        #expect(try await store.mediaAssets(kind: .image).first?.name == "Church logo")
        try await store.removeMediaAsset(id: bell.id)
        #expect(try await store.mediaAssets(kind: .audio).isEmpty)
        await #expect(throws: StoreError.notFound) { try await store.removeMediaAsset(id: bell.id) }
    }

    /// Adding the same file twice returns the existing asset rather than a duplicate.
    @Test func samePathIsNotAddedTwice() async throws {
        let store = try LibraryStore.inMemory()
        let first = try await store.addMediaAsset(name: "Loop", kind: .video, path: "/m/loop.mov", bookmark: nil, duration: 1, pixelWidth: 1, pixelHeight: 1)
        let second = try await store.addMediaAsset(name: "Loop again", kind: .video, path: "/m/loop.mov", bookmark: nil, duration: 1, pixelWidth: 1, pixelHeight: 1)
        #expect(first.id == second.id)
        #expect(try await store.mediaAssets(kind: nil).count == 1)
    }

    /// Removing an asset from the bin never deletes the user's file. (The store only holds a reference.)
    @Test func removingAnAssetLeavesTheFileAlone() async throws {
        let store = try LibraryStore.inMemory()
        let file = FileManager.default.temporaryDirectory.appendingPathComponent("wf-keep-\(UUID().uuidString).txt")
        try Data("keep me".utf8).write(to: file)
        let asset = try await store.addMediaAsset(name: "Keep", kind: .image, path: file.path, bookmark: nil, duration: nil, pixelWidth: nil, pixelHeight: nil)
        try await store.removeMediaAsset(id: asset.id)
        #expect(FileManager.default.fileExists(atPath: file.path))
    }
}
