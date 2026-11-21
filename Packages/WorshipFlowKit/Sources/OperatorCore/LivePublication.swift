// FIX-B R15: what the audience, stage and broadcast screens can see of the show. Preview edits (typing, moving the
// selection, loading a deck) are not part of it, so they do not republish the live scenes. Foundation only.
import Foundation
import Domain

/// Everything of the show that a scene composer reads: the live deck and place, whether the words are cleared, and the
/// live slide's speaker notes (the stage shows them).
public struct LiveOutputKey: Equatable, Sendable {
    var liveDeck: ShowDeck?
    var liveIndex: Int?
    var isCleared: Bool
    var isBlackedOut: Bool
    /// MEDIA-010: Clear background is on.
    var isBackgroundCleared: Bool
    var notes: String?

    public init(state: ShowState, notes: String?) {
        liveDeck = state.liveDeck
        liveIndex = state.liveIndex
        isCleared = state.isCleared
        isBlackedOut = state.isBlackedOut
        isBackgroundCleared = state.isBackgroundCleared
        self.notes = notes
    }
}

/// Remembers the last key that was published and says whether a new one differs from it.
public struct LivePublicationGate: Sendable {
    private var last: LiveOutputKey?

    public init() {}

    /// True when the screens must be republished for `key`; records it as published.
    public mutating func shouldPublish(_ key: LiveOutputKey) -> Bool {
        guard key != last else { return false }
        last = key
        return true
    }
}
