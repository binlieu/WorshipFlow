// FIX-I item 5: what a slide thumbnail draws behind the words, and the cache of still frames it draws a video or picture background from.
// A thumbnail shows the background the slide will have when it goes live with no bin override: its own, else the presentation's or the
// theme's. A video is one still frame (never a player), taken off the main thread and cached by file and modification date. Foundation and Domain.
import Foundation
import Domain

public enum ThumbnailBackground: Equatable, Sendable {
    /// The slide's own picture or video.
    case slideOwn(MediaSelection)
    /// The slide's own background is not in the bin any more: the thumbnail shows the missing-media state and the theme's background.
    case slideOwnMissing(MediaSelection)
    /// No own background: the theme's (the presentation's theme when it has one, else the default).
    case theme(ThemeBackground, fromPresentation: Bool)

    /// - Parameter available: the ids of the bin items that exist now; nil while the bin has not loaded (the background is taken as present).
    public static func resolve(slide: SlideContent, theme: Theme, themeIsThePresentations: Bool, available: Set<UUID>?) -> ThumbnailBackground {
        guard let own = slide.background else { return .theme(theme.background, fromPresentation: themeIsThePresentations) }
        if let available, !available.contains(own.assetID) { return .slideOwnMissing(own) }
        return .slideOwn(own)
    }

    /// The picture or video to take one still frame of, if the thumbnail draws one.
    public var stillToLoad: MediaSelection? {
        if case .slideOwn(let own) = self { return own }
        return nil
    }

    /// A small film mark on a thumbnail whose background is a video, so a still is not mistaken for a picture.
    public var showsFilmMark: Bool { stillToLoad?.kind == .video }

    public var isMissing: Bool {
        if case .slideOwnMissing = self { return true }
        return false
    }
}

/// A file as it was when a still was taken: the same path with another modification date or size is another file.
public struct StillCacheKey: Hashable, Sendable {
    public var path: String
    public var modified: Date?
    public var size: Int64?
    public init(path: String, modified: Date?, size: Int64?) {
        self.path = path
        self.modified = modified
        self.size = size
    }
}

/// A bounded cache of stills, least recently used out first.
public struct StillCache<Value> {
    public let limit: Int
    private var values: [StillCacheKey: Value] = [:]
    private var order: [StillCacheKey] = []          // oldest use first

    public init(limit: Int) { self.limit = max(1, limit) }

    public var count: Int { values.count }

    public mutating func value(for key: StillCacheKey) -> Value? {
        guard let hit = values[key] else { return nil }
        touch(key)
        return hit
    }

    public mutating func insert(_ value: Value, for key: StillCacheKey) {
        values[key] = value
        touch(key)
        while order.count > limit { values[order.removeFirst()] = nil }
    }

    private mutating func touch(_ key: StillCacheKey) {
        order.removeAll { $0 == key }
        order.append(key)
    }
}
