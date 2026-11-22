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
    /// True when the text did not fit under `TextRasterizer.maxDimension` / `maxBitmapBytes` and the bitmap holds only
    /// its top-left part (R2: clipped, never thrown).
    public var clipped = false
    /// UI-005h: where the text block's line boxes sit in the bitmap (the padding before them), and the block's size: the widest line, and
    /// the lines' pitch times their count. Pixels, bitmap coordinates, origin top-left.
    public var lineBoxLeft: Double = 0
    public var lineBoxTop: Double = 0
    public var blockWidth: Double = 0
    public var blockHeight: Double = 0
    /// Premultiplied BGRA (little-endian 32-bit, alpha first), `width * 4` bytes per row, top row first.
    public let pixels: [UInt8]
}

public struct TextRasterizer: Sendable {
    public init() {}

    /// UI-005h: the padding around the line boxes, in bitmap pixels: room for the outline, the shadow and stacked diacritics, so none is
    /// clipped. The compositor uses it to place a text block by its line boxes.
    public static func padding(for style: TextStyle) -> (x: Int, y: Int) {
        let size = CGFloat(max(0, style.fontSize))
        let outline = CGFloat(max(0, style.outlineWidth))
        let shadow = style.shadow.flatMap { $0.color.alpha > 0 ? $0 : nil }
        let blur = CGFloat(max(0, shadow?.blur ?? 0))
        let shadowX = shadow.map { CGFloat(abs($0.offsetX)) + 2 * blur + 1 } ?? 0
        let shadowY = shadow.map { CGFloat(abs($0.offsetY)) + 2 * blur + 1 } ?? 0
        return (Int((outline + size * 0.12 + 2 + shadowX).rounded(.up)), Int((outline + size * 0.45 + 2 + shadowY).rounded(.up)))
    }

    private static let weightAxis = 0x77676874      // 'wght'
    private static let opticalSizeAxis = 0x6F70737A // 'opsz'

    /// UI-005h: the font for a style. Without a weight, optical size or features, exactly `CTFontCreateWithName` (as before). With them, a
    /// variable font gets its weight axis set (and its optical-size axis to the style's, else to the size, as a browser does), any other font
    /// the nearest face of its family for the weight, and the feature tags are switched on.
    static func font(for style: TextStyle, size: CGFloat) -> CTFont {
        var font = CTFontCreateWithName(style.fontName as CFString, size, nil)
        guard style.weight != nil || style.opticalSize != nil || style.fontFeatures?.isEmpty == false else { return font }
        var done = false
        if let axes = CTFontCopyVariationAxes(font) as? [[CFString: Any]] {
            var variation: [NSNumber: NSNumber] = [:]
            for axis in axes {
                guard let id = (axis[kCTFontVariationAxisIdentifierKey] as? NSNumber)?.intValue else { continue }
                let low = (axis[kCTFontVariationAxisMinimumValueKey] as? NSNumber)?.doubleValue ?? 0
                let high = (axis[kCTFontVariationAxisMaximumValueKey] as? NSNumber)?.doubleValue ?? 1000
                if id == weightAxis, let weight = style.weight { variation[NSNumber(value: id)] = NSNumber(value: min(high, max(low, Double(weight)))) }
                if id == opticalSizeAxis {
                    let wanted = style.opticalSize ?? (style.weight != nil ? Double(size) * 4 / 3 : nil)
                    if let wanted { variation[NSNumber(value: id)] = NSNumber(value: min(high, max(low, wanted))) }
                }
            }
            if !variation.isEmpty {
                font = CTFontCreateCopyWithAttributes(font, size, nil, CTFontDescriptorCreateWithAttributes([kCTFontVariationAttribute: variation] as CFDictionary))
                done = true
            }
        }
        if !done, let weight = style.weight, weight != 400 {
            let traits: [CFString: Any] = [kCTFontWeightTrait: Self.coreTextWeight(weight)]
            let descriptor = CTFontDescriptorCreateWithAttributes([kCTFontFamilyNameAttribute: CTFontCopyFamilyName(font), kCTFontTraitsAttribute: traits] as CFDictionary)
            font = CTFontCreateWithFontDescriptor(descriptor, size, nil)
        }
        if let tags = style.fontFeatures, !tags.isEmpty {
            let settings: [[CFString: Any]] = tags.map { [kCTFontOpenTypeFeatureTag: $0, kCTFontOpenTypeFeatureValue: 1] }
            let descriptor = CTFontDescriptorCreateWithAttributes([kCTFontFeatureSettingsAttribute: settings] as CFDictionary)
            font = CTFontCreateCopyWithAttributes(font, size, nil, descriptor)
        }
        return font
    }

