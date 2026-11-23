// MEDIA-010: which media is on screen, and where a choice goes. A choice in the media bin is a LIVE override; a drop on a
// slide is that slide's own background. Foundation and Domain only.
import Foundation
import Domain

public enum LiveMedia {
    /// What plays on the live screens: the live slide's own background unless a live override from the bin is on, and the
    /// clip over the words. The registry opens a player for each of these.
    /// UI-007d: `resolve` adds what the bin knows about the item (its mark in and mark out) to a slide's own background when it is played.
    public static func effective(override: MediaLayers, slide: SlideContent?, at now: Double,
                                 resolve: (MediaSelection) -> MediaSelection = { $0 }) -> MediaLayers {
        guard override.background == nil, let own = slide?.background else { return override }
        var layers = override
        layers.setBackground(resolve(own), at: now)
        return layers
    }

    /// FIX-G item 1: what the media registry plays. The same as `effective`, except that a background hidden by Clear
    /// background or by Stop is not in the set at all, so no player runs for it and nothing of it is heard; Go Live, Next and
    /// Previous bring it (and its sound) back. Blackout keeps the player running (its sound is silenced by the model's
    /// Blackout flag, as before). The clip over the words is not a background and is left as it is.
    public static func playing(override: MediaLayers, state: ShowState, at now: Double,
                               resolve: (MediaSelection) -> MediaSelection = { $0 }) -> MediaLayers {
        if state.isStopped || state.isBackgroundCleared {
            var layers = override
            layers.setBackground(nil, at: now)
            return layers
        }
        return effective(override: override, slide: state.liveSlideAtPlace, at: now, resolve: resolve)
    }

    /// What Preview and the thumbnails know of media: only the slide's own background. Never the live override, never a clip,
    /// so a bin choice leaves Preview exactly as it was.
    public static func preview(slide: SlideContent?, at now: Double) -> MediaLayers {
        var layers = MediaLayers()
        if let own = slide?.background { layers.setBackground(own, at: now) }
        return layers
    }
}

/// FIX-I item 6: the slide thumbnail's context menu for backgrounds (Show grid and list, Edit film strip).
public enum SlideBackgroundMenu {
    public static let setTitle = "Set background…"
    public static let clearTitle = "Clear this slide's background"
    /// Said in the tooltip and the checklist: an edit never reaches the screens by itself.
    public static let liveNote = "Changes the slide, not what is on the screens now. It shows live the next time this slide is taken live."

    /// "Clear this slide's background" is offered whenever the slide has its own.
    public static func clearIsOffered(for content: SlideContent) -> Bool { content.background != nil }

    /// What "Set background…" lists: the bin's pictures and videos in bin order, never a sound.
    public static func choices(from assets: [MediaAsset]) -> [MediaAsset] { assets.filter { $0.kind != .audio } }
}

/// Dropping a video or picture on a slide thumbnail.
public enum SlideBackgroundDrop {
    /// A video or picture can be a background; a sound file cannot.
    public static func selection(for asset: MediaAsset) -> MediaSelection? {
        asset.kind == .audio ? nil : MediaSelection(asset: asset)
    }

    /// The small mark on a thumbnail whose slide has its own background.
    public static func hasOwnBackground(_ content: SlideContent) -> Bool { content.background != nil }

    /// FIX-G: the slide has its own background, but the bin item it names is gone (removed, or never imported). The slide keeps its
    /// choice; the thumbnail says it is missing.
    public static func isMissing(_ content: SlideContent, available: Set<UUID>) -> Bool {
        guard let own = content.background else { return false }
        return !available.contains(own.assetID)
    }

    private static let prefix = "wfmedia:"
    /// What a bin tile puts on the drag. A slide being reordered drags just its index, so the two are never confused.
    public static func dragText(for id: UUID) -> String { prefix + id.uuidString }
    public static func mediaID(fromDragText text: String) -> UUID? {
        guard text.hasPrefix(prefix) else { return nil }
        return UUID(uuidString: String(text.dropFirst(prefix.count)))
    }
}

public struct MediaBinTapResult: Equatable, Sendable {
    public var select: UUID
    /// Set for a double click: what goes live.
    public var sendLive: MediaDockAction?
}

/// A single click on a bin tile selects it (and shows it in the sidebar player); a double click also sends it live.
public enum MediaBinInteraction {
    public static func tap(count: Int, asset: MediaAsset, layer: MediaLayerChoice) -> MediaBinTapResult {
        MediaBinTapResult(select: asset.id, sendLive: count >= 2 ? MediaDock.action(for: asset, layer: layer) : nil)
    }
}
