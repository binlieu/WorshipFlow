// FIX-L: what the output tests share. Two things made the readback test (UI-005h) fail now and then, and cost it 18 minutes when it did.
//
// 1. The built-in looks name the bundled Inter (`Theme.outputFontName`), which the app registers at launch, before any screen draws. A test
//    process has no launch: other suites register Inter whenever they happen to start. A test that drew once before that and once after
//    drew its text in two faces (Inter, then the system font) and its two pictures differed. A test that compares pictures made from the
//    built-in looks registers the font first, with `OutputTestFonts.registerInter()`.
// 2. Comparing two 8 MB arrays in `#expect` makes Swift Testing format both when they differ. `PixelDiff.describe` says in a line what differs.
import Foundation
import CoreText
import RenderEngine

enum OutputTestFonts {
    /// Registers the bundled Inter (Vendor/Inter) for this process, as the app does at launch, and says whether the output text path now
    /// resolves it. Safe to call from any thread, any number of times, and while another suite registers the same file.
    @discardableResult static func registerInter() -> Bool {
        if OutputFont.check().isInter { return true }
        let url = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
            .deletingLastPathComponent().deletingLastPathComponent().appendingPathComponent("Vendor/Inter/InterVariable.ttf")
        var error: Unmanaged<CFError>?
        if !CTFontManagerRegisterFontsForURL(url as CFURL, .process, &error), let e = error?.takeRetainedValue(),
           CFErrorGetCode(e) != CTFontManagerError.alreadyRegistered.rawValue { return false }
        return OutputFont.check().isInter
    }
}

enum PixelDiff {
    /// Nil when the two BGRA pictures are equal. Otherwise one line: how many pixels differ, the box around them, and the first few pairs
    /// of values; never the pictures themselves.
    static func describe(_ actual: [UInt8], _ expected: [UInt8], width: Int) -> String? {
        if actual == expected { return nil }
        guard actual.count == expected.count, width > 0 else { return "sizes differ: \(actual.count) bytes against \(expected.count)" }
        var count = 0, minX = Int.max, minY = Int.max, maxX = -1, maxY = -1
        var samples: [String] = []
        for p in 0..<(actual.count / 4) {
            let i = p * 4
            guard actual[i] != expected[i] || actual[i + 1] != expected[i + 1] || actual[i + 2] != expected[i + 2] || actual[i + 3] != expected[i + 3] else { continue }
            count += 1
            let x = p % width, y = p / width
            minX = min(minX, x); maxX = max(maxX, x); minY = min(minY, y); maxY = max(maxY, y)
            if samples.count < 3 { samples.append("(\(x),\(y)) \(Array(actual[i..<i + 4])) vs \(Array(expected[i..<i + 4]))") }
        }
        let total = actual.count / 4
        return "\(count) of \(total) pixels differ, in x \(minX)...\(maxX), y \(minY)...\(maxY); first: \(samples.joined(separator: "; "))"
    }
}
