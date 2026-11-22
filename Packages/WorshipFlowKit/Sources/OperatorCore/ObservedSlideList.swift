// FIX-O (KI-180): the open presentation's slide list, observable one part at a time. `slides` was one observed array, so a change to any
// one slide made every view that read any slide draw again (the Show inspector's preview, the quick edit tab, the Edit panels, the grid).
// Here a reader asks for what it draws: the count, whether the list is empty, the order, or one slide by position. A change notifies only
// the readers of the parts that changed: editing slide 150 notifies the reader of slide 150 and the readers of the whole list, not the
// reader of slide 7, the count or the order.
import Foundation
import Observation
import Domain

/// One slide's own observation key. Readers of `slide(at:)` depend on it; it changes only when that slide's value changes.
@MainActor
final class SlideToken: Observable {
    private let registrar = ObservationRegistrar()
    private var count = 0
    var revision: Int { registrar.access(self, keyPath: \.revision); return count }
    func willChange() { registrar.willSet(self, keyPath: \.revision) }
    func didChange() { count += 1; registrar.didSet(self, keyPath: \.revision) }
}

@MainActor
public final class ObservedSlideList: Observable {
    private let registrar = ObservationRegistrar()
    private var items: [Slide] = []
    private var tokens: [UUID: SlideToken] = [:]

    public init() {}

    /// The whole list, in play order. Depends on every change (the old behaviour); prefer a part.
    public var all: [Slide] { registrar.access(self, keyPath: \.all); return items }
    /// The list without registering a dependency: for the model's own bookkeeping, never for a view.
    public var current: [Slide] { items }
    /// How many slides. Changes only when slides are added or removed.
    public var count: Int { registrar.access(self, keyPath: \.count); return items.count }
    /// Whether there are none. Changes only when the list becomes empty or stops being empty.
    public var isEmpty: Bool { registrar.access(self, keyPath: \.isEmpty); return items.isEmpty }
    /// The slide ids in order. Changes when slides are added, removed or moved (not when one slide's words change).
    public var order: [UUID] { registrar.access(self, keyPath: \.order); return items.map(\.id) }

    /// The slide at a position: depends on the order (which slide sits there) and on that one slide's value, not on any other slide.
    public func slide(at index: Int) -> Slide? {
        registrar.access(self, keyPath: \.order)
        guard items.indices.contains(index) else { return nil }
        let id = items[index].id
        let token = tokens[id] ?? { let made = SlideToken(); tokens[id] = made; return made }()
        _ = token.revision
        return items[index]
    }

    /// Replaces the list and notifies exactly the parts that differ. Nothing is notified when nothing differs.
    public func set(_ new: [Slide]) {
        if new == items { return }
        let old = items
        let oldIDs = old.map(\.id), newIDs = new.map(\.id)
        let orderChanged = oldIDs != newIDs
        var changed = Set<UUID>()
        if !orderChanged {
            for index in old.indices where old[index] != new[index] { changed.insert(new[index].id) }
        } else {
            let before = Dictionary(old.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
            for slide in new where before[slide.id] != slide { changed.insert(slide.id) }
            changed.formUnion(Set(oldIDs).subtracting(newIDs))
        }
        var notes: [(will: () -> Void, did: () -> Void)] = []
        func note<M>(_ keyPath: KeyPath<ObservedSlideList, M>) {
            notes.append((will: { self.registrar.willSet(self, keyPath: keyPath) }, did: { self.registrar.didSet(self, keyPath: keyPath) }))
        }
        note(\.all)
        if orderChanged { note(\.order) }
        if old.count != new.count { note(\.count) }
        if old.isEmpty != new.isEmpty { note(\.isEmpty) }
        let touched = changed.compactMap { tokens[$0] }
        for item in notes { item.will() }
        for token in touched { token.willChange() }
        items = new
        for item in notes { item.did() }
        for token in touched { token.didChange() }
        if orderChanged { tokens = tokens.filter { Set(newIDs).contains($0.key) } }
    }
}
