// UI-005i: the operator interface is set in Inter (SIL Open Font License 1.1, bundled under Resources/Inter, unmodified).
// The files are registered for this process only (nothing is installed on the Mac). If registration fails the interface uses the
// system font and the log says so once. Scripts Inter lacks (CJK, Hmong, Thai, ...) fall back through CoreText's cascade to the
// system fonts. The operator interface is what this file sets; the output themes name the same bundled font through the same registration
// (`Theme.outputFontName`), and `OutputFont.check()` says at launch whether that font resolved (FIX-J item 6).
import SwiftUI
import AppKit
import CoreText
import os

enum InterFont {
    private static let log = Logger(subsystem: "org.worshipflow.app", category: "font")
    private static let wghtTag = 0x77676874   // 'wght'
    private static let opszTag = 0x6F70737A   // 'opsz'

    /// The variable upright face, or nil when Inter could not be registered. Registers on first use (once, thread-safe).
    nonisolated(unsafe) static let base: CTFontDescriptor? = register()

    /// Registers both files for this process. Safe to call more than once.
    @discardableResult
    static func register() -> CTFontDescriptor? {
        var upright: CTFontDescriptor?
        for name in ["InterVariable", "InterVariable-Italic"] {
            guard let url = fontURL(name) else { log.error("Inter: \(name, privacy: .public).ttf is not in the app bundle; using the system font."); continue }
            var error: Unmanaged<CFError>?
            // An already-registered file reports an error that is not a failure for us.
            if !CTFontManagerRegisterFontsForURL(url as CFURL, .process, &error), let e = error?.takeRetainedValue(),
               CFErrorGetCode(e) != CTFontManagerError.alreadyRegistered.rawValue {
                log.error("Inter: could not register \(name, privacy: .public): \(CFErrorCopyDescription(e) as String, privacy: .public); using the system font.")
                continue
            }
            if name == "InterVariable", let d = (CTFontManagerCreateFontDescriptorsFromURL(url as CFURL) as? [CTFontDescriptor])?.first { upright = d }
        }
        return upright
    }

    static func fontURL(_ name: String) -> URL? {
        Bundle.main.url(forResource: name, withExtension: "ttf", subdirectory: "Inter")
    }

    /// The CSS weight (100 to 900) of a SwiftUI weight.
    static func cssWeight(_ w: Font.Weight) -> CGFloat {
        switch w {
        case .ultraLight: 100
        case .thin: 200
        case .light: 300
        case .regular: 400
        case .medium: 500
        case .semibold: 600
        case .bold: 700
        case .heavy: 800
        case .black: 900
        default: 400
        }
    }

    private static let lock = NSLock()
    nonisolated(unsafe) private static var cache: [String: CTFont] = [:]

    /// Inter at `size` and CSS weight with `tnum` and `cv11` on, as ui.css has them (`font-feature-settings: "tnum","cv11"`), and the
    /// optical-size axis at the size (clamped to its 14 to 32 range), as the browser does for a variable face.
    /// UI-005j: the width of `text` in one line at `size` and the CSS `weight`, for the few places that size a block to its text.
    static func textWidth(_ text: String, size: CGFloat, weight: CGFloat) -> CGFloat {
        let font = ctFont(size: size, weight: weight) ?? CTFont(.system, size: size)
        let line = CTLineCreateWithAttributedString(NSAttributedString(string: text, attributes: [.font: font]))
        return CGFloat(CTLineGetTypographicBounds(line, nil, nil, nil))
    }

    static func ctFont(size: CGFloat, weight: CGFloat) -> CTFont? {
        guard let base else { return nil }
        let key = "\(size)/\(weight)"
        lock.lock(); defer { lock.unlock() }
        if let f = cache[key] { return f }
        let features: [[CFString: Any]] = [
            [kCTFontOpenTypeFeatureTag: "tnum", kCTFontOpenTypeFeatureValue: 1],
        ]
        var d = CTFontDescriptorCreateCopyWithVariation(base, CFNumber.of(wghtTag), weight)
        // The browser that drew the design sets the axis to the size in points (CSS px x 3/4 is the inverse: 17 px asks for about 22.7), which
        // is what makes its 17 px title 123.6 wide; the axis runs 14 to 32. (Measured against the mockup's rectangles, UI-005j.)
        d = CTFontDescriptorCreateCopyWithVariation(d, CFNumber.of(opszTag), min(32, max(14, size * 4 / 3)))
        d = CTFontDescriptorCreateCopyWithAttributes(d, [kCTFontFeatureSettingsAttribute: features] as CFDictionary)
        let f = CTFontCreateWithFontDescriptor(d, size, nil)
        cache[key] = f
        return f
    }
}

private extension CFNumber {
    static func of(_ v: Int) -> CFNumber { v as NSNumber }
}
