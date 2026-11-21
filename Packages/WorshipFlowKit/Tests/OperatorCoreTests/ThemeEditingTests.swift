// APP-001 / KI-023 / PRES-06: the theme editor's rules, the custom theme list, and the rule that a presentation's
// theme reaches the audience screen and not the broadcast one.
import Testing
import Foundation
import Domain
import Persistence
@testable import OperatorCore

@Suite struct ThemeEditingRulesTests {
    @Test func valuesAreKeptInsideWhatCanBeDrawn() {
        var theme = Theme.fullScreen
        theme.primary.style.fontSize = 5000
        theme.primary.style.outlineWidth = -3
        theme.primary.style.fontName = "   "
        theme.primary.frame = NormalizedRect(x: 0.9, y: -2, width: 0.5, height: 0)
        theme.secondary?.style.fontSize = .nan
        theme.secondary?.frame = NormalizedRect(x: .infinity, y: 0.5, width: .nan, height: 3)
        let fixed = ThemeEditing.clamped(theme)
        #expect(fixed.primary.style.fontSize == 400)
        #expect(fixed.primary.style.outlineWidth == 0)
        #expect(fixed.primary.style.fontName == ThemeEditing.defaultFontName)
        #expect(fixed.primary.frame.width == 0.5 && fixed.primary.frame.x == 0.5)     // pulled back inside the screen
        #expect(fixed.primary.frame.height == ThemeEditing.minimumFrameSide && fixed.primary.frame.y == 0)
        #expect(fixed.secondary?.style.fontSize == 64)
        let s = try? #require(fixed.secondary)
        #expect((s?.frame.x ?? -1) >= 0 && (s?.frame.x ?? 2) + (s?.frame.width ?? 2) <= 1)
        #expect((s?.frame.y ?? -1) >= 0 && (s?.frame.y ?? 2) + (s?.frame.height ?? 2) <= 1)
        #expect(ThemeEditing.clamped(Theme.fullScreen) == Theme.fullScreen)           // a good theme is unchanged
        #expect(ThemeEditing.clamped(Theme.lowerThird) == Theme.lowerThird)
    }

    @Test func thePreviewSceneIsTheAudienceSceneOfASampleSlide() {
        var theme = Theme.fullScreen
        theme.background = .color(ColorRGBA(red: 1, green: 0, blue: 0))
        theme.primary.style.fontSize = 120
        theme.secondary = nil
        let scene = ThemeEditing.previewScene(for: theme)
        #expect(scene.backgroundColor == ColorRGBA(red: 1, green: 0, blue: 0))
        #expect(scene.showsVideo == false)
        #expect(scene.textLayers.count == 1)                                          // no second language block, no second layer
        #expect(scene.textLayers.first?.style.fontSize == 120)
        #expect(scene.textLayers.first?.text == ThemeEditing.sampleLines.primary)
        let withBoth = ThemeEditing.previewScene(for: .fullScreen)
        #expect(withBoth.textLayers.count == 2 && withBoth.showsVideo)                // media background flags the video
        #expect(ThemeEditing.previewScene(for: .lowerThird).backgroundColor == .clear)
    }
}

@MainActor
@Suite struct ThemeModelTests {
    func settings(_ store: LibraryStore) -> SettingsModel {
        SettingsModel(store: store, defaultProfiles: {
            [ScreenProfile(name: "Audience", role: .audience, destination: .window),
             ScreenProfile(name: "Broadcast", role: .broadcast, destination: .window)]
        })
    }

    func red() -> ThemeBackground { .color(ColorRGBA(red: 1, green: 0, blue: 0)) }

