// UI-006d: named collections of media-bin items (the design's "Announcement loop" and "Motion backgrounds" rows). A collection is a
// list of references: it never moves, copies or deletes a file. Stored as one JSON text in the library's app state (no schema change).
import Foundation
import Domain

public struct MediaCollection: Sendable, Equatable, Codable, Identifiable {
    public var id: UUID
    public var name: String
    /// In the order they were added; the bin shows them in bin order.
    public var assetIDs: [UUID]

    public init(id: UUID = UUID(), name: String, assetIDs: [UUID] = []) {
        self.id = id
        self.name = name
        self.assetIDs = assetIDs
    }
}

public struct MediaCollections: Sendable, Equatable, Codable {
    public private(set) var items: [MediaCollection] = []

    public init() {}

    public enum NameProblem: Error, Equatable, LocalizedError {
        case empty, taken
        public var errorDescription: String? {
            switch self {
            case .empty: "A collection needs a name."
            case .taken: "Another collection already has that name."
            }
        }
    }

    public static let storageKey = "media.collections"

    public func collection(_ id: UUID) -> MediaCollection? { items.first { $0.id == id } }
    public func containing(_ assetID: UUID) -> [MediaCollection] { items.filter { $0.assetIDs.contains(assetID) } }

    private func checked(_ raw: String, except id: UUID?) throws -> String {
        let name = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty else { throw NameProblem.empty }
        if items.contains(where: { $0.id != id && $0.name.caseInsensitiveCompare(name) == .orderedSame }) { throw NameProblem.taken }
        return name
    }

    @discardableResult
    public mutating func create(name: String, id: UUID = UUID()) throws -> UUID {
        items.append(MediaCollection(id: id, name: try checked(name, except: nil)))
        return id
    }

    public mutating func rename(_ id: UUID, to name: String) throws {
        guard let index = items.firstIndex(where: { $0.id == id }) else { return }
        items[index].name = try checked(name, except: id)
    }

    public mutating func delete(_ id: UUID) { items.removeAll { $0.id == id } }

    /// Returns how many were new to the collection.
    @discardableResult
    public mutating func add(_ assetIDs: [UUID], to id: UUID) -> Int {
        guard let index = items.firstIndex(where: { $0.id == id }) else { return 0 }
        var added = 0
        for asset in assetIDs where !items[index].assetIDs.contains(asset) { items[index].assetIDs.append(asset); added += 1 }
        return added
    }

    public mutating func remove(_ assetIDs: [UUID], from id: UUID) {
        guard let index = items.firstIndex(where: { $0.id == id }) else { return }
        let gone = Set(assetIDs)
        items[index].assetIDs.removeAll { gone.contains($0) }
    }

    /// Forgets items the bin no longer has. True when something changed.
    @discardableResult
    public mutating func prune(keeping valid: Set<UUID>) -> Bool {
        var changed = false
        for index in items.indices {
            let before = items[index].assetIDs.count
            items[index].assetIDs.removeAll { !valid.contains($0) }
            if items[index].assetIDs.count != before { changed = true }
        }
        return changed
    }

    /// The collection's items in the bin's order.
    public func assets(in id: UUID, from bin: [MediaAsset]) -> [MediaAsset] {
        guard let members = collection(id).map({ Set($0.assetIDs) }) else { return [] }
        return bin.filter { members.contains($0.id) }
    }

    public func encoded() -> String? {
        (try? JSONEncoder().encode(self)).flatMap { String(data: $0, encoding: .utf8) }
    }

    /// Stored text back to a value. Nothing, or text that cannot be read, gives no collections (the bin itself is untouched).
    public static func decoded(_ text: String?) -> MediaCollections {
        guard let data = text?.data(using: .utf8), let value = try? JSONDecoder().decode(MediaCollections.self, from: data) else { return MediaCollections() }
        return value
    }
}
