// FIX-G items 4, 5, 6, 12 and 14 (MEDIA-010): hot folders must never block the main thread or the launch, never kill a clip that is on
// air, never scan without bound, and follow a folder that was moved. No file system, no watcher, no wall-clock time: fakes
// for the lister, the watcher, the bookmark door and the prober; "time" is the number of scans.
import Testing
import Foundation
import Domain
import Persistence
@testable import OperatorCore

/// The bookmark door: answers from a table, records the thread it was called on, and can hold a call until released.
final class FakeAccess: FolderAccessing, @unchecked Sendable {
    private let lock = NSLock()
    private var answers: [UUID: FolderResolution] = [:]
    private(set) var threads: [Bool] = []          // true = main thread
    private(set) var forgotten: [UUID] = []
    private var gate: DispatchSemaphore?

    func answer(_ id: UUID, _ resolution: FolderResolution) { lock.lock(); answers[id] = resolution; lock.unlock() }
    func holdCalls() { lock.lock(); gate = DispatchSemaphore(value: 0); lock.unlock() }
    func release() { lock.lock(); let g = gate; gate = nil; lock.unlock(); g?.signal() }
    var calledOnMainThread: Bool { lock.lock(); defer { lock.unlock() }; return threads.contains(true) }
    var callCount: Int { lock.lock(); defer { lock.unlock() }; return threads.count }

    func resolve(_ folder: HotFolder) -> FolderResolution? {
        lock.lock(); threads.append(Thread.isMainThread); let g = gate; let answer = answers[folder.id]; lock.unlock()
        g?.wait()
        g?.signal()
        return answer
    }
    func forget(_ id: UUID) { lock.lock(); forgotten.append(id); lock.unlock() }
}

/// A lister that can be held (to see how many run at once) or made to fail with a chosen error.
final class ScriptedListing: FolderListing, @unchecked Sendable {
    let inner: FakeFolders
    private let lock = NSLock()
    private var gate: DispatchSemaphore?
    private var failure: FolderListingError?
    private var running = 0
    private(set) var maxRunning = 0
    private(set) var calls = 0
    init(_ inner: FakeFolders) { self.inner = inner }
    func hold() { lock.lock(); gate = DispatchSemaphore(value: 0); lock.unlock() }
    func release() { lock.lock(); let g = gate; gate = nil; lock.unlock(); g?.signal() }
    func fail(with error: FolderListingError?) { lock.lock(); failure = error; lock.unlock() }

    func list(folder path: String) throws -> [FolderFile] {
        lock.lock(); calls += 1; running += 1; maxRunning = max(maxRunning, running); let g = gate; let f = failure; lock.unlock()
        defer { lock.lock(); running -= 1; lock.unlock() }
        g?.wait()
        g?.signal()
        if let f { throw f }
        return try inner.list(folder: path)
    }
}

/// Counts probes by file name and fails the files whose name starts with "bad".
final class CountingProber: MediaProber, @unchecked Sendable {
    private let lock = NSLock()
    private(set) var probes: [String] = []
    private func record(_ name: String) { lock.lock(); probes.append(name); lock.unlock() }
    func probe(url: URL) async throws -> MediaProbeResult {
        record(url.lastPathComponent)
        return try await FakeProber().probe(url: url)
    }
    func count(_ name: String) -> Int { lock.lock(); defer { lock.unlock() }; return probes.filter { $0 == name }.count }
}

@MainActor
struct ScriptedRig {
    let store: LibraryStore
    let fs: FakeFolders
    let listing: ScriptedListing
    let watching: FakeWatching
    let access: FakeAccess
    let prober: CountingProber
    let model: HotFolderModel

    init(store: LibraryStore? = nil) throws {
        let store = try store ?? LibraryStore.inMemory()
        let fs = FakeFolders()
        let listing = ScriptedListing(fs)
        let watching = FakeWatching()
        let access = FakeAccess()
        let prober = CountingProber()
        self.store = store; self.fs = fs; self.listing = listing; self.watching = watching; self.access = access; self.prober = prober
        model = HotFolderModel(store: store, listing: listing, watching: watching, prober: prober, access: access)
    }

