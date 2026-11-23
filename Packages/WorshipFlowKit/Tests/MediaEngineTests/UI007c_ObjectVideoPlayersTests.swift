// UI-007c (SLIDE, MEDIA): the players behind video objects: opened from the control side, looked up from the render side, bounded, closed when the
// slide leaves the screen. Real (tiny) movies written at test time; no assertion is about how long anything takes.
import Testing
import Foundation
import Domain
@testable import MediaEngine

@Suite(.serialized) struct UI007c_ObjectVideoPlayersTests {
    private func request(_ url: URL, id: UUID = UUID(), loops: Bool = true, muted: Bool = true) -> ObjectVideoRequest {
        ObjectVideoRequest(assetID: id, url: url, loops: loops, muted: muted, duration: 2)
    }

    @Test func aRequestedClipOpensPlaysAndDeliversFramesThroughTheLookup() async throws {
        let url = try await redThenBlue(in: TestMedia.tempDirectory())
        let players = ObjectVideoPlayers()
        let r = request(url)
        #expect(players.pixelBuffer(for: r.assetID) == nil)                  // nothing is open until the control side says so
        players.apply([r])
        #expect(players.openAssetIDs == [r.assetID])
        #expect(await TestMedia.wait { isRed(players.pixelBuffer(for: r.assetID)) })
        players.closeAll()
        #expect(players.openAssetIDs.isEmpty && players.pixelBuffer(for: r.assetID) == nil)
    }

    @Test func aClipThatDropsOutOfTheRequestsIsClosedAndOneThatStaysIsNotReopened() async throws {
        let dir = try TestMedia.tempDirectory()
        let a = request(try await redThenBlue(in: dir)), b = request(try await redThenBlue(in: dir))
        let players = ObjectVideoPlayers()
        players.apply([a, b])
        #expect(players.openAssetIDs == [a.assetID, b.assetID])
        #expect(await TestMedia.wait { isRed(players.pixelBuffer(for: a.assetID)) })
        let delivered = players.pixelBuffer(for: a.assetID)
        players.apply([a])                                                    // b leaves the screen
        #expect(players.openAssetIDs == [a.assetID])
        #expect(players.pixelBuffer(for: b.assetID) == nil)
        #expect(players.pixelBuffer(for: a.assetID) != nil && delivered != nil, "the clip that stayed keeps playing")
        players.apply([])
        #expect(players.openAssetIDs.isEmpty)
    }

    @Test func aChangeOfLoopOrSoundReopensTheClipWithTheNewSetting() async throws {
        let url = try await redThenBlue(in: TestMedia.tempDirectory())
        let players = ObjectVideoPlayers()
        let id = UUID()
        players.apply([request(url, id: id, loops: true, muted: true)])
        players.apply([request(url, id: id, loops: false, muted: false)])
        #expect(players.openAssetIDs == [id])
        #expect(await TestMedia.wait { isRed(players.pixelBuffer(for: id)) })
        players.closeAll()
    }

    @Test func noMoreThanTheLimitAreOpenAndTheRestAreReportedNotDrawn() async throws {
        let url = try await redThenBlue(in: TestMedia.tempDirectory())
        let players = ObjectVideoPlayers()
        let requests = (0..<(ObjectVideoPlayers.limit + 2)).map { _ in request(url) }
        players.apply(requests)
        #expect(players.openAssetIDs.count == ObjectVideoPlayers.limit)
        #expect(players.skippedAssetIDs == Set(requests.suffix(2).map(\.assetID)))
        #expect(players.openAssetIDs == Set(requests.prefix(ObjectVideoPlayers.limit).map(\.assetID)))
        players.closeAll()
    }

    @Test func aMissingFileIsReportedUnavailableAndTheOthersStillPlay() async throws {
        let url = try await redThenBlue(in: TestMedia.tempDirectory())
        let players = ObjectVideoPlayers()
        let gone = request(URL(fileURLWithPath: "/nonexistent/clip.mov")), ok = request(url)
        let told = Locked<[UUID]>([])
        players.setOnAvailabilityChange { id in told.append(id) }
        players.apply([gone, ok])
        #expect(players.unavailableAssetIDs == [gone.assetID] && players.openAssetIDs == [ok.assetID])
        #expect(told.value == [gone.assetID])
        #expect(await TestMedia.wait { isRed(players.pixelBuffer(for: ok.assetID)) })
        players.apply([ok])                                                   // the missing clip leaves the slide: no longer reported
        #expect(players.unavailableAssetIDs.isEmpty)
        players.closeAll()
    }

    @Test func theRegistryClosesAClipThatLeavesTheBinAndCloseAllClosesThemToo() async throws {
        let url = try await redThenBlue(in: TestMedia.tempDirectory())
        let registry = MediaRegistry()
        let r = request(url)
        registry.objectVideos.apply([r])
        #expect(await TestMedia.wait { isRed(registry.currentObjectPixelBuffer(for: r.assetID)) })
        registry.unregister(r.assetID)
        #expect(registry.objectVideos.openAssetIDs.isEmpty && registry.currentObjectPixelBuffer(for: r.assetID) == nil)
        registry.objectVideos.apply([r])
        registry.closeAll()
        #expect(registry.objectVideos.openAssetIDs.isEmpty)
    }
}

/// A value shared with a callback on another thread.
final class Locked<Value>: @unchecked Sendable {
    private let lock = NSLock()
    private var stored: Value
    init(_ value: Value) { stored = value }
    var value: Value { lock.lock(); defer { lock.unlock() }; return stored }
    func append<T>(_ item: T) where Value == [T] { lock.lock(); stored.append(item); lock.unlock() }
}
