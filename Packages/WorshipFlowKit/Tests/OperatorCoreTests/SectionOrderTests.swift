// APP-001 / KI-023: the section order editor's rules and the model methods behind it.
import Testing
import Foundation
import Domain
import Persistence
@testable import OperatorCore

@Suite struct SectionOrderEditingTests {
    let a = UUID(), b = UUID(), c = UUID()

    @Test func appendRemoveAndMove() {
        #expect(SectionOrderEditing.appending(c, to: [a, b]) == [a, b, c])
        #expect(SectionOrderEditing.appending(a, to: [a]) == [a, a])                      // a section may repeat
        #expect(SectionOrderEditing.removing(at: 1, from: [a, b, c]) == [a, c])
        #expect(SectionOrderEditing.removing(at: 9, from: [a, b, c]) == [a, b, c])
        #expect(SectionOrderEditing.removing(at: -1, from: [a, b, c]) == [a, b, c])
        #expect(SectionOrderEditing.moving(from: 0, to: 2, in: [a, b, c]) == [b, c, a])
        #expect(SectionOrderEditing.moving(from: 2, to: 0, in: [a, b, c]) == [c, a, b])
        #expect(SectionOrderEditing.moving(from: 1, to: 99, in: [a, b, c]) == [a, c, b])  // clamped
        #expect(SectionOrderEditing.moving(from: 7, to: 0, in: [a, b, c]) == [a, b, c])
    }

    @Test func dragReorderUsesListOffsets() {
        // SwiftUI reports the position in the list before the move: dropping entry 0 after entry 2 is offset 3.
        #expect(SectionOrderEditing.moving(from: 0, toOffset: 3, in: [a, b, c]) == [b, c, a])
        #expect(SectionOrderEditing.moving(from: 2, toOffset: 0, in: [a, b, c]) == [c, a, b])
        #expect(SectionOrderEditing.moving(from: 1, toOffset: 1, in: [a, b, c]) == [a, b, c])
        #expect(SectionOrderEditing.moving(from: 1, toOffset: 2, in: [a, b, c]) == [a, b, c])
    }

    @Test func naturalOrderAndNames() {
        let p = UUID()
        let groups = [SlideGroup(id: b, presentationID: p, name: "Chorus", sortOrder: 1),
                      SlideGroup(id: a, presentationID: p, name: "Verse", sortOrder: 0)]
        #expect(SectionOrderEditing.naturalOrder(of: groups) == [a, b])
        #expect(SectionOrderEditing.newName(existing: []) == "Order 1")
        #expect(SectionOrderEditing.newName(existing: ["Order 2"]) == "Order 3")
        #expect(SectionOrderEditing.newName(existing: ["order 2", "Radio"]) == "Order 3")
    }

    @Test func slideCountFollowsRepeats() {
        let p = UUID()
        func slide(_ g: UUID?) -> Slide { Slide(presentationID: p, content: SlideContent(primary: "x"), groupID: g) }
        let slides = [slide(a), slide(a), slide(b), slide(nil)]
        let counts = SectionOrderEditing.slideCounts(of: slides + [slides[0]])           // a repeated slide counts once
        #expect(counts == [a: 2, b: 1])
        #expect(SectionOrderEditing.slideCount(of: [a, b, a], counts: counts) == 5)
        #expect(SectionOrderEditing.slideCount(of: [], counts: counts) == 0)
        #expect(SectionOrderEditing.slideCount(of: [c], counts: counts) == 0)
    }
}

@MainActor
@Suite struct SectionOrderModelTests {
    let song = "Verse 1\nline v1\n\nChorus\nline ch\n\nVerse 2\nline v2"

    func ready() async throws -> (WorkspaceModel, LibraryStore, Presentation) {
        let store = try LibraryStore.inMemory()
        let model = WorkspaceModel(store: store)
        await model.load()
        let p = try #require(await model.importLyrics(title: "Song", primaryText: song, secondaryText: nil, maxLines: 2))
        await model.openPresentation(p.id)
        return (model, store, p)
    }

    func names(_ model: WorkspaceModel, _ order: Arrangement) -> [String] {
        order.groupIDs.compactMap { id in model.groups.first { $0.id == id }?.name }
    }

    @Test func aNewOrderStartsAsTheNaturalOrderAndGetsADefaultName() async throws {
        let (model, store, p) = try await ready()
        let order = try #require(await model.createSectionOrder())
        #expect(order.name == "Order 1")
        #expect(names(model, order) == ["Verse 1", "Chorus", "Verse 2"])
        #expect(model.arrangements.map(\.id) == [order.id])
        #expect(try await store.arrangements(of: p.id).map(\.id) == [order.id])
        let second = try #require(await model.createSectionOrder(name: "  Sunday  "))
        #expect(second.name == "Sunday")
        #expect(model.arrangements.count == 2)
    }

