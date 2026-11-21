// SLIDE-001a: Core Graphics rasteriser for slide shapes. Produces premultiplied BGRA bitmaps, the same layout as text.
import Foundation
import CoreGraphics
import Domain

enum ShapeRasterizer {
    /// Draws the shape filling a `width` x `height` bitmap. The stroke is drawn inside the shape's edge
    /// (`strokeWidth` is in bitmap pixels here; the compositor scales it from points). Antialiased.
    static func rasterize(shape: ShapeObject.Shape, fill: ColorRGBA?, strokeColor: ColorRGBA?, strokeWidth: Double,
                          width: Int, height: Int) -> [UInt8]? {
        guard width > 0, height > 0, width <= 16384, height <= 16384 else { return nil }
        var pixels = [UInt8](repeating: 0, count: width * height * 4)
        let bitmapInfo = CGImageAlphaInfo.premultipliedFirst.rawValue | CGBitmapInfo.byteOrder32Little.rawValue
        let drawn: Bool = pixels.withUnsafeMutableBytes { raw in
            guard let space = CGColorSpace(name: CGColorSpace.sRGB),
                  let ctx = CGContext(data: raw.baseAddress, width: width, height: height, bitsPerComponent: 8,
                                      bytesPerRow: width * 4, space: space, bitmapInfo: bitmapInfo) else { return false }
            ctx.setShouldAntialias(true)
            let bounds = CGRect(x: 0, y: 0, width: width, height: height)
            let path = Self.path(shape, in: bounds)
            if let fill, fill.alpha > 0 {
                ctx.addPath(path)
                ctx.setFillColor(fill.cgColor(space))
                ctx.fillPath()
            }
            if let strokeColor, strokeColor.alpha > 0, strokeWidth > 0 {
                // Clip to the shape and stroke twice the width: only the inner half lands inside the frame edge.
                ctx.saveGState()
                ctx.addPath(path)
                ctx.clip()
                ctx.addPath(path)
                ctx.setStrokeColor(strokeColor.cgColor(space))
                ctx.setLineWidth(CGFloat(strokeWidth) * 2)
                ctx.setLineJoin(.miter)
                ctx.strokePath()
                ctx.restoreGState()
            }
            return true
        }
        return drawn ? pixels : nil
    }

    static func path(_ shape: ShapeObject.Shape, in rect: CGRect) -> CGPath {
        switch shape {
        case .rectangle:
            return CGPath(rect: rect, transform: nil)
        case .ellipse:
            return CGPath(ellipseIn: rect, transform: nil)
        case .roundedRectangle(let fraction):
            let f = fraction.isNaN ? 0 : min(0.5, max(0, fraction))
            let r = CGFloat(f) * min(rect.width, rect.height)
            guard r > 0 else { return CGPath(rect: rect, transform: nil) }
            return CGPath(roundedRect: rect, cornerWidth: r, cornerHeight: r, transform: nil)
        }
    }
}

extension ColorRGBA {
    func cgColor(_ space: CGColorSpace) -> CGColor {
        CGColor(colorSpace: space, components: [CGFloat(red), CGFloat(green), CGFloat(blue), CGFloat(alpha)])
            ?? CGColor(gray: 1, alpha: 1)
    }
}
