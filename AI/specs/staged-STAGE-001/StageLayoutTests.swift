// STAGE-001 acceptance tests: stage layouts, clocks and countdowns (LIVE-01, LIVE-02, LIVE-04, SCRN-03).
// Owned by the coordinator: do not modify.
import Testing
import Foundation
@testable import Domain

@Suite struct ShowTimerTests {
    @Test func countdownRunsPausesAndResets() {
        var t = ShowTimer(id: UUID(), name: "Sermon", kind: .countdown(seconds: 600))
        #expect(t.isRunning == false)
        #expect(t.value(at: 1000) == 600)
        t.start(at: 1000)
        #expect(t.isRunning)
        #expect(t.value(at: 1090) == 510)
        t.pause(at: 1100)
        #expect(t.isRunning == false)
        #expect(t.value(at: 5000) == 500)             // paused: time does not move
        t.start(at: 6000)
        #expect(t.value(at: 6100) == 400)
        t.reset()
        #expect(t.isRunning == false && t.value(at: 9999) == 600)
    }

    /// A countdown keeps counting below zero so an overrun is visible.
    @Test func countdownGoesNegativeAndReportsOverrun() {
        var t = ShowTimer(id: UUID(), name: "Sermon", kind: .countdown(seconds: 60))
        t.start(at: 0)
        #expect(t.value(at: 75) == -15)
        #expect(t.isOverrun(at: 75))
        #expect(t.isOverrun(at: 30) == false)
    }

    @Test func elapsedCountsUp() {
        var t = ShowTimer(id: UUID(), name: "Service", kind: .elapsed)
        #expect(t.value(at: 50) == 0)
        t.start(at: 100)
        #expect(t.value(at: 3761) == 3661)
        t.pause(at: 3761)
        t.start(at: 4000)
        #expect(t.value(at: 4010) == 3671)
    }

    /// A countdown to a time of day ("service starts at 10:30") needs no start: it follows the wall clock.
    @Test func countdownToADateFollowsTheClock() {
        let target = Date(timeIntervalSinceReferenceDate: 10_000)
        let t = ShowTimer(id: UUID(), name: "Starts in", kind: .countdownTo(target))
        #expect(t.value(at: 9_400) == 600)
        #expect(t.value(at: 10_030) == -30)
        #expect(t.isRunning)
    }

    @Test func startingTwiceOrPausingWhenStoppedIsHarmless() {
        var t = ShowTimer(id: UUID(), name: "T", kind: .countdown(seconds: 100))
        t.pause(at: 5)
        t.start(at: 10); t.start(at: 50)
        #expect(t.value(at: 60) == 50)
    }

    @Test func timersRoundTripThroughCodableWhileRunning() throws {
        var t = ShowTimer(id: UUID(), name: "Sermon", kind: .countdown(seconds: 600))
        t.start(at: 1000)
        let decoded = try JSONDecoder().decode(ShowTimer.self, from: JSONEncoder().encode(t))
        #expect(decoded == t)
        #expect(decoded.value(at: 1060) == 540)        // a relaunch mid-countdown keeps the right time
    }
}

@Suite struct TimeFormattingTests {
    @Test func formatsMinutesAndHours() {
        #expect(TimeFormat.clock(seconds: 0) == "0:00")
        #expect(TimeFormat.clock(seconds: 9) == "0:09")
        #expect(TimeFormat.clock(seconds: 600) == "10:00")
        #expect(TimeFormat.clock(seconds: 3599) == "59:59")
        #expect(TimeFormat.clock(seconds: 3600) == "1:00:00")
        #expect(TimeFormat.clock(seconds: 3661) == "1:01:01")
    }

    @Test func negativeValuesShowAMinusSign() {
        #expect(TimeFormat.clock(seconds: -15) == "-0:15")
        #expect(TimeFormat.clock(seconds: -3661) == "-1:01:01")
    }

    /// Fractions round toward the later second for countdowns so "0:00" appears only at zero.
    @Test func roundsFractionsUpForCountdowns() {
        #expect(TimeFormat.clock(seconds: 0.2) == "0:01")
        #expect(TimeFormat.clock(seconds: 59.01) == "1:00")
        #expect(TimeFormat.clock(seconds: -0.2) == "0:00")
    }

