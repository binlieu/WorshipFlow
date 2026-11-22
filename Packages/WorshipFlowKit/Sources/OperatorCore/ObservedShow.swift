// FIX-O (KI-180): the show state, observable one part at a time. `ShowState` is one value; when it was the model's one observed
// property, any change to it (a preview refresh after every slide edit and every reorder, a selection, a live move) made every view that
// read any part of it draw again. Here each part has its own observation key, so a change to one part notifies only the views that read
// that part. The state itself, its commands and what they do are unchanged: `set` takes a whole new `ShowState`, compares it with the old
// one part by part and notifies only the parts that differ.
//
// A reader that needs the whole state (`state`) depends on every part, as before. A reader that needs one thing reads that thing.
import Foundation
import Observation
import Domain

@MainActor
public final class ObservedShow: Observable {
    private let registrar = ObservationRegistrar()
    private var value: ShowState

    public init(_ initial: ShowState = ShowState()) { value = initial }

    // MARK: Whole state

    /// The whole state. Reading it inside an observation scope depends on every part (the old behaviour); prefer a part.
    public var state: ShowState {
        accessAll()
        return value
    }

    /// The whole state without registering any dependency: for the model's own bookkeeping, never for a view.
    public var current: ShowState { value }

    // MARK: Parts

    /// Preview selection (what the operator has highlighted).
    public var selectedIndex: Int { registrar.access(self, keyPath: \.selectedIndex); return value.selectedIndex }
    /// Position in the live deck; nil when stopped.
    public var liveIndex: Int? { registrar.access(self, keyPath: \.liveIndex); return value.liveIndex }
    /// Nothing is live. Changes only when the live deck appears or goes (Stop, the first Go Live), not when it moves or is edited.
    public var isStopped: Bool { registrar.access(self, keyPath: \.isStopped); return value.isStopped }
    /// Which presentation the live deck came from. Changes only when a different one goes live.
    public var liveDeckID: UUID? { registrar.access(self, keyPath: \.liveDeckID); return value.liveDeck?.presentationID }
    /// The live deck's slides (changes on a quick edit and when another deck goes live; not on Next).
    public var liveDeck: ShowDeck? { registrar.access(self, keyPath: \.liveDeck); return value.liveDeck }
    /// The preview deck (changes on every slide edit, reorder and load; not on a selection or a live move).
    public var previewDeck: ShowDeck? { registrar.access(self, keyPath: \.previewDeck); return value.previewDeck }
    public var isCleared: Bool { registrar.access(self, keyPath: \.isCleared); return value.isCleared }
    public var isBlackedOut: Bool { registrar.access(self, keyPath: \.isBlackedOut); return value.isBlackedOut }
    public var isBackgroundCleared: Bool { registrar.access(self, keyPath: \.isBackgroundCleared); return value.isBackgroundCleared }
    /// Words are on screen (`liveSlide != nil`). Changes only when that flips (Go Live, Clear, Stop), not on Next.
    public var hasLiveWords: Bool { registrar.access(self, keyPath: \.hasLiveWords); return value.liveSlide != nil }

    // MARK: Marks (FIX-Q): one slide position's own selection and live flags

    /// Whether slide position `index` is the preview selection. A reader of one position is woken only when that position gains or loses the
    /// mark, so a grid cell can ask for its own state and the grid itself need not read the selection (which would run its body, and walk its
    /// 200 cells, on every Next).
    public func isSelected(at index: Int) -> Bool { registrar.access(self, keyPath: \.[mark: .selected(index)]); return value.selectedIndex == index }
    /// Whether slide position `index` is the live place of the live deck (see `liveDeckID` for which deck that is).
    public func isLive(at index: Int) -> Bool { registrar.access(self, keyPath: \.[mark: .live(index)]); return value.liveIndex == index }

