// OUT-001: turns the live slide state into a scene per screen role. The same slide gets a different
// composition on each output.
import Foundation
import Domain
import OutputEngine

/// Thread-safe snapshot of what is live. Written by the operator on the main actor, read by render threads.
// @unchecked Sendable: all access to `snapshot` goes through `lock`.
final class LiveBox: @unchecked Sendable {
    struct Snapshot: Sendable, Equatable {
        var current = SlideContent(primary: "")
        var next: SlideContent?
        var cleared = true
    }

    private let lock = NSLock()
    private var snapshot = Snapshot()

    func read() -> Snapshot { lock.lock(); defer { lock.unlock() }; return snapshot }
    func update(_ change: (inout Snapshot) -> Void) { lock.lock(); change(&snapshot); lock.unlock() }
}

enum SceneBuilder {
    private static let font = "Helvetica Neue"

    static func audience(_ s: LiveBox.Snapshot) -> SceneDescription {
        let background = ColorRGBA(red: 0.04, green: 0.06, blue: 0.14)
        guard !s.cleared, !s.current.isBlank else {
            return SceneDescription(backgroundColor: background, showsVideo: true, textLayers: [])
        }
        var layers: [TextLayer] = []
        layers.append(TextLayer(
            text: s.current.primary,
            style: TextStyle(fontName: font, fontSize: 84, color: .white, outlineWidth: 4, outlineColor: .black),
            frame: NormalizedRect(x: 0.06, y: 0.18, width: 0.88, height: 0.32),
            alignment: .center, verticalAlignment: .bottom))
        if let secondary = s.current.secondary {
            layers.append(TextLayer(
                text: secondary,
                style: TextStyle(fontName: font, fontSize: 64, color: ColorRGBA(red: 1, green: 0.86, blue: 0.4), outlineWidth: 3, outlineColor: .black),
                frame: NormalizedRect(x: 0.06, y: 0.52, width: 0.88, height: 0.28),
                alignment: .center, verticalAlignment: .top))
        }
        return SceneDescription(backgroundColor: background, showsVideo: true, textLayers: layers)
    }

    /// Stage: large current line top-left, the next slide's line below it in a second colour, dark background, no video.
    static func stage(_ s: LiveBox.Snapshot) -> SceneDescription {
        let background = ColorRGBA(red: 0.02, green: 0.02, blue: 0.02)
        guard !s.cleared else { return SceneDescription(backgroundColor: background, textLayers: []) }
        var layers: [TextLayer] = []
        if !s.current.isBlank {
            layers.append(TextLayer(
                text: s.current.primary,
                style: TextStyle(fontName: font, fontSize: 110, color: .white),
                frame: NormalizedRect(x: 0.04, y: 0.05, width: 0.92, height: 0.50),
                alignment: .leading, verticalAlignment: .top))
        }
        if let next = s.next, !next.isBlank {
            layers.append(TextLayer(
                text: next.primary,
                style: TextStyle(fontName: font, fontSize: 64, color: ColorRGBA(red: 0.35, green: 0.85, blue: 0.55)),
                frame: NormalizedRect(x: 0.04, y: 0.62, width: 0.92, height: 0.32),
                alignment: .leading, verticalAlignment: .top))
        }
        return SceneDescription(backgroundColor: background, textLayers: layers)
    }
}
