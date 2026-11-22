// FIX-I item 7: when the output-fault message card is on screen. A card appears when a fault is new (a new output, a different fault text or
// mirror, a fault that cleared and came back) and fades five seconds later, unless the pointer is over it or keyboard focus is inside it; then
// it fades when the hold ends. The fault itself is not hidden: the toolbar pill and the monitor read the screen's state, and `showAgain` (a click
// on the pill) brings the card back for another five seconds. Time is a value the caller passes in, so tests and the app use the same rules
// with their own clocks. Foundation only.
import Foundation

public struct FaultCardVisibility: Equatable, Sendable {
    public static let fadeAfter: TimeInterval = 5

    private struct Fault: Equatable, Sendable { var slot: OutputSlot; var detail: String }
    private struct Entry: Equatable, Sendable {
        var fault: Fault
        var visibleUntil: Date
        var pointerOver = false
        var focusInside = false
        var isHeld: Bool { pointerOver || focusInside }
    }
    private var entries: [UUID: Entry] = [:]

    public init() {}

    /// Called whenever the cards may have changed (every refresh of the readouts). New or different faults start their five seconds at `now`;
    /// a card that is gone is forgotten, so the same fault coming back later is new again.
    public mutating func update(cards: [OutputFaultCard], now: Date) {
        let present = Set(cards.map(\.screenID))
        entries = entries.filter { present.contains($0.key) }
        for card in cards {
            let fault = Fault(slot: card.slot, detail: card.detail)
            if entries[card.screenID]?.fault != fault {
                entries[card.screenID] = Entry(fault: fault, visibleUntil: now.addingTimeInterval(Self.fadeAfter))
            }
        }
    }

    public mutating func setPointerOver(_ over: Bool, screenID: UUID, now: Date) {
        guard var entry = entries[screenID] else { return }
        entry.pointerOver = over
        entries[screenID] = Self.released(entry, now: now)
    }

    public mutating func setFocusInside(_ inside: Bool, screenID: UUID, now: Date) {
        guard var entry = entries[screenID] else { return }
        entry.focusInside = inside
        entries[screenID] = Self.released(entry, now: now)
    }

    /// A click on the pill (or a Retry that did not work): the card shows again for another five seconds.
    public mutating func showAgain(screenID: UUID, now: Date) {
        guard var entry = entries[screenID] else { return }
        entry.visibleUntil = now.addingTimeInterval(Self.fadeAfter)
        entries[screenID] = entry
    }

    public func isVisible(screenID: UUID, now: Date) -> Bool {
        guard let entry = entries[screenID] else { return false }
        return entry.isHeld || now < entry.visibleUntil
    }

    public func visibleCards(from cards: [OutputFaultCard], now: Date) -> [OutputFaultCard] {
        cards.filter { isVisible(screenID: $0.screenID, now: now) }
    }

    /// The next moment a visible, unheld card fades, so the caller can look again then. Nil when nothing is pending.
    public func nextChange(now: Date) -> Date? {
        entries.values.filter { !$0.isHeld && now < $0.visibleUntil }.map(\.visibleUntil).min()
    }

    /// When a hold ends, the card goes at its original time, or at once if that time has already passed.
    private static func released(_ entry: Entry, now: Date) -> Entry {
        var entry = entry
        if !entry.isHeld { entry.visibleUntil = max(entry.visibleUntil, now) }
        return entry
    }
}
