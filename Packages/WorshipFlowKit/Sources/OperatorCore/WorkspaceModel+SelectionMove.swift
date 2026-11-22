// FIX-I items 2 and 3: the arrow keys. They move the Preview selection and nothing else: no screen changes, no live slide moves. Past the last
// slide of a presentation that was opened from the playlist, Right selects the next playable playlist item (headers are skipped); Left
// before the first slide selects the last slide of the previous one. Up and Down move by a row and never cross items.
import Foundation
import Domain

extension WorkspaceModel {
    /// Moves the selection one step in the slide grid. `columns` is how many slides the grid draws across (1 for the list).
    public func moveSelection(_ move: SelectionMove, columns: Int) async {
        let count = show.previewDeck?.slides.count ?? 0
        // A countdown, a file or a loop is selected as an item: the arrows step through the playlist from it.
        if selectionIsAnItem {
            await selectNeighbouringItem(direction: (move == .left || move == .up) ? -1 : 1, from: selectedPlaylistItemID)
            return
        }
        let runs: [[Int]] = {
            let computed = SectionRuns.runs(slideGroupIDs: slides.map(\.groupID), groups: groups, groupSlideCounts: groupSlideCounts)
            let flat = computed.flatMap(\.indices)
            return flat.count == count && !computed.isEmpty ? computed.map(\.indices) : [Array(0..<count)]      // a passage has no sections
        }()
        if count > 0, let target = SlideGridNavigation.target(from: show.selectedIndex, move: move, columns: columns, runs: runs) {
            apply(.select(index: target))
            placeChanged()
            return
        }
        guard move == .left || move == .right else { return }                // Up and Down stop at the ends
        await selectNeighbouringItem(direction: move == .right ? 1 : -1, from: openPlaylistItemID)
    }

    /// True when what is selected is a playlist item with no slides of its own to move through.
    private var selectionIsAnItem: Bool {
        guard let id = selectedPlaylistItemID, id != openPlaylistItemID, let item = playlistItems.first(where: { $0.id == id }) else { return false }
        if case .countdown = item.kind { return true }
        return item.kind.isMediaPlayback
    }

    /// Selects the playable item next to `from` in the playlist, in Preview only. Nothing when there is none (the end of the playlist, or a
    /// presentation that was opened from the library and so has no place in the playlist).
    private func selectNeighbouringItem(direction: Int, from id: UUID?) async {
        guard let id, let here = playlistItems.firstIndex(where: { $0.id == id }),
              let target = PlaylistStepping.target(kinds: playlistKinds, from: here, direction: direction) else { return }
        let item = playlistItems[target]
        await openPlaylistItem(item.id)
        guard selectedPlaylistItemID == item.id, item.id == openPlaylistItemID, let count = show.previewDeck?.slides.count, count > 0 else { return }
        apply(.select(index: direction > 0 ? 0 : count - 1))          // a song or passage: its first slide going forward, its last going back
        placeChanged()
    }
}
