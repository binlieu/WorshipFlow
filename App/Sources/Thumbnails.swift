// OUT-004: slide thumbnails and per-screen live previews. Both are drawn by the same `Compositor` the outputs use,
// from the same scene descriptions, at reduced size on a background queue. There is no second drawing path.
import SwiftUI
import AppKit
import Domain
import MediaEngine
import OutputEngine
import RenderEngine
import OperatorCore
import SDIEngine

/// An immutable bitmap handed from the render queue to the main actor.
// @unchecked Sendable: a CGImage is immutable once created and is never mutated here.
struct PreviewImage: @unchecked Sendable {
    let image: CGImage
}

/// Which picture of a keyed screen to draw: what the keyer produces, or one of the two signals sent to the card (UI-002).
enum PreviewChannel: Hashable, Sendable { case composite, fill, key }

/// UI-004: hands out an increasing number per name, so the render queue can tell the newest request from an older one.
private final class FollowTickets: @unchecked Sendable {
    private let lock = NSLock()
    private var newest: [UUID: Int] = [:]
    func take(_ name: UUID) -> Int {
        lock.lock(); defer { lock.unlock() }
        let next = (newest[name] ?? 0) + 1
        newest[name] = next
        return next
    }
    func isNewest(_ ticket: Int, for name: UUID) -> Bool {
        lock.lock(); defer { lock.unlock() }
        return newest[name] == ticket
    }
}

private struct RenderKey: Hashable {
    let scene: SceneDescription
    let width: Int
    let height: Int
    var channel: PreviewChannel = .composite
    var straight = false
    /// FIX-I item 5: the still a thumbnail's background was drawn from (file, modification date, size), so a changed file is drawn again.
    var variant: StillCacheKey?
}

/// Owns one `Compositor`, used only on its own serial queue (the compositor is not thread-safe).
// @unchecked Sendable: `compositor`, `cache`, `order` and `failure` are touched only from `queue`.
final class PreviewRenderer: @unchecked Sendable {
    static let shared = PreviewRenderer()

    private let queue = DispatchQueue(label: "org.worshipflow.preview", qos: .utility)
    private var compositor: Compositor?
    private var converter: VideoTextureConverter?
    private var failure: String?
    private var cache: [RenderKey: PreviewImage] = [:]
    private var order: [RenderKey] = []
    private let cacheLimit = 200
    /// R14: the converter's texture cache keeps every texture it hands out until it is flushed, which over a long
    /// service of previews of video would grow without bound. Flushed this often (seconds) after a render that used it.
    private static let textureFlushInterval = 2.0
    private var lastTextureFlush = ProcessInfo.processInfo.systemUptime

    /// Renders `scene` at the given size. Thumbnails are cached by scene; live previews are not.
    /// `frames` supplies the current picture of the media the scene names (MEDIA-001, KI-022); without it the media
    /// layers are simply not drawn.
    ///
    /// UI-004: `follow` names a picture that is being redrawn as fast as the pointer moves (the slide editor during a drag). Only the
    /// newest request under one name is drawn; an older one that has not started yet is dropped and returns nil, so a burst of
    /// requests leaves at most one render running and one waiting, never a growing queue.
    func image(for scene: SceneDescription, width: Int, height: Int, cached: Bool,
               frames: (any MediaFrameSource)? = nil, channel: PreviewChannel = .composite, straight: Bool = false,
               follow: UUID? = nil, variant: StillCacheKey? = nil) async -> PreviewImage? {
        let ticket = follow.map { followTickets.take($0) }
        return await withCheckedContinuation { continuation in
            queue.async {
                if let follow, let ticket, !self.followTickets.isNewest(ticket, for: follow) { continuation.resume(returning: nil); return }
                continuation.resume(returning: self.renderLocked(scene, width, height, cached, frames, channel, straight, variant))
            }
        }
    }

    private let followTickets = FollowTickets()

    #if DEBUG
    /// UI-004: how many renders were asked for (hits included), for the drag exercise in the ui-snapshots hook.
    nonisolated(unsafe) private(set) var requestCount = 0
    #endif

