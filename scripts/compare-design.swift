// UI-005a: compares an app capture with a design picture. Run by hand through scripts/compare-design.sh, never by check.sh.
// Usage: compare-design <design.png> <app.png> <out-prefix> [tolerance 0-255, default 24] [show|components]
// Writes <out-prefix>-side.png (design | app) and <out-prefix>-diff.png (differing pixels in red over a dimmed design) and
// prints the share of pixels whose largest channel difference exceeds the tolerance, overall and per named region.
import Foundation
import CoreGraphics
import ImageIO
import UniformTypeIdentifiers

func load(_ path: String) -> CGImage? {
    guard let src = CGImageSourceCreateWithURL(URL(fileURLWithPath: path) as CFURL, nil) else { return nil }
    return CGImageSourceCreateImageAtIndex(src, 0, nil)
}
func rgba(_ image: CGImage, width: Int, height: Int) -> [UInt8] {
    var data = [UInt8](repeating: 0, count: width * height * 4)
    let space = CGColorSpace(name: CGColorSpace.sRGB)!
    data.withUnsafeMutableBytes { raw in
        let ctx = CGContext(data: raw.baseAddress, width: width, height: height, bitsPerComponent: 8, bytesPerRow: width * 4, space: space,
                            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        ctx.interpolationQuality = .high
        ctx.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
    }
    return data
}
func write(_ data: [UInt8], width: Int, height: Int, to path: String) {
    var d = data
    d.withUnsafeMutableBytes { raw in
        let ctx = CGContext(data: raw.baseAddress, width: width, height: height, bitsPerComponent: 8, bytesPerRow: width * 4,
                            space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        let dest = CGImageDestinationCreateWithURL(URL(fileURLWithPath: path) as CFURL, UTType.png.identifier as CFString, 1, nil)!
        CGImageDestinationAddImage(dest, ctx.makeImage()!, nil)
        CGImageDestinationFinalize(dest)
    }
}

let args = CommandLine.arguments
guard args.count >= 4, let design = load(args[1]), let app = load(args[2]) else { print("usage: compare-design <design.png> <app.png> <out-prefix> [tolerance]"); exit(2) }
let tolerance = args.count > 4 ? Int(args[4]) ?? 24 : 24
let W = design.width, H = design.height
let scale = Double(W) / 1440.0
let a = rgba(design, width: W, height: H)
let b = rgba(app, width: W, height: H)    // an app capture of another size is scaled to the design's (it should be 2880 x 1800)

// Regions in points on the 1440 x 900 window (the design's grid: toolbar 52, columns 256 | 812 | 372, transport bar 56, dock about 180).
let showRegions: [(String, Double, Double, Double, Double)] = [
    ("toolbar", 0, 0, 1440, 52), ("sidebar", 0, 52, 256, 388), ("playlist", 0, 388, 256, 844),
    ("centre", 256, 52, 1068, 664), ("dock", 256, 664, 1068, 844), ("inspector", 1068, 52, 1440, 844), ("transport bar", 0, 844, 1440, 900),
]
let componentRegions: [(String, Double, Double, Double, Double)] = [
    ("buttons", 32, 84, 479, 297), ("selection", 497, 84, 943, 297), ("role and status", 961, 84, 1408, 297),
    ("thumbnail states", 32, 316, 943, 515), ("messages", 961, 316, 1408, 515),
    ("colour", 32, 534, 943, 721), ("brand", 961, 534, 1408, 721),
]
let regions = (args.count > 5 && args[5] == "components") ? componentRegions : showRegions
var diff = a
var total = 0
var perRegion = [Int](repeating: 0, count: regions.count)
var regionPixels = [Int](repeating: 0, count: regions.count)
let regionRects: [(Int, Int, Int, Int)] = regions.map { (Int($0.1 * scale), Int($0.2 * scale), Int($0.3 * scale), Int($0.4 * scale)) }
for y in 0..<H {
    for x in 0..<W {
        let i = (y * W + x) * 4
        let d = max(abs(Int(a[i]) - Int(b[i])), abs(Int(a[i + 1]) - Int(b[i + 1])), abs(Int(a[i + 2]) - Int(b[i + 2])))
        let differs = d > tolerance
        if differs { total += 1 }
        for (r, rect) in regionRects.enumerated() where x >= rect.0 && x < rect.2 && y >= rect.1 && y < rect.3 {
            regionPixels[r] += 1
            if differs { perRegion[r] += 1 }
        }
        if differs { diff[i] = 255; diff[i + 1] = 40; diff[i + 2] = 40 }
        else { diff[i] = UInt8(Int(a[i]) / 3); diff[i + 1] = UInt8(Int(a[i + 1]) / 3); diff[i + 2] = UInt8(Int(a[i + 2]) / 3) }
    }
}
write(diff, width: W, height: H, to: args[3] + "-diff.png")
// Side by side: design on the left, app on the right, each at full size.
var side = [UInt8](repeating: 0, count: W * 2 * H * 4)
for y in 0..<H {
    side.replaceSubrange((y * W * 2) * 4..<(y * W * 2 + W) * 4, with: a[(y * W) * 4..<(y * W + W) * 4])
    side.replaceSubrange((y * W * 2 + W) * 4..<(y * W * 2 + 2 * W) * 4, with: b[(y * W) * 4..<(y * W + W) * 4])
}
write(side, width: W * 2, height: H, to: args[3] + "-side.png")

func pct(_ n: Int, _ d: Int) -> String { String(format: "%5.1f%%", 100.0 * Double(n) / Double(max(d, 1))) }
print("tolerance \(tolerance) of 255, size \(W)x\(H)")
print("overall        \(pct(total, W * H))")
for (r, region) in regions.enumerated() { print(region.0.padding(toLength: 14, withPad: " ", startingAt: 0) + pct(perRegion[r], regionPixels[r])) }
