// CUE-002b (item 1): the show's transport as the cue wiring sees it. The steps that need no waiting are done at once so a
// macro's batch stays synchronous; a step that crosses into another playlist item is left to the full `next()`.
import Foundation
import Domain
import CueEngine

extension WorkspaceModel: CueTransportPort {
    public var isBlackedOut: Bool { showParts.isBlackedOut }

    public func triggerSlide(_ index: Int) { goLive(at: index) }

    public func nextIfInDeck() -> Bool {
        guard let live = showParts.liveDeck, let i = showParts.liveIndex else {
            apply(.next)                                  // nothing live yet: the first slide of the preview goes live
            recordLiveSource()
            placeChanged()
            return true
        }
        guard i + 1 < live.slides.count else { return false }
        apply(.next)
        placeChanged()
        return true
    }

    public func previousIfInDeck() -> Bool {
        if !showParts.isStopped, showParts.liveIndex == 0 { return false }
        apply(.previous)
        placeChanged()
        return true
    }

    /// The slide with this zero-based number of the open song, live. The song on screen must be the open one.
    public func goToSlide(_ index: Int) throws {
        guard !slides.isEmpty else { throw CueTargetError("There is no open song with slides to go to.") }
        guard slides.indices.contains(index) else { throw CueTargetError("There is no slide \(index + 1): the open song has \(slides.count).") }
        if let live = showParts.liveDeck, live.presentationID != openPresentationID {
            throw CueTargetError("The song on the screens is not the open one, so slide \(index + 1) was not chosen. Open the live song, or press Go Live.")
        }
        goLive(at: index)
    }

    public func liveSlideID(for event: SlideLiveEvent) -> UUID? {
        guard showParts.liveDeckID == event.presentationID, showParts.liveIndex == event.index,
              liveSlideIDs.indices.contains(event.index) else { return nil }
        return liveSlideIDs[event.index]
    }
}
