// STAGE-001a: the standard layout must draw what the built-in stage scene draws today.
import Testing
import Foundation
@testable import Domain

@Suite struct StageParityTests {
    private func state(live: Bool, cleared: Bool = false) -> ShowState {
        var s = ShowState()
        s.apply(.load(ShowDeck(presentationID: UUID(), slides: [
            SlideContent(primary: "One", secondary: "Mot"),
            SlideContent(primary: "Two", secondary: "Hai"),
        ])))
        if live { s.apply(.trigger(index: 0)) }
        if cleared { s.apply(.clear) }
        return s
    }

    @Test func standardLayoutMatchesBuiltInStageScene() {
        for (live, cleared) in [(true, false), (true, true), (false, false)] {
            for clock in [nil, "", "10:32"] as [String?] {
                let s = state(live: live, cleared: cleared)
                let old = SceneComposer.scene(for: .stage, state: s, clockText: clock)
                let new = StageComposer.scene(layout: .standard,
                    context: StageContext(state: s, now: 0, timeOfDayText: clock ?? "", timers: [], message: nil, notes: nil))
                #expect(new == old)
            }
        }
    }

    @Test func timeFormatEdgeCases() {
        #expect(TimeFormat.clock(seconds: .nan) == "0:00")
        #expect(TimeFormat.clock(seconds: .infinity) == "99:59:59")
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = TimeZone(identifier: "UTC")!
        let midnight = cal.date(from: DateComponents(year: 2026, month: 1, day: 1, hour: 0, minute: 7, second: 3))!
        #expect(TimeFormat.timeOfDay(midnight, calendar: cal, twentyFourHour: false, showSeconds: true) == "12:07:03 AM")
        #expect(TimeFormat.timeOfDay(midnight, calendar: cal, twentyFourHour: true, showSeconds: false) == "00:07")
    }

    @Test func timerPausedAfterClockWentBackwardsNeverGoesNegativeRun() {
        var t = ShowTimer(id: UUID(), name: "T", kind: .elapsed)
        t.start(at: 100)
        #expect(t.value(at: 50) == 0)
    }
}
