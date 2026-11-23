// FIX-V item 3 (REVIEW-4 M3): removeSection and moveSection acted on a row position captured by the view and computed the new order from a copy
// read before an await, so two quick edits removed or moved the wrong section and left the song's playing order wrong. A section entry is now
// found by identity (the section and which occurrence of it) after the awaits, and the edits run one at a time. Written before the fix.
import Testing
import Foundation
import Domain
import Persistence
@testable import OperatorCore

@MainActor
@Suite struct FIXV_SectionOrderTests {
    let song = "Verse 1\nline v1\n\nChorus\nline ch\n\nVerse 2\nline v2\n\nBridge\nline br"

    func ready() async throws -> (WorkspaceModel, LibraryStore, Presentation, Arrangement) {
        let store = try LibraryStore.inMemory()
        let model = WorkspaceModel(store: store)
        await model.load()
        let p = try #require(await model.importLyrics(title: "Song", primaryText: song, secondaryText: nil, maxLines: 2))
        await model.openPresentation(p.id)
        let order = try #require(await model.createSectionOrder(name: "Set"))
        return (model, store, p, order)
    }

    func stored(_ model: WorkspaceModel, _ store: LibraryStore, _ p: Presentation) async throws -> [String] {
        let found = try #require(try await store.arrangements(of: p.id).first)
        return found.groupIDs.compactMap { id in model.groups.first { $0.id == id }?.name }
    }

    func chorus(_ model: WorkspaceModel) throws -> UUID { try #require(model.groups.first { $0.name == "Chorus" }).id }

    // The reviewer's case: order [Verse 1, Chorus, Verse 2, Bridge]. Remove row 1 and, before the list is re-read, row 3 as drawn.
    @Test func twoQuickRemovesRemoveTheTwoRowsThatWereClicked() async throws {
        let (model, store, p, order) = try await ready()
        #expect(try await stored(model, store, p) == ["Verse 1", "Chorus", "Verse 2", "Bridge"])
        async let first: Void = model.removeSection(at: 1, fromSectionOrder: order.id)
        async let second: Void = model.removeSection(at: 3, fromSectionOrder: order.id)
        _ = await (first, second)
        #expect(try await stored(model, store, p) == ["Verse 1", "Verse 2"])
        let names = model.arrangements.first?.groupIDs.compactMap { id in model.groups.first { $0.id == id }?.name }
        #expect(names == ["Verse 1", "Verse 2"], "the model followed the library")
    }

    @Test func twoQuickMovesAreBothApplied() async throws {
        let (model, store, p, order) = try await ready()
        // [Verse 1, Chorus, Verse 2, Bridge]: Verse 1 later by one, and at once the Bridge earlier by one.
        async let first: Void = model.moveSection(from: 0, to: 1, inSectionOrder: order.id)
        async let second: Void = model.moveSection(from: 3, to: 2, inSectionOrder: order.id)
        _ = await (first, second)
        #expect(try await stored(model, store, p) == ["Chorus", "Verse 1", "Bridge", "Verse 2"])
    }

    @Test func aRemoveAndAnAddInterleaveWithoutLosingEither() async throws {
        let (model, store, p, order) = try await ready()
        let bridge = try #require(model.groups.first { $0.name == "Bridge" }).id
        async let first: Void = model.removeSection(at: 0, fromSectionOrder: order.id)
        async let second: Void = model.addSection(bridge, toSectionOrder: order.id)
        _ = await (first, second)
        #expect(try await stored(model, store, p) == ["Chorus", "Verse 2", "Bridge", "Bridge"])
    }

    @Test func aRepeatedSectionIsToldApartByWhichOccurrenceItIs() async throws {
        let (model, store, p, order) = try await ready()
        await model.addSection(try chorus(model), toSectionOrder: order.id)                // Verse 1, Chorus, Verse 2, Bridge, Chorus
        let entries = model.sectionEntries(of: try #require(model.arrangements.first))
        #expect(entries.map(\.occurrence) == [0, 0, 0, 0, 1])
        await model.removeSection(entries[4], fromSectionOrder: order.id)                  // the second Chorus
        #expect(try await stored(model, store, p) == ["Verse 1", "Chorus", "Verse 2", "Bridge"])
        #expect(model.lastError == nil)
    }

    @Test func anEntryThatIsGoneIsANoOpWithAMessage() async throws {
        let (model, store, p, order) = try await ready()
        await model.addSection(try chorus(model), toSectionOrder: order.id)                // two Choruses
        let entries = model.sectionEntries(of: try #require(model.arrangements.first))
        // The first and then the second Chorus are removed. Once the first is gone the other Chorus is the first one, so "the second Chorus" does
        // not exist any more: that click changes nothing (it never takes a different section) and says so. (In order: two racing tasks start in no
        // fixed order, so the race itself is covered by the tests above, whose result does not depend on which runs first.)
        await model.removeSection(entries[1], fromSectionOrder: order.id)
        #expect(model.lastError == nil)
        await model.removeSection(entries[4], fromSectionOrder: order.id)
        #expect(try await stored(model, store, p) == ["Verse 1", "Verse 2", "Bridge", "Chorus"])
        #expect(model.lastError?.contains("no longer") == true)
        model.lastError = nil
        // A click on an entry that no longer exists changes nothing and says so; so does a move.
        await model.removeSection(entries[4], fromSectionOrder: order.id)
        #expect(try await stored(model, store, p) == ["Verse 1", "Verse 2", "Bridge", "Chorus"])
        #expect(model.lastError?.contains("no longer") == true)
        await model.moveSection(entries[4], by: -1, inSectionOrder: order.id)
        #expect(try await stored(model, store, p) == ["Verse 1", "Verse 2", "Bridge", "Chorus"])
    }

    @Test func aDeletedOrderIsANoOpWithAMessage() async throws {
        let (model, store, p, order) = try await ready()
        let entries = model.sectionEntries(of: try #require(model.arrangements.first))
        await model.deleteSectionOrder(id: order.id)
        model.lastError = nil
        await model.removeSection(entries[0], fromSectionOrder: order.id)
        #expect(try await store.arrangements(of: p.id).isEmpty)
        #expect(model.lastError?.contains("no longer") == true)
    }

    @Test func aDragIsPlacedBeforeTheEntryItWasDroppedOn() async throws {
        let (model, store, p, order) = try await ready()
        let entries = model.sectionEntries(of: try #require(model.arrangements.first))
        await model.moveSection(entries[3], before: entries[1], inSectionOrder: order.id)       // the Bridge before the Chorus
        #expect(try await stored(model, store, p) == ["Verse 1", "Bridge", "Chorus", "Verse 2"])
        let after = model.sectionEntries(of: try #require(model.arrangements.first))
        await model.moveSection(after[0], before: nil, inSectionOrder: order.id)                // Verse 1 to the end
        #expect(try await stored(model, store, p) == ["Bridge", "Chorus", "Verse 2", "Verse 1"])
    }
}