    private func renderLocked(_ scene: SceneDescription, _ width: Int, _ height: Int, _ cached: Bool,
                              _ frames: (any MediaFrameSource)?, _ channel: PreviewChannel, _ straight: Bool, _ variant: StillCacheKey?) -> PreviewImage? {
        #if DEBUG
        requestCount += 1
        #endif
        let key = RenderKey(scene: scene, width: width, height: height, channel: channel, straight: straight, variant: variant)
        if cached, let hit = cache[key] { return hit }
        if compositor == nil, failure == nil {
            do { compositor = try Compositor() } catch { failure = "\(error)" }
        }
        guard let compositor else { return nil }
        // The textures stay alive until the render has finished (renderImage returns the finished pixels).
        var background: VideoTextureConverter.Frame?
        var foreground: VideoTextureConverter.Frame?
        if let frames, scene.backgroundMedia != nil || scene.foregroundMedia != nil {
            if converter == nil { converter = try? VideoTextureConverter(device: compositor.device) }
            if let converter {
                background = scene.backgroundMedia.flatMap { frames.currentPixelBuffer(for: $0, layer: .background) }
                    .flatMap { converter.texture(from: $0) }
                foreground = scene.foregroundMedia.flatMap { frames.currentPixelBuffer(for: $0, layer: .foreground) }
                    .flatMap { converter.texture(from: $0) }
            }
        }
        defer { withExtendedLifetime((background, foreground)) {} }
        guard let frame = try? compositor.renderImage(scene: scene, width: width, height: height,
                                                      backgroundMedia: background?.texture, foregroundMedia: foreground?.texture),
              let image = Self.cgImage(from: frame, channel: channel, straight: straight) else { return nil }
        let result = PreviewImage(image: image)
        flushTexturesIfDue()
        if cached {
            cache[key] = result
            order.append(key)
            if order.count > cacheLimit { cache[order.removeFirst()] = nil }
        }
        return result
    }

    /// Frees textures nothing uses any more (the render above has finished, so none is in use). Called on `queue`.
    private func flushTexturesIfDue() {
        let now = ProcessInfo.processInfo.systemUptime
        guard converter != nil, now - lastTextureFlush >= Self.textureFlushInterval else { return }
        lastTextureFlush = now
        converter?.flush()
    }

    private static func cgImage(from frame: RenderedFrame, channel: PreviewChannel, straight: Bool) -> CGImage? {
        guard channel != .composite else { return cgImage(from: frame) }
        // The same splitter the SDI output uses, so the picture is exactly what each connector would carry.
        let split = FillKeySplitter.split(bgra: frame.bgra, fillAlphaMode: straight ? .straight : .premultiplied)
        let bytes = channel == .fill ? split.fill : split.key
        guard let provider = CGDataProvider(data: Data(bytes) as CFData), let space = CGColorSpace(name: CGColorSpace.sRGB) else { return nil }
        let info = CGBitmapInfo(rawValue: CGImageAlphaInfo.noneSkipFirst.rawValue | CGBitmapInfo.byteOrder32Little.rawValue)
        return CGImage(width: frame.width, height: frame.height, bitsPerComponent: 8, bitsPerPixel: 32, bytesPerRow: frame.width * 4,
                       space: space, bitmapInfo: info, provider: provider, decode: nil, shouldInterpolate: true, intent: .defaultIntent)
    }

    private static func cgImage(from frame: RenderedFrame) -> CGImage? {
        guard let provider = CGDataProvider(data: Data(frame.bgra) as CFData),
              let space = CGColorSpace(name: CGColorSpace.sRGB) else { return nil }
        let info = CGBitmapInfo(rawValue: CGImageAlphaInfo.premultipliedFirst.rawValue | CGBitmapInfo.byteOrder32Little.rawValue)
        return CGImage(width: frame.width, height: frame.height, bitsPerComponent: 8, bitsPerPixel: 32,
                       bytesPerRow: frame.width * 4, space: space, bitmapInfo: info, provider: provider,
                       decode: nil, shouldInterpolate: true, intent: .defaultIntent)
    }
}

