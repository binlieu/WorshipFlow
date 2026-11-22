// FIX-M: the pure rules behind a drop that shows at once. A reorder moves rows by stable identity: the set of cell identities is the same
// before and after, and only the positions between the two ends are marked dirty. The tracker knows which order the database holds, so a
// failed write can put the visible order back. No wall-clock assertions: the numbers per drag kind are in AI/reports/FIX-M-report.md.
import Testing
import Foundation
@testable import OperatorCore

@Suite struct FIXM_OrderTests {
    @Test func movedPutsTheRowAtTheTargetAndClamps() {
        #expect(OrderMove.moved([1, 2, 3, 4, 5], from: 4, to: 1) == [1, 5, 2, 3, 4])
        #expect(OrderMove.moved([1, 2, 3, 4, 5], from: 0, to: 3) == [2, 3, 4, 1, 5])
        #expect(OrderMove.moved([1, 2, 3], from: 0, to: 99) == [2, 3, 1])
        #expect(OrderMove.moved([1, 2, 3], from: 2, to: -4) == [3, 1, 2])
        #expect(OrderMove.moved([1, 2, 3], from: 1, to: 1) == [1, 2, 3])
        #expect(OrderMove.moved([1, 2, 3], from: 7, to: 0) == [1, 2, 3])        // a source that is not there changes nothing
    }

    @Test func onlyThePositionsBetweenTheEndsAreDirty() {
        #expect(OrderMove.dirtyRange(count: 200, from: 149, to: 19) == 19...149)
        #expect(OrderMove.dirtyRange(count: 200, from: 3, to: 4) == 3...4)
        #expect(OrderMove.dirtyRange(count: 200, from: 5, to: 5) == nil)
        #expect(OrderMove.dirtyRange(count: 10, from: 2, to: 99) == 2...9)
        #expect(OrderMove.dirtyRange(count: 0, from: 0, to: 0) == nil)
        let before = Array(0..<200), after = OrderMove.moved(before, from: 149, to: 19)
        let changed = Set(before.indices.filter { before[$0] != after[$0] })
        #expect(changed == Set(19...149))                                         // the marked range is exactly what changed
        #expect(changed == Set(OrderMove.dirtyRange(count: 200, from: 149, to: 19)!))
    }

    @Test func restoringReturnsRowsToAnOrderByIdentityKeepingTheirNewContent() {
        struct Row: Identifiable, Equatable { let id: Int; var text: String }
        let rows = [Row(id: 1, text: "a"), Row(id: 2, text: "b"), Row(id: 3, text: "c")]
        var shown = OrderMove.moved(rows, from: 2, to: 0)
        shown[0].text = "typed meanwhile"
        let back = OrderMove.restoring(shown, toOrder: [1, 2, 3])
        #expect(back.map(\.id) == [1, 2, 3] && back[2].text == "typed meanwhile")
        #expect(OrderMove.restoring(shown, toOrder: [3, 9]).map(\.id) == [3, 1, 2])   // rows the order does not know keep their relative place, after it
    }

    @Test func cellIdentitiesSurviveAReorderAndRepeatedSlidesStayDistinct() {
        let ids = (0..<200).map { _ in UUID() }
        let keys = SlideCellKey.keys(for: ids)
        let moved = OrderMove.moved(ids, from: 149, to: 19)
        let after = SlideCellKey.keys(for: moved)
        #expect(Set(keys) == Set(after))                                          // the same identities, only in other places
        #expect(Set(keys).count == 200)
        for p in 0..<19 { #expect(keys[p] == after[p]) }                          // nothing outside the moved range is touched
        for p in 150..<200 { #expect(keys[p] == after[p]) }
        let repeated = [ids[0], ids[1], ids[0], ids[0]]                           // an arrangement can repeat a slide
        let k = SlideCellKey.keys(for: repeated)
        #expect(Set(k).count == 4 && k[0].occurrence == 0 && k[2].occurrence == 1 && k[3].occurrence == 2)
        #expect(Set(SlideCellKey.keys(for: ids.reversed())) == Set(keys))
    }

    @Test func theTrackerKeepsTheOrderTheDatabaseHoldsAndSaysWhenToPutBack() {
        var t = ReorderTracker<Int>()
        #expect(t.isIdle)
        t.begin(current: [1, 2, 3, 4])                                            // first drop: the database still holds 1 2 3 4
        t.begin(current: [2, 1, 3, 4])                                            // a second drop arrives before the first write ended
        t.begin(current: [2, 1, 4, 3])                                            // and a third
        #expect(t.confirmed == [1, 2, 3, 4] && !t.isIdle)
        let epoch = t.epoch
        t.succeeded(id: 1, to: 1)
        #expect(t.confirmed == [2, 1, 3, 4] && !t.isIdle)
        let restore = t.failed()                                                  // the second write failed
        #expect(restore == [2, 1, 3, 4] && t.epoch == epoch + 1)
        #expect(t.isStale(epoch))                                                 // anything queued behind it must not run
        #expect(!t.isIdle)
        t.skipped()                                                               // the third was dropped without a write
        #expect(t.isIdle)
    }
}
