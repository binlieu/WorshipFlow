// OUT-002: Preview / Live / Clear / Stop semantics. Foundation only.
import Foundation

/// An ordered list of slides taken from one presentation.
public struct ShowDeck: Sendable, Equatable, Hashable {
    public var presentationID: UUID
    public var slides: [SlideContent]
    /// SYS-015: the name of the section (the slide group) each slide belongs to, one entry per slide in `slides` order, nil for a slide in no section.
    /// Empty for a deck built without sections. Nothing is stored for it: it is composed from the slides' groups when the deck is built, so a stage
    /// Section element can show where the song is.
    public var sectionNames: [String?]

    public init(presentationID: UUID, slides: [SlideContent], sectionNames: [String?] = []) {
        self.presentationID = presentationID
        self.slides = slides
        self.sectionNames = sectionNames
    }

    /// The section name of the slide at `index`; nil when there is none or the index is out of range.
    public func sectionName(at index: Int) -> String? {
        slides.indices.contains(index) && sectionNames.indices.contains(index) ? sectionNames[index] : nil
    }
}

public enum ShowCommand: Sendable, Equatable {
    /// Replaces the preview deck. Never touches what is live.
    case load(ShowDeck)
    /// Moves the preview selection. Never touches what is live.
    case select(index: Int)
    /// Takes the preview deck live at `index`. Out-of-range indices are ignored.
    case trigger(index: Int)
    case next
    case previous
    /// Hides the slide on every screen but keeps the place.
    case clear
    /// Hides the slide on every screen and keeps the place, like `clear`. The show state is the same; the difference
    /// is outside it: the operator model also stops the foreground clip (R8, "Clear all").
    case clearAll
    /// UI-001: toggles Blackout. Every audience screen goes black and every broadcast screen transparent, background and
    /// media included; the place, the live deck and the clip transport are kept (stage screens keep their words). Trigger,
    /// next and previous (when they move), and a second blackout lift it; Clear keeps it and takes effect when it lifts.
    /// Ignored while nothing is live.
    case blackout
    /// MEDIA-010: hides the live background (the theme's own, the slide's own and a live override) on every audience and
    /// broadcast screen. The words, the foreground clip and the place are kept. Go Live, Next and Previous (when they move),
    /// Stop and `restoreBackground` bring it back. Ignored while nothing is live.
    case clearBackground
    /// MEDIA-010: a new bin choice brings a cleared background back.
    case restoreBackground
    /// FIX-H item 2: ends Blackout, Clear and Clear background without moving the live place or the preview. What taking a slide live
    /// does to those three, for a file or loop that goes live over the slide that is already there. Ignored while nothing is live.
    case liftHolds
    /// Drops the live deck (and ends Blackout); screens go empty. Preview is kept.
    case stop
    /// The one deliberate way to change live text (PRES-07).
    case quickEdit(index: Int, content: SlideContent)
    /// After a relaunch: fills preview only. Nothing goes live.
    case restore(deck: ShowDeck, selectedIndex: Int)
}

public struct ShowState: Sendable, Equatable {
    public private(set) var previewDeck: ShowDeck?
    public private(set) var liveDeck: ShowDeck?
    /// Preview selection (what the operator has highlighted).
    public private(set) var selectedIndex: Int = 0
    /// Position in `liveDeck`; nil when stopped, kept while cleared.
    public private(set) var liveIndex: Int?
    private var cleared = false
    private var blackedOut = false
    private var backgroundHidden = false

    public init() {}

    /// MEDIA-010: the live background is hidden (Clear background).
    public var isBackgroundCleared: Bool { liveDeck != nil && backgroundHidden }

    /// UI-001: Blackout is on. `liveSlide` and `nextSlide` are unchanged (the stage still needs them); the composers
    /// read this to draw nothing on audience and broadcast screens.
    public var isBlackedOut: Bool { liveDeck != nil && blackedOut }

    public var isStopped: Bool { liveDeck == nil }
    public var isCleared: Bool { liveDeck != nil && cleared }

    public var liveSlide: SlideContent? {
        guard !cleared, let deck = liveDeck, let i = liveIndex, deck.slides.indices.contains(i) else { return nil }
        return deck.slides[i]
    }

    /// MEDIA-010: the slide at the live place even while the words are cleared. The slide's own background stays on screen
    /// under a Clear, so the composer and the media players read it from here.
    public var liveSlideAtPlace: SlideContent? {
        guard let deck = liveDeck, let i = liveIndex, deck.slides.indices.contains(i) else { return nil }
        return deck.slides[i]
    }

    /// SYS-015: the section of the live slide, kept while cleared like the place itself. Nil when stopped or when the slide is in no section.
    public var liveSectionName: String? {
        guard let deck = liveDeck, let i = liveIndex else { return nil }
        return deck.sectionName(at: i)
    }

    /// SYS-015: the section of the next slide; nil when there is no next slide or it is in no section.
    public var nextSectionName: String? {
        guard let deck = liveDeck, let i = liveIndex, deck.slides.indices.contains(i + 1) else { return nil }
        return deck.sectionName(at: i + 1)
    }

    public var nextSlide: SlideContent? {
        guard let deck = liveDeck, let i = liveIndex, deck.slides.indices.contains(i + 1) else { return nil }
        return deck.slides[i + 1]
    }

    public mutating func apply(_ command: ShowCommand) {
        switch command {
        case .load(let deck):
            previewDeck = deck
            selectedIndex = 0

        case .select(let index):
            guard let deck = previewDeck, deck.slides.indices.contains(index) else { return }
            selectedIndex = index

        case .trigger(let index):
            guard let deck = previewDeck, deck.slides.indices.contains(index) else { return }
            liveDeck = deck
            liveIndex = index
            cleared = false
            blackedOut = false
            backgroundHidden = false
            selectedIndex = index

        case .next:
            if let deck = liveDeck, let i = liveIndex {
                guard deck.slides.indices.contains(i + 1) else { return }
                moveLive(to: i + 1)
            } else if let deck = previewDeck, !deck.slides.isEmpty {
                apply(.trigger(index: 0))
            }

        case .previous:
            guard liveDeck != nil, let i = liveIndex, i > 0 else { return }
            moveLive(to: i - 1)

        case .clear, .clearAll:
            guard liveDeck != nil else { return }
            cleared = true

        case .blackout:
            guard liveDeck != nil else { return }
            blackedOut.toggle()

        case .clearBackground:
            guard liveDeck != nil else { return }
            backgroundHidden = true

        case .restoreBackground:
            backgroundHidden = false

        case .liftHolds:
            guard liveDeck != nil else { return }
            cleared = false
            blackedOut = false
            backgroundHidden = false

        case .stop:
            liveDeck = nil
            liveIndex = nil
            cleared = false
            blackedOut = false
            backgroundHidden = false

        case .quickEdit(let index, let content):
            guard var deck = liveDeck, deck.slides.indices.contains(index) else { return }
            deck.slides[index] = content
            liveDeck = deck
            if var preview = previewDeck, preview.presentationID == deck.presentationID, preview.slides.indices.contains(index) {
                preview.slides[index] = content
                previewDeck = preview
            }

        case .restore(let deck, let selectedIndex):
            previewDeck = deck
            self.selectedIndex = deck.slides.indices.contains(selectedIndex) ? selectedIndex : 0
        }
    }

    private mutating func moveLive(to index: Int) {
        liveIndex = index
        cleared = false
        blackedOut = false
        backgroundHidden = false
        if let live = liveDeck, let preview = previewDeck, live.presentationID == preview.presentationID {
            selectedIndex = index   // the preview follows the show only while it shows the same presentation
        }
    }
}
