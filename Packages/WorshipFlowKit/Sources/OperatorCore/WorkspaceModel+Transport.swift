// OUT-004 / OUT-002 / PRES-03: Go Live, Next, Previous, Clear and Stop. Selecting a slide never changes live.
import Foundation
import Domain
import Persistence

extension WorkspaceModel {
    /// Moves the preview highlight. Preview only.
    public func selectSlide(_ index: Int) {
        apply(.select(index: index))
        placeChanged()
    }

    /// Takes the selected slide live. Edits made since the last trigger go out now.
    public func goLive() async { goLive(at: show.selectedIndex) }

    public func goLive(at index: Int) {
        apply(.trigger(index: index))
        recordLiveSource()
        placeChanged()
    }

    /// Notes which slides and which playlist item the live deck came from (only when something is live).
    func recordLiveSource() {
        guard show.liveDeck != nil, show.liveDeck?.presentationID == openPresentationID else { return }
        liveSlideIDs = slides.map(\.id)
        liveItemID = selectedPlaylistItemID
    }

    /// Next slide; at the end of an item, the first slide of the next playlist item; at the end of the playlist, nothing.
    public func next() async {
        guard let live = show.liveDeck, let i = show.liveIndex else {
            apply(.next)                       // nothing live yet: the first slide of the preview goes live
            recordLiveSource()
            placeChanged()
            return
        }
        if i + 1 < live.slides.count { apply(.next); placeChanged(); return }
        _ = await step(by: 1)
    }

    /// Previous slide; at the start of an item, the last slide of the previous playlist item.
    public func previous() async {
        if show.liveDeck != nil, show.liveIndex == 0, await step(by: -1) { return }
        apply(.previous)
        placeChanged()
    }

    public func clear() { apply(.clear) }

    public func stop() {
        apply(.stop)
        liveItemID = nil
        liveSlideIDs = []
    }

    /// Moves live into the neighbouring playlist item that has slides. Returns false if there is none.
    private func step(by direction: Int) async -> Bool {
        guard !stepping, let current = liveItemID, var j = playlistItems.firstIndex(where: { $0.id == current }) else { return false }
        stepping = true
        defer { stepping = false }
        j += direction
        while playlistItems.indices.contains(j) {
            let item = playlistItems[j]
            let count = (try? await store.slides(forPlaylistItem: item.id))?.count ?? 0
            if count > 0 {
                await openPlaylistItem(item.id)
                guard selectedPlaylistItemID == item.id, !slides.isEmpty else { return false }
                apply(.trigger(index: direction > 0 ? 0 : slides.count - 1))
                recordLiveSource()
                placeChanged()
                return true
            }
            j += direction
        }
        return false
    }
}
