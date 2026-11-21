// STAGE-001b (LIVE-01, LIVE-02): the pure rules behind the stage layout editor.
import Testing
import Foundation
import Domain
@testable import OperatorCore

@Suite struct StageEditingTests {
    func layout(_ kinds: [StageElement.Kind]) -> StageLayout {
        StageLayout(id: UUID(), name: "L", background: .black, elements: kinds.map { kind in
            StageElement(id: UUID(), kind: kind, frame: NormalizedRect(x: 0.1, y: 0.1, width: 0.5, height: 0.2),
                         style: TextStyle(fontName: "Helvetica Neue", fontSize: 40, color: .white), alignment: .leading)
        })
    }

    // MARK: Per-second refresh

    @Test func aLayoutNeedsAPerSecondRefreshOnlyWhenItShowsAClockOrATimer() {
        #expect(StageEditing.needsPerSecondRefresh(StageLayout.standard))                 // it has a clock
        #expect(StageEditing.needsPerSecondRefresh(layout([.currentSlide, .timer(UUID())])))
        #expect(StageEditing.needsPerSecondRefresh(layout([.timeOfDay])))
        #expect(!StageEditing.needsPerSecondRefresh(layout([.currentSlide, .nextSlide, .message, .notes])))
        #expect(!StageEditing.needsPerSecondRefresh(layout([])))
    }

    // MARK: New elements

    @Test func everyKindOfNewElementIsOnScreenAndDrawable() throws {
        let timerID = UUID()
        for template in NewStageElement.allCases {
            let e = try #require(StageEditing.newElement(template, timerID: timerID))
            #expect(e.frame.x >= 0 && e.frame.y >= 0)
            #expect(e.frame.x + e.frame.width <= 1.0000001 && e.frame.y + e.frame.height <= 1.0000001)
            #expect(e.frame.width >= StageElement.minimumSize && e.frame.height >= StageElement.minimumSize)
            #expect(StageEditing.fontSizeRange.contains(e.style.fontSize))
            #expect(StageEditing.sanitized(e) == e)                       // already clean
        }
        #expect(StageEditing.newElement(.timer, timerID: nil) == nil)     // a timer element needs a timer
        #expect(StageEditing.newElement(.timer, timerID: timerID)?.kind == .timer(timerID))
    }

    // MARK: Frames and style limits

    @Test func framedKeepsTheSizeAndMovesThePositionInsideIt() throws {
        let e = try #require(StageEditing.newElement(.message, timerID: nil))
        let pushed = StageEditing.framed(e, x: 0.9, y: 0.95, width: 0.4, height: 0.2)
        #expect(pushed.frame.width == 0.4 && pushed.frame.height == 0.2)             // the size is not eaten by the edge
        #expect(abs(pushed.frame.x - 0.6) < 1e-9 && abs(pushed.frame.y - 0.8) < 1e-9)
        let negative = StageEditing.framed(e, x: -3, y: -3, width: 0.3, height: 0.3)
        #expect(negative.frame == NormalizedRect(x: 0, y: 0, width: 0.3, height: 0.3))
        let tiny = StageEditing.framed(e, x: 0.5, y: 0.5, width: 0, height: -1)
        #expect(tiny.frame.width == StageElement.minimumSize && tiny.frame.height == StageElement.minimumSize)
        let huge = StageEditing.framed(e, x: 0.5, y: 0.5, width: 7, height: 7)
        #expect(huge.frame == NormalizedRect.full)
    }

    @Test func nonFiniteNumbersNeverReachTheFrameOrTheFont() throws {
        var e = try #require(StageEditing.newElement(.notes, timerID: nil))
        e.style.fontSize = .nan
        let clean = StageEditing.framed(StageEditing.sanitized(e), x: .nan, y: .infinity, width: .nan, height: .infinity)
        #expect(clean.frame.x.isFinite && clean.frame.y.isFinite && clean.frame.width.isFinite && clean.frame.height.isFinite)
        #expect(clean.frame.x >= 0 && clean.frame.x + clean.frame.width <= 1.0000001)
        #expect(clean.frame.y >= 0 && clean.frame.y + clean.frame.height <= 1.0000001)
        #expect(StageEditing.sanitized(e).style.fontSize == 64)
    }

    @Test func fontSizeAndNameAreKeptInRange() throws {
        var e = try #require(StageEditing.newElement(.nextSlide, timerID: nil))
        e.style.fontSize = 9_999
        #expect(StageEditing.sanitized(e).style.fontSize == StageEditing.fontSizeRange.upperBound)
        e.style.fontSize = 1
        #expect(StageEditing.sanitized(e).style.fontSize == StageEditing.fontSizeRange.lowerBound)
        e.style.fontName = "   "
        #expect(StageEditing.sanitized(e).style.fontName == ThemeEditing.defaultFontName)
    }

    // MARK: Sample scene

    @Test func theSampleSceneDrawsEveryKindOfElementWithSampleContent() {
        let timer = ShowTimer(id: UUID(), name: "Sermon", kind: .countdown(seconds: 600))
        let all = layout([.currentSlide, .nextSlide, .timeOfDay, .timer(timer.id), .message, .notes])
        let scene = StageEditing.sampleScene(layout: all, timers: [timer], now: 0)
        #expect(scene.textLayers.count == 6)
        let texts = scene.textLayers.map(\.text)
        #expect(texts.contains { $0.contains(StageEditing.sampleLines.current) && $0.contains(StageEditing.sampleLines.currentSecond) })
        #expect(texts.contains(StageEditing.sampleLines.next))
        #expect(texts.contains(StageEditing.sampleLines.clock))
        #expect(texts.contains("10:00"))                                              // the real timer's value
        #expect(texts.contains(StageEditing.sampleLines.message))
        #expect(texts.contains(StageEditing.sampleLines.notes))
    }

    @Test func aTimerElementWithoutItsTimerDrawsNothingInTheSample() {
        let scene = StageEditing.sampleScene(layout: layout([.timer(UUID())]), timers: [], now: 0)
        #expect(scene.textLayers.isEmpty)
    }
}