    /// CSS weight to Core Text's -1...1 weight trait (the values of NSFont.Weight).
    private static func coreTextWeight(_ css: Int) -> CGFloat {
        switch css {
        case ..<150: return -0.8
        case ..<250: return -0.6
        case ..<350: return -0.4
        case ..<450: return 0
        case ..<550: return 0.23
        case ..<650: return 0.3
        case ..<750: return 0.4
        case ..<850: return 0.56
        default: return 0.62
        }
    }

    // A typeset line: a line box taller than the font's own pitch when the style has a line height; the glyphs sit in it as in a web page.
    fileprivate struct Line { let line: CTLine; let width: CGFloat; let ascent: CGFloat; let descent: CGFloat; let leading: CGFloat; let pitch: CGFloat; let baselineInset: CGFloat }

    /// Breaks `text` into lines of at most `layoutWidth` and measures them. A line height replaces the font's own pitch (ascent + descent +
    /// leading) with `lineHeight * size`: half of the room the line box has beyond the font's ascent + descent goes above the glyphs, half below.
    /// Nil when the attributed string cannot be made.
    fileprivate static func layoutLines(_ text: String, style: TextStyle, font: CTFont, size: CGFloat, layoutWidth: Double) -> [Line]? {
        var attributes: [CFString: Any] = [
            kCTFontAttributeName: font,
            kCTForegroundColorFromContextAttributeName: true,
        ]
        if let spacing = style.letterSpacing, spacing != 0 { attributes[kCTKernAttributeName] = spacing * Double(size) }
        guard let attributed = CFAttributedStringCreate(kCFAllocatorDefault, text as CFString, attributes as CFDictionary) else { return nil }
        let typesetter = CTTypesetterCreateWithAttributedString(attributed)
        let length = CFAttributedStringGetLength(attributed)
        let fixedPitch: CGFloat? = style.lineHeight.map { CGFloat($0) * size }
        var lines: [Line] = []
        var start = 0
        while start < length {
            var count = CTTypesetterSuggestLineBreak(typesetter, start, layoutWidth)
            if count <= 0 { count = 1 }
            let line = CTTypesetterCreateLine(typesetter, CFRange(location: start, length: count))
            var ascent: CGFloat = 0, descent: CGFloat = 0, leading: CGFloat = 0
            let full = CTLineGetTypographicBounds(line, &ascent, &descent, &leading)
            let width = CGFloat(full) - CGFloat(CTLineGetTrailingWhitespaceWidth(line))
            let pitch = fixedPitch ?? (ascent + descent + leading)
            let inset = fixedPitch.map { ($0 - (ascent + descent)) / 2 + ascent } ?? ascent
            lines.append(Line(line: line, width: max(0, width), ascent: ascent, descent: descent, leading: leading, pitch: pitch, baselineInset: inset))
            start += count
        }
        return lines
    }

    /// FIX-J: how big `text` is laid out in `style` at `maxWidth` (the same measure `rasterize` uses), without drawing it. Pixels at the style's
    /// own size. `blockWidth` is the widest line, `blockHeight` the lines' pitch times their count; `padX` and `padY` are the bitmap padding.
    public struct Measure: Sendable, Equatable {
        public var blockWidth: Double
        public var blockHeight: Double
        public var lineCount: Int
        public var padX: Int
        public var padY: Int
    }