    func names(_ id: UUID) -> [String] { model.state(of: id)?.items.map(\.name) ?? [] }
}

@MainActor
@Suite struct FIXG_HotFolderTests {
    // MARK: Item 4 and 12: bookmarks, launch, a moved folder

    @Test func theBookmarkIsResolvedOffTheMainThreadAndLoadDoesNotWaitForAHungVolume() async throws {
        let r = try ScriptedRig()
        r.fs.create("/hot/a", ["one.mov": 100])
        let folder = HotFolder(name: "a", path: "/hot/a", bookmark: Data([1]))
        try await r.store.saveMediaFolder(folder)
        r.access.holdCalls()                       // the volume is not answering
        await r.model.load(waitForScans: false)           // returns anyway: launch never waits on a hot folder
        #expect(r.model.folders.map(\.folder.path) == ["/hot/a"])
        #expect(r.names(folder.id).isEmpty)
        r.access.release()
        await r.model.rescan()
        await r.model.rescan()
        #expect(r.names(folder.id) == ["one"])
        #expect(r.access.callCount > 0 && !r.access.calledOnMainThread, "the door was only used off the main thread")
    }

    @Test func aFolderThatWasMovedIsScannedWhereTheBookmarkLeadsAndAStaleBookmarkIsRefreshed() async throws {
        let r = try ScriptedRig()
        r.fs.create("/hot/renamed", ["one.mov": 100])
        let folder = HotFolder(name: "old", path: "/hot/old", bookmark: Data([1]))
        try await r.store.saveMediaFolder(folder)
        r.access.answer(folder.id, FolderResolution(path: "/hot/renamed", refreshedBookmark: Data([9, 9])))
        await r.model.load()
        await r.model.rescan()
        let state = try #require(r.model.state(of: folder.id))
        #expect(state.status == .ok && state.items.map(\.name) == ["one"])
        #expect(state.folder.path == "/hot/renamed" && state.folder.bookmark == Data([9, 9]))
        let saved = try #require(try await r.store.mediaFolders().first)
        #expect(saved.path == "/hot/renamed" && saved.bookmark == Data([9, 9]), "the new place and the fresh bookmark are remembered")
        #expect(r.watching.watched.contains("/hot/renamed"), "and the new place is the one watched")
        #expect(saved.id == folder.id, "the folder keeps its identity, so cues that name its files keep working")
    }

    @Test func removingAFolderLetsGoOfItsAccess() async throws {
        let r = try ScriptedRig()
        r.fs.create("/hot/a")
        let folder = try #require(await r.model.add(path: "/hot/a", bookmark: Data([1])))
        await r.model.remove(folder.id)
        #expect(r.access.forgotten == [folder.id])
    }

    // MARK: Item 5: a listing error, a clip on air, the launch order

    @Test func aListingErrorKeepsTheLastItemsShowsTheFolderAsUnreachableAndRecoveryHoldsNothingBack() async throws {
        let r = try ScriptedRig()
        r.fs.create("/hot/a", ["one.mov": 100, "two.mov": 100])
        let folder = try #require(await r.model.add(path: "/hot/a", bookmark: nil))
        await r.model.rescan(); await r.model.rescan()
        #expect(r.names(folder.id) == ["one", "two"])
        r.listing.fail(with: .unreachable)
        await r.model.rescan(folder.id)
        let state = try #require(r.model.state(of: folder.id))
        #expect(state.status == .unreachable)
        #expect(state.items.map(\.name) == ["one", "two"], "the last known items stay")
        #expect(r.model.lastError == nil)
        r.listing.fail(with: nil)
        await r.model.rescan(folder.id)       // one scan is enough: files already known as complete are not held back again
        let back = try #require(r.model.state(of: folder.id))
        #expect(back.status == .ok && back.items.map(\.name) == ["one", "two"] && back.heldBack.isEmpty)
    }

