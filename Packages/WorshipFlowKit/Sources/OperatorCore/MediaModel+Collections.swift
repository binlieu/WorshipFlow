// UI-006d: the model's side of named collections. Every change is stored (app state, key `media.collections`) through the model's retrying
// write chain, like the other bin settings. Nothing here touches a file or a bin item.
import Foundation
import Domain

extension MediaModel {
    func loadCollections() async {
        let text = try? await store.state(for: MediaCollections.storageKey)
        collections = MediaCollections.decoded(text)
        // FIX-V item 6 (L3): stored text that cannot be read is kept under its own key before a later change replaces it.
        if let text, !text.isEmpty, !MediaCollections.isReadable(text) {
            let key = MediaCollections.storageKey + ".unreadable"
            persist(key: "collections.unreadable", "keep the unreadable collections") { [store] in try await store.setState(text, for: key) }
            lastError = "The saved collections could not be read, so the bin starts with none. The damaged text was kept."
        }
        if collections.prune(keeping: Set(assets.map(\.id))) { persistCollections() }
    }

    /// FIX-V item 6 (L2): only bin items can be in a collection (the bin's own change prunes by the bin). A hot-folder item is refused, with
    /// the reason, instead of being accepted and dropped at the next bin change. Returns the ids that were accepted.
    private func binIDs(_ ids: [UUID]) -> [UUID] {
        let binSet = Set(assets.map(\.id))
        let accepted = ids.filter { binSet.contains($0) }
        if accepted.count != ids.count, ids.contains(where: { asset($0) != nil && !binSet.contains($0) }) {
            lastError = "Items from a hot folder cannot be put in a collection: they are not in the bin. Add the file to the bin first."
        }
        return accepted
    }

    /// Called whenever the bin's list changed: items that are gone leave every collection, and the open collection may be gone too.
    func binChanged() {
        if collections.prune(keeping: Set(assets.map(\.id))) { persistCollections() }
        scheduleOfflineCheck()
    }

    func persistCollections() {
        let text = collections.encoded()
        persist(key: "collections", "remember the collections") { [store] in try await store.setState(text, for: MediaCollections.storageKey) }
    }

    /// Makes a collection and puts `adding` in it. Nil, with `lastError` saying why, when the name is empty or taken.
    @discardableResult
    public func createCollection(_ name: String, adding ids: [UUID] = []) -> UUID? {
        do {
            let id = try collections.create(name: name)
            collections.add(binIDs(ids), to: id)
            persistCollections()
            return id
        } catch {
            lastError = error.localizedDescription
            return nil
        }
    }

    @discardableResult
    public func renameCollection(_ id: UUID, to name: String) -> Bool {
        do {
            try collections.rename(id, to: name)
            persistCollections()
            return true
        } catch {
            lastError = error.localizedDescription
            return false
        }
    }

    /// Deletes the collection only. Its items stay in the bin.
    public func deleteCollection(_ id: UUID) {
        collections.delete(id)
        if collectionFilter == id { collectionFilter = nil }
        persistCollections()
    }

    public func addToCollection(_ ids: [UUID], collection id: UUID) {
        guard collections.add(binIDs(ids), to: id) > 0 else { return }
        persistCollections()
    }

    public func removeFromCollection(_ ids: [UUID], collection id: UUID) {
        collections.remove(ids, from: id)
        persistCollections()
    }
}