    @Test func timeOfDayUsesTheGivenCalendarAndStyle() {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = TimeZone(identifier: "UTC")!
        let date = cal.date(from: DateComponents(year: 2026, month: 11, day: 22, hour: 14, minute: 5, second: 9))!
        #expect(TimeFormat.timeOfDay(date, calendar: cal, twentyFourHour: true, showSeconds: false) == "14:05")
        #expect(TimeFormat.timeOfDay(date, calendar: cal, twentyFourHour: true, showSeconds: true) == "14:05:09")
        #expect(TimeFormat.timeOfDay(date, calendar: cal, twentyFourHour: false, showSeconds: false) == "2:05 PM")
    }
}

@Suite struct StageComposerTests {
    func liveState() -> ShowState {
        var s = ShowState()
        s.apply(.load(ShowDeck(presentationID: UUID(), slides: [
            SlideContent(primary: "Amazing grace, how sweet the sound", secondary: "Ân điển lạ lùng thay"),
            SlideContent(primary: "That saved a wretch like me", secondary: "Đã cứu vớt tôi"),
        ])))
        s.apply(.trigger(index: 0))
        return s
    }
    func texts(_ s: SceneDescription) -> [String] { s.textLayers.map(\.text) }
    var sermon: ShowTimer {
        var t = ShowTimer(id: UUID(), name: "Sermon", kind: .countdown(seconds: 600)); t.start(at: 0); return t
    }

    @Test func standardLayoutShowsCurrentNextAndClock() {
        let layout = StageLayout.standard
        #expect(layout.elements.map(\.kind).contains(.currentSlide))
        #expect(layout.elements.map(\.kind).contains(.nextSlide))
        #expect(layout.elements.map(\.kind).contains(.timeOfDay))
        let ctx = StageContext(state: liveState(), now: 0, timeOfDayText: "10:32", timers: [], message: nil, notes: nil)
        let scene = StageComposer.scene(layout: layout, context: ctx)
        #expect(scene.showsVideo == false && scene.backgroundColor.alpha == 1 && scene.overlayImages.isEmpty)
        #expect(texts(scene).contains { $0.contains("Amazing grace") })
        #expect(texts(scene).contains { $0.contains("That saved a wretch") })
        #expect(texts(scene).contains("10:32"))
    }

    /// LIVE-01: a resized element is drawn where the layout says.
    @Test func elementsUseTheirFramesAndStyles() {
        let frame = NormalizedRect(x: 0.1, y: 0.2, width: 0.5, height: 0.3)
        let style = TextStyle(fontName: "Helvetica Neue", fontSize: 150, color: ColorRGBA(red: 1, green: 1, blue: 0))
        let layout = StageLayout(id: UUID(), name: "Big", background: .black,
                                 elements: [StageElement(id: UUID(), kind: .currentSlide, frame: frame, style: style, alignment: .leading)])
        let scene = StageComposer.scene(layout: layout, context: StageContext(state: liveState(), now: 0, timeOfDayText: "", timers: [], message: nil, notes: nil))
        #expect(scene.textLayers.count == 1)
        #expect(scene.textLayers[0].frame == frame && scene.textLayers[0].style == style && scene.textLayers[0].alignment == .leading)
    }

    @Test func secondLanguageIsOptionalPerElement() {
        func scene(_ show: Bool) -> SceneDescription {
            var el = StageElement(id: UUID(), kind: .currentSlide, frame: .full, style: TextStyle(fontName: "Helvetica Neue", fontSize: 90, color: .white), alignment: .leading)
            el.showsSecondLanguage = show
            let layout = StageLayout(id: UUID(), name: "L", background: .black, elements: [el])
            return StageComposer.scene(layout: layout, context: StageContext(state: liveState(), now: 0, timeOfDayText: "", timers: [], message: nil, notes: nil))
        }
        #expect(texts(scene(true)).joined().contains("Ân điển lạ lùng thay"))
        #expect(texts(scene(false)).joined().contains("Ân điển lạ lùng thay") == false)
    }

