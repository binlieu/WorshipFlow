// FIX-H item 8 (UI-005b): the rules behind the app's custom controls that need no interface to be right. Foundation only.
import Foundation

/// How a focused slider moves with the keyboard: arrows by a twentieth of the range, Page Up and Page Down by a fifth, Home and End to
/// the ends. The value always stays inside the range.
public enum SliderStepping {
    public enum Move: Sendable, Equatable { case smaller, larger, smallerPage, largerPage, minimum, maximum }

    public static func value(from current: Double, range: ClosedRange<Double>, move: Move) -> Double {
        let span = range.upperBound - range.lowerBound
        guard span > 0, span.isFinite else { return range.lowerBound }
        let start = current.isNaN ? range.lowerBound : min(range.upperBound, max(range.lowerBound, current))      // an infinity is held at an end
        let result: Double
        switch move {
        case .larger: result = start + span / 20
        case .smaller: result = start - span / 20
        case .largerPage: result = start + span / 5
        case .smallerPage: result = start - span / 5
        case .minimum: result = range.lowerBound
        case .maximum: result = range.upperBound
        }
        // Rounded to the nearest millionth so repeated steps do not drift (0.1 + 0.05 + 0.05 ...).
        let rounded = (result * 1_000_000).rounded() / 1_000_000
        return min(range.upperBound, max(range.lowerBound, rounded))
    }
}

/// A disabled custom control is dimmed and takes no input.
public enum ControlEnabledStyle {
    public static func opacity(isEnabled: Bool) -> Double { isEnabled ? 1 : 0.45 }
    public static func acceptsInput(isEnabled: Bool) -> Bool { isEnabled }
}

/// Segments are told apart by their position, not by their label: two segments may be named alike (and the label is also the
/// spoken name, which is not always unique).
public enum SegmentIdentity {
    public static func ids(count: Int) -> [Int] { Array(0..<max(0, count)) }
    public static func selectedIndex<Value: Equatable>(values: [Value], selection: Value) -> Int? { values.firstIndex(of: selection) }
}
