// FIX-V item 6 (REVIEW-4 L2, L3, L5, L8): the low findings that are confirmed and small. Written before the fixes.
import Testing
import Foundation
import Domain
import Persistence
import CueStore
@testable import OperatorCore

@MainActor
@Suite struct FIXV_CollectionLowTests {
    /// L2: a hot-folder item could be put in a collection and then dropped from it at the next bin change. It is refused with a message instead.
    @Test func aHotFolderItemIsRefusedAtTheAddNotDroppedLater() async throws {
        let rig = try MediaRig()
        let a = await rig.add("a.mov")
        let hot = MediaAsset(name: "hot", kind: .video, path: "/hot/h.mov", duration: 5)
        rig.model.setHotAssets(UUID(), [hot])
        let id = try #require(rig.model.createCollection("Loops", adding: [a.id, hot.id]))
        #expect(rig.model.collections.collection(id)?.assetIDs == [a.id], "only the bin item went in")
        #expect(rig.model.lastError?.contains("hot folder") == true)
        rig.model.lastError = nil
        rig.model.addToCollection([hot.id], collection: id)
        #expect(rig.model.collections.collection(id)?.assetIDs == [a.id])
        #expect(rig.model.lastError?.contains("hot folder") == true)
        rig.model.binChanged()
        #expect(rig.model.collections.collection(id)?.assetIDs == [a.id], "nothing that was accepted disappears")
    }

    @Test func aBinItemAddedWithNoHotItemSaysNothing() async throws {
        let rig = try MediaRig()
        let a = await rig.add("a.mov")
        let id = try #require(rig.model.createCollection("Loops", adding: [a.id]))
        #expect(rig.model.collections.collection(id)?.assetIDs == [a.id] && rig.model.lastError == nil)
    }

    /// L3: stored text that cannot be read must not be replaced without a trace by the next change.
    @Test func unreadableStoredCollectionsAreKeptBeforeTheNextWriteReplacesThem() async throws {
        let rig = try MediaRig()
        try await rig.store.setState("{ this is not json", for: MediaCollections.storageKey)
        await rig.model.load()
        #expect(rig.model.collections.items.isEmpty)
        #expect(rig.model.lastError?.contains("could not be read") == true)
        let a = await rig.add("a.mov")
        _ = rig.model.createCollection("New", adding: [a.id])
        await rig.model.flush()
        #expect(try await rig.store.state(for: MediaCollections.storageKey + ".unreadable") == "{ this is not json")
    }
}

@MainActor
@Suite struct FIXV_CueLowTests {
    private func rig() async throws -> (cue: CueModel, library: LibraryStore, workspace: WorkspaceModel) {
        let library = try LibraryStore.inMemory()
        let show = FakeShow()
        let workspace = WorkspaceModel(store: library)
        await workspace.load()
        let cue = CueModel(store: CueStore(library: library), ports: CuePorts(transport: workspace, looks: show, stage: show, media: show, midiOut: { show }),
                           clock: TestCueClock(), settingsStore: library)
        return (cue, library, workspace)
    }

    /// L3: an unreadable `cue.macro.keys` is kept before the next setKey replaces it.
    @Test func unreadableStoredKeysAreKeptBeforeTheNextWriteReplacesThem() async throws {
        let r = try await rig()
        try await r.library.setState("garbage", for: CueModel.keyTriggersKey)
        await r.cue.start()
        #expect(r.cue.keyTriggers.isEmpty)
        let macro = try #require(await r.cue.createMacro(name: "One"))
        await r.cue.setKey(.f2, for: macro.id)
        #expect(try await r.library.state(for: CueModel.keyTriggersKey + ".unreadable") == "garbage")
        #expect(r.cue.notices.contains { $0.text.contains("could not be read") })
    }