    @Test func addRemoveAndReorderSectionsAreSaved() async throws {
        let (model, store, p) = try await ready()
        let order = try #require(await model.createSectionOrder(name: "Short"))
        let chorus = try #require(model.groups.first { $0.name == "Chorus" })
        await model.addSection(chorus.id, toSectionOrder: order.id)                      // Verse 1, Chorus, Verse 2, Chorus
        func stored() async throws -> [String] {
            let found = try #require(try await store.arrangements(of: p.id).first)
            return names(model, found)
        }
        #expect(try await stored() == ["Verse 1", "Chorus", "Verse 2", "Chorus"])
        await model.removeSection(at: 2, fromSectionOrder: order.id)                     // Verse 1, Chorus, Chorus
        #expect(try await stored() == ["Verse 1", "Chorus", "Chorus"])
        await model.moveSection(from: 0, to: 2, inSectionOrder: order.id)                // Chorus, Chorus, Verse 1
        #expect(try await stored() == ["Chorus", "Chorus", "Verse 1"])
        #expect(model.arrangements.first.map { names(model, $0) } == ["Chorus", "Chorus", "Verse 1"])   // the model followed
        #expect(model.lastError == nil)
        await model.removeSection(at: 40, fromSectionOrder: order.id)                    // out of range: nothing happens
        #expect(try await stored() == ["Chorus", "Chorus", "Verse 1"])
    }

    @Test func sectionSlideCountsDoNotDependOnThePlayOrder() async throws {
        let (model, _, p) = try await ready()
        await model.addToPlaylist(p.id)
        let item = try #require(model.playlistItems.first)
        await model.openPlaylistItem(item.id)
        #expect(model.groupSlideCounts.values.reduce(0, +) == 3)
        let order = try #require(await model.createSectionOrder(name: "Chorus only"))
        for _ in 0..<2 { await model.removeSection(at: 0, fromSectionOrder: order.id) }      // leaves just the last section
        await model.setArrangement(order.id, forPlaylistItem: item.id)
        #expect(model.slides.count == 1)
        #expect(model.groupSlideCounts.values.reduce(0, +) == 3)                             // the song still has three
    }

    @Test func renameAndDelete() async throws {
        let (model, _, _) = try await ready()
        let order = try #require(await model.createSectionOrder(name: "Old"))
        await model.renameSectionOrder(id: order.id, to: "New")
        #expect(model.arrangements.map(\.name) == ["New"])
        await model.renameSectionOrder(id: order.id, to: "   ")
        #expect(model.arrangements.map(\.name) == ["New"])
        #expect(model.lastError?.contains("a name is needed") == true)
        model.dismissError()
        await model.deleteSectionOrder(id: order.id)
        #expect(model.arrangements.isEmpty && model.lastError == nil)
        await model.deleteSectionOrder(id: UUID())                                       // unknown id: ignored
        #expect(model.lastError == nil)
    }

    @Test func aPlaylistItemPlaysTheChosenOrderAndFallsBackWhenItIsDeleted() async throws {
        let (model, _, p) = try await ready()
        await model.addToPlaylist(p.id)
        let item = try #require(model.playlistItems.first)
        await model.openPlaylistItem(item.id)
        let order = try #require(await model.createSectionOrder(name: "Chorus first"))
        await model.moveSection(from: 1, to: 0, inSectionOrder: order.id)                // Chorus, Verse 1, Verse 2
        await model.setArrangement(order.id, forPlaylistItem: item.id)
        #expect(model.slides.map(\.content.primary) == ["line ch", "line v1", "line v2"])
        #expect(model.sectionOrderName(forPlaylistItem: item.id) == "Chorus first")

        await model.deleteSectionOrder(id: order.id)
        #expect(model.playlistItems.first?.arrangementID == nil)
        #expect(model.slides.map(\.content.primary) == ["line v1", "line ch", "line v2"])
        #expect(model.lastError == nil)
    }

    @Test func choicesForAnItemThatIsNotOpenComeFromItsOwnSong() async throws {
        let (model, _, p) = try await ready()
        _ = try #require(await model.createSectionOrder(name: "Mine"))
        let other = try #require(await model.importLyrics(title: "Other", primaryText: "one\n\ntwo", secondaryText: nil, maxLines: 1))
        await model.addToPlaylist(p.id)
        await model.addToPlaylist(other.id)
        let first = try #require(model.playlistItems.first { $0.presentationID == p.id })
        let second = try #require(model.playlistItems.first { $0.presentationID == other.id })
        await model.openPlaylistItem(second.id)                                          // the other song is open
        #expect(await model.sectionOrderChoices(forPlaylistItem: first.id).map(\.name) == ["Mine"])
        #expect(await model.sectionOrderChoices(forPlaylistItem: second.id).isEmpty)
        #expect(await model.sectionOrderChoices(forPlaylistItem: UUID()).isEmpty)
    }

    @Test func anOrderFromAnotherSongIsRefusedWithAMessage() async throws {
        let (model, _, p) = try await ready()
        let mine = try #require(await model.createSectionOrder(name: "Mine"))
        let other = try #require(await model.importLyrics(title: "Other", primaryText: "one\n\ntwo", secondaryText: nil, maxLines: 1))
        await model.addToPlaylist(other.id)
        let item = try #require(model.playlistItems.first)
        await model.setArrangement(mine.id, forPlaylistItem: item.id)
        #expect(model.lastError?.contains("different song") == true)
        #expect(model.playlistItems.first?.arrangementID == nil)
        _ = p
    }
}
