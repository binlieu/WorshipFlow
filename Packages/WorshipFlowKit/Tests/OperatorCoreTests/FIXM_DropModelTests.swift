// FIX-M: a drop edits the visible model at once and writes afterwards. The write is one commit, writes keep the order the drops arrived in,
// a failed write puts the previous order back with a plain message, and nothing a drop does touches what is live.
import Testing
import Foundation
import Domain
import Persistence
@testable import OperatorCore

@MainActor
@Suite struct FIXM_DropModelTests {
    /// A write the test holds until it says go, so what the screen shows in between can be looked at.
    @MainActor final class Gate {
        var waiting: [CheckedContinuation<Void, Never>] = []
        var log: [String] = []
        var isOpen = false
        func hold() async { if isOpen { return }; await withCheckedContinuation { waiting.append($0) } }
        /// Lets this write and every later one through.
        func release() { isOpen = true; let w = waiting; waiting = []; w.forEach { $0.resume() } }
    }
    struct Boom: Error {}

    func rig(slides: Int = 30) async throws -> (WorkspaceModel, LibraryStore) {
        let store = try LibraryStore.inMemory()
        let model = WorkspaceModel(store: store, clock: ManualSaveClock())
        await model.load()
        let text = (1...slides).map { "Line \($0)" }.joined(separator: "\n\n")
        let p = try #require(await model.importLyrics(title: "Long", primaryText: text, secondaryText: nil, maxLines: 1))
        await model.openPresentation(p.id)
        return (model, store)
    }
    func words(_ model: WorkspaceModel) -> [String] { model.slides.map(\.content.primary) }
    func spin() async { for _ in 0..<20 { await Task.yield() } }

    @Test func aSlideDropShowsAtOnceThenWritesExactlyOnce() async throws {
        let (model, store) = try await rig()
        let gate = Gate()
        let real = model.slideMoveWriter
        model.slideMoveWriter = { id, to in gate.log.append("write"); await gate.hold(); try await real(id, to) }
        let before = model.slides.map(\.id), commits = store.commitCount
        let drop = Task { await model.moveSlide(from: 20, to: 3) }
        await spin()
        #expect(model.slides[3].content.primary == "Line 21")                       // visible while the write has not ended
        #expect(Set(model.slides.map(\.id)) == Set(before))                          // the same identities
        #expect(model.slides.map(\.sortOrder) == Array(0..<30))
        #expect(store.commitCount == commits)                                        // nothing written yet
        gate.release(); await drop.value
        #expect(store.commitCount - commits == 1 && gate.log == ["write"])
        let stored = try await store.slides(of: try #require(model.openPresentationID)).map(\.content.primary)
        #expect(stored == words(model))                                              // what was shown is what the database holds
    }

    @Test func quickSuccessiveDropsWriteInTheOrderTheyArrived() async throws {
        let (model, store) = try await rig()
        let gate = Gate()
        let real = model.slideMoveWriter
        model.slideMoveWriter = { id, to in gate.log.append("\(to)"); await gate.hold(); try await real(id, to) }
        let a = Task { await model.moveSlide(from: 10, to: 0) }
        await spin()
        let b = Task { await model.moveSlide(from: 5, to: 29) }
        await spin()
        let c = Task { await model.moveSlide(from: 0, to: 12) }
        await spin()
        var expected = Array(1...30).map { "Line \($0)" }
        expected = OrderMove.moved(OrderMove.moved(OrderMove.moved(expected, from: 10, to: 0), from: 5, to: 29), from: 0, to: 12)
        #expect(words(model) == expected)                                            // all three are on screen before any write ends
        gate.release()
        await a.value; await b.value; await c.value
        #expect(gate.log == ["0", "29", "12"])
        let stored = try await store.slides(of: try #require(model.openPresentationID)).map(\.content.primary)
        #expect(stored == expected && words(model) == expected)
    }

    @Test func aFailedWritePutsThePreviousOrderBackWithAPlainMessage() async throws {
        let (model, store) = try await rig()
        let original = words(model), commits = store.commitCount
        model.slideMoveWriter = { _, _ in throw Boom() }
        await model.moveSlide(from: 20, to: 3)
        #expect(words(model) == original && model.slides.map(\.sortOrder) == Array(0..<30))
        #expect(model.lastError?.hasPrefix("Could not move the slide") == true)
        #expect(store.commitCount == commits)
    }

    @Test func aDropQueuedBehindAFailedOneIsRolledBackAndNeverWritten() async throws {
        let (model, store) = try await rig()
        let original = words(model)
        let gate = Gate()
        var calls = 0
        model.slideMoveWriter = { _, _ in calls += 1; await gate.hold(); throw Boom() }
        let a = Task { await model.moveSlide(from: 20, to: 3) }
        await spin()
        let b = Task { await model.moveSlide(from: 1, to: 9) }
        await spin()
        #expect(words(model) != original)
        gate.release(); await a.value; await b.value
        #expect(calls == 1)                                                          // the second write was never tried
        #expect(words(model) == original)
        #expect(try await store.slides(of: try #require(model.openPresentationID)).map(\.content.primary) == original)
    }

    @Test func aDropDoesNotChangeWhatIsLive() async throws {
        let (model, _) = try await rig()
        await model.goLive(at: 2)
        let live = model.show.liveDeck, index = model.show.liveIndex
        await model.moveSlide(from: 20, to: 0)
        #expect(model.show.liveDeck == live && model.show.liveIndex == index)
        await model.moveSlide(from: 0, to: 25)
        #expect(model.show.liveDeck == live && model.show.liveIndex == index)
    }

    @Test func aPlaylistDropShowsAtOnceAndAFailedWriteRestoresTheOrder() async throws {
        let (model, store) = try await rig(slides: 3)
        await model.addToPlaylist(try #require(model.openPresentationID))
        for title in ["B", "C"] {
            let p = try #require(await model.importLyrics(title: title, primaryText: "x", secondaryText: nil, maxLines: 1))
            await model.addToPlaylist(p.id)
        }
        let original = model.playlistItems.map(\.id)
        let gate = Gate()
        let real = model.playlistMoveWriter
        model.playlistMoveWriter = { id, to in await gate.hold(); try await real(id, to) }
        let commits = store.commitCount
        let drop = Task { await model.movePlaylistItem(id: original[0], to: 2) }
        await spin()
        #expect(model.playlistItems.map(\.id) == [original[1], original[2], original[0]])
        gate.release(); await drop.value
        #expect(store.commitCount - commits == 1 && model.playlistItems.map(\.id) == [original[1], original[2], original[0]])
        model.playlistMoveWriter = { _, _ in throw Boom() }
        await model.movePlaylistItem(id: original[1], to: 2)
        #expect(model.playlistItems.map(\.id) == [original[1], original[2], original[0]])
        #expect(model.lastError?.hasPrefix("Could not move the item") == true)
    }

    @Test func aSlideThatIsNotThereChangesNothingAndWritesNothing() async throws {
        let (model, store) = try await rig(slides: 5)
        let before = words(model), commits = store.commitCount
        await model.moveSlide(from: 9, to: 0)                                        // no such slide
        #expect(words(model) == before && store.commitCount == commits)
    }
}
