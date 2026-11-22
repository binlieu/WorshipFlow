// OUT-004 / SLIDE-005 / PRES-07: editing the open presentation and the one live edit.
import Foundation
import Domain
import Persistence

extension WorkspaceModel {
    /// Changes a slide's text or notes at once in the editor and in preview, and schedules the save (within two
    /// seconds, never later than five). The live output is not touched.
    public func editSlide(id: UUID, content: SlideContent, notes: String? = nil) {
        guard let i = slides.firstIndex(where: { $0.id == id }) else { return }
        var changed = false
        for j in slides.indices where slides[j].id == id {      // an arrangement can repeat a slide
            if slides[j].content != content { slides[j].content = content; changed = true }
            if let notes, slides[j].notes != notes { slides[j].notes = notes; changed = true }
        }
        guard changed else { return }
        pendingDrafts[id] = slides[i]
        refreshPreview()
        scheduleDraftSave()
    }

    /// Like `editSlide` but written before it returns.
    public func updateSlide(at index: Int, content: SlideContent, notes: String? = nil) async {
        guard slides.indices.contains(index) else { return }
        editSlide(id: slides[index].id, content: content, notes: notes)
        await flushDrafts()
    }

    /// The one deliberate way to change what is on screen (PRES-07). It also saves the text.
    public func quickEditLiveSlide(_ content: SlideContent) async {
        guard let index = showParts.liveIndex, !showParts.isStopped else {
            lastError = "Nothing is live, so there is nothing to quick-edit. Go live first."
            return
        }
        apply(.quickEdit(index: index, content: content))
        guard liveSlideIDs.indices.contains(index), showParts.liveDeckID == openPresentationID else { return }
        let id = liveSlideIDs[index]
        guard let stored = slides.first(where: { $0.id == id }) else { return }
        // Only the words are saved: objects edited in preview since going live are not replaced by the live ones.
        var saved = stored.content
        saved.primary = content.primary
        saved.secondary = content.secondary
        editSlide(id: id, content: saved)
        await flushDrafts()
    }

    // MARK: Structure of the open presentation

    private func requireNaturalOrder(_ what: String) -> Bool {
        guard openPlaylistItemID.flatMap({ id in playlistItems.first { $0.id == id }?.arrangementID }) == nil else {
            lastError = "Could not \(what): this item plays a custom section order. Choose \"Natural order\" for the item, make the change, then choose the order again."
            return false
        }
        return true
    }

    public func addSlide(_ content: SlideContent) async {
        guard let id = openPresentationID, requireNaturalOrder("add a slide") else { return }
        await flushDrafts()
        guard await attempt("add the slide", { try await self.store.appendSlide(to: id, content: content) }) != nil else { return }
        await reloadOpen()
    }

    /// Moves slide `from` so that it ends at index `to`. FIX-M: the visible order changes at once (the rows keep their identity); the library is written
    /// afterwards, one write per drop and in the order the drops arrived. A failed write puts the previous order back with a message, and drops queued
    /// behind it are put back too and never written. Returns when this drop's write has ended; the screen did not wait for it.
    public func moveSlide(from: Int, to: Int) async {
        guard slides.indices.contains(from), requireNaturalOrder("move the slide"), let presentationID = openPresentationID else { return }
        let target = max(0, min(to, slides.count - 1))
        guard target != from else { return }
        let id = slides[from].id
        slideMoves.begin(current: slides.map(\.id))
        let began = slideMoves.epoch
        slides = Self.renumbered(OrderMove.moved(slides, from: from, to: target))
        refreshAfterReorder()
        let previous = slideMoveTail
        let write = Task { @MainActor [weak self] in
            await previous?.value
            guard let self else { return }
            if self.slideMoves.isStale(began) { self.slideMoves.skipped(); return }
            do {
                try await self.slideMoveWriter(id, target)
                self.slideMoves.succeeded(id: id, to: target)
                if self.slideMoves.isIdle, self.openPresentationID == presentationID, self.slides.map(\.id) != self.slideMoves.confirmed { await self.reloadOpen() }
            } catch {
                let order = self.slideMoves.failed()
                self.lastError = Self.message(for: error, doing: "move the slide")
                if self.openPresentationID == presentationID {
                    self.slides = Self.renumbered(OrderMove.restoring(self.slides, toOrder: order))
                    self.refreshAfterReorder()
                }
            }
        }
        slideMoveTail = write
        await write.value
    }

    static func renumbered(_ slides: [Slide]) -> [Slide] {
        var out = slides
        for i in out.indices where out[i].sortOrder != i { out[i].sortOrder = i }
        return out
    }

    /// The preview deck follows the new order, the selection stays on its index (as after a reload). Live is not touched. The saved place
    /// (presentation and slide index) is the same, so it is not written again: a drop is one write.
    private func refreshAfterReorder() {
        let keep = min(showParts.selectedIndex, max(slides.count - 1, 0))
        apply(.restore(deck: previewDeck(), selectedIndex: keep))
    }

    public func deleteSlide(at index: Int) async {
        guard slides.indices.contains(index), requireNaturalOrder("delete the slide") else { return }
        await flushDrafts()
        let id = slides[index].id
        guard await attempt("delete the slide", { try await self.store.deleteSlide(id: id) }) != nil else { return }
        await reloadOpen()
    }
}