    @Test func timerElementsShowFormattedValues() {
        let timer = sermon
        let countdown = StageElement(id: UUID(), kind: .timer(timer.id), frame: .full,
                                     style: TextStyle(fontName: "Helvetica Neue", fontSize: 90, color: .white), alignment: .center)
        let layout = StageLayout(id: UUID(), name: "T", background: .black, elements: [countdown])
        let at90 = StageComposer.scene(layout: layout, context: StageContext(state: liveState(), now: 90, timeOfDayText: "", timers: [timer], message: nil, notes: nil))
        #expect(texts(at90) == ["8:30"])
        // Overrun turns the timer's colour to the layout's warning colour.
        let over = StageComposer.scene(layout: layout, context: StageContext(state: liveState(), now: 615, timeOfDayText: "", timers: [timer], message: nil, notes: nil))
        #expect(texts(over) == ["-0:15"])
        #expect(over.textLayers[0].style.color == layout.warningColor)
        #expect(at90.textLayers[0].style.color == .white)
        // A timer that no longer exists draws nothing rather than a placeholder.
        let gone = StageComposer.scene(layout: layout, context: StageContext(state: liveState(), now: 0, timeOfDayText: "", timers: [], message: nil, notes: nil))
        #expect(gone.textLayers.isEmpty)
    }

    /// LIVE-03 groundwork: a stage message appears only when one is set.
    @Test func messageAndNotesElements() {
        let style = TextStyle(fontName: "Helvetica Neue", fontSize: 60, color: .white)
        let layout = StageLayout(id: UUID(), name: "M", background: .black, elements: [
            StageElement(id: UUID(), kind: .message, frame: NormalizedRect(x: 0, y: 0, width: 1, height: 0.2), style: style, alignment: .center),
            StageElement(id: UUID(), kind: .notes, frame: NormalizedRect(x: 0, y: 0.8, width: 1, height: 0.2), style: style, alignment: .leading),
        ])
        let quiet = StageComposer.scene(layout: layout, context: StageContext(state: liveState(), now: 0, timeOfDayText: "", timers: [], message: nil, notes: "  "))
        #expect(quiet.textLayers.isEmpty)
        let loud = StageComposer.scene(layout: layout, context: StageContext(state: liveState(), now: 0, timeOfDayText: "", timers: [], message: "Wrap up", notes: "Pause here"))
        #expect(texts(loud) == ["Wrap up", "Pause here"])
    }

    @Test func clearedAndStoppedStates() {
        var s = liveState(); s.apply(.clear)
        let cleared = StageComposer.scene(layout: .standard, context: StageContext(state: s, now: 0, timeOfDayText: "10:32", timers: [], message: nil, notes: nil))
        #expect(texts(cleared).contains { $0.contains("Amazing grace") } == false)
        #expect(texts(cleared).contains { $0.contains("That saved a wretch") })       // next is still shown
        #expect(texts(cleared).contains("10:32"))
        s.apply(.stop)
        let stopped = StageComposer.scene(layout: .standard, context: StageContext(state: s, now: 0, timeOfDayText: "10:32", timers: [], message: nil, notes: nil))
        #expect(texts(stopped) == ["10:32"])                                          // the clock keeps running for the stage
    }

    @Test func layoutsRoundTripThroughCodable() throws {
        let data = try JSONEncoder().encode(StageLayout.standard)
        #expect(try JSONDecoder().decode(StageLayout.self, from: data) == StageLayout.standard)
        #expect(StageLayout.standard.id == StageLayout.standard.id)                   // fixed id
    }

    /// Editing helpers used by the layout editor: frames stay on screen and keep a minimum size.
    @Test func movingAndResizingStaysOnScreen() {
        var el = StageElement(id: UUID(), kind: .currentSlide, frame: NormalizedRect(x: 0.5, y: 0.5, width: 0.4, height: 0.4),
                              style: TextStyle(fontName: "Helvetica Neue", fontSize: 90, color: .white), alignment: .leading)
        el.move(dx: 0.9, dy: -0.9)
        #expect(abs(el.frame.x - 0.6) < 1e-9 && el.frame.y == 0)
        el.resize(width: 5, height: 0.0001)
        #expect(el.frame.x + el.frame.width <= 1.000001)
        #expect(el.frame.height >= StageElement.minimumSize)
    }
}