    fileprivate enum Mark: Hashable { case selected(Int), live(Int) }
    /// Only ever the subject of a key path (the observation key of one position's mark); never read.
    fileprivate subscript(mark mark: Mark) -> Bool {
        switch mark {
        case .selected(let i): value.selectedIndex == i
        case .live(let i): value.liveIndex == i
        }
    }

    // MARK: Derived (each depends only on the parts it is made from)

    /// The words on screen now: nil when stopped or cleared. Depends on the live deck, the live position and Clear.
    public var liveSlide: SlideContent? {
        registrar.access(self, keyPath: \.liveDeck); registrar.access(self, keyPath: \.liveIndex); registrar.access(self, keyPath: \.isCleared)
        return value.liveSlide
    }
    /// The slide at the live place even while cleared. Depends on the live deck and the live position.
    public var liveSlideAtPlace: SlideContent? {
        registrar.access(self, keyPath: \.liveDeck); registrar.access(self, keyPath: \.liveIndex)
        return value.liveSlideAtPlace
    }
    public var nextSlide: SlideContent? {
        registrar.access(self, keyPath: \.liveDeck); registrar.access(self, keyPath: \.liveIndex)
        return value.nextSlide
    }

    // MARK: Change

    /// Replaces the state and notifies exactly the parts that differ. Nothing is notified when nothing differs.
    public func set(_ new: ShowState) {
        let old = value
        var changed: [(will: () -> Void, did: () -> Void)] = []
        func note<M>(_ path: KeyPath<ObservedShow, M>) {
            nonisolated(unsafe) let keyPath = path      // a key path is immutable; the release compiler cannot see that it is safe to capture
            changed.append((will: { self.registrar.willSet(self, keyPath: keyPath) }, did: { self.registrar.didSet(self, keyPath: keyPath) }))
        }
        if new.selectedIndex != old.selectedIndex {
            note(\.selectedIndex)
            note(\.[mark: .selected(old.selectedIndex)]); note(\.[mark: .selected(new.selectedIndex)])
        }
        if new.liveIndex != old.liveIndex {
            note(\.liveIndex)
            if let was = old.liveIndex { note(\.[mark: .live(was)]) }
            if let now = new.liveIndex { note(\.[mark: .live(now)]) }
        }
        if new.isStopped != old.isStopped { note(\.isStopped) }
        if new.liveDeck?.presentationID != old.liveDeck?.presentationID { note(\.liveDeckID) }
        if new.liveDeck != old.liveDeck { note(\.liveDeck) }
        if new.previewDeck != old.previewDeck { note(\.previewDeck) }
        if (new.liveSlide != nil) != (old.liveSlide != nil) { note(\.hasLiveWords) }
        if new.isCleared != old.isCleared { note(\.isCleared) }
        if new.isBlackedOut != old.isBlackedOut { note(\.isBlackedOut) }
        if new.isBackgroundCleared != old.isBackgroundCleared { note(\.isBackgroundCleared) }
        // The private flags can differ with no visible part changing (Clear while stopped is ignored, so they never do); the state is
        // stored regardless so `current` is always exact.
        guard !changed.isEmpty else { value = new; return }
        for item in changed { item.will() }
        value = new
        for item in changed { item.did() }
    }

    /// Runs a command on the state and notifies the parts it changed.
    public func apply(_ command: ShowCommand) {
        var next = value
        next.apply(command)
        set(next)
    }

    private func accessAll() {
        registrar.access(self, keyPath: \.selectedIndex)
        registrar.access(self, keyPath: \.liveIndex)
        registrar.access(self, keyPath: \.isStopped)
        registrar.access(self, keyPath: \.liveDeckID)
        registrar.access(self, keyPath: \.liveDeck)
        registrar.access(self, keyPath: \.previewDeck)
        registrar.access(self, keyPath: \.isCleared)
        registrar.access(self, keyPath: \.isBlackedOut)
        registrar.access(self, keyPath: \.isBackgroundCleared)
        registrar.access(self, keyPath: \.hasLiveWords)
    }
}