    @Test func aFolderThatIsReallyGoneStillShowsAsMissingWithNoItems() async throws {
        let r = try ScriptedRig()
        r.fs.create("/hot/a", ["one.mov": 100])
        let folder = try #require(await r.model.add(path: "/hot/a", bookmark: nil))
        await r.model.rescan(); await r.model.rescan()
        r.fs.vanish("/hot/a")
        await r.model.rescan(folder.id)
        #expect(r.model.state(of: folder.id)?.status == .missing && r.model.state(of: folder.id)?.items.isEmpty == true)
    }

    @Test func aClipThatIsOnAirStaysRegisteredWhenItsFileVanishesFromTheFolder() async throws {
        let rig = try MediaRig()
        rig.model.showStateChanged(isLive: true)
        let id = UUID()
        let clip = MediaAsset(id: id, name: "live", kind: .video, path: "/hot/a/live.mov", duration: 10, pixelWidth: 1920, pixelHeight: 1080, addedAt: .distantPast)
        let folder = UUID()
        var registered: [[UUID]] = []
        rig.model.onAssetsChange = { registered.append($0.map(\.id)) }
        rig.model.setHotAssets(folder, [clip])
        rig.model.setBackground(id)
        rig.model.setHotAssets(folder, [])                      // the next scan no longer lists it
        #expect(rig.model.allAssets.map(\.id) == [id], "still registered while it plays")
        #expect(registered.last == [id])
        #expect(rig.model.layers.background?.selection.assetID == id)
        rig.model.clearBackground()                             // it stopped playing: now it can go
        #expect(rig.model.allAssets.isEmpty)
        #expect(registered.last == [])
    }

    @Test func aForegroundClipAndAFolderPlayAreKeptRegisteredToo() async throws {
        let rig = try MediaRig()
        rig.model.showStateChanged(isLive: true)
        let a = MediaAsset(id: UUID(), name: "a", kind: .video, path: "/hot/a/a.mov", duration: 10, pixelWidth: 1, pixelHeight: 1, addedAt: .distantPast)
        let folder = UUID()
        rig.model.setHotAssets(folder, [a])
        rig.model.playFolder(folder, on: .foreground)
        rig.model.setHotAssets(folder, [])
        #expect(rig.model.allAssets.map(\.id) == [a.id])
        rig.model.stopForeground()
        #expect(rig.model.allAssets.isEmpty)
    }

    @Test func aRememberedHotFolderBackgroundIsRestoredWhenTheFolderLoadsAfterTheBin() async throws {
        let rig = try MediaRig()
        let clip = MediaAsset(id: HotFolderFiles.id(folder: UUID(), fileName: "loop.mov"), name: "loop", kind: .video,
                              path: "/hot/a/loop.mov", duration: 10, pixelWidth: 1, pixelHeight: 1, addedAt: .distantPast)
        let folder = UUID()
        rig.model.setHotAssets(folder, [clip])
        rig.model.setBackground(clip.id)
        await rig.model.flush()
        // A relaunch: the bin loads first, the hot folders a moment later (launch does not wait for them).
        let again = try #require(rig.relaunched())
        await again.model.load()
        #expect(again.model.layers.background == nil, "the folder has not answered yet")
        again.model.setHotAssets(folder, [clip])
        #expect(again.model.layers.background?.selection.assetID == clip.id, "restored as soon as the folder lists it")
    }

    @Test func aChoiceMadeBeforeTheFolderAnswersIsNotReplacedByTheRememberedOne() async throws {
        let rig = try MediaRig()
        let remembered = MediaAsset(id: UUID(), name: "old", kind: .video, path: "/hot/a/old.mov", duration: 10, pixelWidth: 1, pixelHeight: 1, addedAt: .distantPast)
        let folder = UUID()
        rig.model.setHotAssets(folder, [remembered])
        rig.model.setBackground(remembered.id)
        await rig.model.flush()
        let again = try #require(rig.relaunched())
        await again.model.load()
        let chosen = await again.add("chosen.mov")
        again.model.setBackground(chosen.id)
        again.model.setHotAssets(folder, [remembered])
        #expect(again.model.layers.background?.selection.assetID == chosen.id)
    }

    // MARK: Item 6: bounded scanning

