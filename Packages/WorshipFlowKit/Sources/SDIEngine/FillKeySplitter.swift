// KEY-001 / SCRN-10: turn one BGRA frame with alpha into a fill frame and a key frame for a fill-and-key pair.
import Foundation

/// How the colour in a frame relates to its alpha.
public enum AlphaMode: Equatable, Sendable {
    /// Colour is already multiplied by alpha (what the compositor produces).
    case premultiplied
    /// Colour is independent of alpha, so premultiplied input is divided by alpha.
    case straight
}

public struct FillKeyFrames: Equatable, Sendable {
    /// BGRA, fully opaque.
    public var fill: [UInt8]
    /// The alpha as a grey level in BGR, fully opaque. Black means transparent.
    public var key: [UInt8]
}

public enum FillKeySplitter {
    /// `bgra` is premultiplied BGRA. Trailing bytes that do not make a whole pixel are ignored.
    public static func split(bgra: [UInt8], fillAlphaMode: AlphaMode) -> FillKeyFrames {
        let pixels = bgra.count / 4
        let count = pixels * 4
        var keyArray: [UInt8] = []
        let fill = [UInt8](unsafeUninitializedCapacity: count) { fillOut, fillCount in
            keyArray = [UInt8](unsafeUninitializedCapacity: count) { keyOut, keyCount in
                bgra.withUnsafeBufferPointer { src in
                    guard let s = src.baseAddress, let f = fillOut.baseAddress, let k = keyOut.baseAddress else {
                        keyCount = 0
                        return
                    }
                    switch fillAlphaMode {
                    case .premultiplied: splitPremultiplied(s, f, k, pixels)
                    case .straight: straight.withUnsafeBufferPointer { if let t = $0.baseAddress { splitStraight(s, f, k, pixels, t) } }
                    }
                    keyCount = count
                }
            }
            fillCount = keyArray.isEmpty && count > 0 ? 0 : count
        }
        return FillKeyFrames(fill: fill, key: keyArray)
    }

    // The two loops run over every pixel of every keyed frame. They are optimised even in a Debug build, where a
    // checked loop over a full HD frame takes a third of a second and would hide everything else a Debug run shows.
    @_optimize(speed)
    private static func splitPremultiplied(_ src: UnsafePointer<UInt8>, _ fill: UnsafeMutablePointer<UInt8>,
                                           _ key: UnsafeMutablePointer<UInt8>, _ pixels: Int) {
        var i = 0
        let end = pixels * 4
        while i < end {
            let a = src[i + 3]
            fill[i] = src[i]; fill[i + 1] = src[i + 1]; fill[i + 2] = src[i + 2]; fill[i + 3] = 255
            key[i] = a; key[i + 1] = a; key[i + 2] = a; key[i + 3] = 255
            i += 4
        }
    }

    @_optimize(speed)
    private static func splitStraight(_ src: UnsafePointer<UInt8>, _ fill: UnsafeMutablePointer<UInt8>,
                                      _ key: UnsafeMutablePointer<UInt8>, _ pixels: Int, _ table: UnsafePointer<UInt8>) {
        var i = 0
        let end = pixels * 4
        while i < end {
            let a = src[i + 3]
            let row = Int(a) << 8
            fill[i] = table[row | Int(src[i])]; fill[i + 1] = table[row | Int(src[i + 1])]; fill[i + 2] = table[row | Int(src[i + 2])]; fill[i + 3] = 255
            key[i] = a; key[i + 1] = a; key[i + 2] = a; key[i + 3] = 255
            i += 4
        }
    }

    /// `table[alpha << 8 | colour]` is the straight colour for a premultiplied one. Built once.
    private static let straight: [UInt8] = {
        var t = [UInt8](repeating: 0, count: 256 * 256)
        for a in 0..<256 { for c in 0..<256 { t[a << 8 | c] = unpremultiply(UInt8(c), alpha: UInt8(a)) } }
        return t
    }()

    private static func unpremultiply(_ colour: UInt8, alpha: UInt8) -> UInt8 {
        guard alpha > 0 else { return 0 }
        if alpha == 255 { return colour }
        let a = Int(alpha)
        let value = (Int(colour) * 255 + a / 2) / a
        return UInt8(min(255, value))
    }
}
