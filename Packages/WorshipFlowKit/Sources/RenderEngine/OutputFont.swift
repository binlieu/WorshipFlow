// FIX-J item 6 (UI-005h): does the font the output looks name resolve to the bundled Inter? A Mac that could not register it draws the looks
// in a system font whose line breaks differ, so the operator is told once, and the hardware-test environment section records it.
import Foundation
import CoreText
import Domain

public struct OutputFontStatus: Sendable, Equatable {
    /// The font name asked for.
    public let requestedName: String
    /// The PostScript name of the font Core Text handed back.
    public let resolvedName: String
    public let resolvedFamily: String
    public var isInter: Bool { resolvedFamily.hasPrefix("Inter") || resolvedName.hasPrefix("Inter") }

    /// What the operator is told, once, when the bundled font is not what the screens use; nil when it is.
    public var operatorNotice: String? {
        isInter ? nil : "The bundled font could not be loaded; screens are using a system font and line breaks may differ"
    }

    /// One line for the hardware-test environment section.
    public var environmentLine: String {
        isInter ? "Inter (bundled)" : "system font (\(resolvedName)) in place of the bundled Inter: the bundled font could not be loaded"
    }
}

public enum OutputFont {
    /// Resolves `name` (default: the font the built-in output looks use) the way the rasteriser does and says what came back. Call it after the
    /// app has registered its fonts.
    public static func check(name: String = Theme.outputFontName) -> OutputFontStatus {
        let font = CTFontCreateWithName(name as CFString, 40, nil)
        return OutputFontStatus(requestedName: name, resolvedName: CTFontCopyPostScriptName(font) as String, resolvedFamily: CTFontCopyFamilyName(font) as String)
    }
}
