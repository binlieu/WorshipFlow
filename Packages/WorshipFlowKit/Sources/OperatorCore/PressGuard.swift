// FIX-P item 4 (UI-005e, UI-004): a pointer press that was ended early (the window resigned key, the layout changed, another write closed the drag)
// while SwiftUI keeps delivering the same gesture must not start again from the same press: the box would jump by the offset a second time.
// The gesture's events after the interruption are ignored until its own end. A press at another place is a new press, so a gesture whose end never
// came cannot swallow the next click. Foundation only.
import Foundation

public struct PressGuard: Equatable, Sendable {
    public struct Point: Equatable, Sendable {
        public let x: Double, y: Double
        public init(x: Double, y: Double) { self.x = x; self.y = y }
    }
    public enum Event: Equatable, Sendable { case began, continuing, ignored }

    public private(set) var pressed = false
    private var start: Point?
    private var interrupted = false
    private var interruptedStart: Point?

    public init() {}

    /// One event of the gesture (`startedAt` is the gesture's start location, when it has one).
    public mutating func event(startedAt: Point? = nil) -> Event {
        if interrupted {
            if let startedAt, startedAt != interruptedStart { interrupted = false } else { return .ignored }
        }
        if pressed { return .continuing }
        pressed = true
        start = startedAt
        return .began
    }

    /// The press was ended by something other than the gesture. Its remaining events are ignored until `ended()`.
    public mutating func interrupt() {
        guard pressed else { return }
        pressed = false
        interrupted = true
        interruptedStart = start
    }

    /// The gesture's own end.
    public mutating func ended() {
        pressed = false
        interrupted = false
        start = nil
        interruptedStart = nil
    }
}
