// UI-006d: named collections of bin items (the design's "Announcement loop" and "Motion backgrounds" rows). A collection holds
// references only; it never moves, copies or deletes a file, and removing a bin item takes it out of every collection.
import Testing
import Foundation
import Domain
import Persistence
@testable import OperatorCore

@Suite struct UI006d_CollectionValueTests {
    @Test func namesAreTrimmedNeverEmptyAndUniqueIgnoringCase() throws {
        var c = MediaCollections()
        let id = try c.create(name: "  Announcement loop ")
        #expect(c.collection(id)?.name == "Announcement loop")
        func problem(_ body: () throws -> Void) -> MediaCollections.NameProblem? {
            do { try body(); return nil } catch { return error as? MediaCollections.NameProblem }
        }
        let p1 = problem { try c.create(name: "   ") }
        #expect(p1 == .empty)
        let p2 = problem { try c.create(name: "announcement LOOP") }
        #expect(p2 == .taken)
        let other = try c.create(name: "Sound cues")
        let p3 = problem { try c.rename(other, to: "Announcement Loop") }
        #expect(p3 == .taken)
        try c.rename(other, to: "Sound cues")      // its own name again is fine
        try c.rename(other, to: "Walk-in")
        #expect(c.collection(other)?.name == "Walk-in")
    }

    @Test func addingKeepsOrderIgnoresRepeatsAndCountsWhatIsNew() throws {
        var c = MediaCollections()
        let id = try c.create(name: "A")
        let x = UUID(), y = UUID()
        let first = c.add([x, y, x], to: id), second = c.add([y], to: id)
        #expect(first == 2 && second == 0)
        #expect(c.collection(id)?.assetIDs == [x, y])
        c.remove([x], from: id)
        #expect(c.collection(id)?.assetIDs == [y])
    }

    @Test func pruningDropsItemsTheBinNoLongerHasAndReportsAChange() throws {
        var c = MediaCollections()
        let id = try c.create(name: "A")
        let x = UUID(), y = UUID()
        c.add([x, y], to: id)
        let changed = c.prune(keeping: [y])
        #expect(changed)
        #expect(c.collection(id)?.assetIDs == [y])
        let again = c.prune(keeping: [y])
        #expect(!again)
    }

    @Test func theItemsOfACollectionComeInBinOrder() throws {
        var c = MediaCollections()
        let id = try c.create(name: "A")
        let a = MediaAsset(name: "a", kind: .video, path: "/a"), b = MediaAsset(name: "b", kind: .image, path: "/b"), d = MediaAsset(name: "d", kind: .video, path: "/d")
        c.add([d.id, a.id], to: id)
        #expect(c.assets(in: id, from: [a, b, d]).map(\.name) == ["a", "d"])
    }

    @Test func itSurvivesTheStoredTextAndATornOrUnknownTextGivesNothing() throws {
        var c = MediaCollections()
        let id = try c.create(name: "A"); c.add([UUID()], to: id)
        #expect(MediaCollections.decoded(c.encoded()) == c)
        #expect(MediaCollections.decoded(nil) == MediaCollections())
        #expect(MediaCollections.decoded("{not json") == MediaCollections())
    }

    @Test func deletingACollectionLeavesTheOthersAlone() throws {
        var c = MediaCollections()
        let a = try c.create(name: "A"), b = try c.create(name: "B")
        c.delete(a)
        #expect(c.items.map(\.id) == [b])
    }
}

@MainActor
@Suite struct UI006d_CollectionModelTests {
    @Test func creatingAddingFilteringAndRelaunchingKeepsTheCollection() async throws {
        let rig = try MediaRig()
        let a = await rig.add("a.mov"), b = await rig.add("b.png"), _ = await rig.add("c.mov")
        let id = try #require(rig.model.createCollection("Announcement loop", adding: [a.id, b.id]))
        rig.model.collectionFilter = id
        #expect(rig.model.visibleAssets.map(\.id) == [a.id, b.id])
        rig.model.collectionFilter = nil
        #expect(rig.model.visibleAssets.count == 3)
        await rig.model.flush()
        let again = try #require(rig.relaunched())
        await again.model.load()
        #expect(again.model.collections.collection(id)?.assetIDs == [a.id, b.id])
    }

    @Test func removingABinItemTakesItOutOfItsCollectionsAndStoresThat() async throws {
        let rig = try MediaRig()
        let a = await rig.add("a.mov"), b = await rig.add("b.mov")
        let id = try #require(rig.model.createCollection("A", adding: [a.id, b.id]))
        await rig.model.remove(a.id)
        #expect(rig.model.collections.collection(id)?.assetIDs == [b.id])
        await rig.model.flush()
        let again = try #require(rig.relaunched())
        await again.model.load()
        #expect(again.model.collections.collection(id)?.assetIDs == [b.id])
    }

    @Test func aBadNameIsRefusedWithAMessageAndChangesNothing() async throws {
        let rig = try MediaRig()
        _ = rig.model.createCollection("A")
        #expect(rig.model.createCollection("a") == nil)
        #expect(rig.model.lastError != nil)
        #expect(rig.model.collections.items.count == 1)
    }

    @Test func deletingTheOpenCollectionGoesBackToTheWholeBinAndNeverTouchesTheItems() async throws {
        let rig = try MediaRig()
        let a = await rig.add("a.mov")
        let id = try #require(rig.model.createCollection("A", adding: [a.id]))
        rig.model.collectionFilter = id
        rig.model.deleteCollection(id)
        #expect(rig.model.collectionFilter == nil)
        #expect(rig.model.assets.map(\.id) == [a.id])
        #expect(rig.model.visibleAssets.map(\.id) == [a.id])
    }

    @Test func removingFromTheOpenCollectionKeepsTheItemInTheBin() async throws {
        let rig = try MediaRig()
        let a = await rig.add("a.mov")
        let id = try #require(rig.model.createCollection("A", adding: [a.id]))
        rig.model.removeFromCollection([a.id], collection: id)
        #expect(rig.model.collections.collection(id)?.assetIDs.isEmpty == true)
        #expect(rig.model.assets.count == 1)
    }
}