    @Test func createDuplicateRenameAndListInOrder() async throws {
        let store = try LibraryStore.inMemory()
        let s = settings(store)
        await s.load()
        #expect(s.themes.map(\.name) == ["Full screen", "Lower third"])
        let made = try #require(s.createTheme(name: " Zebra "))
        #expect(made.name == "Zebra" && made.id != Theme.fullScreenID && made.primary == Theme.fullScreen.primary)
        let copy = try #require(s.duplicateTheme(Theme.lowerThirdID))                  // a built-in can be copied
        #expect(copy.name == "Lower third copy" && copy.background == .transparent && copy.id != Theme.lowerThirdID)
        #expect(s.customThemes.map(\.name) == ["Lower third copy", "Zebra"])           // by folded name
        s.renameTheme(made.id, to: "Alpha")
        #expect(s.customThemes.map(\.name) == ["Alpha", "Lower third copy"])
        #expect(s.createTheme(name: "  ") == nil && s.lastError?.contains("a name is needed") == true)
        s.dismissError()
        s.renameTheme(made.id, to: "")
        #expect(s.customThemes.first?.name == "Alpha" && s.lastError != nil)
        s.renameTheme(Theme.fullScreenID, to: "Hacked")                                // built-ins cannot be renamed
        #expect(s.themes.first?.name == "Full screen")
        await s.flush()
        let again = settings(store)
        await again.load()
        #expect(again.customThemes.map(\.name) == ["Alpha", "Lower third copy"])
    }

    @Test func editsAreClampedSavedAndOnlyForCustomThemes() async throws {
        let store = try LibraryStore.inMemory()
        let s = settings(store)
        await s.load()
        let t = try #require(s.createTheme(name: "Mine"))
        var changes = 0
        s.onAppearanceChange = { changes += 1 }
        s.updateTheme(t.id) {
            $0.background = .color(ColorRGBA(red: 0, green: 0, blue: 1))
            $0.primary.style.fontSize = 9999
            $0.primary.alignment = .leading
            $0.secondary?.style.fontName = "Georgia"
            $0.name = "ignored rename"
            $0.id = UUID()
        }
        let saved = try #require(s.customThemes.first)
        #expect(saved.id == t.id && saved.name == "Mine")
        #expect(saved.primary.style.fontSize == 400 && saved.primary.alignment == .leading)
        #expect(saved.secondary?.style.fontName == "Georgia")
        #expect(changes == 1)
        s.updateTheme(t.id) { $0.primary.style.fontSize = 400 }                        // no change: nothing published
        #expect(changes == 1)
        s.updateTheme(Theme.fullScreenID) { $0.background = .transparent }             // a built-in is not editable
        #expect(s.themes.first == Theme.fullScreen && changes == 1)
        await s.flush()
        #expect(try await store.themes().first == saved)
    }

    @Test func deletingAThemeClearsScreensAndPresentationsThatUsedIt() async throws {
        let store = try LibraryStore.inMemory()
        let s = settings(store)
        await s.load()
        let workspace = WorkspaceModel(store: store)
        await workspace.load()
        let p = try #require(await workspace.importLyrics(title: "Song", primaryText: "one", secondaryText: nil, maxLines: 1))
        let t = try #require(s.createTheme(name: "Doomed"))
        let audience = try #require(s.profiles.first { $0.role == .audience })
        s.setTheme(t.id, forScreen: audience.id)
        await s.flush()
        await workspace.setTheme(t.id, forPresentation: p.id)
        #expect(workspace.presentationThemes[p.id] == t.id)

        await s.deleteTheme(t.id)
        await workspace.themesChanged()
        #expect(s.customThemes.isEmpty && s.lastError == nil)
        #expect(s.screenLook(for: audience.id).themeID == nil)
        #expect(workspace.presentationThemes[p.id] == nil)
        #expect(workspace.presentations.first { $0.id == p.id }?.themeID == nil)
        await s.flush()
        #expect(try await store.looks().first?.screens[audience.id]?.themeID == nil)
        await s.deleteTheme(Theme.fullScreenID)                                        // a built-in is not deletable
        #expect(s.themes.count == 2)
    }

    // MARK: The presentation's theme reaches the outputs (PRES-06)

