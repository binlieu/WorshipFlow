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
        endLiveMediaItem()
        transportEpoch &+= 1
        liveCountdown = nil
        let visual: Bool
        switch item.kind {
        case .media(let spec): visual = spec.kind != .audio
        case .announcements: visual = true
        default: return
        }
        selectedPlaylistItemID = item.id
        if visual, show.isStopped || show.liveDeck == nil {
            let keptSelection = show.selectedIndex
            apply(.load(ShowDeck(presentationID: item.id, slides: [SlideContent(primary: "")])))
            apply(.trigger(index: 0))
            apply(.restore(deck: previewDeck(), selectedIndex: keptSelection))     // the preview goes back to what the operator had
            liveSlideIDs = []
            liveSlideNotes = [""]
            liveTitle = item.title
            liveSectionNames = [nil]
        }
        liveItemID = item.id
        liveMediaItemID = item.id
        switch item.kind {
        case .media(let spec): onMediaItem?(.play(spec))
        case .announcements(let spec): onMediaItem?(.startLoop(spec))
        default: break
        }
        placeChanged()
    }

    /// Ends the media item that is live, if one is: the app stops its file or loop. The slides are not touched.
    func endLiveMediaItem() {
        guard let id = liveMediaItemID else { return }
        liveMediaItemID = nil
        guard let item = playlistItems.first(where: { $0.id == id }) else { return }
        switch item.kind {
        case .media(let spec): onMediaItem?(.stop(spec))
        case .announcements(let spec): onMediaItem?(.stopLoop(spec))
        default: break
        }
    }
}
