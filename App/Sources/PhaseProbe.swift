// FIX-Q (measuring builds only: Debug, or a build with the WF_MEASURE compilation condition; empty in the packaged app): adds up the main-thread
// time of named phases inside one command, and records when the screens were handed a new scene, so Next's time can be split and the time from the
// command to the publication measured. A call is `PhaseProbe.time("name") { ... }`; in a normal release build it only runs the closure.
import Foundation

enum PhaseProbe {
    #if DEBUG || WF_MEASURE
    @MainActor private static var totals: [String: Double] = [:]
    @MainActor private static var order: [String] = []
    /// When the command being measured began and when the scenes were handed to the outputs (both on the main thread).
    @MainActor static var commandStart: ContinuousClock.Instant?
    @MainActor static var publishedAt: ContinuousClock.Instant?
    @MainActor static var publications = 0

    @MainActor static func time<T>(_ name: String, _ body: () -> T) -> T {
        let t0 = ContinuousClock.now
        let result = body()
        let d = ContinuousClock.now - t0
        let ms = Double(d.components.seconds) * 1000 + Double(d.components.attoseconds) / 1e15
        if totals[name] == nil { order.append(name) }
        totals[name, default: 0] += ms
        return result
    }
    @MainActor static func markPublished() { publishedAt = ContinuousClock.now; publications += 1 }
    @MainActor static func reset() { totals = [:]; order = []; commandStart = nil; publishedAt = nil }
    @MainActor static func summary() -> String { order.map { String(format: "%@ %.2f", $0, totals[$0] ?? 0) }.joined(separator: ", ") }
    /// Milliseconds from the command's start to the publication, or nil when nothing was published since `reset`.
    @MainActor static func commandToPublication() -> Double? {
        guard let a = commandStart, let b = publishedAt else { return nil }
        let d = b - a
        return Double(d.components.seconds) * 1000 + Double(d.components.attoseconds) / 1e15
    }
    #else
    @inline(__always) @MainActor static func time<T>(_ name: String, _ body: () -> T) -> T { body() }
    @inline(__always) @MainActor static func markPublished() {}
    #endif
}
