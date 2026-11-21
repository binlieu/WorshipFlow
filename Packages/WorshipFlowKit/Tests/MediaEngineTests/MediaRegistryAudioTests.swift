// MEDIA-001: the foreground clip's volume and mute are set on the registry, so they hold before the first sound.
import Testing
import Foundation
import Domain
@testable import MediaEngine

@Suite(.serialized) struct MediaRegistryAudioTests {
    @Test func foregroundAudioIsAppliedToASourceOpenedLater() async throws {
        let url = try await redThenBlue(in: TestMedia.tempDirectory())
        let asset = MediaAsset(name: "clip", kind: .video, path: url.path, duration: 2)
        let registry = MediaRegistry()
        registry.register(asset)
        registry.setForegroundAudio(volume: 0.25, muted: false)
        var layers = MediaLayers()
        layers.startForeground(MediaSelection(asset: asset), at: 0)
        layers.setBackground(MediaSelection(asset: asset), at: 0)
        registry.apply(layers, at: 0)
        let foreground = try #require(registry.videoSource(in: .foreground))
        #expect(foreground.volume == 0.25 && !foreground.isMuted)
        // The background loop of the very same asset stays silent whatever the foreground setting is.
        #expect(try #require(registry.videoSource(in: .background)).isMuted)
        registry.closeAll()
    }

    @Test func changingTheLevelReachesTheOpenSource() async throws {
        let url = try await redThenBlue(in: TestMedia.tempDirectory())
        let asset = MediaAsset(name: "clip", kind: .video, path: url.path, duration: 2)
        let registry = MediaRegistry()
        registry.register(asset)
        var layers = MediaLayers()
        layers.startForeground(MediaSelection(asset: asset), at: 0)
        registry.apply(layers, at: 0)
        let foreground = try #require(registry.videoSource(in: .foreground))
        registry.setForegroundAudio(volume: 0.4, muted: true)
        #expect(foreground.volume == 0.4 && foreground.isMuted)
        registry.setForegroundAudio(volume: 7, muted: false)      // out of range is clamped
        #expect(foreground.volume == 1 && !foreground.isMuted)
        registry.setForegroundAudio(volume: .nan, muted: false)
        #expect(foreground.volume == 0)
        registry.closeAll()
    }

    @Test func aMutedForegroundOpensMuted() async throws {
        let url = try await redThenBlue(in: TestMedia.tempDirectory())
        let asset = MediaAsset(name: "clip", kind: .video, path: url.path, duration: 2)
        let registry = MediaRegistry()
        registry.register(asset)
        registry.setForegroundAudio(volume: 0.5, muted: true)
        var layers = MediaLayers()
        layers.startForeground(MediaSelection(asset: asset), at: 0)
        registry.apply(layers, at: 0)
        #expect(try #require(registry.videoSource(in: .foreground)).isMuted)
        registry.closeAll()
    }
}

@Suite(.serialized) struct PlayerStallWatchdogTests {
    @Test func aPlayerThatPlaysNormallyIsNeverKicked() async throws {
        let url = try await redThenBlue(in: TestMedia.tempDirectory())
        let source = try VideoPlayerSource(url: url, loops: false, duration: 2)
        source.play()
        #expect(await TestMedia.wait { _ = source.latestPixelBuffer(); return source.status() == .ended })
        #expect(source.stallRecoveries == 0)
        source.stop()
    }
}
