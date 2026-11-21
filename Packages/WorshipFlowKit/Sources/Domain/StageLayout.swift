// STAGE-001a (LIVE-01, LIVE-02, LIVE-04): configurable stage display. Foundation only.
import Foundation

public struct StageElement: Sendable, Equatable, Codable, Hashable, Identifiable {
    public enum Kind: Sendable, Equatable, Codable, Hashable {
        case currentSlide, nextSlide, timeOfDay
        case timer(UUID)
        case message, notes
    }

    /// Smallest width or height of a frame, as a fraction of the screen.
    public static let minimumSize: Double = 0.05

    public var id: UUID
    public var kind: Kind
    public var frame: NormalizedRect
    public var style: TextStyle
    public var alignment: TextAlignment
    public var verticalAlignment: VerticalAlignment
    /// Current slide only: also show the second-language line.
    public var showsSecondLanguage: Bool

    public init(id: UUID, kind: Kind, frame: NormalizedRect, style: TextStyle, alignment: TextAlignment,
                verticalAlignment: VerticalAlignment = .top, showsSecondLanguage: Bool = true) {
        self.id = id
        self.kind = kind
        self.frame = frame
        self.style = style
        self.alignment = alignment
        self.verticalAlignment = verticalAlignment
        self.showsSecondLanguage = showsSecondLanguage
    }

    /// Moves the frame, keeping it on screen.
    public mutating func move(dx: Double, dy: Double) {
        frame.x = Self.clamp(frame.x + dx, 0, 1 - frame.width)
        frame.y = Self.clamp(frame.y + dy, 0, 1 - frame.height)
    }

    /// Sets the size, keeping the frame on screen and at least `minimumSize` in each direction.
    public mutating func resize(width: Double, height: Double) {
        let minimum = Self.minimumSize
        frame.x = Self.clamp(frame.x, 0, 1 - minimum)
        frame.y = Self.clamp(frame.y, 0, 1 - minimum)
        frame.width = Self.clamp(width, minimum, 1 - frame.x)
        frame.height = Self.clamp(height, minimum, 1 - frame.y)
    }

    private static func clamp(_ v: Double, _ low: Double, _ high: Double) -> Double {
        v.isNaN ? low : min(high, max(low, v))
    }
}

public struct StageLayout: Sendable, Equatable, Codable, Hashable, Identifiable {
    /// Fixed id of the built-in layout. It is never stored.
    public static let standardID = UUID(uuidString: "5A6E0001-0000-4000-8000-000000000001") ?? UUID()

    public var id: UUID
    public var name: String
    public var background: ColorRGBA
    /// Colour of a timer that has run over.
    public var warningColor: ColorRGBA
    public var elements: [StageElement]

    public init(id: UUID, name: String, background: ColorRGBA,
                warningColor: ColorRGBA = ColorRGBA(red: 1, green: 0.25, blue: 0.2), elements: [StageElement]) {
        self.id = id
        self.name = name
        self.background = background
        self.warningColor = warningColor
        self.elements = elements
    }

    /// Looks like the built-in stage scene: current slide, next slide and a clock.
    public static let standard: StageLayout = {
        let s = SceneStyles.standard
        func id(_ n: Int) -> UUID { UUID(uuidString: "5A6E0002-0000-4000-8000-00000000000\(n)") ?? UUID() }
        return StageLayout(id: standardID, name: "Standard", background: s.stageBackground, elements: [
            StageElement(id: id(1), kind: .currentSlide, frame: s.stageCurrentFrame, style: s.stageCurrent, alignment: .leading),
            StageElement(id: id(2), kind: .nextSlide, frame: s.stageNextFrame, style: s.stageNext, alignment: .leading,
                         showsSecondLanguage: false),
            StageElement(id: id(3), kind: .timeOfDay, frame: s.stageClockFrame, style: s.stageClock, alignment: .trailing),
        ])
    }()
}

/// Everything a stage screen needs to draw one frame.
public struct StageContext: Sendable, Equatable {
    public var state: ShowState
    /// Seconds since the reference date; drives the timers.
    public var now: TimeInterval
    public var timeOfDayText: String
    public var timers: [ShowTimer]
    public var message: String?
    public var notes: String?

    public init(state: ShowState, now: TimeInterval, timeOfDayText: String, timers: [ShowTimer],
                message: String?, notes: String?) {
        self.state = state
        self.now = now
        self.timeOfDayText = timeOfDayText
        self.timers = timers
        self.message = message
        self.notes = notes
    }
}

public enum StageComposer {
    /// One text layer per element that has something to show, in element order.
    public static func scene(layout: StageLayout, context: StageContext) -> SceneDescription {
        var layers: [TextLayer] = []
        for element in layout.elements {
            var style = element.style
            let text: String?
            switch element.kind {
            case .currentSlide:
                if let slide = context.state.liveSlide, var t = visible(slide.primary) {
                    if element.showsSecondLanguage, let second = visible(slide.secondary) { t += "\n" + second }
                    text = t
                } else { text = nil }
            case .nextSlide:
                if let slide = context.state.nextSlide, var t = visible(slide.primary) {
                    if element.showsSecondLanguage, let second = visible(slide.secondary) { t += "\n" + second }
                    text = t
                } else { text = nil }
            case .timeOfDay: text = visible(context.timeOfDayText)
            case .timer(let id):
                if let timer = context.timers.first(where: { $0.id == id }) {
                    text = TimeFormat.clock(seconds: timer.value(at: context.now))
                    if timer.isOverrun(at: context.now) { style.color = layout.warningColor }
                } else { text = nil }
            case .message: text = visible(context.message)
            case .notes: text = visible(context.notes)
            }
            if let text {
                layers.append(TextLayer(text: text, style: style, frame: element.frame, alignment: element.alignment,
                                        verticalAlignment: element.verticalAlignment))
            }
        }
        return SceneDescription(backgroundColor: layout.background, showsVideo: false, textLayers: layers)
    }

    private static func visible(_ text: String?) -> String? {
        guard let text, !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return nil }
        return text
    }
}
