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
        guard let current = arrangements.first(where: { $0.id == id }) else { return }
        await writeOrder(id: id, name: name, groupIDs: current.groupIDs, doing: "rename the section order")
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
        guard let current = arrangements.first(where: { $0.id == id }) else { return }
        await writeOrder(id: id, name: current.name, groupIDs: SectionOrderEditing.appending(groupID, to: current.groupIDs),
                         doing: "add the section")
    }

    public func removeSection(at index: Int, fromSectionOrder id: UUID) async {
        guard let current = arrangements.first(where: { $0.id == id }), current.groupIDs.indices.contains(index) else { return }
        await writeOrder(id: id, name: current.name, groupIDs: SectionOrderEditing.removing(at: index, from: current.groupIDs),
                         doing: "remove the section")
    }

    /// Moves the entry at `from` so that it ends at index `to`.
    public func moveSection(from: Int, to: Int, inSectionOrder id: UUID) async {
        guard let current = arrangements.first(where: { $0.id == id }), current.groupIDs.indices.contains(from) else { return }
        await writeOrder(id: id, name: current.name, groupIDs: SectionOrderEditing.moving(from: from, to: to, in: current.groupIDs),
                         doing: "move the section")
    }

    private func writeOrder(id: UUID, name: String, groupIDs: [UUID], doing what: String) async {
        await flushDrafts()
        guard await attempt(what, { try await self.store.updateArrangement(id: id, name: name, groupIDs: groupIDs) }) != nil else { return }
        await reloadPlaylistItems()
        await reloadOpen()
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
