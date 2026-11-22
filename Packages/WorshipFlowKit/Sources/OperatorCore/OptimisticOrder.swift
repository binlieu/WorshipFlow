// FIX-M: the rules behind a drop that shows at once. A reorder changes the visible order first (rows keep their identity, only the
// positions between the two ends change) and the database write follows; the tracker remembers the order the database holds so a failed
// write can put the visible order back. Foundation only.
import Foundation

public enum OrderMove {
    /// `items` with the row at `from` moved so that it ends at `to` (clamped to the list). A source that is not there changes nothing.
    public static func moved<T>(_ items: [T], from: Int, to: Int) -> [T] {
        guard items.indices.contains(from) else { return items }
        var out = items
        let row = out.remove(at: from)
        out.insert(row, at: min(max(to, 0), out.count))
        return out
    }

    /// The positions whose row differs after the move: from the smaller end to the larger, or nil when nothing moves.
    public static func dirtyRange(count: Int, from: Int, to: Int) -> ClosedRange<Int>? {
        guard from >= 0, from < count else { return nil }
        let target = min(max(to, 0), count - 1)
        return target == from ? nil : min(from, target)...max(from, target)
    }

    /// `items` put back in the order `ids` gives, each row keeping its current content. Rows the order does not name follow, in their place.
    public static func restoring<T: Identifiable>(_ items: [T], toOrder ids: [T.ID]) -> [T] {
        var byID: [T.ID: T] = [:]
        for item in items { byID[item.id] = item }
        let known = ids.compactMap { byID[$0] }
        let named = Set(ids)
        return known + items.filter { !named.contains($0.id) }
    }
}

/// The identity a slide cell keeps across a reorder: the slide's id, and which time it appears (an arrangement can repeat a slide).
public struct SlideCellKey: Hashable, Sendable {
    public let id: UUID
    public let occurrence: Int

    public static func keys(for ids: [UUID]) -> [SlideCellKey] {
        var seen: [UUID: Int] = [:]
        return ids.map { id in
            let n = seen[id, default: 0]
            seen[id] = n + 1
            return SlideCellKey(id: id, occurrence: n)
        }
    }
}

/// Which order the database holds while drops are being written, so the visible order can go back there when a write fails.
public struct ReorderTracker<ID: Hashable & Sendable>: Sendable {
    public private(set) var confirmed: [ID] = []
    public private(set) var pending = 0
    public private(set) var epoch = 0

    public init() {}
    public var isIdle: Bool { pending == 0 }
    /// A write queued behind a failure (it began in an older epoch) must not run: the visible order was already put back.
    public func isStale(_ began: Int) -> Bool { began != epoch }

    /// A drop was applied to the screen. `current` is the visible order from before it; with nothing pending it is what the database holds.
    public mutating func begin(current: [ID]) {
        if pending == 0 { confirmed = current }
        pending += 1
    }

    /// The write of the oldest pending drop succeeded: the database now holds that move too.
    public mutating func succeeded(id: ID, to index: Int) {
        if let from = confirmed.firstIndex(of: id) { confirmed = OrderMove.moved(confirmed, from: from, to: index) }
        pending = max(0, pending - 1)
    }

    /// The write failed: the order to show again (the one the database holds). Later queued drops are stale.
    public mutating func failed() -> [ID] {
        pending = max(0, pending - 1)
        epoch += 1
        return confirmed
    }

    /// A queued drop that was dropped without a write (it was stale).
    public mutating func skipped() { pending = max(0, pending - 1) }
}
