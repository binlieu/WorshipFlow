// APP-001 / KI-023 / PRES-06: rules for the theme editor that are not interface: keeping every value inside what
// the compositor can draw, and the sample scene the editor's thumbnail shows. Foundation and Domain only.
import Foundation
import Domain

public enum ThemeEditing {
    public static let fontSizeRange: ClosedRange<Double> = 8...400
    public static let outlineRange: ClosedRange<Double> = 0...40
    /// Smallest width or height of a text frame, as a fraction of the screen.
    public static let minimumFrameSide = 0.02
    public static let defaultFontName = "Helvetica Neue"

    public static let sampleLines = (primary: "Amazing grace, how sweet the sound",
                                     secondary: "Ân điển lạ lùng thay")

    /// Every number inside its range, every frame inside the screen, no blank font name. Equal input stays equal.
    public static func clamped(_ theme: Theme) -> Theme {
        var theme = theme
        theme.primary = clamped(theme.primary)
        theme.secondary = theme.secondary.map(clamped)
        return theme
    }

    public static func clamped(_ block: TextBlock) -> TextBlock {
        var block = block
        let name = block.style.fontName.trimmingCharacters(in: .whitespacesAndNewlines)
        block.style.fontName = name.isEmpty ? defaultFontName : name
        block.style.fontSize = limit(block.style.fontSize, fontSizeRange, fallback: 64)
        block.style.outlineWidth = limit(block.style.outlineWidth, outlineRange, fallback: 0)
        block.frame = clamped(block.frame)
        return block
    }

    public static func clamped(_ frame: NormalizedRect) -> NormalizedRect {
        let width = limit(frame.width, minimumFrameSide...1, fallback: 0.5)
        let height = limit(frame.height, minimumFrameSide...1, fallback: 0.2)
        return NormalizedRect(x: limit(frame.x, 0...(1 - width), fallback: 0),
                              y: limit(frame.y, 0...(1 - height), fallback: 0),
                              width: width, height: height)
    }

    private static func limit(_ value: Double, _ range: ClosedRange<Double>, fallback: Double) -> Double {
        guard value.isFinite else { return fallback }
        return min(range.upperBound, max(range.lowerBound, value))
    }

    /// The scene the editor's thumbnail draws: one sample slide, composed exactly as the audience screen composes it.
    /// With a `.media` background the video is flagged but not available to the thumbnail, so it shows the fallback colour.
    public static func previewScene(for theme: Theme, primary: String = sampleLines.primary,
                                    secondary: String? = sampleLines.secondary) -> SceneDescription {
        var state = ShowState()
        state.apply(.load(ShowDeck(presentationID: UUID(), slides: [SlideContent(primary: primary, secondary: secondary)])))
        state.apply(.trigger(index: 0))
        return SceneComposer.scene(for: .audience, state: state, theme: theme, look: .standard, props: [])
    }
}