    /// L3: the first prune at start sees no keys; a stored key whose macro is gone is dropped from the store at load, not only in memory.
    @Test func aStoredKeyOfAMacroThatIsGoneLeavesTheStoreAtStart() async throws {
        let r = try await rig()
        let gone = UUID()
        try await r.library.setState(#"{"version":1,"keys":[{"macro":"\#(gone.uuidString)","key":"F4"}]}"#, for: CueModel.keyTriggersKey)
        await r.cue.start()
        #expect(r.cue.keyTriggers.isEmpty)
        let stored = try await r.library.state(for: CueModel.keyTriggersKey) ?? ""
        #expect(!stored.contains(gone.uuidString), "the store no longer lists the gone macro")
    }

    /// L3: two quick key changes leave the store as the screen shows it.
    @Test func twoQuickKeyChangesAreStoredInOrder() async throws {
        let r = try await rig()
        await r.cue.start()
        let one = try #require(await r.cue.createMacro(name: "One"))
        let two = try #require(await r.cue.createMacro(name: "Two"))
        async let first: Void = r.cue.setKey(.f1, for: one.id)
        async let second: Void = r.cue.setKey(.f2, for: two.id)
        _ = await (first, second)
        let stored = try #require(try await r.library.state(for: CueModel.keyTriggersKey))
        let back = try JSONDecoder().decode(CueKeyTriggers.self, from: Data(stored.utf8))
        #expect(back == r.cue.keyTriggers)
        #expect(back.key(for: one.id) == .f1 && back.key(for: two.id) == .f2)
    }

    /// L5: the presentations listed in the Cues sidebar follow a rename, a deletion and a change of actions when asked to refresh.
    @Test func theSlideActionListFollowsARenameWhenRefreshed() async throws {
        let r = try await rig()
        let song = try #require(await r.workspace.importLyrics(title: "Old title", primaryText: "Verse 1\nline", secondaryText: nil, maxLines: 2))
        await r.workspace.openPresentation(song.id)
        await r.cue.start()
        let slide = try #require(r.workspace.slides.first)
        try await r.cue.setSlideActions([.selectLook(UUID())], for: slide.id)
        #expect(r.cue.slideActionPresentations.map(\.title) == ["Old title"])
        await r.workspace.renamePresentation(id: song.id, to: "New title")
        #expect(r.cue.slideActionPresentations.map(\.title) == ["Old title"], "stale until asked")
        await r.cue.refreshSlideActionPresentations()
        #expect(r.cue.slideActionPresentations.map(\.title) == ["New title"])
    }
}

@MainActor
@Suite struct FIXV_OfflineCheckTests {
    final class Counter: @unchecked Sendable {
        private let lock = NSLock()
        private var n = 0
        private var blockNext = true
        let entered = DispatchSemaphore(value: 0)
        let gate = DispatchSemaphore(value: 0)
        var count: Int { lock.withLock { n } }
        func hit() {
            let block = lock.withLock { () -> Bool in n += 1; let b = blockNext; blockNext = false; return b }
            if block { entered.signal(); gate.wait() }      // the first check stays "reading the file system" until released
        }
        func armBlock() { lock.withLock { blockNext = true } }
        func waitUntilEntered() { entered.wait() }
    }

    /// L8: asking again while a check is still reading the file system does not start a second one beside it; one more runs after it.
    @Test func askingAgainDuringACheckRunsOneMoreAfterItNeverTwoAtOnce() async throws {
        let counter = Counter()
        let store = try LibraryStore.inMemory()
        let model = MediaModel(store: store, prober: FakeProber(), isAvailable: { _ in counter.hit(); return true })
        _ = await model.add(url: URL(fileURLWithPath: "/media/a.mov"))
        counter.gate.signal()                       // the add's own check runs through
        await model.finishOfflineCheck()
        let before = counter.count
        counter.armBlock()
        model.scheduleOfflineCheck()
        await Task.detached { counter.waitUntilEntered() }.value      // the check is inside its file system read
        for _ in 0..<5 { model.scheduleOfflineCheck() }           // five more asks during the read
        counter.gate.signal()
        await model.finishOfflineCheck()
        #expect(counter.count - before == 2, "one check, and one more after it: never six, never two at once")
        #expect(model.offlineIDs.isEmpty)
    }

    /// L8: coming forward asks for a check only when something changed or the last one is old; a burst of activations is one check.
    @Test func activationChecksOnlyWhenTheBinOrTheVolumesChangedOrTheLastCheckIsOld() {
        let t0 = Date(timeIntervalSinceReferenceDate: 1000)
        let sig = MediaOffline.Signature(paths: ["/Volumes/A/a.mov"], volumes: ["/Volumes/A"])
        #expect(MediaOffline.shouldCheckOnActivation(last: nil, now: t0, signature: sig), "never checked")
        let done = MediaOffline.LastCheck(signature: sig, at: t0)
        #expect(!MediaOffline.shouldCheckOnActivation(last: done, now: t0.addingTimeInterval(5), signature: sig), "an activation burst")
        #expect(MediaOffline.shouldCheckOnActivation(last: done, now: t0.addingTimeInterval(5),
                                                     signature: MediaOffline.Signature(paths: sig.paths, volumes: [])), "a disk went away")
        #expect(MediaOffline.shouldCheckOnActivation(last: done, now: t0.addingTimeInterval(5),
                                                     signature: MediaOffline.Signature(paths: sig.paths + ["/x.mov"], volumes: sig.volumes)), "the bin changed")
        #expect(MediaOffline.shouldCheckOnActivation(last: done, now: t0.addingTimeInterval(MediaOffline.activationInterval + 1), signature: sig), "an old check")
    }
}
