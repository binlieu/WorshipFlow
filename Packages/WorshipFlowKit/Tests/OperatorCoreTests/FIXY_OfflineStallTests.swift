// FIX-Y item 10 (MEDIA; REVIEW-5 L16): one hung volume no longer blocks every later offline check. A check that does not return within the limit is
// abandoned for that volume (its files keep the marks they had); the other volumes are still checked; the volume is not probed again while its own
// stuck read is still out (one read at a time per volume, so threads stay bounded); when that read ends the volume is checked again.
import Testing
import Foundation
import Domain
import Persistence
@testable import OperatorCore

@MainActor
@Suite struct FIXY_OfflineStallTests {
    final class HungVolume: @unchecked Sendable {
        private let lock = NSLock()
        private var n = 0
        private var released = false
        private let gate = DispatchSemaphore(value: 0)
        var reads: Int { lock.withLock { n } }
        /// Reads of the hung volume's files never return until `release`.
        func read() { lock.withLock { n += 1 }; gate.wait() }
        func release(_ times: Int) { lock.withLock { released = true }; for _ in 0..<times { gate.signal() } }
        /// True once the stuck reads have been let go (by the test, or by the safety net).
        var wasReleased: Bool { lock.withLock { released } }
    }

    private func model(_ hung: HungVolume, missing: Set<String> = []) throws -> MediaModel {
        let store = try LibraryStore.inMemory()
        let m = MediaModel(store: store, prober: FakeProber(), isAvailable: { asset in
            if asset.path.hasPrefix("/Volumes/Hung/") { hung.read(); return true }
            return !missing.contains(asset.path)
        })
        m.offlineCheckLimit = 0.2
        DispatchQueue.global().asyncAfter(deadline: .now() + 45) { hung.release(100) }        // a safety net: a broken check ends the test instead of hanging it
        return m
    }

    @Test func aHungVolumeDoesNotBlockTheCheckOfAnotherDisk() async throws {
        let hung = HungVolume()
        let m = try model(hung, missing: ["/Volumes/Other/c.mov"])
        defer { hung.release(10) }
        _ = await m.add(url: URL(fileURLWithPath: "/Volumes/Hung/a.mov"))
        _ = await m.add(url: URL(fileURLWithPath: "/Volumes/Other/c.mov"))
        await m.refreshOffline()
        let other = try #require(m.assets.first { $0.path == "/Volumes/Other/c.mov" })
        #expect(m.offlineIDs == [other.id], "the unplugged disk's file is marked although another volume hangs")
        #expect(!hung.wasReleased, "the check returned while the hung volume's read was still stuck: it did not wait for it")
    }

    @Test func aHungVolumeIsReadByOneThreadAtATimeNoMatterHowOftenItIsAsked() async throws {
        let hung = HungVolume()
        let m = try model(hung)
        defer { hung.release(10) }
        _ = await m.add(url: URL(fileURLWithPath: "/Volumes/Hung/a.mov"))
        for _ in 0..<6 { await m.refreshOffline() }
        #expect(!hung.wasReleased && hung.reads == 1, "six checks, one stuck read: threads are bounded")
    }

    @Test func whenTheStuckReadEndsTheVolumeIsCheckedAgain() async throws {
        let hung = HungVolume()
        let m = try model(hung)
        _ = await m.add(url: URL(fileURLWithPath: "/Volumes/Hung/a.mov"))
        await m.refreshOffline()
        let first = hung.reads
        hung.release(1)                                                            // the volume answers at last
        for _ in 0..<1500 where hung.reads == first { try await Task.sleep(nanoseconds: 20_000_000); await m.finishOfflineCheck() }
        #expect(hung.reads > first, "the volume is read again after its stuck read ended")
        hung.release(10)
    }

    @Test func anAbandonedVolumeKeepsItsLastMarksAndTheNextActivationChecksAgain() async throws {
        let hung = HungVolume()
        let m = try model(hung)
        defer { hung.release(10) }
        _ = await m.add(url: URL(fileURLWithPath: "/Volumes/Hung/a.mov"))
        await m.refreshOffline()
        #expect(m.offlineIDs.isEmpty && !hung.wasReleased)
        #expect(m.lastOfflineCheck == nil, "a check that left a volume unread is not a finished check, so the next activation looks again")
    }
}