    @Test func oneScanRunsAtATimePerFolderAndRequestsWhileItRunsAreCoalesced() async throws {
        let r = try ScriptedRig()
        r.fs.create("/hot/a", ["one.mov": 100])
        let folder = try #require(await r.model.add(path: "/hot/a", bookmark: nil))
        await r.model.rescan(); await r.model.rescan()
        let before = r.listing.calls
        r.listing.hold()
        for _ in 0..<20 { r.model.requestRescan() }
        for _ in 0..<20 { r.model.requestRescan(folder.id) }
        r.listing.release()
        await r.model.waitForRescans()
        await r.model.rescan(folder.id)
        #expect(r.listing.maxRunning == 1, "never two listings of the same folder at once")
        #expect(r.listing.calls - before <= 4, "forty requests became a handful of scans: \(r.listing.calls - before)")
    }

    @Test func aFileThatCannotBeProbedIsRememberedAsUnreadableAndRetriedWithAGrowingDelay() async throws {
        let r = try ScriptedRig()
        r.fs.create("/hot/a", ["good.mov": 100, "bad1.mov": 100])
        let folder = try #require(await r.model.add(path: "/hot/a", bookmark: nil))
        var attempts: [Int] = []
        var seen = 0
        for scan in 1...40 {
            await r.model.rescan(folder.id)
            let now = r.prober.count("bad1.mov")
            if now > seen { attempts.append(scan); seen = now }
        }
        #expect(attempts.count >= 3 && attempts.count <= 6, "retried a few times, not every scan: \(attempts)")
        let gaps = zip(attempts.dropFirst(), attempts).map { $0 - $1 }
        #expect(gaps == gaps.sorted() && Set(gaps).count == gaps.count, "each gap is longer than the one before: \(gaps)")
        let state = try #require(r.model.state(of: folder.id))
        #expect(state.unreadable == ["bad1.mov"] && state.heldBack.isEmpty)
        #expect(r.model.pendingCount == 0, "an unreadable file does not ask for a rescan every two seconds")
        #expect(state.items.map(\.name) == ["good"])
        #expect(r.prober.count("good.mov") == 1, "a readable file is probed once")
    }

    @Test func aFileThatChangedIsProbedAgainAtOnce() async throws {
        let r = try ScriptedRig()
        r.fs.create("/hot/a", ["bad1.mov": 100])
        let folder = try #require(await r.model.add(path: "/hot/a", bookmark: nil))
        for _ in 0..<12 { await r.model.rescan(folder.id) }
        let before = r.prober.count("bad1.mov")
        r.fs.put("/hot/a", "bad1.mov", size: 250)
        await r.model.rescan(folder.id); await r.model.rescan(folder.id)
        #expect(r.prober.count("bad1.mov") > before)
    }

    @Test func theProbeCacheHoldsOnlyFilesThatStillExist() async throws {
        let r = try ScriptedRig()
        r.fs.create("/hot/a", ["one.mov": 100, "two.mov": 100, "three.mov": 100])
        let folder = try #require(await r.model.add(path: "/hot/a", bookmark: nil))
        await r.model.rescan(); await r.model.rescan()
        #expect(r.model.probeCacheCount == 3)
        r.fs.drop("/hot/a", "one.mov"); r.fs.drop("/hot/a", "two.mov")
        await r.model.rescan(folder.id)
        #expect(r.model.probeCacheCount == 1)
        r.fs.put("/hot/a", "three.mov", size: 999)             // a file that changed size is a different cache entry
        await r.model.rescan(folder.id); await r.model.rescan(folder.id)
        #expect(r.model.probeCacheCount == 1, "the old entry of the same file is gone")
        await r.model.remove(folder.id)
        #expect(r.model.probeCacheCount == 0)
    }

