// UI-005b item 7: the error card for an output that stopped (the design's "Retry output" and "Details"). A card exists only for an
// enabled output whose state is faulted (a screen or one of its mirrors): that is where reopening means something. A covered window, a
// stopped or disabled screen and a render warning get no card. Retry goes through the coordinator's own restart; it never touches Live.
import Foundation

public struct OutputFaultCard: Equatable, Identifiable, Sendable {
    public var id: UUID { screenID }
    public var screenID: UUID
    public var name: String
    /// The card's words: what stopped, and that nothing else did.
    public var message: String
    /// The recorded fault text, exactly as the output reported it, for Details and Copy.
    public var detail: String
    public var canRetry: Bool
    /// FIX-H item 4: the output that is faulted: the screen itself, or one of its mirrors. Retry restarts this and nothing else.
    public var slot: OutputSlot

    public init(screenID: UUID, name: String, message: String, detail: String, canRetry: Bool, slot: OutputSlot? = nil) {
        self.screenID = screenID
        self.name = name
        self.message = message
        self.detail = detail
        self.canRetry = canRetry
        self.slot = slot ?? OutputSlot(screenID: screenID)
    }
}

/// What a Retry needs from the coordinator, so a test can record which output was asked to restart.
@MainActor
public protocol OutputRestarting: AnyObject {
    func restart(slot: OutputSlot)
    func readouts() -> [ScreenReadout]
}

extension OutputCoordinator: OutputRestarting {}

public enum RetryOutcome: Equatable, Sendable {
    case reopened
    /// The output is still faulted (or gone); the text says so in plain words, with the new recorded text.
    case stillFailing(String)
}

public enum OutputFaultCards {
    /// One card per faulted output, in the order of `readouts`. A screen whose mirror and itself are both faulted gets one card, from the screen.
    public static func cards(from readouts: [ScreenReadout]) -> [OutputFaultCard] {
        readouts.compactMap { r in
            guard r.isEnabled else { return nil }
            var text: String?
            var which = r.name
            var slot = OutputSlot(screenID: r.id)
            if case .faulted(let t) = r.state { text = t }
            else if let m = r.mirrors.first(where: { if case .faulted = $0.state { true } else { false } }), case .faulted(let t) = m.state {
                text = t
                which = "\(r.name) (mirror \(m.index + 1))"
                slot = OutputSlot(screenID: r.id, mirror: m.index)
            }
            guard let text else { return nil }
            return OutputFaultCard(screenID: r.id, name: r.name,
                                   message: "\(which) is not sending. The operator controls and the other screens are not affected.",
                                   detail: text, canRetry: true, slot: slot)
        }
    }

    /// FIX-H item 4: restarts the card's own output once (a mirror's card restarts that mirror, never the healthy screen beside it) and
    /// reports what it now looks like.
    @MainActor public static func retry(_ card: OutputFaultCard, on coordinator: some OutputRestarting) -> RetryOutcome {
        coordinator.restart(slot: card.slot)
        let readout = coordinator.readouts().first { $0.id == card.screenID }
        guard let readout else {
            return .stillFailing("\(card.name) is no longer in the screen list, so it could not be reopened. Open the Screens tab to check its settings.")
        }
        let state: ScreenState? = card.slot.mirror.flatMap { i in readout.mirrors.first { $0.index == i }?.state } ?? (card.slot.mirror == nil ? readout.state : nil)
        if case .faulted(let text)? = state {
            return .stillFailing("\(card.name) did not reopen: \(text) Check the cable, display or card, then try Retry output again.")
        }
        return .reopened
    }

    /// FIX-H item 4: the "did not reopen" notes that still have a card. A note for an output that came back, or went, is dropped.
    public static func notes(_ notes: [UUID: String], keepingCardsOf cards: [OutputFaultCard]) -> [UUID: String] {
        let ids = Set(cards.map(\.screenID))
        return notes.filter { ids.contains($0.key) }
    }

    /// Reopens the output once through `reopen` (the coordinator's restart) and reports what it now looks like.
    public static func retry(_ id: UUID, name: String, reopen: (UUID) -> Void, state: (UUID) -> ScreenState?) -> RetryOutcome {
        reopen(id)
        switch state(id) {
        case .faulted(let text)?:
            return .stillFailing("\(name) did not reopen: \(text) Check the cable, display or card, then try Retry output again.")
        case nil:
            return .stillFailing("\(name) is no longer in the screen list, so it could not be reopened. Open the Screens tab to check its settings.")
        default:
            return .reopened
        }
    }
}
