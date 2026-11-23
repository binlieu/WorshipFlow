// APP-001 / KI-023 / SLIDE-003: creating, renaming, deleting and editing the section orders of the open song,
// and the choices for a playlist item. Edits are written at once; the open song and the playlist are re-read.
import Foundation
import Domain
import Persistence

extension WorkspaceModel {
    /// A new section order for the open song, starting as every section once in the song's own order (an empty
    /// order would play nothing). Blank `name` becomes "Order N".
    @discardableResult
    public func createSectionOrder(name: String? = nil) async -> Arrangement? {
        guard openPresentationID != nil else { return nil }
        let wanted = name?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let chosen = wanted.isEmpty ? SectionOrderEditing.newName(existing: arrangements.map(\.name)) : wanted
        return await createArrangement(name: chosen, groupIDs: SectionOrderEditing.naturalOrder(of: groups))
    }

    public func renameSectionOrder(id: UUID, to name: String) async {
        await editSectionOrder(id: id, doing: "rename the section order", name: name) { $0 }
    }

    /// Deleting an order sends the playlist items that used it back to natural order.
    public func deleteSectionOrder(id: UUID) async {
        guard arrangements.contains(where: { $0.id == id }) else { return }
        await flushDrafts()
        guard await attempt("delete the section order", { try await self.store.deleteArrangement(id: id) }) != nil else { return }
        await reloadPlaylistItems()
        await reloadOpen()
    }

    public func addSection(_ groupID: UUID, toSectionOrder id: UUID) async {
        await editSectionOrder(id: id, doing: "add the section") { SectionOrderEditing.appending(groupID, to: $0) }
    }

    /// FIX-V item 3: the entries of an order, each with the identity the editor passes back (the section and which occurrence of it).
    public func sectionEntries(of order: Arrangement) -> [SectionEntry] { SectionOrderEditing.entries(of: order.groupIDs) }

    /// Removes one entry of the order. The entry is found again, in the order as the library holds it, after every earlier edit has finished and
    /// the draft flush has been awaited; if it is gone (another quick edit took it, or the order was deleted) nothing changes and the operator
    /// is told. FIX-V item 3 (REVIEW-4 M3).
    public func removeSection(_ entry: SectionEntry, fromSectionOrder id: UUID) async {
        await editSectionOrder(id: id, doing: "remove the section") { order in
            SectionOrderEditing.index(of: entry, in: order).map { SectionOrderEditing.removing(at: $0, from: order) }
        }
    }

    /// Moves an entry earlier (negative) or later (positive) by `delta` places, from where it is now.
    public func moveSection(_ entry: SectionEntry, by delta: Int, inSectionOrder id: UUID) async {
        await editSectionOrder(id: id, doing: "move the section") { order in
            guard let from = SectionOrderEditing.index(of: entry, in: order) else { return nil }
            let to = max(0, min(from + delta, order.count - 1))
            return SectionOrderEditing.moving(from: from, to: to, in: order)
        }
    }

    /// Drag and drop: places an entry before another entry (nil: at the end). Both are found again by identity.
    public func moveSection(_ entry: SectionEntry, before target: SectionEntry?, inSectionOrder id: UUID) async {
        await editSectionOrder(id: id, doing: "move the section") { order in
            guard let from = SectionOrderEditing.index(of: entry, in: order) else { return nil }
            var offset = order.count
            if let target {
                guard let at = SectionOrderEditing.index(of: target, in: order) else { return nil }
                offset = at
            }
            return SectionOrderEditing.moving(from: from, toOffset: offset, in: order)
        }
    }

    /// By position, as the first version had it: the position is turned into the entry that is there now, at the call, and the edit then runs by
    /// identity. A position that does not exist changes nothing.
    public func removeSection(at index: Int, fromSectionOrder id: UUID) async {
        guard let current = arrangements.first(where: { $0.id == id }), current.groupIDs.indices.contains(index) else { return }
        await removeSection(sectionEntries(of: current)[index], fromSectionOrder: id)
    }

    /// Moves the entry at `from` so that it ends at index `to`.
    public func moveSection(from: Int, to: Int, inSectionOrder id: UUID) async {
        guard let current = arrangements.first(where: { $0.id == id }), current.groupIDs.indices.contains(from) else { return }
        await moveSection(sectionEntries(of: current)[from], by: to - from, inSectionOrder: id)
    }

    static let sectionGone = "That section is no longer in this order, so nothing was changed."

    /// One edit of a section order, run after every earlier edit has finished. The order is read from the library after the draft flush (the
    /// copy the view drew may be older), `change` gets its entries and returns the new ones, or nil when what the edit names is gone.
    private func editSectionOrder(id: UUID, doing what: String, name: String? = nil,
                                  _ change: @escaping @MainActor ([UUID]) -> [UUID]?) async {
        let presentationID = openPresentationID
        let previous = sectionEditTail
        let task = Task { @MainActor in
            await previous?.value
            guard let presentationID else { return }
            await self.flushDrafts()
            guard let stored = await self.attempt("read the section order", { try await self.store.arrangements(of: presentationID) }) else { return }
            guard let fresh = stored.first(where: { $0.id == id }) else { self.lastError = "That section order is no longer there, so nothing was changed."; return }
            guard let groupIDs = change(fresh.groupIDs) else { self.lastError = Self.sectionGone; return }
            let newName = name ?? fresh.name
            guard groupIDs != fresh.groupIDs || newName != fresh.name else { return }
            guard await self.attempt(what, { try await self.store.updateArrangement(id: id, name: newName, groupIDs: groupIDs) }) != nil else { return }
            await self.reloadPlaylistItems()
            await self.reloadOpen()
        }
        sectionEditTail = task
        await task.value
    }

    /// The section orders a playlist item's song has, for the item's picker (the item need not be open).
    public func sectionOrderChoices(forPlaylistItem itemID: UUID) async -> [Arrangement] {
        guard let item = playlistItems.first(where: { $0.id == itemID }) else { return [] }
        if item.presentationID == openPresentationID { return arrangements }
        return await attempt("read the section orders") { try await self.store.arrangements(of: item.presentationID) } ?? []
    }

    /// The name of the section order a playlist item plays, or nil for natural order.
    public func sectionOrderName(forPlaylistItem itemID: UUID) -> String? {
        guard let id = playlistItems.first(where: { $0.id == itemID })?.arrangementID else { return nil }
        return arrangements.first { $0.id == id }?.name
    }
}
