// STAGE-001b (LIVE-01, LIVE-02, LIVE-04): rules for the stage layout editor that are not interface. Foundation and
// Domain only.
import Foundation
import Domain

/// How the stage clock reads (a setting, LIVE-04).
public struct ClockStyle: Sendable, Equatable, Codable {
    public var twentyFourHour: Bool
    public var showsSeconds: Bool

    public init(twentyFourHour: Bool = false, showsSeconds: Bool = false) {
        self.twentyFourHour = twentyFourHour
        self.showsSeconds = showsSeconds
    }
}

/// The kinds of element the operator can add. A timer element needs a timer, chosen when it is added.
public enum NewStageElement: String, Sendable, CaseIterable, Identifiable {
    case currentSlide, nextSlide, timeOfDay, timer, message, notes, sectionName, nextSectionName
    public var id: String { rawValue }

    /// The six elements with a plain Add button. UI-007e: the two Section elements have their own menu (`sectionElements`), so they are not here.
    public static var allCases: [NewStageElement] { [.currentSlide, .nextSlide, .timeOfDay, .timer, .message, .notes] }
    /// UI-007e: the Section elements, added from the Section menu.
    public static var sectionElements: [NewStageElement] { [.sectionName, .nextSectionName] }

    public var title: String {
        switch self {
        case .currentSlide: "Current slide"
        case .nextSlide: "Next slide"
        case .timeOfDay: "Clock"
        case .timer: "Timer"
        case .message: "Message"
        case .notes: "Notes"
        case .sectionName: "Section"
        case .nextSectionName: "Next section"
        }
    }
}

public enum StageEditing {
    /// FIX-Y (REVIEW-4 L7): why the eye may not hide this element, or nil when it may. The Current slide is what the stage screen is for: it cannot be
    /// hidden when it is the last visible one and no Next slide or Notes element is left to show the show, because the screen would then show nothing
    /// from the show. Every other element, and every layout with no Current slide, can be hidden as before.
    public static func hideRefusal(hiding elementID: UUID, in layout: StageLayout) -> String? {
        guard let target = layout.elements.first(where: { $0.id == elementID }), target.kind == .currentSlide, !target.isHidden else { return nil }
        let others = layout.elements.filter { $0.id != elementID && !$0.isHidden }
        guard !others.contains(where: { [.currentSlide, .nextSlide, .notes].contains($0.kind) }) else { return nil }
        return "Could not hide the Current slide: the stage screen would show nothing from the show. Keep it visible, or add a Next slide or Notes element first."
    }

    /// Largest and smallest font size the compositor is asked to draw.
    public static let fontSizeRange = ThemeEditing.fontSizeRange

    /// True when a layout shows something that changes with the clock, so the app has to republish every second.
    /// A layout with only slide text never needs it.
    public static func needsPerSecondRefresh(_ layout: StageLayout) -> Bool {
        layout.elements.contains { element in
            switch element.kind {
            case .timeOfDay, .timer, .firstCountdown: true
            case .currentSlide, .nextSlide, .message, .notes, .sectionName, .nextSectionName: false
            }
        }
    }

