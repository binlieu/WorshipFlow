// SLIDE-001b: where to put a new box so it does not land on top of the ones already there. Foundation only.
import Foundation

public enum FreeSpace {
    /// Distance between candidate positions, as a fraction of the slide or screen.
    static let step = 0.02

    /// Area two frames share, in 0...1 units.
    public static func overlap(_ a: NormalizedRect, _ b: NormalizedRect) -> Double {
        let w = min(a.x + a.width, b.x + b.width) - max(a.x, b.x)
        let h = min(a.y + a.height, b.y + b.height) - max(a.y, b.y)
        // Frames that only touch (up to rounding in the sums above) do not overlap.
        return w > 1e-9 && h > 1e-9 ? w * h : 0
    }

    /// A frame of the given size on the unit square that covers as little as possible of `occupied`: the position
    /// closest to `preferred` (a top-left corner) among those that overlap nothing, or, when the space is full, among
    /// those that overlap least. The size is kept (but never larger than the square) and the frame stays on it.
    public static func place(width: Double, height: Double, avoiding occupied: [NormalizedRect],
                             preferred: (x: Double, y: Double) = (0.5, 0.5)) -> NormalizedRect {
        let w = width.isFinite ? min(1, max(0.001, width)) : 0.2
        let h = height.isFinite ? min(1, max(0.001, height)) : 0.2
        let wantX = min(1 - w, max(0, preferred.x.isFinite ? preferred.x : 0))
        let wantY = min(1 - h, max(0, preferred.y.isFinite ? preferred.y : 0))
        let preferredFrame = NormalizedRect(x: wantX, y: wantY, width: w, height: h)
        if occupied.allSatisfy({ overlap($0, preferredFrame) == 0 }) { return preferredFrame }

        var best = preferredFrame
        var bestOverlap = Double.infinity
        var bestDistance = Double.infinity
        let columns = Int(((1 - w) / step).rounded(.down))
        let rows = Int(((1 - h) / step).rounded(.down))
        for row in 0...max(0, rows) {
            for column in 0...max(0, columns) {
                // The last column and row sit exactly on the far edge, so the whole square can be reached.
                let x = column == columns ? 1 - w : Double(column) * step
                let y = row == rows ? 1 - h : Double(row) * step
                let candidate = NormalizedRect(x: x, y: y, width: w, height: h)
                let covered = occupied.reduce(0) { $0 + overlap($1, candidate) }
                let distance = (x - wantX) * (x - wantX) + (y - wantY) * (y - wantY)
                if covered < bestOverlap - 1e-12 || (abs(covered - bestOverlap) <= 1e-12 && distance < bestDistance) {
                    best = candidate
                    bestOverlap = covered
                    bestDistance = distance
                }
            }
        }
        return best
    }
}
