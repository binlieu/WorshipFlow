// UI-002 Part 5: playlist section headers and countdown items. Stepping, countdown arithmetic and storage encoding.
import Testing
import Foundation
@testable import Domain

@Suite struct UI002_PlaylistSteppingTests {
    let pres = PlaylistItemKind.presentation
    let head = PlaylistItemKind.header(label: "Worship")
    let down = PlaylistItemKind.countdown(CountdownSpec(label: "Starting soon", mode: .duration(seconds: 300)))

    @Test func headersAreNotSelectableForLiveAndOthersAre() {
        #expect(!head.isSelectableLive && pres.isSelectableLive && down.isSelectableLive)
    }
    @Test func nextSkipsOverHeaders() {
        let kinds = [head, pres, head, head, pres, down]
        #expect(PlaylistStepping.target(kinds: kinds, from: 1, direction: 1) == 4)
        #expect(PlaylistStepping.target(kinds: kinds, from: 4, direction: 1) == 5)
        #expect(PlaylistStepping.target(kinds: kinds, from: 4, direction: -1) == 1)
    }
    @Test func nothingBeforeTheFirstOrAfterTheLastPlayableItem() {
        let kinds = [head, pres, head, down]
        #expect(PlaylistStepping.target(kinds: kinds, from: 1, direction: -1) == nil)      // only a header before it
        #expect(PlaylistStepping.target(kinds: kinds, from: 3, direction: 1) == nil)       // a countdown as the last item
        #expect(PlaylistStepping.target(kinds: [pres, head], from: 0, direction: 1) == nil)  // trailing header
    }
    @Test func fromNothingTheFirstPlayableItemIsFound() {
        #expect(PlaylistStepping.target(kinds: [head, head, pres], from: nil, direction: 1) == 2)
        #expect(PlaylistStepping.target(kinds: [head], from: nil, direction: 1) == nil)
    }
    @Test func anEmptyPlaylistHasNoTarget() {
        #expect(PlaylistStepping.target(kinds: [], from: nil, direction: 1) == nil)
        #expect(PlaylistStepping.target(kinds: [], from: 0, direction: -1) == nil)
    }
    @Test func aPlaceOnAHeaderLandsOnTheNextPlayableItem() {
        // Relaunch restore: the stored place is a header; the preview lands on the nearest playable item after it, else before it.
        #expect(PlaylistStepping.landing(kinds: [head, pres, down], at: 0) == 1)
        #expect(PlaylistStepping.landing(kinds: [pres, head], at: 1) == 0)
        #expect(PlaylistStepping.landing(kinds: [head], at: 0) == nil)
        #expect(PlaylistStepping.landing(kinds: [pres, down], at: 1) == 1)
    }
    @Test func afterDeletingTheLiveItemTheNeighbourIsNotTakenLive() {
        // Deleting leaves nothing live; the stepper only reports where a later Next would go.
        #expect(PlaylistStepping.target(kinds: [pres, pres], from: 0, direction: 1) == 1)
    }
}

@Suite struct UI002_CountdownTests {
    var calendar: Calendar { var c = Calendar(identifier: .gregorian); c.timeZone = TimeZone(identifier: "UTC")!; return c }
    func date(_ h: Int, _ m: Int, _ s: Int = 0) -> Date {
        calendar.date(from: DateComponents(year: 2026, month: 11, day: 22, hour: h, minute: m, second: s))!
    }

    @Test func aDurationCountsDownFromWhenItWentLive() {
        let run = CountdownRun(spec: CountdownSpec(label: "", mode: .duration(seconds: 300)), startedAt: date(9, 0), calendar: calendar)
        #expect(run.remaining(at: date(9, 0)) == 300)
        #expect(run.remaining(at: date(9, 1, 30)) == 210)
    }
    @Test func aTargetTimeCountsToThatTimeToday() {
        let run = CountdownRun(spec: CountdownSpec(label: "", mode: .targetTime(hour: 9, minute: 30)), startedAt: date(9, 0), calendar: calendar)
        #expect(run.remaining(at: date(9, 0)) == 1800 && run.remaining(at: date(9, 29, 59)) == 1)
    }
    @Test func aTargetTimeAlreadyPastIsZero() {
        let run = CountdownRun(spec: CountdownSpec(label: "", mode: .targetTime(hour: 8, minute: 0)), startedAt: date(9, 0), calendar: calendar)
        #expect(run.remaining(at: date(9, 0)) == 0 && run.isFinished(at: date(9, 0)))
    }
    @Test func atZeroItStaysAtZeroForever() {
        let run = CountdownRun(spec: CountdownSpec(label: "", mode: .duration(seconds: 5)), startedAt: date(9, 0), calendar: calendar)
        #expect(run.remaining(at: date(9, 0, 5)) == 0 && run.remaining(at: date(23, 59)) == 0)
        #expect(CountdownText.format(run.remaining(at: date(12, 0))) == "0:00")
    }
    @Test func aClockGoingBackwardsDoesNotExceedTheDuration() {
        let run = CountdownRun(spec: CountdownSpec(label: "", mode: .duration(seconds: 60)), startedAt: date(9, 0), calendar: calendar)
        #expect(run.remaining(at: date(8, 0)) == 60)
    }
    @Test func textIsMinutesAndSecondsOrHours() {
        #expect(CountdownText.format(0) == "0:00" && CountdownText.format(65) == "1:05" && CountdownText.format(600) == "10:00")
        #expect(CountdownText.format(3725) == "1:02:05" && CountdownText.format(-4) == "0:00")
    }
    @Test func specsValidateTheirNumbers() {
        #expect(CountdownSpec(label: "x", mode: .duration(seconds: -5)).mode == .duration(seconds: 0))
        #expect(CountdownSpec(label: "x", mode: .targetTime(hour: 30, minute: 99)).mode == .targetTime(hour: 23, minute: 59))
    }
}

@Suite struct UI002_PlaylistKindStorageTests {
    @Test func everyKindRoundTripsThroughItsStoredForm() throws {
        let kinds: [PlaylistItemKind] = [.presentation, .header(label: "Pre-service"),
                                         .countdown(CountdownSpec(label: "Starting soon", mode: .targetTime(hour: 9, minute: 0)))]
        for kind in kinds {
            let stored = kind.stored
            #expect(PlaylistItemKind(storedKind: stored.kind, payload: stored.payload) == kind)
        }
        #expect(PlaylistItemKind.presentation.stored.payload == nil)
    }
    @Test func anUnreadableStoredItemBecomesAHeaderNotACrash() {
        #expect(PlaylistItemKind(storedKind: "countdown", payload: "not json") == .header(label: "Countdown"))
        #expect(PlaylistItemKind(storedKind: "future-kind", payload: nil) == .header(label: "Unknown item"))
        #expect(PlaylistItemKind(storedKind: "header", payload: nil) == .header(label: "Header"))
    }
    @Test func aPlaylistItemDefaultsToAPresentation() {
        let item = PlaylistItem(playlistID: UUID(), presentationID: UUID(), title: "S", sortOrder: 0)
        #expect(item.kind == .presentation)
    }
}
