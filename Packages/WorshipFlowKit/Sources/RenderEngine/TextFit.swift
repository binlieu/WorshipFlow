// FIX-J item 1 (UI-005h): fit text to its block. When the words of a slide are taller or wider than the block the theme gives them, the size
// is reduced in steps until they fit, never below the design's floor; first and second language shrink by the same factor, so their ratio
// holds. The measure is made at the 1080-line reference size, so a thumbnail and an output of the same slide agree on the factor. Pure
// measurement (Core Text layout, no drawing); the compositor computes it once per slide and theme and keeps it.
import Foundation
import CoreGraphics
import Domain

/// What fitting decided for a scene's text: the factor its sizes are multiplied by, and whether the words fit at that factor.
public struct TextFitStatus: Sendable, Equatable {
    /// 1 when nothing needed shrinking (or the theme does not fit its text). At most 1.
    public var factor: Double
    /// False when the words still do not fit at the floor: they are drawn at the floor, clipped to the title-safe frame, and flagged.
    public var fits: Bool

    public static let unchanged = TextFitStatus(factor: 1, fits: true)
}

enum TextFitter {
    /// The reference height the measure is made at (the compositor's reference height).
    static let referenceHeight = 1080.0
    /// Each step takes this much of the design size off.
    static let step = 0.04
    /// The title-safe frame (5 % on each side), which unfittable text is clipped to.
    static let titleSafe = NormalizedRect(x: 0.05, y: 0.05, width: 0.9, height: 0.9)

    /// The layers fitting applies to: those with a floor. They shrink together.
    static func group(_ layers: [TextLayer]) -> [TextLayer] { layers.filter { $0.fitFloor != nil && !$0.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && $0.opacity > 0 } }

    /// The reference width for an output of `width` x `height` (the same aspect at 1080 lines).
    static func referenceWidth(width: Int, height: Int) -> Int { Int((referenceHeight * Double(width) / Double(max(1, height))).rounded()) }

    /// `style` with its sizes (font, outline, shadow) multiplied by `factor`.
    static func scaled(_ style: TextStyle, by factor: Double) -> TextStyle {
        guard factor != 1 else { return style }
        var s = style
        s.fontSize *= factor
        s.outlineWidth *= factor
        if var shadow = s.shadow {
            shadow.offsetX *= factor
            shadow.offsetY *= factor
            shadow.blur *= factor
            s.shadow = shadow
        }
        return s
    }

    /// The width the plate gives its text, at the reference height (nil: too narrow to draw).
    static func plateTextWidth(_ plate: TextPlate, referenceWidth: Int) -> Double? {
        let plateX = plate.x * Double(referenceWidth), plateW = plate.width * Double(referenceWidth)
        let barW = plate.bar?.width ?? 0, gap = plate.bar?.gap ?? 0
        let left = plateX + plate.paddingX + (plate.bar == nil ? 0 : barW + gap)
        let width = plateX + plateW - plate.paddingX - left
        return width > 8 ? width : nil
    }

    /// Whether every layer of `group` fits its block when its size is multiplied by `factor`.
    static func fits(_ group: [TextLayer], factor: Double, plate: TextPlate?, referenceWidth: Int, rasterizer: TextRasterizer) -> Bool {
        let refW = Double(referenceWidth), refH = referenceHeight
        for layer in group {
            let style = scaled(layer.style, by: factor)
            let lineBoxMode = layer.style.lineHeight != nil
            let pad = TextRasterizer.padding(for: style)
            if plate != nil, layer.inPlate {
                guard let plate, let textWidth = plateTextWidth(plate, referenceWidth: referenceWidth),
                      let m = rasterizer.measure(layer.text, style: style, maxWidth: Int(textWidth.rounded()) + 2 * pad.x) else { continue }
                // "Reflow before shrinking": a plated block may take two lines at its design size before it is shrunk.
                let designPitch = (layer.style.lineHeight ?? 1.2) * layer.style.fontSize
                let budget = max(layer.frame.height * refH, 2 * designPitch)
                if m.blockHeight > budget + 0.5 || m.blockWidth > textWidth + 0.5 { return false }
            } else {
                let frame = layer.frame.pixelRect(width: referenceWidth, height: Int(refH))
                guard frame.width > 8, frame.height > 0 else { continue }
                let fw = layer.frame.width * refW, fh = layer.frame.height * refH
                if lineBoxMode {
                    guard let m = rasterizer.measure(layer.text, style: style, maxWidth: frame.width + 2 * pad.x) else { continue }
                    if m.blockHeight > fh + 0.5 || m.blockWidth > fw + 0.5 { return false }
                } else {
                    // A style without a line height is placed by its padded bitmap.
                    guard let m = rasterizer.measure(layer.text, style: style, maxWidth: frame.width) else { continue }
                    if m.blockHeight + Double(2 * m.padY) > fh + 0.5 || m.blockWidth + Double(2 * m.padX) > fw + 0.5 { return false }
                }
            }
        }
        return true
    }

    static func status(layers: [TextLayer], plate: TextPlate?, referenceWidth: Int, rasterizer: TextRasterizer) -> TextFitStatus {
        let group = group(layers)
        guard let first = group.first, let floor = first.fitFloor, first.style.fontSize > 0 else { return .unchanged }
        let lowest = min(1, floor / first.style.fontSize)
        var factor = 1.0
        while true {
            if fits(group, factor: factor, plate: plate, referenceWidth: referenceWidth, rasterizer: rasterizer) { return TextFitStatus(factor: factor, fits: true) }
            if factor <= lowest { return TextFitStatus(factor: lowest, fits: false) }
            factor = max(lowest, factor - step)
        }
    }
}
