// FIX-B R1: held keys never drive the transport, and transport commands run one at a time.
import Testing
import Foundation
import Domain
import Persistence
@testable import OperatorCore

@Suite struct KeyRepeatRoutingTests {
    @Test func aRepeatedTransportKeyIsIgnored() {
        for key: KeyboardKey in [.returnKey, .keypadEnter, .space, .leftArrow, .rightArrow, .upArrow, .downArrow, .escape] {
            #expect(KeyRouting.decision(for: key, textInputFocused: false, sheetOpen: false, isRepeat: true) == .ignore, "\(key)")
            #expect(KeyRouting.transportCommand(for: key, textInputFocused: false, sheetOpen: false, isRepeat: true) == nil, "\(key)")
        }
    }

    @Test func aFirstPressStillDrivesTheTransport() {
        #expect(KeyRouting.decision(for: .space, textInputFocused: false, sheetOpen: false, isRepeat: false) == .transport(.next))
        #expect(KeyRouting.decision(for: .space, textInputFocused: false, sheetOpen: false) == .transport(.next))
    }

    @Test func repeatsStillReachTextFieldsSheetsAndMenus() {
        // Typing, deleting and arrow-keying in a field must keep auto-repeating.
        for key: KeyboardKey in [.space, .leftArrow, .rightArrow, .deleteKey, .returnKey] {
            #expect(KeyRouting.decision(for: key, textInputFocused: true, sheetOpen: false, isRepeat: true) == .passThrough, "\(key)")
            #expect(KeyRouting.decision(for: key, textInputFocused: false, sheetOpen: true, isRepeat: true) == .passThrough, "\(key)")
            #expect(KeyRouting.decision(for: key, textInputFocused: false, sheetOpen: false, commandModifierDown: true, isRepeat: true) == .passThrough, "\(key)")
        }
        #expect(KeyRouting.decision(for: .other, textInputFocused: false, sheetOpen: false, isRepeat: true) == .passThrough)
    }

    @Test func aHeldDeleteDoesNotRemoveObjectsOneAfterAnother() {
        #expect(KeyRouting.decision(for: .deleteKey, textInputFocused: false, sheetOpen: false, isRepeat: true) == .passThrough)
    }
}

@Suite struct ClearAllKeyTests {
    @Test func shiftEscapeIsClearAllAndPlainEscapeStaysClear() {
        #expect(KeyRouting.decision(for: .escape, textInputFocused: false, sheetOpen: false, shiftDown: true) == .transport(.clearAll))
        #expect(KeyRouting.decision(for: .escape, textInputFocused: false, sheetOpen: false) == .transport(.clear))
    }

    @Test func shiftEscapeFollowsTheSameRulesAsEveryTransportKey() {
        #expect(KeyRouting.decision(for: .escape, textInputFocused: false, sheetOpen: false, shiftDown: true, isRepeat: true) == .ignore)
        #expect(KeyRouting.decision(for: .escape, textInputFocused: true, sheetOpen: false, shiftDown: true) == .passThrough)
        #expect(KeyRouting.decision(for: .escape, textInputFocused: false, sheetOpen: true, shiftDown: true) == .passThrough)
        #expect(KeyRouting.decision(for: .escape, textInputFocused: false, sheetOpen: false, commandModifierDown: true, shiftDown: true) == .passThrough)
        // Shift does not change what the other keys do.
        #expect(KeyRouting.decision(for: .space, textInputFocused: false, sheetOpen: false, shiftDown: true) == .transport(.next))
    }
}

@MainActor
@Suite struct TransportSerialisationTests {
    /// Three one-slide songs in one playlist, the first open and live.
    func threeSongsLive() async throws -> WorkspaceModel {
        let store = try LibraryStore.inMemory()
        let model = WorkspaceModel(store: store)
        await model.load()
        for name in ["A", "B", "C"] {
            let p = try #require(await model.importLyrics(title: "Song \(name)", primaryText: "\(name.lowercased())1", secondaryText: nil, maxLines: 2))
            await model.addToPlaylist(p.id)
        }
        await model.openPlaylistItem(model.playlistItems[0].id)
        await model.goLive()
        #expect(model.show.liveSlide?.primary == "a1")
        return model
    }

    @Test func twoNextsArrivingTogetherBothAdvanceInOrder() async throws {
        let model = try await threeSongsLive()
        let first = Task { @MainActor in await model.next() }
        let second = Task { @MainActor in await model.next() }
        await first.value
        await second.value
        #expect(model.show.liveSlide?.primary == "c1")          // A -> B -> C, never "second one dropped"
        #expect(model.lastError == nil)
    }

    @Test func nextThenPreviousArrivingTogetherEndWhereTheyStarted() async throws {
        let model = try await threeSongsLive()
        let first = Task { @MainActor in await model.next() }        // started in this order, on the main actor
        let second = Task { @MainActor in await model.previous() }
        await first.value
        await second.value
        #expect(model.show.liveSlide?.primary == "a1")
    }

    @Test func stopDuringAPlaylistStepIsNotUndoneByTheStep() async throws {
        let model = try await threeSongsLive()
        let step = Task { @MainActor in await model.next() }
        await Task.yield(); await Task.yield()
        model.stop()
        await step.value
        #expect(model.show.isStopped)
    }

    @Test func clearDuringAPlaylistStepStaysCleared() async throws {
        let model = try await threeSongsLive()
        let step = Task { @MainActor in await model.next() }
        await Task.yield(); await Task.yield()
        model.clear()
        await step.value
        #expect(model.show.isCleared)
    }
}
