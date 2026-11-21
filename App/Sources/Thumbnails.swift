// OUT-004: slide thumbnails and per-screen live previews. Both are drawn by the same `Compositor` the outputs use,
// from the same scene descriptions, at reduced size on a background queue. There is no second drawing path.
import SwiftUI
import AppKit
import Domain
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
    private var failure: String?
    private var cache: [RenderKey: PreviewImage] = [:]
    private var order: [RenderKey] = []
    private let cacheLimit = 200

    /// Renders `scene` at the given size. Thumbnails are cached by scene; live previews are not.
    func image(for scene: SceneDescription, width: Int, height: Int, cached: Bool) async -> PreviewImage? {
        await withCheckedContinuation { continuation in
            queue.async { continuation.resume(returning: self.renderLocked(scene, width, height, cached)) }
        }
    }

    private func renderLocked(_ scene: SceneDescription, _ width: Int, _ height: Int, _ cached: Bool) -> PreviewImage? {
        let key = RenderKey(scene: scene, width: width, height: height)
        if cached, let hit = cache[key] { return hit }
        if compositor == nil, failure == nil {
            do { compositor = try Compositor() } catch { failure = "\(error)" }
        }
        guard let compositor else { return nil }
        guard let frame = try? compositor.renderImage(scene: scene, width: width, height: height),
              let image = Self.cgImage(from: frame) else { return nil }
        let result = PreviewImage(image: image)
        if cached {
            cache[key] = result
            order.append(key)
            if order.count > cacheLimit { cache[order.removeFirst()] = nil }
        }
        return result
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
            let made = await PreviewRenderer.shared.image(for: scene, width: width, height: height, cached: cached)
            guard !Task.isCancelled, let made else { return }
            picture = made
        }
        .accessibilityHidden(true)
    }
}

/// A slide as the audience screen draws it.
struct SlideThumbnail: View {
    let app: AppModel
    let slide: SlideContent

    var body: some View {
        // Reading `sceneRevision` makes the thumbnail follow Look, theme and prop changes.
        let _ = app.sceneRevision
        ScenePreview(scene: app.thumbnailScene(for: slide), width: 320, cached: true)
            .clipShape(RoundedRectangle(cornerRadius: 3))
    }
}

/// What one screen is showing right now.
struct LiveScreenPreview: View {
    let app: AppModel
    let screenID: UUID

    var body: some View {
        let _ = app.sceneRevision
        ScenePreview(scene: app.scene(forScreen: screenID), width: 320, cached: false)
            .clipShape(RoundedRectangle(cornerRadius: 3))
            .overlay(RoundedRectangle(cornerRadius: 3).stroke(.quaternary))
    }
}