private struct ScenePreviewTask: Hashable { let scene: SceneDescription; let variant: StillCacheKey? }

/// A 16:9 picture of a scene. Redraws when the scene changes, waiting a tenth of a second first so a burst of
/// changes (typing, a Look change) becomes at most about ten renders per second.
struct ScenePreview: View {
    let scene: SceneDescription
    var width = 320
    var cached = true
    /// Where to get the pictures of background and foreground media. When the scene shows a video, the preview
    /// redraws about four times a second so it moves.
    var frames: (any MediaFrameSource)?
    /// A keyed screen (fill and key) is transparent where nothing is drawn: show the checkerboard-over-transparency
    /// convention behind it, so the operator can see what is transparent (HW-002 / SCRN-10).
    var keyed = false
    /// False for a thumbnail: one frame of the media, drawn once, not a moving picture.
    var animated = true
    /// Keyed screens: draw the composite (over a checkerboard), or the fill or the key signal.
    var channel: PreviewChannel = .composite
    var straightAlpha = false
    /// UI-004: draw at once, as fast as the scene changes, instead of waiting a tenth of a second (the slide editor during a drag).
    var follow = false
    /// FIX-I item 5: `frames` are stills (a thumbnail's background): drawn once per scene and still, never redrawn on a timer. `variant` names the still.
    var stills = false
    var variant: StillCacheKey?
    @State private var picture: PreviewImage?
    @State private var followName = UUID()

    var body: some View {
        ZStack {
            if keyed, channel == .composite { CheckerboardView() } else if keyed { Color.black } else { Color(white: 0.16) }     // shows through transparent (broadcast) scenes
            if let picture {
                Image(decorative: picture.image, scale: 1).resizable().interpolation(.medium)
            }
        }
        .aspectRatio(16.0 / 9.0, contentMode: .fit)
        .task(id: ScenePreviewTask(scene: scene, variant: variant)) {
            if picture != nil, !follow { try? await Task.sleep(for: .milliseconds(100)) }
            guard !Task.isCancelled else { return }
            let height = width * 9 / 16
            let made = await PreviewRenderer.shared.image(for: scene, width: width, height: height, cached: cached, frames: frames, channel: channel, straight: straightAlpha,
                                                          follow: follow ? followName : nil, variant: variant)
            guard !Task.isCancelled, let made else { return }
            picture = made
            if stills { return }
            // A thumbnail of a media background: the player may not have a frame yet, so draw it again twice.
            if !animated, frames != nil, Self.hasMedia(scene) {
                for pause in [800, 2500] {
                    try? await Task.sleep(for: .milliseconds(pause))
                    guard !Task.isCancelled,
                          let next = await PreviewRenderer.shared.image(for: scene, width: width, height: height, cached: false, frames: frames),
                          !Task.isCancelled else { return }
                    picture = next
                }
                return
            }
            // A video moves, and a still or a player that is still starting shows up a moment later: keep redrawing.
            while animated, frames != nil, Self.hasMedia(scene), !Task.isCancelled {
                try? await Task.sleep(for: .milliseconds(250))
                guard !Task.isCancelled,
                      let next = await PreviewRenderer.shared.image(for: scene, width: width, height: height, cached: false, frames: frames, channel: channel, straight: straightAlpha),
                      !Task.isCancelled else { return }
                picture = next
            }
        }
        .accessibilityHidden(true)
    }
}

/// The grey-and-white squares that mean "transparent".
struct CheckerboardView: View {
    var body: some View {
        Canvas { context, size in
            let square: CGFloat = 8
            let columns = Int((size.width / square).rounded(.up)), rows = Int((size.height / square).rounded(.up))
            context.fill(Path(CGRect(origin: .zero, size: size)), with: .color(Color(white: 0.82)))
            for row in 0..<rows {
                for column in 0..<columns where (row + column) % 2 == 1 {
                    context.fill(Path(CGRect(x: CGFloat(column) * square, y: CGFloat(row) * square, width: square, height: square)),
                                 with: .color(Color(white: 0.55)))
                }
            }
        }
        .accessibilityHidden(true)
    }
}

