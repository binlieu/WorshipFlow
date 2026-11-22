// FIX-O (debug builds only): counts how many times chosen SwiftUI view bodies ran, so a change to one part of the show state can be seen to
// draw only the views that read it. A body calls `let _ = BodyProbe.hit("Name")`; in a release build the call is empty. The measuring hooks
// (`UISnapshotFixM`) reset and read the counts around a gesture.
import Foundation

enum BodyProbe {
    #if DEBUG
    @MainActor private static var counts: [String: Int] = [:]
    @MainActor @discardableResult static func hit(_ name: String) -> Bool { counts[name, default: 0] += 1; return true }
    @MainActor static func reset() { counts = [:] }
    @MainActor static func snapshot() -> [String: Int] { counts }
    /// "Name n, Name n" sorted by name, only the views that ran.
    @MainActor static func summary() -> String { counts.sorted { $0.key < $1.key }.map { "\($0.key) \($0.value)" }.joined(separator: ", ") }
    #else
    @inline(__always) @discardableResult static func hit(_ name: String) -> Bool { true }
    #endif
}
