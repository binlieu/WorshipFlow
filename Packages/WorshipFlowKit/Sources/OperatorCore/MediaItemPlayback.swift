// UI-005b item 4: media-file items and announcements loops in the playlist. Going live on one tells the app to play the file
// (to the foreground over the screens, or as audio) or to start the loop; stepping on, taking a song live, or Stop ends it. Nothing
// here ever ends or advances by itself: only the operator's Next, Previous, Go Live, Clear all or Stop do.
import Foundation
import Domain

/// What the model asks the app to do with a media-file item or a loop.
public enum MediaItemCommand: Equatable, Sendable {
    /// The item was selected: show it in the bin player. Nothing goes to the screens.
    case preview(MediaItemSpec)
    case play(MediaItemSpec)
    case stop(MediaItemSpec)
    case startLoop(AnnouncementsSpec)
    case stopLoop(AnnouncementsSpec)
}

extension WorkspaceModel {
    /// Takes the selected media item or loop live. A video, picture or loop is shown over the screens; with nothing live the screens
    /// start on an empty slide so there is a show to play over. A sound plays and leaves the slide alone.
    func goLiveOnMediaItem(_ item: PlaylistItem) {
        let visual: Bool
        switch item.kind {
        case .media(let spec): visual = spec.kind != .audio
        case .announcements: visual = true
        default: return
        }
        // FIX-H item 6: a file that cannot play changes nothing: the audience keeps what it had, and the operator is told which file.
        if let problem = mediaItemPreflight?(item.kind) { lastError = problem; return }
        endLiveMediaItem()
        transportEpoch &+= 1
        liveCountdown = nil
        let previousLiveItemID = liveItemID
        selectedPlaylistItemID = item.id
        var startedBlank = false
        if visual, show.isStopped || show.liveDeck == nil {
            startedBlank = true
            let keptSelection = show.selectedIndex
            apply(.load(ShowDeck(presentationID: item.id, slides: [SlideContent(primary: "")])))
            apply(.trigger(index: 0))
            apply(.restore(deck: previewDeck(), selectedIndex: keptSelection))     // the preview goes back to what the operator had
            liveSlideIDs = []
            liveSlideNotes = [""]
            liveTitle = item.title
            liveSectionNames = [nil]
        } else {
            apply(.liftHolds)             // FIX-H item 2: taking a file live lifts Blackout, Clear and a hidden background, as a slide does
        }
        liveItemID = item.id
        liveMediaItemID = item.id
        liveMediaCopy = item
        liveMediaEnded = false
        let outcome: MediaItemOutcome
        switch item.kind {
        case .media(let spec): outcome = perform(.play(spec))
        case .announcements(let spec): outcome = perform(.startLoop(spec))
        default: outcome = .ok
        }
        if case .failed(let text) = outcome {          // it did not start: nothing is marked live
            liveMediaItemID = nil
            liveMediaCopy = nil
            liveItemID = previousLiveItemID
            if startedBlank {
                apply(.stop)
                liveSlideIDs = []; liveSlideNotes = []; liveTitle = nil; liveSectionNames = []
            }
            lastError = text
        }
        placeChanged()
    }

    /// Tells the app's player (and the recorder that tests attach) what to do, and says whether it started.
    func perform(_ command: MediaItemCommand) -> MediaItemOutcome {
        onMediaItem?(command)
        return mediaItemHandler?(command) ?? .ok
    }

    /// FIX-H item 11: the player says the loop ended by itself (the foreground was cleared, or the operator played something else there).
    /// The loop is no longer marked live; its place in the playlist stays, so Next and Previous go on from it.
    public func mediaItemEnded() {
        guard liveMediaItemID != nil, !liveMediaEnded else { return }
        liveMediaEnded = true
    }

    /// What the live chip says in Edit, Stage and Screens: the live file or loop by its title, otherwise the live slide's words.
    public var liveChipLine: String? {
        if liveMediaMarkID != nil, let title = liveMediaCopy?.title { return title }
        return show.liveSlide.map(LiveSummary.line(for:))
    }

    /// Ends the media item that is live, if one is: the app stops its file or loop. The slides are not touched.
    func endLiveMediaItem() {
        guard liveMediaItemID != nil else { return }
        let item = liveMediaCopy                 // FIX-H item 3: from the copy kept at Go Live, not a lookup in a list that may have changed
        liveMediaItemID = nil
        liveMediaCopy = nil
        liveMediaEnded = false
        guard let item else { return }
        switch item.kind {
        case .media(let spec): _ = perform(.stop(spec))
        case .announcements(let spec): _ = perform(.stopLoop(spec))
        default: break
        }
    }
}
