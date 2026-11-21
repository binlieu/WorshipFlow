// MEDIA-010: a hot folder, a folder the media bin follows. Foundation only.
import Foundation

public struct HotFolder: Sendable, Equatable, Hashable, Identifiable {
    public let id: UUID
    public var name: String
    /// Absolute path as last seen.
    public var path: String
    /// Security-scoped bookmark, so access survives a relaunch.
    public var bookmark: Data?

    public init(id: UUID = UUID(), name: String, path: String, bookmark: Data? = nil) {
        self.id = id
        self.name = name
        self.path = path
        self.bookmark = bookmark
    }
}
