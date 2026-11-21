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
        var fill = [UInt8](repeating: 255, count: pixels * 4)
        var key = [UInt8](repeating: 255, count: pixels * 4)
        for p in 0..<pixels {
            let i = p * 4
            let a = bgra[i + 3]
            key[i] = a; key[i + 1] = a; key[i + 2] = a
            switch fillAlphaMode {
            case .premultiplied:
                fill[i] = bgra[i]; fill[i + 1] = bgra[i + 1]; fill[i + 2] = bgra[i + 2]
            case .straight:
                for k in 0..<3 { fill[i + k] = unpremultiply(bgra[i + k], alpha: a) }
            }
        }
        return FillKeyFrames(fill: fill, key: key)
    }

    private static func unpremultiply(_ colour: UInt8, alpha: UInt8) -> UInt8 {
        guard alpha > 0 else { return 0 }
        if alpha == 255 { return colour }
        let a = Int(alpha)
        let value = (Int(colour) * 255 + a / 2) / a
        return UInt8(min(255, value))
    }
}
