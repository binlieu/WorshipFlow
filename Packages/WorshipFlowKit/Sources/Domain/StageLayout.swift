// STAGE-001a (LIVE-01, LIVE-02, LIVE-04): configurable stage display. Foundation only.
import Foundation

public struct StageElement: Sendable, Equatable, Codable, Hashable, Identifiable {
    public enum Kind: Sendable, Equatable, Codable, Hashable {
        case currentSlide, nextSlide, timeOfDay
        case timer(UUID)
        case message, notes
        /// UI-005h: the first countdown timer (else the first timer). Draws nothing when there are no timers.
        case firstCountdown

        /// FIX-J: the text of this element changes every second (the clock and the timers).
        public var ticks: Bool {
            switch self {
            case .timeOfDay, .timer, .firstCountdown: return true
            case .currentSlide, .nextSlide, .message, .notes: return false
            }
        }
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
    /// UI-005h: current slide only. The second language in its own line with its own style and frame, its lines joined by `separator`,
    /// instead of appended to the first language's text. Nil: appended, as before.
    public var secondLanguage: StageSecondLanguage?
    /// UI-005h: next slide only. A caption ("NEXT") drawn with its own style and frame while there is a next slide.
    public var label: StageLabel?

    public init(id: UUID, kind: Kind, frame: NormalizedRect, style: TextStyle, alignment: TextAlignment,
                verticalAlignment: VerticalAlignment = .top, showsSecondLanguage: Bool = true,
                secondLanguage: StageSecondLanguage? = nil, label: StageLabel? = nil) {
        self.id = id
        self.kind = kind
        self.frame = frame
        self.style = style
        self.alignment = alignment
        self.verticalAlignment = verticalAlignment
        self.showsSecondLanguage = showsSecondLanguage
        self.secondLanguage = secondLanguage
        self.label = label
    }

    private enum CodingKeys: String, CodingKey {
        case id, kind, frame, style, alignment, verticalAlignment, showsSecondLanguage, secondLanguage, label
    }

    /// FIX-J item 5: the second-language line and the label are stored relative to this element. A layout saved before that stored their frames
    /// as frames of the screen (`frame`); those are converted here, in memory, so they are drawn where they always were. Nothing is rewritten
    /// until the layout is saved again.
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let frame = try c.decode(NormalizedRect.self, forKey: .frame)
        self.init(id: try c.decode(UUID.self, forKey: .id), kind: try c.decode(Kind.self, forKey: .kind), frame: frame,
                  style: try c.decode(TextStyle.self, forKey: .style), alignment: try c.decode(TextAlignment.self, forKey: .alignment),
                  verticalAlignment: try c.decode(VerticalAlignment.self, forKey: .verticalAlignment),
                  showsSecondLanguage: try c.decode(Bool.self, forKey: .showsSecondLanguage),
                  secondLanguage: try c.decodeIfPresent(StageSecondLanguage.Stored.self, forKey: .secondLanguage)?.resolved(in: frame),
                  label: try c.decodeIfPresent(StageLabel.Stored.self, forKey: .label)?.resolved(in: frame))
    }

    /// The frame of the second-language line on the screen (nil when the element has none).
    public var secondLanguageFrame: NormalizedRect? { secondLanguage.map { $0.relativeFrame.placed(in: frame) } }
    /// The frame of the label on the screen (nil when the element has none).
    public var labelFrame: NormalizedRect? { label.map { $0.relativeFrame.placed(in: frame) } }

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

/// UI-005h: a current slide's second language drawn as its own line.
public struct StageSecondLanguage: Sendable, Equatable, Codable, Hashable {
    public var style: TextStyle
    /// FIX-J: relative to the element it belongs to (see `NormalizedRect.relative(to:)`): so it moves and scales with it.
    public var relativeFrame: NormalizedRect
    public var alignment: TextAlignment
    public var verticalAlignment: VerticalAlignment
    /// Put between the second language's lines (" \u{00B7} " joins "Tan" and "Do" as "Tan \u{00B7} Do").
    public var separator: String

    public init(style: TextStyle, relativeFrame: NormalizedRect, alignment: TextAlignment = .leading,
                verticalAlignment: VerticalAlignment = .top, separator: String = " \u{00B7} ") {
        self.style = style
        self.relativeFrame = relativeFrame
        self.alignment = alignment
        self.verticalAlignment = verticalAlignment
        self.separator = separator
    }

    /// A line given by its frame on the screen, for the element frame it belongs to.
    public init(style: TextStyle, frame: NormalizedRect, onElement element: NormalizedRect, alignment: TextAlignment = .leading,
                verticalAlignment: VerticalAlignment = .top, separator: String = " \u{00B7} ") {
        self.init(style: style, relativeFrame: frame.relative(to: element), alignment: alignment, verticalAlignment: verticalAlignment, separator: separator)
    }

