// UI-005h: Core Graphics rasteriser for the design's backgrounds and plates. Premultiplied BGRA, the same layout as text and shapes.
import Foundation
import CoreGraphics
import Domain

enum LooksRasterizer {
    private static func makeContext(_ raw: UnsafeMutableRawPointer, width: Int, height: Int) -> CGContext? {
        guard let space = CGColorSpace(name: CGColorSpace.sRGB) else { return nil }
        let info = CGImageAlphaInfo.premultipliedFirst.rawValue | CGBitmapInfo.byteOrder32Little.rawValue
        return CGContext(data: raw, width: width, height: height, bitsPerComponent: 8, bytesPerRow: width * 4, space: space, bitmapInfo: info)
    }

    /// The radial gradient over a whole `width` x `height` frame: an ellipse centred at (centerX, centerY) of the frame with radii of
    /// radiusX times the width and radiusY times the height, colours interpolated in sRGB as a browser does, the last colour past the radius.
    static func gradient(_ g: GradientBackground, width: Int, height: Int) -> [UInt8]? {
        guard width > 0, height > 0, width <= 16384, height <= 16384, g.stops.count >= 2 else { return nil }
        var pixels = [UInt8](repeating: 0, count: width * height * 4)
        let drawn: Bool = pixels.withUnsafeMutableBytes { raw in
            guard let base = raw.baseAddress, let ctx = makeContext(base, width: width, height: height),
                  let space = CGColorSpace(name: CGColorSpace.sRGB) else { return false }
            var components: [CGFloat] = []
            for stop in g.stops { components += [CGFloat(stop.color.red), CGFloat(stop.color.green), CGFloat(stop.color.blue), CGFloat(stop.color.alpha)] }
            let locations = g.stops.map { CGFloat($0.position) }
            guard let gradient = CGGradient(colorSpace: space, colorComponents: components, locations: locations, count: g.stops.count) else { return false }
            ctx.translateBy(x: CGFloat(g.centerX) * CGFloat(width), y: CGFloat(height) - CGFloat(g.centerY) * CGFloat(height))
            ctx.scaleBy(x: CGFloat(g.radiusX) * CGFloat(width), y: CGFloat(g.radiusY) * CGFloat(height))
            ctx.drawRadialGradient(gradient, startCenter: .zero, startRadius: 0, endCenter: .zero, endRadius: 1,
                                   options: [.drawsAfterEndLocation])
            return true
        }
        return drawn ? pixels : nil
    }

    /// A plate bitmap: its rounded rectangle in `fill` (the alpha is the plate's opacity), and, when given, the accent bar (fully rounded
    /// ends, a vertical gradient from `top` to `bottom`) at the integer rectangle `bar` in bitmap pixels, drawn opaque over the plate.
    static func plate(width: Int, height: Int, radius: Double, fill: ColorRGBA,
                      bar: (x: Int, y: Int, width: Int, height: Int, top: ColorRGBA, bottom: ColorRGBA)?) -> [UInt8]? {
        guard width > 0, height > 0, width <= 16384, height <= 16384 else { return nil }
        var pixels = [UInt8](repeating: 0, count: width * height * 4)
        let drawn: Bool = pixels.withUnsafeMutableBytes { raw in
            guard let base = raw.baseAddress, let ctx = makeContext(base, width: width, height: height),
                  let space = CGColorSpace(name: CGColorSpace.sRGB) else { return false }
            ctx.setShouldAntialias(true)
            let bounds = CGRect(x: 0, y: 0, width: width, height: height)
            let r = CGFloat(min(radius, Double(min(width, height)) / 2))
            if fill.alpha > 0 {
                ctx.addPath(r > 0 ? CGPath(roundedRect: bounds, cornerWidth: r, cornerHeight: r, transform: nil) : CGPath(rect: bounds, transform: nil))
                ctx.setFillColor(fill.cgColor(space))
                ctx.fillPath()
            }
            if let bar, bar.width > 0, bar.height > 0 {
                // Bitmap rows run bottom-up in Core Graphics.
                let rect = CGRect(x: bar.x, y: height - bar.y - bar.height, width: bar.width, height: bar.height)
                let br = CGFloat(min(bar.width, bar.height)) / 2
                ctx.saveGState()
                ctx.addPath(CGPath(roundedRect: rect, cornerWidth: br, cornerHeight: br, transform: nil))
                ctx.clip()
                let comps: [CGFloat] = [CGFloat(bar.top.red), CGFloat(bar.top.green), CGFloat(bar.top.blue), CGFloat(bar.top.alpha),
                                        CGFloat(bar.bottom.red), CGFloat(bar.bottom.green), CGFloat(bar.bottom.blue), CGFloat(bar.bottom.alpha)]
                if let gradient = CGGradient(colorSpace: space, colorComponents: comps, locations: [0, 1], count: 2) {
                    ctx.drawLinearGradient(gradient, start: CGPoint(x: rect.minX, y: rect.maxY), end: CGPoint(x: rect.minX, y: rect.minY), options: [])
                }
                ctx.restoreGState()
            }
            return true
        }
        return drawn ? pixels : nil
    }
}
