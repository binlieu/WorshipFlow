import Foundation
import Domain

/// FIX-S (KI-193): one cell of the slide grid, the slide list or the Edit film strip, made once by the body that lays the cells out. It carries the
/// slide itself, so the lazy closure that draws the cell never indexes the model's slide list by a position. A lazy container runs its content
/// closure later than the body that made the slots, and still runs the closures of cells that are on their way out; with a live read
/// (`workspace.slides[index]`) a position of a longer presentation was asked of a shorter one (the crash in build 139). A slot cannot go out of range,
/// because it holds what it shows.
public struct CellSlot: Identifiable, Sendable {
    public let index: Int
    public let key: SlideCellKey
    public let slide: Slide
    public let isLast: Bool
    public var id: SlideCellKey { key }

    /// The slot for `index`, or nil when `slides` or `keys` has nothing at that position (a run that names more slides than the list has).
    public init?(at index: Int, slides: [Slide], keys: [SlideCellKey]) {
        guard slides.indices.contains(index), keys.indices.contains(index) else { return nil }
        self.index = index
        self.key = keys[index]
        self.slide = slides[index]
        self.isLast = index == slides.count - 1
    }
}