    /// What is stored: `relativeFrame`, or (a layout saved before FIX-J) `frame`, a frame of the screen.
    struct Stored: Decodable {
        var style: TextStyle
        var frame: NormalizedRect?
        var relativeFrame: NormalizedRect?
        var alignment: TextAlignment
        var verticalAlignment: VerticalAlignment
        var separator: String

        func resolved(in element: NormalizedRect) -> StageSecondLanguage {
            StageSecondLanguage(style: style, relativeFrame: relativeFrame ?? (frame ?? .full).relative(to: element), alignment: alignment,
                                verticalAlignment: verticalAlignment, separator: separator)
        }
    }
}

extension NormalizedRect {
    /// This frame (of the screen) as a frame relative to `element`: its offset from the element's corner and its size, as fractions of the
    /// element's width and height.
    public func relative(to element: NormalizedRect) -> NormalizedRect {
        let w = element.width > 1e-9 ? element.width : 1, h = element.height > 1e-9 ? element.height : 1
        return NormalizedRect(x: (x - element.x) / w, y: (y - element.y) / h, width: width / w, height: height / h)
    }

    /// A frame relative to `element`, as a frame of the screen.
    public func placed(in element: NormalizedRect) -> NormalizedRect {
        NormalizedRect(x: element.x + x * element.width, y: element.y + y * element.height, width: width * element.width, height: height * element.height)
    }
}

/// UI-005h: a caption that goes with an element ("NEXT" above the next line).
public struct StageLabel: Sendable, Equatable, Codable, Hashable {
    public var text: String
    public var style: TextStyle
    /// FIX-J: relative to the element it belongs to, so it moves and scales with it.
    public var relativeFrame: NormalizedRect
    public var alignment: TextAlignment
    public var verticalAlignment: VerticalAlignment

    public init(text: String, style: TextStyle, relativeFrame: NormalizedRect, alignment: TextAlignment = .leading,
                verticalAlignment: VerticalAlignment = .top) {
        self.text = text
        self.style = style
        self.relativeFrame = relativeFrame
        self.alignment = alignment
        self.verticalAlignment = verticalAlignment
    }

    /// A label given by its frame on the screen, for the element frame it belongs to.
    public init(text: String, style: TextStyle, frame: NormalizedRect, onElement element: NormalizedRect, alignment: TextAlignment = .leading,
                verticalAlignment: VerticalAlignment = .top) {
        self.init(text: text, style: style, relativeFrame: frame.relative(to: element), alignment: alignment, verticalAlignment: verticalAlignment)
    }

    /// What is stored: `relativeFrame`, or (a layout saved before FIX-J) `frame`, a frame of the screen.
    struct Stored: Decodable {
        var text: String
        var style: TextStyle
        var frame: NormalizedRect?
        var relativeFrame: NormalizedRect?
        var alignment: TextAlignment
        var verticalAlignment: VerticalAlignment

        func resolved(in element: NormalizedRect) -> StageLabel {
            StageLabel(text: text, style: style, relativeFrame: relativeFrame ?? (frame ?? .full).relative(to: element), alignment: alignment,
                       verticalAlignment: verticalAlignment)
        }
    }
}

/// UI-005h: how a layout draws the stage message without a message element: a full-width band with dark text, instead of large
/// warning-coloured text. Nil (every layout saved before this) keeps the large text.
public struct StageMessageBand: Sendable, Equatable, Codable, Hashable {
    public var plate: TextPlate
    public var style: TextStyle

