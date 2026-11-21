// MEDIA-010: which media is on screen, and where a choice goes. A choice in the media bin is a LIVE override; a drop on a
// slide is that slide's own background. Foundation and Domain only.
import Foundation
import Domain

public enum LiveMedia {
    /// What plays on the live screens: the live slide's own background unless a live override from the bin is on, and the
    /// clip over the words. The registry opens a player for each of these.
    public static func effective(override: MediaLayers, slide: SlideContent?, at now: Double) -> MediaLayers {
        guard override.background == nil, let own = slide?.background else { return override }
        var layers = override
        layers.setBackground(own, at: now)
        return layers
    }

    /// What Preview and the thumbnails know of media: only the slide's own background. Never the live override, never a clip,
    /// so a bin choice leaves Preview exactly as it was.
    public static func preview(slide: SlideContent?, at now: Double) -> MediaLayers {
        var layers = MediaLayers()
        if let own = slide?.background { layers.setBackground(own, at: now) }
        return layers
    }
}

/// Dropping a video or picture on a slide thumbnail.
public enum SlideBackgroundDrop {
    /// A video or picture can be a background; a sound file cannot.
    public static func selection(for asset: MediaAsset) -> MediaSelection? {
        asset.kind == .audio ? nil : MediaSelection(asset: asset)
    }

    /// The small mark on a thumbnail whose slide has its own background.
    public static func hasOwnBackground(_ content: SlideContent) -> Bool { content.background != nil }

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
