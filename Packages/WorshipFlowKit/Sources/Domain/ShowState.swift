// OUT-002: Preview / Live / Clear / Stop semantics. Foundation only.
import Foundation

/// An ordered list of slides taken from one presentation.
public struct ShowDeck: Sendable, Equatable, Hashable {
    public var presentationID: UUID
    public var slides: [SlideContent]

    public init(presentationID: UUID, slides: [SlideContent]) {
        self.presentationID = presentationID
        self.slides = slides
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
    /// Drops the live deck; screens go empty. Preview is kept.
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

    public init() {}

    public var isStopped: Bool { liveDeck == nil }
    public var isCleared: Bool { liveDeck != nil && cleared }

    public var liveSlide: SlideContent? {
        guard !cleared, let deck = liveDeck, let i = liveIndex, deck.slides.indices.contains(i) else { return nil }
        return deck.slides[i]
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

        case .clear:
            guard liveDeck != nil else { return }
            cleared = true

        case .stop:
            liveDeck = nil
            liveIndex = nil
            cleared = false

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
        if let live = liveDeck, let preview = previewDeck, live.presentationID == preview.presentationID {
            selectedIndex = index   // the preview follows the show only while it shows the same presentation
        }
    }
}
