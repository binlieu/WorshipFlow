// FIX-Y item 3 (MEDIA; REVIEW-5 L4): focusing and leaving a mark or marker time field must not change the stored time.
import Testing
import Foundation
@testable import OperatorCore

@Suite struct FIXY_TimeFieldEditTests {
    @Test func leavingAFieldThatShowsTheRoundedTimeChangesNothing() {
        let stored = 12.37
        let shown = MediaTimeText.format(stored)                       // "00:12.4"
        #expect(TimeFieldEdit.edit(text: shown, stored: stored, emptyClears: true) == .unchanged)
        #expect(TimeFieldEdit.edit(text: shown, stored: stored, emptyClears: false) == .unchanged)
    }

    @Test func aNewValueTheOperatorTypedIsWritten() {
        #expect(TimeFieldEdit.edit(text: "00:13.0", stored: 12.37, emptyClears: true) == .set(13))
        #expect(TimeFieldEdit.edit(text: "12.5", stored: 12.37, emptyClears: false) == .set(12.5))
    }

    @Test func typingTheSameRoundedTextAgainOnAnExactTimeIsNotAWrite() {
        #expect(TimeFieldEdit.edit(text: "00:12.4", stored: 12.4, emptyClears: true) == .unchanged)
    }

    @Test func aMarkWithNothingStoredAndAnEmptyFieldChangesNothing() {
        #expect(TimeFieldEdit.edit(text: "", stored: nil, emptyClears: true) == .unchanged)
        #expect(TimeFieldEdit.edit(text: "  ", stored: 5, emptyClears: true) == .clear)
    }

    @Test func aMarkerTimeCannotBeEmptiedAndGarbageGoesBack() {
        #expect(TimeFieldEdit.edit(text: "", stored: 5, emptyClears: false) == .invalid)
        #expect(TimeFieldEdit.edit(text: "abc", stored: 5, emptyClears: true) == .invalid)
    }

    @Test func aTimeTypedForAMarkWithNoStoredValueIsWritten() {
        #expect(TimeFieldEdit.edit(text: "1:05", stored: nil, emptyClears: true) == .set(65))
    }
}
