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
    public func goLive() async {
        await serialized { [self] in goLive(at: show.selectedIndex) }
    }

    public func goLive(at index: Int) {
        transportEpoch &+= 1
        apply(.trigger(index: index))
        recordLiveSource()
        placeChanged()
    }

    /// Notes which slides and which playlist item the live deck came from (only when something is live).
    func recordLiveSource() {
        guard show.liveDeck != nil, show.liveDeck?.presentationID == openPresentationID else { return }
        liveSlideIDs = slides.map(\.id)
        liveSlideNotes = slides.map(\.notes)
        liveTitle = presentations.first { $0.id == openPresentationID }?.title
        liveSectionNames = slides.map { slide in slide.groupID.flatMap { id in groups.first { $0.id == id }?.name } }
        liveItemID = selectedPlaylistItemID
    }

    /// Next slide; at the end of an item, the first slide of the next playlist item; at the end of the playlist, nothing.
    public func next() async {
        let epoch = transportEpoch
        await serialized { [self] in
            guard epoch == transportEpoch else { return }       // Clear, Stop or a direct trigger came after this press
            await nextNow(epoch: epoch)
        }
    }

    /// Runs `body` after every earlier transport command has finished (R1).
    private func serialized(_ body: @escaping @MainActor () async -> Void) async {
        let previous = transportTail
        let mine = Task { @MainActor in
            await previous?.value
            await body()
        }
        transportTail = mine
        await mine.value
    }

    private func nextNow(epoch: Int) async {
        guard let live = show.liveDeck, let i = show.liveIndex else {
            apply(.next)                       // nothing live yet: the first slide of the preview goes live
            recordLiveSource()
            placeChanged()
            return
        }
        if i + 1 < live.slides.count { apply(.next); placeChanged(); return }
        _ = await step(by: 1, epoch: epoch)
    }

    /// Previous slide; at the start of an item, the last slide of the previous playlist item.
    public func previous() async {
        let epoch = transportEpoch
        await serialized { [self] in
            guard epoch == transportEpoch else { return }
            if show.liveDeck != nil, show.liveIndex == 0, await step(by: -1, epoch: epoch) { return }
            guard epoch == transportEpoch else { return }
            apply(.previous)
            placeChanged()
        }
    }

    public func clear() {
        transportEpoch &+= 1
        apply(.clear)
    }

    /// R8, "Clear all": the words go (as with `clear`) and a clip playing over the slide stops. Clear alone leaves the clip.
    public func clearAll() {
        transportEpoch &+= 1
        apply(.clearAll)
        onClearAll?()
    }

    /// UI-001: toggles Blackout. The place and the live deck are kept; a trigger, Next or Previous lifts it.
    public func blackout() {
        transportEpoch &+= 1
        apply(.blackout)
    }

    public func stop() {
        transportEpoch &+= 1
        apply(.stop)
        liveItemID = nil
        liveSlideIDs = []
        liveSlideNotes = []
        liveTitle = nil
        liveSectionNames = []
    }

    /// UI-001: "Amazing Grace · Chorus · slide 3 of 9" for the transport bar; nil when nothing is live.
    public var livePositionLine: String? {
        guard let deck = show.liveDeck, let i = show.liveIndex else { return nil }
        return LiveSummary.positionLine(title: liveTitle, section: liveSectionNames.indices.contains(i) ? liveSectionNames[i] : nil,
                                        index: i, count: deck.slides.count)
    }

    /// Speaker notes of the slide that is live, for the stage screen (LIVE-02); nil when nothing is live or the
    /// slide has none. Follows edits while the live presentation is the open one.
    public var liveNotes: String? {
        guard let i = show.liveIndex, show.liveSlide != nil, liveSlideIDs.indices.contains(i) else { return nil }
        let text: String?
        if show.liveDeck?.presentationID == openPresentationID, let slide = slides.first(where: { $0.id == liveSlideIDs[i] }) {
            text = slide.notes
        } else {
            text = liveSlideNotes.indices.contains(i) ? liveSlideNotes[i] : nil
        }
        guard let text, !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return nil }
        return text
    }

    /// Moves live into the neighbouring playlist item. Returns false if there is none, or if it has no slides (then
    /// `lastError` says so: an item is never skipped silently, R11).
    private func step(by direction: Int, epoch: Int) async -> Bool {
        guard !stepping, let current = liveItemID, let here = playlistItems.firstIndex(where: { $0.id == current }) else { return false }
        stepping = true
        defer { stepping = false }
        let j = here + direction
        guard playlistItems.indices.contains(j) else { return false }
        let item = playlistItems[j]
        let count = (try? await store.slides(forPlaylistItem: item.id))?.count ?? 0
        guard epoch == transportEpoch else { return false }
        guard count > 0 else {
            let what = direction > 0 ? "Next" : "Previous"
            lastError = "\(what) stopped: \"\(item.title)\" has no slides to show (its section order may be empty). Choose another song in the playlist and press Go Live, or fix its section order."
            return false
        }
        await openPlaylistItem(item.id)
        guard epoch == transportEpoch, selectedPlaylistItemID == item.id, !slides.isEmpty else { return false }
        apply(.trigger(index: direction > 0 ? 0 : slides.count - 1))
        recordLiveSource()
        placeChanged()
        return true
    }
}
