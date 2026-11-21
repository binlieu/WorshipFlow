// FIX-B R13: the theme of the live presentation is captured when it is triggered. Choosing another theme for it
// changes preview at once and the screens from the next trigger. (Editing a theme that is in use still changes the
// screens at once: KI-027, accepted and unchanged.)
import Testing
import Foundation
import Domain
import Persistence
@testable import OperatorCore

@MainActor
@Suite struct LiveThemeCaptureTests {
    struct Rig {
        let workspace: WorkspaceModel
        let settings: SettingsModel
        let a: Presentation
        let b: Presentation
    }

    private func rig() async throws -> Rig {
        let store = try LibraryStore.inMemory()
        let settings = SettingsModel(store: store, defaultProfiles: SettingsModelTests.defaults)
        await settings.load()
        let workspace = WorkspaceModel(store: store)
        await workspace.load()
        let a = try #require(await workspace.importLyrics(title: "A", primaryText: "a1\n\na2", secondaryText: nil, maxLines: 1))
        let b = try #require(await workspace.importLyrics(title: "B", primaryText: "b1", secondaryText: nil, maxLines: 1))
        await workspace.addToPlaylist(a.id)
        await workspace.addToPlaylist(b.id)
        return Rig(workspace: workspace, settings: settings, a: a, b: b)
    }

    @Test func choosingAThemeForTheLivePresentationChangesPreviewAtOnceAndTheScreensFromTheNextTrigger() async throws {
        let r = try await rig()
        await r.workspace.setTheme(Theme.fullScreenID, forPresentation: r.a.id)
        await r.workspace.openPresentation(r.a.id)
        await r.workspace.goLive()
        #expect(r.workspace.shownThemeID == Theme.fullScreenID)

        await r.workspace.setTheme(Theme.lowerThirdID, forPresentation: r.a.id)
        #expect(r.workspace.openThemeID == Theme.lowerThirdID)           // preview follows at once
        #expect(r.workspace.shownThemeID == Theme.fullScreenID)          // the audience does not change under the operator

        await r.workspace.goLive()                                       // the next trigger
        #expect(r.workspace.shownThemeID == Theme.lowerThirdID)
    }

    @Test func movingToTheNextSlideOfTheLiveSongDoesNotApplyTheNewTheme() async throws {
        let r = try await rig()
        await r.workspace.openPresentation(r.a.id)
        await r.workspace.goLive()
        await r.workspace.setTheme(Theme.lowerThirdID, forPresentation: r.a.id)
        await r.workspace.next()
        #expect(r.workspace.show.liveIndex == 1)
        #expect(r.workspace.shownThemeID == nil)
    }

    @Test func steppingIntoTheNextPlaylistItemCapturesThatItemsTheme() async throws {
        let r = try await rig()
        await r.workspace.setTheme(Theme.lowerThirdID, forPresentation: r.b.id)
        await r.workspace.openPlaylistItem(r.workspace.playlistItems[0].id)
        await r.workspace.goLive()
        await r.workspace.next()
        await r.workspace.next()                                         // into B
        #expect(r.workspace.show.liveDeck?.presentationID == r.b.id)
        #expect(r.workspace.shownThemeID == Theme.lowerThirdID)
    }

    @Test func theFirstNextFromAStoppedShowCapturesTheTheme() async throws {
        let r = try await rig()
        await r.workspace.setTheme(Theme.lowerThirdID, forPresentation: r.a.id)
        await r.workspace.openPresentation(r.a.id)
        await r.workspace.next()
        #expect(r.workspace.shownThemeID == Theme.lowerThirdID)
    }

    @Test func stopForgetsTheCapturedTheme() async throws {
        let r = try await rig()
        await r.workspace.setTheme(Theme.lowerThirdID, forPresentation: r.a.id)
        await r.workspace.openPresentation(r.a.id)
        await r.workspace.goLive()
        r.workspace.stop()
        #expect(r.workspace.shownThemeID == nil)
    }

    @Test func editingAThemeThatIsInUseStillChangesTheScreensAtOnce() async throws {
        let r = try await rig()
        let theme = try #require(r.settings.createTheme(name: "Red"))
        await r.settings.flush()
        await r.workspace.setTheme(theme.id, forPresentation: r.a.id)
        await r.workspace.openPresentation(r.a.id)
        await r.workspace.goLive()
        let audience = try #require(r.settings.profiles.first { $0.role == .audience })
        func scene() -> SceneDescription {
            PublishedScenes(state: r.workspace.show, clockText: nil, profiles: r.settings.profiles, themes: r.settings.themes,
                            look: r.settings.currentLook, props: r.settings.props, presentationThemeID: r.workspace.shownThemeID)
                .scene(forScreen: audience.id)
        }
        let before = scene()
        r.settings.updateTheme(theme.id) { $0.background = .color(ColorRGBA(red: 1, green: 0, blue: 0)) }
        #expect(scene() != before)                                       // KI-027: unchanged
    }
}
