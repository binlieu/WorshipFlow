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
        guard let index = show.liveIndex, show.liveDeck != nil else {
            lastError = "Nothing is live, so there is nothing to quick-edit. Go live first."
            return
        }
        apply(.quickEdit(index: index, content: content))
        guard liveSlideIDs.indices.contains(index), show.liveDeck?.presentationID == openPresentationID else { return }
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

    /// Moves slide `from` so that it ends at index `to`.
    public func moveSlide(from: Int, to: Int) async {
        guard slides.indices.contains(from), requireNaturalOrder("move the slide") else { return }
        await flushDrafts()
        let id = slides[from].id
        let target = max(0, min(to, slides.count - 1))
        guard await attempt("move the slide", { try await self.store.moveSlide(id: id, to: target) }) != nil else { return }
        await reloadOpen()
    }

    public func deleteSlide(at index: Int) async {
        guard slides.indices.contains(index), requireNaturalOrder("delete the slide") else { return }
        await flushDrafts()
        let id = slides[index].id
        guard await attempt("delete the slide", { try await self.store.deleteSlide(id: id) }) != nil else { return }
        await reloadOpen()
    }
}
