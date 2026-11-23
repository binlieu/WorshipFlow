// FIX-X item 2 (MEDIA, CUE-33; REVIEW-5 L9, L13): the one decision behind deleting a marker.
import Testing
import Foundation
@testable import OperatorCore

@Suite struct FIXX_MarkerDeleteConfirmationTests {
    @Test func aMarkerWithNoActionsIsDeletedAtOnce() {
        #expect(MarkerDeleteConfirmation.prompt(name: "Verse", time: 12, actionCount: 0, actionsAreUnreadable: false) == nil)
    }

    @Test func aMarkerWithActionsAsksAndNamesTheMarkerAndTheCount() throws {
        let p = try #require(MarkerDeleteConfirmation.prompt(name: "Verse", time: 12, actionCount: 3, actionsAreUnreadable: false))
        #expect(p.title.contains("Verse"))
        #expect(p.message.contains("3 actions"))
        #expect(p.message.contains("cannot be undone"))
        #expect(p.confirmTitle == "Delete marker")
    }

    @Test func oneActionIsSingular() throws {
        let p = try #require(MarkerDeleteConfirmation.prompt(name: "Verse", time: 12, actionCount: 1, actionsAreUnreadable: false))
        #expect(p.message.contains("1 action ") && !p.message.contains("1 actions"))
    }

    @Test func aMarkerWithoutANameIsNamedByItsTime() throws {
        let p = try #require(MarkerDeleteConfirmation.prompt(name: nil, time: 65.5, actionCount: 2, actionsAreUnreadable: false))
        #expect(p.title.contains(MediaTimeText.format(65.5)))
        let blank = try #require(MarkerDeleteConfirmation.prompt(name: "  ", time: 65.5, actionCount: 2, actionsAreUnreadable: false))
        #expect(blank.title == p.title)
    }

    @Test func storedActionsThatCannotBeReadStillAskBecauseTheyAreLostToo() throws {
        let p = try #require(MarkerDeleteConfirmation.prompt(name: "Verse", time: 12, actionCount: 0, actionsAreUnreadable: true))
        #expect(p.message.contains("cannot read"))
    }
}
