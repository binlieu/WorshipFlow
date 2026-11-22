// FIX-J item 7 (UI-005h): the metrics of a text style as the rasteriser will draw it, for rules that decide how much text a block holds (the
// scripture slide limits). Measured with the same font the rasteriser uses, once per font, weight and features; never on the live path.
import Foundation
import CoreText
import Domain

public enum TextMetrics {
    /// A few sentences of ordinary prose, English and Vietnamese (invented words, no scripture), whose average advance stands for running text:
    /// letters, spaces, marks and punctuation in their usual proportion.
    static let samples = [
        "The river keeps singing its quiet song to the hills, and the evening answers with a gentle light that rests on every roof.",
        "Bu\u{1ED5}i s\u{00E1}ng \u{0111}\u{1EBF}n ch\u{1EAD}m r\u{00E3}i tr\u{00EA}n thung l\u{0169}ng, ng\u{01B0}\u{1EDD}i n\u{00F4}ng d\u{1EAD}y s\u{1EDB}m v\u{00E0} nh\u{1EEF}ng ch\u{00FA} chim b\u{1EAF}t \u{0111}\u{1EA7}u h\u{00E1}t.",
    ]

    private static let lock = NSLock()
    nonisolated(unsafe) private static var cache: [String: Double] = [:]

    /// The average advance of a character of running text in `style`, as a multiple of the font size, spaces included: the larger of the English
    /// and the Vietnamese sample (the wider the letters, the fewer fit a line, so this errs on the side of splitting sooner).
    public static func averageAdvance(of style: TextStyle) -> Double {
        let key = "\(style.fontName)|\(style.weight ?? 0)|\(style.opticalSize ?? 0)|\(style.letterSpacing ?? 0)|\((style.fontFeatures ?? []).joined(separator: ","))"
        lock.lock(); defer { lock.unlock() }
        if let hit = cache[key] { return hit }
        let size = 100.0
        var probe = style
        probe.fontSize = size
        let font = TextRasterizer.font(for: probe, size: CGFloat(size))
        var attributes: [CFString: Any] = [kCTFontAttributeName: font]
        if let spacing = style.letterSpacing, spacing != 0 { attributes[kCTKernAttributeName] = spacing * size }
        var widest = 0.0
        for sample in samples {
            guard let text = CFAttributedStringCreate(kCFAllocatorDefault, sample as CFString, attributes as CFDictionary) else { continue }
            let width = CTLineGetTypographicBounds(CTLineCreateWithAttributedString(text), nil, nil, nil)
            widest = max(widest, width / size / Double(sample.count))
        }
        let value = widest > 0 ? widest : 0.5
        cache[key] = value
        return value
    }
}
