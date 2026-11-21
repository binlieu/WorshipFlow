// FIX-B R11: the operator is told before a re-flow damages a section order, an emptied playlist item is shown as
// empty, and Next stops on it with a message instead of skipping the song.
import Testing
import Foundation
import Domain
import Persistence
@testable import OperatorCore

@MainActor
@Suite struct ReflowImpactModelTests {
    let twoSections = "Verse 1\nOne\n\nChorus\nTwo"
    let verseOnly = "Verse 1\nOne"

    struct Rig {
        let model: WorkspaceModel
        let a: Presentation
        let b: Presentation
        let c: Presentation
        let orderB: Arrangement
    }

    /// A, B and C in one playlist. B plays a section order that holds only its Chorus.
    private func rig() async throws -> Rig {
        let store = try LibraryStore.inMemory()
        let model = WorkspaceModel(store: store)
        await model.load()
        let a = try #require(await model.importLyrics(title: "A", primaryText: "a1", secondaryText: nil, maxLines: 2))
        let b = try #require(await model.importLyrics(title: "B", primaryText: twoSections, secondaryText: nil, maxLines: 2))
        let c = try #require(await model.importLyrics(title: "C", primaryText: "c1", secondaryText: nil, maxLines: 2))
        for p in [a, b, c] { await model.addToPlaylist(p.id) }
        await model.openPresentation(b.id)
        let chorus = try #require(model.groups.first { $0.name == "Chorus" })
        let order = try #require(await model.createArrangement(name: "Chorus only", groupIDs: [chorus.id]))
        await model.setArrangement(order.id, forPlaylistItem: model.playlistItems[1].id)
        return Rig(model: model, a: a, b: b, c: c, orderB: order)
    }

    private func results(_ text: String) -> [ReflowResult] { Reflow.contents(primary: text, secondary: nil, maxLines: 2) }

    @Test func theModelReportsTheOrdersAndPlaylistItemsAReflowWouldDamage() async throws {
        let r = try await rig()
        let impact = await r.model.reflowImpact(id: r.b.id, results: results(verseOnly))
        #expect(impact.count == 1)
        #expect(impact.first?.arrangementName == "Chorus only")
        #expect(impact.first?.lostSections == ["Chorus"])
        #expect(impact.first?.becomesEmpty == true)
        #expect(impact.first?.playlistItemTitles == ["B"])
        #expect(try await r.model.reflowImpact(id: r.b.id, results: results(twoSections)).isEmpty)   // nothing lost: nothing said
        // Reading the impact changes nothing.
        #expect(r.model.groups.map(\.name) == ["Verse 1", "Chorus"])
    }

    @Test func aReflowThatEmptiesAnOrderShowsThePlaylistItemAsEmpty() async throws {
        let r = try await rig()
        #expect(r.model.emptyPlaylistItemIDs.isEmpty)
        #expect(await r.model.reflowPresentation(id: r.b.id, results: results(verseOnly)))
        #expect(r.model.emptyPlaylistItemIDs == [r.model.playlistItems[1].id])
    }

    @Test func nextStopsOnAnEmptyPlaylistItemWithAMessageInsteadOfSkippingIt() async throws {
        let r = try await rig()
        _ = await r.model.reflowPresentation(id: r.b.id, results: results(verseOnly))
        await r.model.openPlaylistItem(r.model.playlistItems[0].id)
        await r.model.goLive()
        await r.model.next()
        #expect(r.model.show.liveDeck?.presentationID == r.a.id)           // still on A: C was not jumped to
        #expect(r.model.show.liveSlide?.primary == "a1")
        let message = try #require(r.model.lastError)
        #expect(message.contains("\"B\"") && message.contains("no slides"))
    }

    @Test func previousStopsOnAnEmptyPlaylistItemToo() async throws {
        let r = try await rig()
        _ = await r.model.reflowPresentation(id: r.b.id, results: results(verseOnly))
        await r.model.openPlaylistItem(r.model.playlistItems[2].id)
        await r.model.goLive()
        await r.model.previous()
        #expect(r.model.show.liveDeck?.presentationID == r.c.id)
        #expect(r.model.lastError?.contains("\"B\"") == true)
    }

    @Test func playlistItemsWithSlidesStillStepNormally() async throws {
        let r = try await rig()
        await r.model.openPlaylistItem(r.model.playlistItems[0].id)
        await r.model.goLive()
        await r.model.next()
        #expect(r.model.show.liveDeck?.presentationID == r.b.id)           // B's order still has its Chorus
        #expect(r.model.show.liveSlide?.primary == "Two")
        #expect(r.model.lastError == nil)
    }
}
