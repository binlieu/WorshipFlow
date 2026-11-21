// MEDIA-010 items 1 and 4 (selection): a choice in the media bin is a LIVE override. It never writes to the open
// presentation, its slides or its theme, and it does not change Preview. Single click selects, double click sends live.
import Testing
import Foundation
import Domain
import Persistence
@testable import OperatorCore

@MainActor
@Suite struct MEDIA010_LiveOverrideTests {
    struct Rig {
        let store: LibraryStore
        let workspace: WorkspaceModel
        let media: MediaRig
        let loop: MediaAsset
        let other: MediaAsset
    }

    static let colourTheme = Theme(id: UUID(), name: "Plain", background: .color(ColorRGBA(red: 0.1, green: 0.1, blue: 0.4)),
                                   primary: Theme.fullScreen.primary, secondary: Theme.fullScreen.secondary)

    private func rig() async throws -> Rig {
        let store = try LibraryStore.inMemory()
        let workspace = WorkspaceModel(store: store, clock: ManualSaveClock())
        await workspace.load()
        let media = try MediaRig(store: store)
        await media.model.load()
        let loop = await media.add("loop.mov")
        let other = await media.add("other.mov")
        workspace.onShowChange = { state in media.model.showStateChanged(isLive: !state.isStopped, isBlackedOut: state.isBlackedOut) }
        let song = try #require(await workspace.importLyrics(title: "Song", primaryText: "one\n\ntwo\n\nthree", secondaryText: nil, maxLines: 1))
        await workspace.openPresentation(song.id)
        await workspace.goLive()
        return Rig(store: store, workspace: workspace, media: media, loop: loop, other: other)
    }

    private func json<T: Encodable>(_ value: T) throws -> String {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        return String(decoding: try encoder.encode(value), as: UTF8.self)
    }

    private func liveScene(_ r: Rig, theme: Theme) -> SceneDescription {
        let layers = LiveMedia.effective(override: r.media.model.layers, slide: r.workspace.show.liveSlide, at: 1000)
        return SceneComposer.scene(for: .audience, state: r.workspace.show, theme: theme, look: .standard, props: [], media: layers)
    }

    private func previewScene(_ r: Rig, theme: Theme) throws -> SceneDescription {
        let slide = r.workspace.slides[r.workspace.show.selectedIndex].content
        return SceneComposer.scene(for: .audience, state: r.workspace.show, theme: theme, look: .standard, props: [],
                                   media: LiveMedia.preview(slide: slide, at: 1000))
    }

    @Test func aBinChoiceChangesLiveAndLeavesStoredSlidesAndPreviewUnchanged() async throws {
        for theme in [Theme.fullScreen, Self.colourTheme] {
            let r = try await rig()
            let storedBefore = try json(try await r.store.slides(of: try #require(r.workspace.openPresentationID)))
            let openBefore = try json(r.workspace.slides)
            let previewBefore = try json(try previewScene(r, theme: theme))
            let liveBefore = liveScene(r, theme: theme)
            #expect(liveBefore.backgroundMedia == nil)

            r.media.model.setBackground(r.loop.id)
            await r.media.model.flush()

            #expect(liveScene(r, theme: theme).backgroundMedia == .video(r.loop.id), "Live takes the choice")
            #expect(try json(try await r.store.slides(of: try #require(r.workspace.openPresentationID))) == storedBefore, "stored slides")
            #expect(try json(r.workspace.slides) == openBefore, "the open presentation's slides")
            #expect(try json(try previewScene(r, theme: theme)) == previewBefore, "Preview is byte for byte the same")
            #expect(r.workspace.slides.allSatisfy { $0.content.background == nil })
        }
    }

    @Test func aBinChoiceNeverTouchesThePresentationsTheme() async throws {
        let r = try await rig()
        let themeBefore = r.workspace.openThemeID
        r.media.model.setBackground(r.loop.id)
        r.media.model.playForeground(r.other.id)
        #expect(r.workspace.openThemeID == themeBefore)
    }

    @Test func theOverrideSurvivesNextAndIsReplacedByTheNextChoice() async throws {
        let r = try await rig()
        r.media.model.setBackground(r.loop.id)
        await r.workspace.next()
        await r.workspace.next()
        #expect(r.workspace.show.liveIndex == 2)
        #expect(r.media.model.layers.background?.selection.assetID == r.loop.id)
        #expect(liveScene(r, theme: Self.colourTheme).backgroundMedia == .video(r.loop.id))
        r.media.model.setBackground(r.other.id)
        #expect(liveScene(r, theme: Self.colourTheme).backgroundMedia == .video(r.other.id))
    }

    @Test func theOverrideStaysWhenTheNextPlaylistItemGoesLiveAndWhenTheShowStops() async throws {
        // Decision: it stays until it is cleared or replaced. Stop and a new deck do not drop it.
        let r = try await rig()
        r.media.model.setBackground(r.loop.id)
        r.media.model.showStateChanged(isLive: true)       // another item went live
        #expect(r.media.model.layers.background != nil)
        r.media.model.showStateChanged(isLive: false)      // Stop
        #expect(r.media.model.layers.background != nil)
        #expect(r.media.model.hasLiveBackgroundOverride)
    }

    @Test func theDropButtonReturnsToTheSlidesOwnBackground() async throws {
        let r = try await rig()
        r.media.model.setBackground(r.loop.id)
        #expect(r.media.model.hasLiveBackgroundOverride)
        r.media.model.dropBackgroundOverride()
        #expect(!r.media.model.hasLiveBackgroundOverride)
        #expect(liveScene(r, theme: Self.colourTheme).backgroundMedia == nil)
        #expect(r.workspace.slides.allSatisfy { $0.content.background == nil }, "dropping it writes nothing either")
    }

    @Test func aBinChoiceReportsItselfSoAClearedBackgroundComesBack() async throws {
        let r = try await rig()
        var chosen = 0
        r.media.model.onBackgroundChosen = { chosen += 1 }
        r.media.model.setBackground(r.loop.id)
        #expect(chosen == 1)
        r.media.model.setBackground(r.loop.id)      // the same choice again changes nothing
        #expect(chosen == 1)
    }

    // MARK: single click selects, double click sends live

    @Test func singleClickSelectsAndOnlyADoubleClickSendsLive() {
        let video = MediaAsset(name: "v", kind: .video, path: "/m/v.mov", duration: 5)
        let sound = MediaAsset(name: "s", kind: .audio, path: "/m/s.mp3", duration: 5)
        let one = MediaBinInteraction.tap(count: 1, asset: video, layer: .background)
        #expect(one.select == video.id && one.sendLive == nil)
        let two = MediaBinInteraction.tap(count: 2, asset: video, layer: .background)
        #expect(two.select == video.id && two.sendLive == .setBackground(video.id))
        let foreground = MediaBinInteraction.tap(count: 2, asset: video, layer: .foreground)
        #expect(foreground.sendLive == .playForeground(video.id))
        #expect(MediaBinInteraction.tap(count: 1, asset: sound, layer: .background).sendLive == nil)
        #expect(MediaBinInteraction.tap(count: 2, asset: sound, layer: .background).sendLive == .playAudio(sound.id))
    }
}