    public init(plate: TextPlate, style: TextStyle) {
        self.plate = plate
        self.style = style
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
    /// UI-005h: see `StageMessageBand`.
    public var messageBand: StageMessageBand?

    public init(id: UUID, name: String, background: ColorRGBA,
                warningColor: ColorRGBA = ColorRGBA(red: 1, green: 0.25, blue: 0.2), elements: [StageElement],
                messageBand: StageMessageBand? = nil) {
        self.id = id
        self.name = name
        self.background = background
        self.warningColor = warningColor
        self.elements = elements
        self.messageBand = messageBand
    }

    /// UI-005h: the built-in layout is the design's stage composition (`OutputLooks.stageLayout`): current lyric, the second language in its own
    /// line, "NEXT" and the next line, the clock, the first countdown, and the stage message as a warning band. Layouts the operator made from the
    /// earlier built-in keep their own copy of its elements and are not changed.
    public static let standard: StageLayout = OutputLooks.stageLayout()
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
                    if let second = element.secondLanguage {
                        // UI-005h: the second language is its own line, its lines joined, in its own style.
                        layers.append(layer(t, style, element))
                        if element.showsSecondLanguage, let line = joined(slide.secondary, separator: second.separator) {
                            layers.append(TextLayer(text: line, style: second.style, frame: second.relativeFrame.placed(in: element.frame), alignment: second.alignment,
                                                    verticalAlignment: second.verticalAlignment))
                        }
                        text = nil
                    } else {
                        if element.showsSecondLanguage, let second = visible(slide.secondary) { t += "\n" + second }
                        text = t
                    }
                } else { text = nil }
            case .nextSlide:
                if let slide = context.state.nextSlide, var t = visible(slide.primary) {
                    if element.showsSecondLanguage, let second = visible(slide.secondary) { t += "\n" + second }
                    if let label = element.label {
                        layers.append(TextLayer(text: label.text, style: label.style, frame: label.relativeFrame.placed(in: element.frame), alignment: label.alignment,
                                                verticalAlignment: label.verticalAlignment))
                    }
                    text = t
                } else { text = nil }
            case .timeOfDay: text = visible(context.timeOfDayText)
            case .timer(let id):
                if let timer = context.timers.first(where: { $0.id == id }) {
                    text = TimeFormat.clock(seconds: timer.value(at: context.now))
                    if timer.isOverrun(at: context.now) { style.color = layout.warningColor }
                } else { text = nil }
            case .firstCountdown:
                let timer = context.timers.first { if case .countdown = $0.kind { return true } else if case .countdownTo = $0.kind { return true } else { return false } }
                    ?? context.timers.first
                if let timer {
                    text = TimeFormat.clock(seconds: timer.value(at: context.now))
                    if timer.isOverrun(at: context.now) { style.color = layout.warningColor }
                } else { text = nil }
            case .message: text = visible(context.message)
            case .notes: text = visible(context.notes)
            }
            if let text { layers.append(layer(text, style, element, ticks: element.kind.ticks)) }
        }
        var plate: TextPlate?
        // UI-003 (LIVE-03): a layout that has no message element still shows a message that was sent, as a banner along
        // the bottom, so a message sent from the Show inspector is never silently lost. UI-005h: a layout with a message band draws it as
        // the band (dark text on a full-width warning plate); every other layout keeps the large warning-coloured text.
        if !layout.elements.contains(where: { $0.kind == .message }), let banner = visible(context.message) {
            if let band = layout.messageBand {
                plate = band.plate
                layers.append(TextLayer(text: banner, style: band.style, frame: .full, alignment: .leading, verticalAlignment: .top, inPlate: true))
            } else {
                layers.append(bannerLayer(banner, warning: layout.warningColor))
            }
        }
        if context.state.isBlackedOut { layers.append(blackoutLayer(warning: layout.warningColor)) }
        return SceneDescription(backgroundColor: layout.background, showsVideo: false, textLayers: layers, plate: plate)
    }

    private static func layer(_ text: String, _ style: TextStyle, _ element: StageElement, ticks: Bool = false) -> TextLayer {
        TextLayer(text: text, style: style, frame: element.frame, alignment: element.alignment, verticalAlignment: element.verticalAlignment, ticks: ticks)
    }

    /// The non-blank lines of `text` joined by `separator`; nil when there are none.
    private static func joined(_ text: String?, separator: String) -> String? {
        guard let text else { return nil }
        let lines = text.split(whereSeparator: \.isNewline).map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
        return lines.isEmpty ? nil : lines.joined(separator: separator)
    }

    /// The stage message of a layout that has no message element: large warning-coloured text along the bottom.
    static func bannerLayer(_ text: String, warning: ColorRGBA) -> TextLayer {
        TextLayer(text: text,
                  style: TextStyle(fontName: "Helvetica Neue", fontSize: 64, color: warning),
                  frame: NormalizedRect(x: 0.04, y: 0.84, width: 0.92, height: 0.14),
                  alignment: .center, verticalAlignment: .center)
    }

    /// UI-001: the word the stage shows while Blackout is on, so the band knows the other screens are dark.
    static func blackoutLayer(warning: ColorRGBA) -> TextLayer {
        TextLayer(text: "BLACKOUT",
                  style: TextStyle(fontName: "Helvetica Neue", fontSize: 48, color: warning),
                  frame: NormalizedRect(x: 0.30, y: 0.01, width: 0.40, height: 0.08),
                  alignment: .center, verticalAlignment: .top)
    }

    private static func visible(_ text: String?) -> String? {
        guard let text, !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return nil }
        return text
    }
}