    @Test func aPresentationThemeChangesTheAudienceSceneAndNotTheBroadcastOne() async throws {
        let store = try LibraryStore.inMemory()
        let s = settings(store)
        await s.load()
        let workspace = WorkspaceModel(store: store)
        await workspace.load()
        let p = try #require(await workspace.importLyrics(title: "Song", primaryText: "Amazing grace", secondaryText: nil, maxLines: 1))
        await workspace.openPresentation(p.id)
        let theme = try #require(s.createTheme(name: "Red room"))
        s.updateTheme(theme.id) { $0.background = red(); $0.primary.style.fontSize = 111 }
        await s.flush()                                   // the store must have the theme before a presentation can use it
        let audience = try #require(s.profiles.first { $0.role == .audience })
        let broadcast = try #require(s.profiles.first { $0.role == .broadcast })

        func scenes() -> PublishedScenes {
            PublishedScenes(state: workspace.show, clockText: nil, profiles: s.profiles, themes: s.themes,
                            look: s.currentLook, props: s.props, presentationThemeID: workspace.liveThemeID)
        }
        await workspace.goLive()
        let before = scenes()
        #expect(before.scene(forScreen: audience.id).showsVideo)                       // the default theme: the video background
        #expect(workspace.liveThemeID == nil)

        await workspace.setTheme(theme.id, forPresentation: p.id)
        #expect(workspace.liveThemeID == theme.id && workspace.openThemeID == theme.id)
        let after = scenes()
        let aud = after.scene(forScreen: audience.id)
        #expect(aud.backgroundColor == ColorRGBA(red: 1, green: 0, blue: 0) && !aud.showsVideo)
        #expect(aud.textLayers.first?.style.fontSize == 111)
        #expect(after.scene(forScreen: broadcast.id) == before.scene(forScreen: broadcast.id))   // broadcast ignores it
        #expect(after.scene(forScreen: broadcast.id).textLayers.first?.text == "Amazing grace")

        // A Look theme on the audience screen wins over the presentation's theme.
        s.setTheme(Theme.lowerThirdID, forScreen: audience.id)
        #expect(scenes().scene(forScreen: audience.id).backgroundColor == .clear)
        s.setTheme(nil, forScreen: audience.id)

        // Choosing "default" returns the audience to the role default.
        await workspace.setTheme(nil, forPresentation: p.id)
        #expect(scenes().scene(forScreen: audience.id) == before.scene(forScreen: audience.id))
    }

    @Test func theLiveThemeBelongsToTheLivePresentationNotTheOpenOne() async throws {
        let store = try LibraryStore.inMemory()
        let s = settings(store)
        await s.load()
        let workspace = WorkspaceModel(store: store)
        await workspace.load()
        let a = try #require(await workspace.importLyrics(title: "A", primaryText: "a", secondaryText: nil, maxLines: 1))
        let b = try #require(await workspace.importLyrics(title: "B", primaryText: "b", secondaryText: nil, maxLines: 1))
        let t = try #require(s.createTheme(name: "T"))
        await s.flush()
        await workspace.setTheme(t.id, forPresentation: b.id)
        await workspace.openPresentation(a.id)
        await workspace.goLive()
        await workspace.openPresentation(b.id)
        #expect(workspace.openThemeID == t.id)
        #expect(workspace.liveThemeID == nil)                                          // A is live and has no theme
        await workspace.goLive()
        #expect(workspace.liveThemeID == t.id)
    }

    @Test func aThemeThatDoesNotExistIsRefusedWithAMessage() async throws {
        let store = try LibraryStore.inMemory()
        let workspace = WorkspaceModel(store: store)
        await workspace.load()
        let p = try #require(await workspace.importLyrics(title: "A", primaryText: "a", secondaryText: nil, maxLines: 1))
        var notified = 0
        workspace.onAppearanceChange = { notified += 1 }
        await workspace.setTheme(UUID(), forPresentation: p.id)
        #expect(workspace.lastError?.contains("no longer exists") == true)
        #expect(workspace.presentationThemes.isEmpty && notified == 0)
        await workspace.setTheme(Theme.lowerThirdID, forPresentation: p.id)           // a built-in id is fine
        #expect(workspace.presentationThemes[p.id] == Theme.lowerThirdID && notified == 1)
    }

    @Test func aThemeOfAPresentationInAnotherLibraryIsFoundWhenItsPlaylistItemOpens() async throws {
        let store = try LibraryStore.inMemory()
        let workspace = WorkspaceModel(store: store)
        await workspace.load()
        let p = try #require(await workspace.importLyrics(title: "A", primaryText: "a", secondaryText: nil, maxLines: 1))
        await workspace.setTheme(Theme.lowerThirdID, forPresentation: p.id)
        await workspace.addToPlaylist(p.id)
        await workspace.createLibrary(name: "Other")                                   // another library is now selected
        let fresh = WorkspaceModel(store: store)
        await fresh.load()
        await fresh.selectLibrary(try #require(fresh.libraries.last).id)
        let item = try #require(fresh.playlistItems.first)
        await fresh.openPlaylistItem(item.id)
        #expect(fresh.openThemeID == Theme.lowerThirdID)
    }
}