extension ScenePreview {
    static func hasMedia(_ scene: SceneDescription) -> Bool { scene.backgroundMedia != nil || scene.foregroundMedia != nil }
}

/// A slide as the audience screen draws it, with the background it will have when it goes live (FIX-I item 5): its own, else the
/// presentation's or the theme's. A picture or video is one cached still frame taken off the main thread; the Live monitor, not this, shows a bin override.
struct SlideThumbnail: View {
    let app: AppModel
    let slide: SlideContent
    /// The design's thumbnails are radius 4; the monitors in the inspector are radius 6.
    var cornerRadius: CGFloat = Radius.sm
    @State private var stillsLoaded = 0

    var body: some View {
        // Reading `appearanceRevision` makes the thumbnail follow Look, theme and prop changes, and nothing else:
        // typing in one slide rebuilds that slide's thumbnail only (R15).
        let _ = app.appearanceRevision
        let _ = stillsLoaded
        let scene = app.thumbnailScene(for: slide)
        let resolved = app.thumbnailBackground(for: slide)
        let variant = resolved.stillToLoad.flatMap { app.thumbnailStills.loadedKey(for: $0.assetID) }
        ScenePreview(scene: scene, width: 320, cached: true, frames: scene.backgroundMedia != nil ? app.thumbnailStills : nil,
                     animated: false, stills: true, variant: variant)
            .clipShape(RoundedRectangle(cornerRadius: cornerRadius))
            .overlay(alignment: .bottomLeading) {
                if resolved.showsFilmMark {
                    Image(systemName: "film").font(.wf(9, .bold)).foregroundStyle(.white).padding(3)
                        .background(.black.opacity(0.6), in: RoundedRectangle(cornerRadius: 3)).padding(4).accessibilityHidden(true)
                }
            }
            .task(id: resolved.stillToLoad) {
                guard let own = resolved.stillToLoad, let asset = app.media?.asset(own.assetID) else { return }
                if await app.thumbnailStills.ensure(asset) { stillsLoaded += 1 }
            }
    }
}

/// What one screen is showing right now.
struct LiveScreenPreview: View {
    let app: AppModel
    let screenID: UUID
    var cornerRadius: CGFloat = Radius.sm

    var body: some View {
        let _ = app.liveRevision
        let keyed = app.profiles.first { $0.id == screenID }?.destination.isKeyed ?? false
        ScenePreview(scene: app.scene(forScreen: screenID), width: 320, cached: false, frames: app.mediaFrames, keyed: keyed)
            .clipShape(RoundedRectangle(cornerRadius: cornerRadius))
    }
}

/// MEDIA-010: the small mark on a slide thumbnail whose slide has its own background (set by dropping a video or picture on it).
struct OwnBackgroundMark: View {
    let content: SlideContent
    /// FIX-G: ids of the bin items that exist now. A slide whose own background is not among them shows the missing-media state.
    var available: Set<UUID>? = nil

    var body: some View {
        if SlideBackgroundDrop.hasOwnBackground(content) {
            let missing = available.map { SlideBackgroundDrop.isMissing(content, available: $0) } ?? false
            Image(systemName: missing ? "exclamationmark.triangle.fill" : (content.background?.kind == .video ? "film" : "photo"))
                .font(.wf(10, .bold)).foregroundStyle(missing ? Tok.warning : .white)
                .padding(4).background(.black.opacity(0.65), in: Circle())
                .help(missing ? "This slide's own background is no longer in the media bin. The slide shows its words on the theme's own background. Drop another item on it, or right-click and choose Clear this slide's background."
                              : "This slide has its own background. Right-click the slide and choose Clear this slide's background to go back to the presentation's.")
                .accessibilityHidden(true)
        }
    }
}
