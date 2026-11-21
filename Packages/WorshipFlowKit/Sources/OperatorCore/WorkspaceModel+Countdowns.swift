// UI-002 Part 5: playlist headers and countdowns. A header is a label in the list: it cannot be selected for live and Next
// and Previous skip it. A countdown goes live as a one-slide deck whose words are the time left, so the audience screen draws
// it with the theme's primary text style and the stage screen shows it as the current slide. At zero it stays at zero until
// the operator moves on; nothing here ever steps the show by itself.
import Foundation
import Domain
import Persistence

/// The countdown that is live now.
public struct LiveCountdown: Equatable, Sendable {
    public let itemID: UUID
    public let run: CountdownRun
    public let label: String
    public func isFinished(at now: Date) -> Bool { run.isFinished(at: now) }
}

extension WorkspaceModel {
    public func addHeader(_ label: String) async {
        let playlist = await ensurePlaylist()
        guard let playlist else { return }
        guard await attempt("add the header", { try await self.store.addPlaylistHeader(label, to: playlist) }) != nil else { return }
        await reloadPlaylistItems()
        placeChanged()
    }

    public func addCountdown(_ spec: CountdownSpec) async {
        let playlist = await ensurePlaylist()
        guard let playlist else { return }
        guard await attempt("add the countdown", { try await self.store.addPlaylistCountdown(spec, to: playlist) }) != nil else { return }
        await reloadPlaylistItems()
        placeChanged()
    }

    /// Changes a header's label or a countdown's settings.
    public func updatePlaylistItem(id: UUID, kind: PlaylistItemKind) async {
        guard await attempt("change the item", { try await self.store.updatePlaylistItem(id: id, kind: kind) }) != nil else { return }
        await reloadPlaylistItems()
    }

    private func ensurePlaylist() async -> UUID? {
        if selectedPlaylistID == nil {
            guard let p = await attempt("create the playlist", { try await self.store.createPlaylist(name: "Service") }) else { return nil }
            await reloadPlaylists()
            selectedPlaylistID = p.id
        }
        return selectedPlaylistID
    }

    var playlistKinds: [PlaylistItemKind] { playlistItems.map(\.kind) }

    /// Takes the countdown item live: the time left becomes the one slide of a deck.
    func goLiveOnCountdown(_ item: PlaylistItem) {
        guard case .countdown(let spec) = item.kind else { return }
        let run = CountdownRun(spec: spec, startedAt: countdownClock())
        transportEpoch &+= 1
        selectedPlaylistItemID = item.id
        let text = CountdownText.format(run.remaining(at: countdownClock()))
        let keptSelection = show.selectedIndex
        apply(.load(ShowDeck(presentationID: item.id, slides: [SlideContent(primary: text)])))
        apply(.trigger(index: 0))
        // FIX-D S2: the countdown is live, but the preview goes back to the open presentation with the operator's own selection,
        // so a slide chosen next is a slide of that presentation and Go Live starts it.
        apply(.restore(deck: previewDeck(), selectedIndex: keptSelection))
        liveItemID = item.id
        liveSlideIDs = []
        liveSlideNotes = [""]
        liveTitle = spec.label.isEmpty ? "Countdown" : spec.label
        liveSectionNames = [nil]
        liveCountdown = LiveCountdown(itemID: item.id, run: run, label: liveTitle ?? "")
        placeChanged()
    }

    /// Called about once a second by the app while a countdown is live. Rewrites the live slide's time; at zero it
    /// keeps showing 0:00 and never advances.
    public func countdownTick(now: Date? = nil) {
        guard let live = liveCountdown, show.liveDeck?.presentationID == live.itemID, show.liveIndex == 0 else { return }
        let text = CountdownText.format(live.run.remaining(at: now ?? countdownClock()))
        guard show.liveSlide?.primary != text else { return }
        apply(.quickEdit(index: 0, content: SlideContent(primary: text)))
    }

    /// A header or countdown that was removed while live: a countdown leaves the screens (cleared), a stored place on it is dropped.
    func countdownItemRemoved(_ id: UUID) {
        guard liveCountdown?.itemID == id else { return }
        liveCountdown = nil
        apply(.clear)
    }
}
