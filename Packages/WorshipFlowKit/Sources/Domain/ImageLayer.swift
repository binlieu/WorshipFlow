// OUT-003: an image the compositor draws, either under the text (background) or over it (overlay). Foundation only.
import Foundation

public enum ImageContentMode: String, Sendable, Equatable, Codable, Hashable {
    /// Whole image visible, aspect ratio kept, centred in the frame.
    case fit
    /// Frame completely covered, aspect ratio kept, excess cropped.
    case fill
}

public struct ImageLayer: Sendable, Equatable, Codable, Hashable {
    public var path: String
    public var frame: NormalizedRect
    /// 0...1, applied on top of the image's own alpha.
    public var opacity: Double
    public var contentMode: ImageContentMode

    public init(path: String, frame: NormalizedRect, opacity: Double = 1, contentMode: ImageContentMode = .fit) {
        self.path = path
        self.frame = frame
        self.opacity = opacity.isNaN ? 1 : min(1, max(0, opacity))
        self.contentMode = contentMode
    }
}
