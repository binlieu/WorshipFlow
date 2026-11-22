// FIX-N item 5 (UI-005e): arrow-key nudges of a Stage canvas box. Holding an arrow key used to write, publish and record an undo step on every
// auto-repeat (about 30 a second). A run of nudges now moves a transient frame the canvas draws, and is committed once: when the key is released,
// after a short quiet period, or when the selection changes, the layout changes or the view goes (`flush`). One run is one undo step and one
// write, so a stage screen updates once per commit. The clock is injected. Foundation, Observation and Domain only.
import Foundation
import Observation
import Domain

@MainActor
@Observable
public final class StageNudgeSession {
    /// The one write a run ends in.
    public struct Commit: Equatable, Sendable {
        public let elementID: UUID
        public let from: NormalizedRect
        public let to: NormalizedRect
    }

    private struct Run { let elementID: UUID; let start: NormalizedRect; var current: NormalizedRect; var lastNudge: Date }

    @ObservationIgnored private var run: Run?
    /// Bumped by each nudge so a view that reads `transientFrame(for:)` redraws.
    public private(set) var revision = 0
    @ObservationIgnored public let quietPeriod: TimeInterval
    @ObservationIgnored private let autoTick: Bool
    @ObservationIgnored private let clock: () -> Date
    /// Where a finished run goes (the view writes it with `StageCanvasEditing.commit`, which registers the undo step). The view keeps it current.
    @ObservationIgnored public var onCommit: (Commit) -> Void
    @ObservationIgnored private var idle: Task<Void, Never>?

    public init(quietPeriod: TimeInterval = 0.6, autoTick: Bool = true, clock: @escaping () -> Date = { Date() }, onCommit: @escaping (Commit) -> Void = { _ in }) {
        self.quietPeriod = quietPeriod
        self.autoTick = autoTick
        self.clock = clock
        self.onCommit = onCommit
    }

    /// The frame the canvas draws for `elementID` while a run is open on it, else nil (draw the stored frame).
    public func transientFrame(for elementID: UUID) -> NormalizedRect? {
        _ = revision
        guard let run, run.elementID == elementID else { return nil }
        return run.current
    }

    /// True while a run is open.
    public var isOpen: Bool { run != nil }

    /// One arrow press: moves the open run's frame (or opens a run from `stored`) by one point, ten with Shift, kept on the canvas.
    public func nudge(elementID: UUID, stored: NormalizedRect, directionX: Int, directionY: Int, shift: Bool, canvasWidth: Double, canvasHeight: Double) {
        if let run, run.elementID != elementID { flush() }
        let base = run?.current ?? stored
        let to = StageCanvasEditing.nudged(base, directionX: directionX, directionY: directionY, points: StageCanvasEditing.nudgeDistance(shift: shift),
                                           canvasWidth: canvasWidth, canvasHeight: canvasHeight)
        run = Run(elementID: elementID, start: run?.start ?? stored, current: to, lastNudge: clock())
        revision &+= 1
        scheduleTick()
    }

    /// The arrow key was released: the run ends.
    public func keyReleased() { flush() }

    /// Ends the run when the quiet period has passed since the last nudge.
    public func tick() {
        guard let run, clock().timeIntervalSince(run.lastNudge) >= quietPeriod else { return }
        _ = run
        flush()
    }

    /// Ends the run now: the selection or the layout changed, another edit is about to happen, or the view is going. Nothing is written when the
    /// run ended where it began.
    public func flush() {
        idle?.cancel()
        idle = nil
        guard let finished = run else { return }
        run = nil
        revision &+= 1
        if finished.start != finished.current { onCommit(Commit(elementID: finished.elementID, from: finished.start, to: finished.current)) }
    }

    private func scheduleTick() {
        guard autoTick else { return }
        idle?.cancel()
        let wait = quietPeriod
        idle = Task { [weak self] in
            try? await Task.sleep(for: .seconds(wait))
            guard !Task.isCancelled else { return }
            self?.tick()
        }
    }
}
