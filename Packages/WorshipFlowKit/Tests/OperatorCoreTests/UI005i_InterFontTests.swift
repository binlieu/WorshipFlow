// UI-005i: the operator interface is set in Inter. These tests check the vendored files, the licence, the fallback for scripts Inter
// lacks (no missing glyph, a bounded line height) and that the projected output text path never uses the interface font styles.
// No wall-clock or pixel assertions: coverage and metrics come from CoreText on the vendored file itself.
import Testing
import Foundation
import CoreText

@Suite struct UI005i_InterFontTests {
    private var root: URL { DesignTokenParityTests.root }
    private func read(_ path: String) throws -> String { try String(contentsOf: root.appendingPathComponent(path), encoding: .utf8) }

    /// Inter from the vendored file, without registering anything.
    private func inter(size: CGFloat = 13) throws -> CTFont {
        let url = root.appendingPathComponent("Vendor/Inter/InterVariable.ttf") as CFURL
        let d = try #require((CTFontManagerCreateFontDescriptorsFromURL(url) as? [CTFontDescriptor])?.first)
        return CTFontCreateWithFontDescriptor(d, size, nil)
    }

    /// The font CoreText actually draws `s` with when the text starts in Inter (Inter itself, or the cascade's fallback).
    private func fonts(for s: String, base: CTFont) -> [(Character, CTFont)] {
        s.compactMap { ch in
            if ch == " " { return nil }
            let str = String(ch) as CFString
            return (ch, CTFontCreateForString(base, str, CFRange(location: 0, length: CFStringGetLength(str))))
        }
    }

    private func hasGlyph(_ font: CTFont, _ ch: Character) -> Bool {
        let units = Array(String(ch).utf16)
        var glyphs = [CGGlyph](repeating: 0, count: units.count)
        return CTFontGetGlyphsForCharacters(font, units, &glyphs, units.count) && glyphs[0] != 0
    }

    private func lineHeight(_ f: CTFont) -> CGFloat { CTFontGetAscent(f) + CTFontGetDescent(f) + CTFontGetLeading(f) }

    @Test func theVendoredFontAndLicenceAreInTheRepositoryAndTheBuildCopiesThem() throws {
        for f in ["InterVariable.ttf", "InterVariable-Italic.ttf", "LICENSE.txt", "SOURCE.txt"] {
            let size = (try? FileManager.default.attributesOfItem(atPath: root.appendingPathComponent("Vendor/Inter/\(f)").path)[.size] as? Int) ?? 0
            #expect(size > 100, "\(f) is vendored")
        }
        #expect(try read("Vendor/Inter/LICENSE.txt").contains("SIL OPEN FONT LICENSE Version 1.1"))
        let yml = try read("project.yml")
        #expect(yml.contains("path: Vendor/Inter") && yml.contains("buildPhase: resources"), "the app copies the font folder, not a second repository copy")
        #expect(try read("NOTICE").contains("Inter 4.1"))
        #expect(try read("README.md").contains("Inter"))
    }

    @Test func interCoversLatinVietnameseCyrillicAndGreek() throws {
        let f = try inter()
        for s in ["Amazing grace", "Ệ ẫ ự ỗ Ằ ở ế ạ Ơ Ư", "Благодать", "Χάρις"] {
            for (ch, font) in fonts(for: s, base: f) {
                #expect(hasGlyph(font, ch) && CTFontCopyFamilyName(font) as String == CTFontCopyFamilyName(f) as String, "Inter draws \(ch)")
            }
        }
    }

    /// Everything Inter lacks falls back to a system font: a glyph for every character (no missing-glyph box) and a line height that
    /// stays close enough to Inter's that a fixed-height row does not clip it. The ratio is printed for the report.
    @Test func otherScriptsFallBackToTheSystemFontWithAGlyphAndABoundedLineHeight() throws {
        let f = try inter()
        let interHeight = lineHeight(f)
        let samples: [(String, String)] = [
            ("Chinese simplified", "亲爱的主，我们赞美你"),
            ("Chinese traditional", "親愛的主，我們讚美你"),
            ("Hmong (Latin)", "Peb hlub Vajtswv, nws yog peb tus Tswv"),
            ("Hmong (Pahawh)", "\u{16B1C}\u{16B1D}\u{16B20}"),
            ("Thai", "ภาษาไทย"), ("Lao", "ພາສາລາວ"), ("Khmer", "ភាសាខ្មែរ"), ("Burmese", "မြန်မာဘာသာ"),
            ("Devanagari", "हिन्दी भाषा"), ("Arabic", "اللغة العربية"), ("Hebrew", "עברית"), ("Korean", "한국어"), ("Japanese", "日本語のひらがな"),
        ]
        for (name, text) in samples {
            for (ch, font) in fonts(for: text, base: f) {
                #expect(hasGlyph(font, ch), "\(name): a glyph for \(ch) in \(CTFontCopyFullName(font) as String)")
                // The widest line height any fallback in the cascade brings, against Inter's 1.21 em: Burmese is the tallest, about 1.8x, so a 26 pt row holds a 13 pt line only by overflowing; nothing may exceed 2x.
                #expect(lineHeight(font) <= interHeight * 2.0, "\(name): line height \(lineHeight(font)) of \(CTFontCopyFullName(font) as String) against Inter \(interHeight)")
            }
        }
    }

    /// The projected text follows each theme's own font. Neither the render engine nor the output hosts mention the interface styles.
    @Test func theOutputTextPathDoesNotUseTheInterfaceFontStyles() throws {
        let banned = ["InterFont", ".wf(", "Font.wf", ".wfBody", ".wfCaption", ".wfControl", ".wfSectionLabel", ".wfBadge", ".wfMono", ".wfSmall",
                      ".wfCallout", ".wfHeadline", ".wfTitle", ".wfLargeTitle", ".wfTag", ".wfSubheadline"]
        let sources = root.appendingPathComponent("Packages/WorshipFlowKit/Sources")
        let walker = try #require(FileManager.default.enumerator(at: sources, includingPropertiesForKeys: nil))
        var swiftFiles = 0
        for case let url as URL in walker where url.pathExtension == "swift" {
            swiftFiles += 1
            let text = try String(contentsOf: url, encoding: .utf8)
            for b in banned { #expect(!text.contains(b), "\(url.lastPathComponent) must not use \(b)") }
        }
        #expect(swiftFiles > 50)
        let raster = try read("Packages/WorshipFlowKit/Sources/RenderEngine/TextRasterizer.swift")
        #expect(raster.contains("fontName"), "the rasteriser takes the theme's font name")
        let live = try read("App/Sources/LiveScenes.swift")
        for b in banned { #expect(!live.contains(b), "LiveScenes.swift must not use \(b)") }
    }

    @Test func theInterfaceStylesAreNamedInOnePlaceAndNoViewSetsASystemFont() throws {
        let tokens = try read("App/Sources/DesignTokens.swift")
        #expect(tokens.contains("static func wf(") && tokens.contains("static func wfMono("))
        let appDir = root.appendingPathComponent("App/Sources")
        for url in try FileManager.default.contentsOfDirectory(at: appDir, includingPropertiesForKeys: nil) where url.pathExtension == "swift" {
            let name = url.lastPathComponent
            if name == "DesignTokens.swift" || name == "InterFont.swift" { continue }
            let text = try String(contentsOf: url, encoding: .utf8)
            #expect(!text.contains(".system(size:") && !text.contains("NSFont.systemFont") && !text.contains("NSFont.monospaced"), "\(name) takes its font from the named styles")
        }
    }
}