    /// A new element with a sensible place and style, using the built-in layout's styles.
    public static func newElement(_ template: NewStageElement, timerID: UUID?, id: UUID = UUID()) -> StageElement? {
        let s = SceneStyles.standard
        switch template {
        case .currentSlide:
            return StageElement(id: id, kind: .currentSlide, frame: NormalizedRect(x: 0.04, y: 0.2, width: 0.92, height: 0.4),
                                style: s.stageCurrent, alignment: .leading)
        case .nextSlide:
            return StageElement(id: id, kind: .nextSlide, frame: s.stageNextFrame, style: s.stageNext, alignment: .leading,
                                showsSecondLanguage: false)
        case .timeOfDay:
            return StageElement(id: id, kind: .timeOfDay, frame: s.stageClockFrame, style: s.stageClock, alignment: .trailing)
        case .timer:
            guard let timerID else { return nil }
            return StageElement(id: id, kind: .timer(timerID), frame: NormalizedRect(x: 0.04, y: 0.01, width: 0.22, height: 0.07),
                                style: s.stageClock, alignment: .leading)
        case .message:
            var style = s.stageClock
            style.fontSize = 56
            style.color = ColorRGBA(red: 1, green: 0.8, blue: 0.3)
            return StageElement(id: id, kind: .message, frame: NormalizedRect(x: 0.04, y: 0.6, width: 0.92, height: 0.12),
                                style: style, alignment: .center, verticalAlignment: .center)
        case .notes:
            var style = s.stageClock
            style.fontSize = 40
            return StageElement(id: id, kind: .notes, frame: NormalizedRect(x: 0.04, y: 0.62, width: 0.92, height: 0.3),
                                style: style, alignment: .leading)
        case .sectionName:
            // UI-007e: where the design draws its Section element (right edge, 60% down), the name in the design's blue.
            var style = s.stageClock
            style.fontSize = 40
            style.color = ColorRGBA(red: 0.44, green: 0.72, blue: 0.98)
            return StageElement(id: id, kind: .sectionName, frame: NormalizedRect(x: 0.74, y: 0.6, width: 0.22, height: 0.07),
                                style: style, alignment: .trailing, verticalAlignment: .center)
        case .nextSectionName:
            // The design's "then Verse 2" line, in the muted colour under the section, with its caption.
            var style = s.stageNext
            style.fontSize = 32
            var caption = s.stageClock
            caption.fontSize = 20
            let label = StageLabel(text: "NEXT", style: caption, relativeFrame: NormalizedRect(x: 0, y: 0, width: 1, height: 0.38), alignment: .trailing)
            return StageElement(id: id, kind: .nextSectionName, frame: NormalizedRect(x: 0.74, y: 0.68, width: 0.22, height: 0.12),
                                style: style, alignment: .trailing, verticalAlignment: .bottom, label: label)
        }
    }

    /// The element with its frame set to the given values, kept on screen and at least the minimum size. The size is
    /// kept first and the position moved inside it, so a frame never shrinks because it was pushed to an edge.
    public static func framed(_ element: StageElement, x: Double, y: Double, width: Double, height: Double) -> StageElement {
        var e = element
        e.frame = NormalizedRect(x: 0, y: 0, width: 1, height: 1)
        e.resize(width: width, height: height)
        e.frame.x = 0
        e.frame.y = 0
        e.move(dx: x, dy: y)
        return e
    }

    /// Every value inside what the compositor can draw. Equal input stays equal.
    public static func sanitized(_ element: StageElement) -> StageElement {
        var e = framed(element, x: element.frame.x, y: element.frame.y, width: element.frame.width, height: element.frame.height)
        let size = e.style.fontSize
        e.style.fontSize = size.isFinite ? min(fontSizeRange.upperBound, max(fontSizeRange.lowerBound, size)) : 64
        let name = e.style.fontName.trimmingCharacters(in: .whitespacesAndNewlines)
        e.style.fontName = name.isEmpty ? ThemeEditing.defaultFontName : name
        return e
    }

    /// Words shown in the editor's canvas so every element has something to draw.
    public static let sampleLines = (current: "Amazing grace, how sweet the sound", currentSecond: "Ân điển lạ lùng thay",
                                     next: "That saved a wretch like me", clock: "10:30 AM",
                                     message: "Wrap up in five minutes", notes: "Pause here and invite the church to stand.",
                                     currentSection: "Verse 1", nextSection: "Chorus")

    /// The layout as the stage screen would draw it, with sample slides, clock, message and notes, and the real timers.
    public static func sampleScene(layout: StageLayout, timers: [ShowTimer], now: TimeInterval,
                                   timeOfDayText: String = sampleLines.clock) -> SceneDescription {
        var state = ShowState()
        let deck = ShowDeck(presentationID: UUID(), slides: [
            SlideContent(primary: sampleLines.current, secondary: sampleLines.currentSecond),
            SlideContent(primary: sampleLines.next),
        ], sectionNames: [sampleLines.currentSection, sampleLines.nextSection])
        state.apply(.load(deck))
        state.apply(.trigger(index: 0))
        let context = StageContext(state: state, now: now, timeOfDayText: timeOfDayText, timers: timers,
                                   message: layout.elements.contains { $0.kind == .message } ? sampleLines.message : nil,   // the canvas shows the layout, not the banner a layout without a message element gets
                                   notes: sampleLines.notes)
        return StageComposer.scene(layout: layout, context: context)
    }
}
