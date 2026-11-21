// FIX-F item 4 (LIB-004c): one request counter for everything that puts something into preview. An older request that finishes after
// a newer one never reaches Preview. The first library read of the scripture model is held and released in a chosen order through
// `readGate`. Written before the fix; invented text only. No wall-clock time: the test waits for the held read by yielding.
import Testing
import Foundation
import Domain
import Persistence
import ScriptureEngine
import ScriptureStore
@testable import OperatorCore

@MainActor
final class FIXF_Hold {
    private var continuation: CheckedContinuation<Void, Never>?
    private(set) var parked = false
    private var armed = false
    func arm() { armed = true; parked = false }
    func gate() async {
        guard armed else { return }
        armed = false
        parked = true
        await withCheckedContinuation { continuation = $0 }
    }
    func waitUntilParked() async { while !parked { await Task.yield() } }
    func release() { continuation?.resume(); continuation = nil }
}

@MainActor
@Suite struct FIXF_StaleRequestTests {
    private func rig() async throws -> (L4C.Rig, FIXF_Hold) {
        let r = try await L4C.rig()
        let hold = FIXF_Hold()
        r.scripture.readGate = { await hold.gate() }
        return (r, hold)
    }

    @Test func anOlderTypedReferenceThatFinishesLastDoesNotReplaceTheNewerOne() async throws {
        let (r, hold) = try await rig()
        hold.arm()
        let older = Task { await r.scripture.show("John 3:16") }
        await hold.waitUntilParked()
        await r.scripture.show("Psalm 23:1")                    // newer, finishes first
        #expect(r.scripture.passage?.spec.ranges.first?.book == "PSA")
        hold.release()
        await older.value
        #expect(r.scripture.passage?.spec.ranges.first?.book == "PSA", "the older request was dropped")
        #expect(r.workspace.show.previewDeck?.slides.first?.primary.contains("lamp is lit") == true)
        #expect(r.workspace.openScripture?.contents.first?.primary.contains("lamp is lit") == true)
    }

    @Test func anOlderPlaylistItemThatFinishesAfterATypedReferenceDoesNotReplaceIt() async throws {
        let (r, hold) = try await rig()
        await r.scripture.show("John 3:16")
        await r.scripture.addToPlaylist()
        let id = try #require(r.workspace.playlistItems.last).id
        hold.arm()
        let older = Task { await r.workspace.openPlaylistItem(id) }
        await hold.waitUntilParked()
        await r.scripture.show("Psalm 23:1")
        hold.release()
        await older.value
        #expect(r.workspace.openScripture?.itemID == nil, "the typed passage stays; the older item did not land")
        #expect(r.workspace.openScripture?.contents.first?.primary.contains("lamp is lit") == true)
        #expect(r.workspace.show.previewDeck?.slides.first?.primary.contains("lamp is lit") == true)
    }

    @Test func anOlderPassageThatFinishesAfterASongWasOpenedDoesNotReplaceTheSong() async throws {
        let (r, hold) = try await rig()
        let song = try #require(await r.workspace.importLyrics(title: "A", primaryText: "a1\n\na2", secondaryText: nil, maxLines: 1))
        hold.arm()
        let older = Task { await r.scripture.show("John 3:16") }
        await hold.waitUntilParked()
        await r.workspace.openPresentation(song.id)
        hold.release()
        await older.value
        #expect(r.workspace.openPresentationID == song.id)
        #expect(r.workspace.openScripture == nil, "the song stays in preview")
        #expect(r.workspace.show.previewDeck?.slides.first?.primary == "a1")
        #expect(r.workspace.centreShowsScripture == false)
    }

    @Test func anOlderPlaylistItemThatFinishesAfterASongWasOpenedDoesNotReplaceTheSong() async throws {
        let (r, hold) = try await rig()
        let song = try #require(await r.workspace.importLyrics(title: "A", primaryText: "a1\n\na2", secondaryText: nil, maxLines: 1))
        await r.scripture.show("John 3:16")
        await r.scripture.addToPlaylist()
        let id = try #require(r.workspace.playlistItems.last).id
        hold.arm()
        let older = Task { await r.workspace.openPlaylistItem(id) }
        await hold.waitUntilParked()
        await r.workspace.openPresentation(song.id)
        hold.release()
        await older.value
        #expect(r.workspace.openPresentationID == song.id && r.workspace.openScripture == nil)
        #expect(r.workspace.show.previewDeck?.slides.first?.primary == "a1")
    }

    @Test func aNewerRequestThatFinishesFirstAndAnOlderOneInOrderStillShowTheNewest() async throws {
        let (r, hold) = try await rig()
        hold.arm()
        let first = Task { await r.scripture.show("John 3:16") }
        await hold.waitUntilParked()
        hold.release()                                          // in order: the first one finishes, then the second
        await first.value
        await r.scripture.show("Psalm 23:1")
        #expect(r.scripture.passage?.spec.ranges.first?.book == "PSA")
    }
}
