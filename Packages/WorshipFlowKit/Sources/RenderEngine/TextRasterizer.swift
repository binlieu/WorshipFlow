// OUT-001: Core Text rasteriser. Produces premultiplied BGRA bitmaps with generous padding so that
// outlines and stacked diacritics (Vietnamese) are never clipped.
import Foundation
import CoreGraphics
import CoreText
import Domain

public enum RenderError: Error, Sendable, Equatable {
    case noMetalDevice
    case shaderCompilation(String)
    case pipeline(String)
    case resourceCreation(String)
    case invalidSize
    case rasterization(String)
}

public struct RasterizedText: Sendable {
    public let width: Int
    public let height: Int
    /// Bounds of pixels with non-zero alpha, bitmap pixel coordinates, origin top-left. maxX/maxY are exclusive edges.
    public let inkBounds: CGRect
    public let lineCount: Int
    /// Premultiplied BGRA (little-endian 32-bit, alpha first), `width * 4` bytes per row, top row first.
    public let pixels: [UInt8]
}

public struct TextRasterizer: Sendable {
    public init() {}

    /// Lays out `text` with Core Text (font fallback is automatic) and draws it.
    /// `style.fontSize` and `style.outlineWidth` are used as pixel sizes here; the compositor scales them.
    /// The returned bitmap is never wider than `maxWidth`.
    public func rasterize(_ text: String, style: TextStyle, maxWidth: Int,
                          alignment: TextAlignment = .center) throws -> RasterizedText {
        guard style.fontSize > 0, maxWidth > 8 else { throw RenderError.invalidSize }
        let size = CGFloat(style.fontSize)
        let outline = CGFloat(max(0, style.outlineWidth))
        let font = CTFontCreateWithName(style.fontName as CFString, size, nil)

        // A shadow can reach |offset| + about 2 * blur (the Gaussian's visible tail) past the glyphs. Padding stays
        // symmetric so the text keeps its place in the bitmap.
        let shadow = style.shadow.flatMap { $0.color.alpha > 0 ? $0 : nil }
        let shadowBlur = CGFloat(max(0, shadow?.blur ?? 0))
        let shadowX = shadow.map { CGFloat(abs($0.offsetX)) + 2 * shadowBlur + 1 } ?? 0
        let shadowY = shadow.map { CGFloat(abs($0.offsetY)) + 2 * shadowBlur + 1 } ?? 0
        let padX = Int((outline + size * 0.12 + 2 + shadowX).rounded(.up))
        let padY = Int((outline + size * 0.45 + 2 + shadowY).rounded(.up))
        let layoutWidth = Double(max(1, maxWidth - 2 * padX))

        let attributes: [CFString: Any] = [
            kCTFontAttributeName: font,
            kCTForegroundColorFromContextAttributeName: true,
        ]
        guard let attributed = CFAttributedStringCreate(kCFAllocatorDefault, text as CFString, attributes as CFDictionary) else {
            throw RenderError.rasterization("attributed string")
        }
        let typesetter = CTTypesetterCreateWithAttributedString(attributed)
        let length = CFAttributedStringGetLength(attributed)

        struct Line { let line: CTLine; let width: CGFloat; let ascent: CGFloat; let descent: CGFloat; let leading: CGFloat }
        var lines: [Line] = []
        var start = 0
        while start < length {
            var count = CTTypesetterSuggestLineBreak(typesetter, start, layoutWidth)
            if count <= 0 { count = 1 }
            let line = CTTypesetterCreateLine(typesetter, CFRange(location: start, length: count))
            var ascent: CGFloat = 0, descent: CGFloat = 0, leading: CGFloat = 0
            let full = CTLineGetTypographicBounds(line, &ascent, &descent, &leading)
            let width = CGFloat(full) - CGFloat(CTLineGetTrailingWhitespaceWidth(line))
            lines.append(Line(line: line, width: max(0, width), ascent: ascent, descent: descent, leading: leading))
            start += count
        }

        guard !lines.isEmpty else {
            return RasterizedText(width: 1, height: 1, inkBounds: .zero, lineCount: 0, pixels: [0, 0, 0, 0])
        }

        let maxLineWidth = lines.map(\.width).max() ?? 0
        let width = min(maxWidth, Int(maxLineWidth.rounded(.up)) + 2 * padX)
        let textHeight = lines.reduce(CGFloat(0)) { $0 + ($1.ascent + $1.descent + $1.leading) }
        let height = Int(textHeight.rounded(.up)) + 2 * padY
        guard width > 0, height > 0, width <= 16384, height <= 16384 else { throw RenderError.invalidSize }

        var pixels = [UInt8](repeating: 0, count: width * height * 4)
        let bitmapInfo = CGImageAlphaInfo.premultipliedFirst.rawValue | CGBitmapInfo.byteOrder32Little.rawValue
        let drawn: Bool = pixels.withUnsafeMutableBytes { raw in
            guard let space = CGColorSpace(name: CGColorSpace.sRGB),
                  let ctx = CGContext(data: raw.baseAddress, width: width, height: height, bitsPerComponent: 8,
                                      bytesPerRow: width * 4, space: space, bitmapInfo: bitmapInfo) else { return false }
            ctx.setShouldAntialias(true)
            ctx.setShouldSmoothFonts(false)
            ctx.setAllowsFontSmoothing(false)

            var baselines: [(CGFloat, CGFloat)] = []   // (x, y) in CG coordinates (origin bottom-left)
            var top = CGFloat(padY)
            let flush: CGFloat
            switch alignment { case .leading: flush = 0; case .center: flush = 0.5; case .trailing: flush = 1 }
            for l in lines {
                let baselineFromTop = top + l.ascent
                let x = CGFloat(padX) + (maxLineWidth - l.width) * flush
                baselines.append((x, CGFloat(height) - baselineFromTop))
                top += l.ascent + l.descent + l.leading
            }

            // The shadow belongs to the whole glyph group (outline and fill), so draw both inside one transparency
            // layer: the fill's shadow must not land on top of the outline. Positive offsetY is down the screen.
            if let shadow {
                ctx.setShadow(offset: CGSize(width: shadow.offsetX, height: -shadow.offsetY), blur: shadowBlur,
                              color: shadow.color.cgColor(space))
                ctx.beginTransparencyLayer(auxiliaryInfo: nil)
            }
            defer { if shadow != nil { ctx.endTransparencyLayer() } }

            if outline > 0 {
                ctx.setTextDrawingMode(.stroke)
                ctx.setLineWidth(outline * 2)
                ctx.setLineJoin(.round)
                ctx.setStrokeColor(style.outlineColor.cgColor(space))
                for (l, p) in zip(lines, baselines) {
                    ctx.textPosition = CGPoint(x: p.0, y: p.1)
                    CTLineDraw(l.line, ctx)
                }
            }
            ctx.setTextDrawingMode(.fill)
            ctx.setFillColor(style.color.cgColor(space))
            for (l, p) in zip(lines, baselines) {
                ctx.textPosition = CGPoint(x: p.0, y: p.1)
                CTLineDraw(l.line, ctx)
            }
            return true
        }
        guard drawn else { throw RenderError.rasterization("could not create bitmap context") }

        return RasterizedText(width: width, height: height, inkBounds: Self.inkBounds(pixels, width: width, height: height),
                              lineCount: lines.count, pixels: pixels)
    }

    private static func inkBounds(_ pixels: [UInt8], width: Int, height: Int) -> CGRect {
        var minX = width, minY = height, maxX = -1, maxY = -1
        pixels.withUnsafeBufferPointer { p in
            for y in 0..<height {
                let row = y * width * 4 + 3
                var x = 0
                while x < width {
                    if p[row + x * 4] != 0 {
                        if x < minX { minX = x }
                        if x > maxX { maxX = x }
                        if y < minY { minY = y }
                        if y > maxY { maxY = y }
                    }
                    x += 1
                }
            }
        }
        guard maxX >= 0 else { return .zero }
        return CGRect(x: minX, y: minY, width: maxX - minX + 1, height: maxY - minY + 1)
    }
}