    public func measure(_ text: String, style: TextStyle, maxWidth: Int) -> Measure? {
        guard style.fontSize > 0, maxWidth > 8 else { return nil }
        let size = CGFloat(style.fontSize)
        let (padX, padY) = Self.padding(for: style)
        let font = Self.font(for: style, size: size)
        guard let lines = Self.layoutLines(text, style: style, font: font, size: size, layoutWidth: Double(max(1, maxWidth - 2 * padX))) else { return nil }
        return Measure(blockWidth: Double(lines.map(\.width).max() ?? 0), blockHeight: Double(lines.reduce(CGFloat(0)) { $0 + $1.pitch }),
                       lineCount: lines.count, padX: padX, padY: padY)
    }

    /// Largest bitmap side, in pixels (also the largest Metal texture side on Apple GPUs).
    public static let maxDimension = 16384
    /// Largest bitmap, in bytes. A frame-wide block of text at the dimension limit would otherwise be about 1 GB.
    public static let maxBitmapBytes = 512 * 1024 * 1024

    /// Lays out `text` with Core Text (font fallback is automatic) and draws it.
    /// `style.fontSize` and `style.outlineWidth` are used as pixel sizes here; the compositor scales them.
    /// The returned bitmap is never wider than `maxWidth`.
    public func rasterize(_ text: String, style: TextStyle, maxWidth: Int,
                          alignment: TextAlignment = .center) throws -> RasterizedText {
        guard style.fontSize > 0, maxWidth > 8 else { throw RenderError.invalidSize }
        let size = CGFloat(style.fontSize)
        let outline = CGFloat(max(0, style.outlineWidth))
        let font = Self.font(for: style, size: size)

        // A shadow can reach |offset| + about 2 * blur (the Gaussian's visible tail) past the glyphs. Padding stays
        // symmetric so the text keeps its place in the bitmap.
        let shadow = style.shadow.flatMap { $0.color.alpha > 0 ? $0 : nil }
        let shadowBlur = CGFloat(max(0, shadow?.blur ?? 0))
        let (padX, padY) = Self.padding(for: style)
        let layoutWidth = Double(max(1, maxWidth - 2 * padX))

        guard let lines = Self.layoutLines(text, style: style, font: font, size: size, layoutWidth: layoutWidth) else {
            throw RenderError.rasterization("attributed string")
        }

        guard !lines.isEmpty else {
            return RasterizedText(width: 1, height: 1, inkBounds: .zero, lineCount: 0, pixels: [0, 0, 0, 0])
        }

        let maxLineWidth = lines.map(\.width).max() ?? 0
        let wanted = (width: min(maxWidth, Int(maxLineWidth.rounded(.up)) + 2 * padX),
                      height: Int(lines.reduce(CGFloat(0)) { $0 + $1.pitch }.rounded(.up)) + 2 * padY)
        guard wanted.width > 0, wanted.height > 0 else { throw RenderError.invalidSize }
        // Text that is too big for one bitmap keeps its top-left part: the baselines below are measured from the top.
        let width = min(wanted.width, Self.maxDimension)
        let height = min(wanted.height, Self.maxDimension, max(1, Self.maxBitmapBytes / (width * 4)))
        let clipped = width < wanted.width || height < wanted.height

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
                let baselineFromTop = top + l.baselineInset
                let x = CGFloat(padX) + (maxLineWidth - l.width) * flush
                baselines.append((x, CGFloat(height) - baselineFromTop))
                top += l.pitch
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
                              lineCount: lines.count, clipped: clipped, lineBoxLeft: Double(padX), lineBoxTop: Double(padY),
                              blockWidth: Double(maxLineWidth), blockHeight: Double(lines.reduce(CGFloat(0)) { $0 + $1.pitch }), pixels: pixels)
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
