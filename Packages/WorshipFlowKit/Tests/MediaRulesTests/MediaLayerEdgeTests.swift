// MEDIA-002: edges the coordinator tests do not cover (transport corners, Look gating, stored scenes).
import Testing
import Foundation
@testable import Domain

@Suite struct MediaTransportEdgeTests {
    @Test func pausingAnEndedClipKeepsItEnded() {
        var t = MediaTransport(duration: 10, loops: false)
        t.play(at: 0)
        t.pause(at: 20)
        #expect(t.status(at: 25) == .ended && t.position(at: 25) == 10)
    }

    @Test func seekingAnEndedClipPlaysFromThere() {
        var t = MediaTransport(duration: 10, loops: false)
        t.play(at: 0)
        t.seek(to: 4, at: 30)
        #expect(t.status(at: 32) == .playing && t.position(at: 32) == 6)
    }

    @Test func seekThenPlayContinuesFromTheSeek() {
        var t = MediaTransport(duration: 10, loops: false)
        t.seek(to: 7, at: 0)
        #expect(t.status(at: 5) == .idle)
        t.play(at: 5)
        #expect(t.position(at: 6) == 8)
        var end = MediaTransport(duration: 10, loops: false)
        end.seek(to: 10, at: 0); end.play(at: 1)               // from the very end, play restarts
        #expect(end.position(at: 2) == 1)
    }

    @Test func nonFiniteInputsAreIgnored() {
        var t = MediaTransport(duration: .nan, loops: false)
        #expect(t.duration == 0)
        t = MediaTransport(duration: 10, loops: false)
        t.play(at: .nan); t.seek(to: .infinity, at: 0); t.seek(to: .nan, at: 0)
        #expect(t.status(at: 0) == .idle && t.position(at: 0) == 0)
        t.play(at: 5)
        #expect(t.position(at: .nan) == 0 && t.position(at: 1) == 0)   // a clock that went backwards never gives a negative position
    }

    @Test func loopingPauseKeepsTheWrappedPosition() {
        var t = MediaTransport(duration: 20, loops: true)
        t.play(at: 0)
        t.pause(at: 45)
        #expect(t.status(at: 100) == .paused && t.position(at: 100) == 5)
        t.seek(to: 20, at: 100)                                  // the end of a loop is its start
        #expect(t.position(at: 100) == 0)
    }
}

@Suite struct MediaLayerEdgeTests {
    func state() -> ShowState {
        var s = ShowState()
        s.apply(.load(ShowDeck(presentationID: UUID(), slides: [SlideContent(primary: "One", secondary: "Hai")])))
        s.apply(.trigger(index: 0))
        return s
    }
    let clip = MediaSelection(assetID: UUID(), kind: .video, duration: 30)

    @Test func foregroundFollowsTheSlideLayerOfTheLook() {
        var layers = MediaLayers(); layers.startForeground(clip, at: 0)
        let propsOnly = ScreenLook(themeID: nil, visibleLayers: [.props])
        let hidden = SceneComposer.scene(for: .broadcast, state: state(), theme: .lowerThird, look: propsOnly, props: [], media: layers)
        #expect(hidden.foregroundMedia == nil)                  // a props-only screen never gets a full-frame clip
        let shown = SceneComposer.scene(for: .broadcast, state: state(), theme: .lowerThird, look: .standard, props: [], media: layers)
        #expect(shown.foregroundMedia == .video(clip.assetID) && shown.textLayers.isEmpty)
    }

    @Test func foregroundShowsWhileTheSlideTextIsCleared() {
        var layers = MediaLayers(); layers.startForeground(clip, at: 0)
        var s = state(); s.apply(.clear)
        #expect(SceneComposer.scene(for: .audience, state: s, theme: .fullScreen, look: .standard, props: [], media: layers).foregroundMedia == .video(clip.assetID))
    }

    @Test func aMediaBackgroundOnAnImageThemeDoesNotShow() {
        var layers = MediaLayers(); layers.setBackground(clip, at: 0)
        var theme = Theme.fullScreen
        theme.background = .image(path: "/tmp/x.png")
        let scene = SceneComposer.scene(for: .audience, state: state(), theme: theme, look: .standard, props: [], media: layers)
        #expect(scene.backgroundMedia == nil && scene.backgroundImage != nil && scene.showsVideo == false)
    }

    @Test func rejectedAudioLeavesTheCurrentLayerAlone() {
        var layers = MediaLayers(); layers.setBackground(clip, at: 0)
        layers.setBackground(MediaSelection(assetID: UUID(), kind: .audio, duration: 5), at: 1)
        #expect(layers.background?.selection == clip)
    }

    @Test func stateAndStoredScenesRoundTrip() throws {
        var layers = MediaLayers(); layers.setBackground(clip, at: 0); layers.startForeground(clip, at: 3)
        let data = try JSONEncoder().encode(layers)
        #expect(try JSONDecoder().decode(MediaLayers.self, from: data) == layers)

        // A scene written before media layers existed still decodes, with no media.
        var scene = SceneDescription(backgroundColor: .black, textLayers: [])
        scene.backgroundMedia = .image(clip.assetID)
        let json = try JSONEncoder().encode(scene)
        var object = try #require(JSONSerialization.jsonObject(with: json) as? [String: Any])
        object["backgroundMedia"] = nil
        let old = try JSONDecoder().decode(SceneDescription.self, from: JSONSerialization.data(withJSONObject: object))
        #expect(old.backgroundMedia == nil && old.foregroundMedia == nil)
        #expect(try JSONDecoder().decode(SceneDescription.self, from: json) == scene)
    }

    @Test func selectionFromAnAsset() {
        let asset = MediaAsset(name: "Loop", kind: .video, path: "/tmp/loop.mov", duration: 12)
        #expect(MediaSelection(asset: asset) == MediaSelection(assetID: asset.id, kind: .video, duration: 12))
    }
}
