// MEDIA-010 item 3 at the player: the background video's sound level reaches the open player, is applied to a player
// opened later, and does not disturb the foreground. (The earlier rule "a background is always muted" becomes "muted
// until the operator says otherwise".)
import Testing
import Foundation
import Domain
@testable import MediaEngine

@Suite(.serialized) struct MEDIA010_RegistryBackgroundAudioTests {
    @Test func aBackgroundStartsMutedAndTheForegroundSettingDoesNotUnmuteIt() async throws {
        let url = try await redThenBlue(in: TestMedia.tempDirectory())
        let asset = MediaAsset(name: "clip", kind: .video, path: url.path, duration: 2)
        let registry = MediaRegistry()
        registry.register(asset)
        registry.setForegroundAudio(volume: 1, muted: false)
        var layers = MediaLayers()
        layers.setBackground(MediaSelection(asset: asset), at: 0)
        registry.apply(layers, at: 0)
        #expect(try #require(registry.videoSource(in: .background)).isMuted)
        registry.closeAll()
    }

    @Test func unmutingTheBackgroundReachesTheOpenPlayer() async throws {
        let url = try await redThenBlue(in: TestMedia.tempDirectory())
        let asset = MediaAsset(name: "clip", kind: .video, path: url.path, duration: 2)
        let registry = MediaRegistry()
        registry.register(asset)
        var layers = MediaLayers()
        layers.setBackground(MediaSelection(asset: asset), at: 0)
        registry.apply(layers, at: 0)
        let background = try #require(registry.videoSource(in: .background))
        registry.setBackgroundAudio(volume: 0.6, muted: false)
        #expect(!background.isMuted && background.volume == 0.6, "the state heard is the state asked for")
        registry.setBackgroundAudio(volume: 0.6, muted: true)
        #expect(background.isMuted)
        registry.closeAll()
    }

    @Test func theChoiceHoldsForABackgroundOpenedLaterAndLeavesTheForegroundAlone() async throws {
        let url = try await redThenBlue(in: TestMedia.tempDirectory())
        let asset = MediaAsset(name: "clip", kind: .video, path: url.path, duration: 2)
        let registry = MediaRegistry()
        registry.register(asset)
        registry.setForegroundAudio(volume: 0.25, muted: true)
        registry.setBackgroundAudio(volume: 0.5, muted: false)
        var layers = MediaLayers()
        layers.setBackground(MediaSelection(asset: asset), at: 0)
        layers.startForeground(MediaSelection(asset: asset), at: 0)
        registry.apply(layers, at: 0)
        let background = try #require(registry.videoSource(in: .background))
        let foreground = try #require(registry.videoSource(in: .foreground))
        #expect(!background.isMuted && background.volume == 0.5)
        #expect(foreground.isMuted && foreground.volume == 0.25)
        registry.closeAll()
    }
}