    @Test func aFolderIsCappedAtTwoThousandItemsWithANotice() async throws {
        let r = try ScriptedRig()
        var files: [String: Int64] = [:]
        for i in 0..<2_300 { files[String(format: "f%04d.mov", i)] = 100 }
        r.fs.create("/hot/big", files)
        let folder = try #require(await r.model.add(path: "/hot/big", bookmark: nil))
        await r.model.rescan(); await r.model.rescan()
        let state = try #require(r.model.state(of: folder.id))
        #expect(state.items.count == HotFolderModel.maxItemsPerFolder && HotFolderModel.maxItemsPerFolder == 2_000)
        #expect(state.items.first?.name == "f0000" && state.items.last?.name == "f1999")
        let notice = try #require(state.notice)
        #expect(notice.contains("2,000") && notice.contains("2300") == false && notice.contains("2,300"))
        r.fs.drop("/hot/big", "f0000.mov")                      // back under the cap: no notice
        for i in 0..<400 { r.fs.drop("/hot/big", String(format: "f%04d.mov", 1_900 + i)) }
        await r.model.rescan(folder.id)
        #expect(r.model.state(of: folder.id)?.notice == nil)
    }

    // MARK: Item 6: Play folder skips what it cannot read

    private func playRig(_ names: [String]) async throws -> (MediaRig, UUID, [MediaAsset]) {
        let rig = try MediaRig()
        rig.model.showStateChanged(isLive: true)
        let folder = UUID()
        let items = names.map { MediaAsset(id: UUID(), name: $0, kind: .video, path: "/hot/p/\($0).mov", duration: 10, pixelWidth: 1, pixelHeight: 1, addedAt: .distantPast) }
        rig.model.setHotAssets(folder, items)
        return (rig, folder, items)
    }

    @Test func playFolderSkipsAnUnreadableFileGoesOnAndSaysSoOnce() async throws {
        let (rig, folder, items) = try await playRig(["a", "b", "c"])
        rig.files.lose(items[0].path)
        rig.model.playFolder(folder, on: .background)
        #expect(rig.model.layers.background.flatMap { rig.model.asset($0.selection.assetID)?.name } == "b", "went on to the next one")
        let message = try #require(rig.model.lastError)
        #expect(message.contains("\"a\"") && message.contains("skipped"))
        // Later passes over the same file do not say it again.
        rig.model.dismissError()
        rig.clock.advance(10.5); rig.model.tick()               // b ends, c plays
        rig.clock.advance(10.5); rig.model.tick()               // c ends, wraps past a (unreadable) to b
        #expect(rig.model.lastError == nil, "the skipped file was reported once")
        #expect(rig.model.layers.background.flatMap { rig.model.asset($0.selection.assetID)?.name } == "b")
    }

    @Test func aFileThatBecomesUnreadableWhileTheFolderPlaysIsSkippedAndReportedOnce() async throws {
        let (rig, folder, items) = try await playRig(["a", "b", "c"])
        rig.model.playFolder(folder, on: .background)
        rig.files.lose(items[1].path)                           // b goes bad before its turn
        rig.clock.advance(10.5); rig.model.tick()
        #expect(rig.model.layers.background.flatMap { rig.model.asset($0.selection.assetID)?.name } == "c")
        let message = try #require(rig.model.lastError)
        #expect(message.contains("\"b\"") && message.contains("skipped"))
        rig.model.dismissError()
        rig.clock.advance(10.5); rig.model.tick()               // c ends, wraps to a, skipping b again
        rig.clock.advance(10.5); rig.model.tick()               // a ends, c again
        #expect(rig.model.lastError == nil)
    }

    @Test func ifNoFileCanBePlayedItStopsAndSaysSo() async throws {
        let (rig, folder, items) = try await playRig(["a", "b"])
        for item in items { rig.files.lose(item.path) }
        rig.model.playFolder(folder, on: .background)
        #expect(rig.model.layers.background == nil && rig.model.playingFolderID == nil)
        let message = try #require(rig.model.lastError)
        #expect(message.contains("none") || message.contains("None"))
        // And while playing, if every remaining file goes bad, it stops and says so.
        let (rig2, folder2, items2) = try await playRig(["a", "b"])
        rig2.model.playFolder(folder2, on: .background)
        for item in items2 { rig2.files.lose(item.path) }
        rig2.clock.advance(10.5); rig2.model.tick()
        #expect(rig2.model.layers.background == nil && rig2.model.playingFolderID == nil)
        #expect(rig2.model.lastError != nil)
    }
}
