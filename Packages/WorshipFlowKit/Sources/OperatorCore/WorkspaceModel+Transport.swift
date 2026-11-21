// OUT-004 / OUT-002 / PRES-03: Go Live, Next, Previous, Clear and Stop. Selecting a slide never changes live.
import Foundation
import Domain
import Persistence

extension WorkspaceModel {
    /// Moves the preview highlight. Preview only.
    public func selectSlide(_ index: Int) {
        chooseOpenPresentation()
        apply(.select(index: index))
        placeChanged()
    }

    /// FIX-D S2: the operator's last choice is a slide of the open presentation, so the target is that presentation's playlist
    /// item (none when it came from the library), not a countdown chosen before. Go Live then starts the slide.
    func chooseOpenPresentation() {
        guard let selected = selectedPlaylistItemID, selected != openPlaylistItemID,
              playlistItems.first(where: { $0.id == selected }).map({ item -> Bool in if case .countdown = item.kind { return true } else { return false } }) ?? false
        else { return }
        selectedPlaylistItemID = openPlaylistItemID
    }

    /// Takes the selected slide live. Edits made since the last trigger go out now.
    public func goLive() async {
        await serialized { [self] in
            if let id = selectedPlaylistItemID, let item = playlistItems.first(where: { $0.id == id }), case .countdown = item.kind {
                goLiveOnCountdown(item)
            } else {
                goLive(at: show.selectedIndex)
            }
        }
    }

    public func goLive(at index: Int) {
        transportEpoch &+= 1
        liveCountdown = nil
        chooseOpenPresentation()                 // the slide named here is the target, whatever was selected before
        apply(.trigger(index: index))
        recordLiveSource()
        placeChanged()
    }

    /// Notes which slides and which playlist item the live deck came from (only when something is live).
    func recordLiveSource() {
        // LIB-004c: a Bible passage is live. It has no stored slides, notes or sections; it belongs to the playlist item it came from, if any.
        if let deck = show.liveDeck, let open = openScripture, deck.presentationID == open.deckID {
            liveSlideIDs = []
            liveSlideNotes = []
            liveTitle = open.title
            liveSectionNames = []
            liveItemID = openPlaylistItemID
            return
        }
        guard show.liveDeck != nil, show.liveDeck?.presentationID == openPresentationID else { return }
        liveSlideIDs = slides.map(\.id)
        liveSlideNotes = slides.map(\.notes)
        liveTitle = presentations.first { $0.id == openPresentationID }?.title
        liveSectionNames = slides.map { slide in slide.groupID.flatMap { id in groups.first { $0.id == id }?.name } }
        liveItemID = openPlaylistItemID          // the item the slides belong to (FIX-D S2), never a countdown that was merely selected
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

    /// MEDIA-010: hides the live background on every screen. Nothing else changes and nothing is cancelled: no epoch bump, so
    /// a Next that is waiting still happens. The next Go Live, Next or Previous, or a bin choice, brings a background back.
    public func clearBackground() {
        apply(.clearBackground)
    }

    /// MEDIA-010: a new bin choice brings a cleared background back.
    public func showBackground() {
        apply(.restoreBackground)
    }

    /// UI-001: toggles Blackout. The place and the live deck are kept; a trigger, Next or Previous lifts it.
    public func blackout() {
        transportEpoch &+= 1
        apply(.blackout)
    }

    public func stop() {
        transportEpoch &+= 1
        apply(.stop)
        liveCountdown = nil
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
        // UI-002: headers are skipped; a countdown starts instead of opening slides.
        guard var j = PlaylistStepping.target(kinds: playlistKinds, from: here, direction: direction) else { return false }
        let what = direction > 0 ? "Next" : "Previous"
        // FIX-F item 8: a passage whose translation is missing stops the step the first time; a second step onto it in the same stay
        // skips it (and any further such passage) and says so.
        let firstTarget = playlistItems[j].id
        let skipping = blockedStep == BlockedStep(epoch: transportEpoch, from: current, target: firstTarget, direction: direction)
        var skipped: [String] = []
        while case .scripture(let spec) = playlistItems[j].kind {
            _ = beginPreviewRequest()               // the step is the newest request: an older one still reading must not land after it
            // LIB-004c: a passage item is read from the Bible library; a missing translation stops the step with a message.
            let resolution = await scripture?.resolve(spec) ?? .failed("Scripture is not available in this session.")
            guard epoch == transportEpoch else { return false }
            switch resolution {
            case .ready(let passage):
                blockedStep = nil
                openScripturePassage(passage, itemID: playlistItems[j].id)
                liveCountdown = nil
                apply(.trigger(index: direction > 0 ? 0 : passage.contents.count - 1))
                recordLiveSource()
                placeChanged()
                if !skipped.isEmpty { lastError = Self.skipNote(what, skipped) }
                return true
            case .notInstalled(let text), .failed(let text):
                if skipping {
                    skipped.append("“\(spec.label)”")
                    guard let next = PlaylistStepping.target(kinds: playlistKinds, from: j, direction: direction) else {
                        lastError = "\(what) skipped \(skipped.joined(separator: ", ")), but there is nothing playable after it. \(text)"
                        return false
                    }
                    j = next
                    continue
                }
                blockedStep = BlockedStep(epoch: transportEpoch, from: current, target: playlistItems[j].id, direction: direction)
                lastError = "\(what) stopped: \(text) Press \(what) again to skip it."
                return false
            }
        }
        let item = playlistItems[j]
        if case .countdown = item.kind {
            guard epoch == transportEpoch else { return false }
            blockedStep = nil
            goLiveOnCountdown(item)
            if !skipped.isEmpty { lastError = Self.skipNote(what, skipped) }
            return true
        }
        let count = (try? await store.slides(forPlaylistItem: item.id))?.count ?? 0
        guard epoch == transportEpoch else { return false }
        guard count > 0 else {
            let what = direction > 0 ? "Next" : "Previous"
            lastError = "\(what) stopped: \"\(item.title)\" has no slides to show (its section order may be empty). Choose another song in the playlist and press Go Live, or fix its section order."
            return false
        }
        await openPlaylistItem(item.id)
        guard epoch == transportEpoch, selectedPlaylistItemID == item.id, !slides.isEmpty else { return false }
        liveCountdown = nil
        apply(.trigger(index: direction > 0 ? 0 : slides.count - 1))
        recordLiveSource()
        placeChanged()
        if !skipped.isEmpty { lastError = Self.skipNote(what, skipped) }
        return true
    }

    static func skipNote(_ what: String, _ skipped: [String]) -> String {
        "\(what) skipped \(skipped.joined(separator: ", ")): its translation is not installed."
    }
}
