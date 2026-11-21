// OUT-004: slide thumbnails and per-screen live previews. Both are drawn by the same `Compositor` the outputs use,
// from the same scene descriptions, at reduced size on a background queue. There is no second drawing path.
import SwiftUI
import AppKit
import Domain
import MediaEngine
import OutputEngine
import RenderEngine

/// An immutable bitmap handed from the render queue to the main actor.
// @unchecked Sendable: a CGImage is immutable once created and is never mutated here.
struct PreviewImage: @unchecked Sendable {
    let image: CGImage
}

private struct RenderKey: Hashable {
    let scene: SceneDescription
    let width: Int
    let height: Int
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
    func image(for scene: SceneDescription, width: Int, height: Int, cached: Bool,
               frames: (any MediaFrameSource)? = nil) async -> PreviewImage? {
        await withCheckedContinuation { continuation in
            queue.async { continuation.resume(returning: self.renderLocked(scene, width, height, cached, frames)) }
        }
    }

    private func renderLocked(_ scene: SceneDescription, _ width: Int, _ height: Int, _ cached: Bool,
                              _ frames: (any MediaFrameSource)?) -> PreviewImage? {
        let key = RenderKey(scene: scene, width: width, height: height)
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
              let image = Self.cgImage(from: frame) else { return nil }
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

    private static func cgImage(from frame: RenderedFrame) -> CGImage? {
        guard let provider = CGDataProvider(data: Data(frame.bgra) as CFData),
              let space = CGColorSpace(name: CGColorSpace.sRGB) else { return nil }
        let info = CGBitmapInfo(rawValue: CGImageAlphaInfo.premultipliedFirst.rawValue | CGBitmapInfo.byteOrder32Little.rawValue)
        return CGImage(width: frame.width, height: frame.height, bitsPerComponent: 8, bitsPerPixel: 32,
                       bytesPerRow: frame.width * 4, space: space, bitmapInfo: info, provider: provider,
                       decode: nil, shouldInterpolate: true, intent: .defaultIntent)
    }
}

/// A 16:9 picture of a scene. Redraws when the scene changes, waiting a tenth of a second first so a burst of
/// changes (typing, a Look change) becomes at most about ten renders per second.
struct ScenePreview: View {
    let scene: SceneDescription
    var width = 320
    var cached = true
    /// Where to get the pictures of background and foreground media. When the scene shows a video, the preview
    /// redraws about four times a second so it moves.
    var frames: (any MediaFrameSource)?
    @State private var picture: PreviewImage?

    var body: some View {
        ZStack {
            Color(white: 0.16)          // shows through transparent (broadcast) scenes
            if let picture {
                Image(decorative: picture.image, scale: 1).resizable().interpolation(.medium)
            }
        }
        .aspectRatio(16.0 / 9.0, contentMode: .fit)
        .task(id: scene) {
            if picture != nil { try? await Task.sleep(for: .milliseconds(100)) }
            guard !Task.isCancelled else { return }
            let height = width * 9 / 16
            let made = await PreviewRenderer.shared.image(for: scene, width: width, height: height, cached: cached, frames: frames)
            guard !Task.isCancelled, let made else { return }
            picture = made
            // A video moves, and a still or a player that is still starting shows up a moment later: keep redrawing.
            while frames != nil, Self.hasMedia(scene), !Task.isCancelled {
                try? await Task.sleep(for: .milliseconds(250))
                guard !Task.isCancelled,
                      let next = await PreviewRenderer.shared.image(for: scene, width: width, height: height, cached: false, frames: frames),
                      !Task.isCancelled else { return }
                picture = next
            }
        }
        .accessibilityHidden(true)
    }
}

extension ScenePreview {
    static func hasMedia(_ scene: SceneDescription) -> Bool { scene.backgroundMedia != nil || scene.foregroundMedia != nil }
}

/// A slide as the audience screen draws it.
struct SlideThumbnail: View {
    let app: AppModel
    let slide: SlideContent

    var body: some View {
        // Reading `appearanceRevision` makes the thumbnail follow Look, theme and prop changes, and nothing else:
        // typing in one slide rebuilds that slide's thumbnail only (R15).
        let _ = app.appearanceRevision
        ScenePreview(scene: app.thumbnailScene(for: slide), width: 320, cached: true)
            .clipShape(RoundedRectangle(cornerRadius: 3))
    }
}

/// What one screen is showing right now.
struct LiveScreenPreview: View {
    let app: AppModel
    let screenID: UUID

    var body: some View {
        let _ = app.liveRevision
        ScenePreview(scene: app.scene(forScreen: screenID), width: 320, cached: false, frames: app.mediaFrames)
            .clipShape(RoundedRectangle(cornerRadius: 3))
            .overlay(RoundedRectangle(cornerRadius: 3).stroke(.quaternary))
    }
}
