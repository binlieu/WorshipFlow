// FIX-J item 3 (UI-005h): stored theme values go through the same validation as the initialisers. Hostile JSON for each type; every test
// here uses the existing API only, so it could be run red first (a decoded value used to bypass every clamp).
import Testing
import Foundation
import Domain

@Suite struct FIXJ_ClampTests {
    static let white = #"{"red":1,"green":1,"blue":1,"alpha":1}"#

    func decode<T: Decodable>(_ type: T.Type, _ json: String) throws -> T { try JSONDecoder().decode(type, from: Data(json.utf8)) }

    // MARK: Colour

    @Test func aColourOutsideZeroToOneIsClamped() throws {
        let c = try decode(ColorRGBA.self, #"{"red":9,"green":-3,"blue":0.5,"alpha":40}"#)
        #expect(c.red == 1 && c.green == 0 && c.blue == 0.5 && c.alpha == 1)
    }

    // MARK: TextStyle

    func style(_ extra: String) throws -> TextStyle {
        try decode(TextStyle.self, #"{"fontName":"Inter","fontSize":40,"color":\#(Self.white),"outlineWidth":0,"outlineColor":\#(Self.white)\#(extra)}"#)
    }

    @Test func aStyleWithHostileTypeValuesIsClamped() throws {
        let s = try style(#","weight":5000,"lineHeight":1000000,"opticalSize":99999,"letterSpacing":1e9"#)
        #expect(s.weight == 900)
        #expect(try #require(s.lineHeight) <= 4)
        #expect(try #require(s.opticalSize) <= 144)
        #expect(try #require(s.letterSpacing) <= 2)
        let low = try style(#","weight":-40,"lineHeight":0.0001,"opticalSize":0.0001,"letterSpacing":-1e9"#)
        #expect(low.weight == 100)
        #expect(try #require(low.lineHeight) >= 0.5)
        #expect(try #require(low.opticalSize) >= 6)
        #expect(try #require(low.letterSpacing) >= -0.5)
    }

    @Test func aLineHeightOrOpticalSizeThatCannotBeValidIsDropped() throws {
        let s = try style(#","lineHeight":0,"opticalSize":-5"#)
        #expect(s.lineHeight == nil && s.opticalSize == nil)
        let n = try style(#","lineHeight":-2"#)
        #expect(n.lineHeight == nil)
    }

    @Test func aShadowWithHostileValuesIsClamped() throws {
        let s = try style(#","shadow":{"color":{"red":0,"green":0,"blue":0,"alpha":7},"offsetX":1e9,"offsetY":-1e9,"blur":-50}"#)
        let shadow = try #require(s.shadow)
        #expect(shadow.color.alpha == 1 && shadow.blur == 0)
        #expect(abs(shadow.offsetX) <= 2000 && abs(shadow.offsetY) <= 2000)
        let big = try style(#","shadow":{"color":\#(Self.white),"offsetX":0,"offsetY":0,"blur":1e9}"#)
        #expect(try #require(big.shadow).blur <= 1000)
    }

    @Test func validValuesDecodeAndEncodeAsTheyWereStored() throws {
        let s = TextStyle(fontName: "Inter", fontSize: 119.04, color: .white, outlineWidth: 2, outlineColor: .black,
                          shadow: TextShadow(color: .black, offsetX: 0, offsetY: 5.76, blur: 23.04), weight: 600, letterSpacing: 0.08, lineHeight: 1.2,
                          opticalSize: 14, fontFeatures: ["cv11"])
        let json = try JSONEncoder().encode(s)
        #expect(try JSONDecoder().decode(TextStyle.self, from: json) == s)
        // A style saved before this slice has none of the optional fields.
        let old = try style("")
        #expect(old.weight == nil && old.lineHeight == nil && old.opticalSize == nil && old.letterSpacing == nil && old.shadow == nil && old.fontFeatures == nil)
        let sorted = JSONEncoder()
        sorted.outputFormatting = [.sortedKeys]
        #expect(try sorted.encode(old) == sorted.encode(try JSONDecoder().decode(TextStyle.self, from: sorted.encode(old))))
        #expect(!String(decoding: try sorted.encode(old), as: UTF8.self).contains("weight"))
    }

    // MARK: Gradient

    func gradient(_ stops: String, _ rest: String = #","centerX":0.5,"centerY":0.5,"radiusX":1,"radiusY":1"#) throws -> GradientBackground {
        try decode(GradientBackground.self, #"{"stops":\#(stops)\#(rest)}"#)
    }
    func stop(_ position: String, _ color: String = FIXJ_ClampTests.white) -> String { #"{"position":\#(position),"color":\#(color)}"# }

    @Test func gradientStopsAreSortedClampedAndAtLeastTwo() throws {
        let g = try gradient("[\(stop("0.9")),\(stop("-4")),\(stop("0.4")),\(stop("77"))]")
        #expect(g.stops.map(\.position) == [0, 0.4, 0.9, 1])
        #expect(try gradient("[]").stops.count >= 2)
        let one = try gradient("[\(stop("0.3", #"{"red":0,"green":1,"blue":0,"alpha":1}"#))]")
        #expect(one.stops.count >= 2)
        #expect(one.stops.allSatisfy { $0.color.green == 1 })
        #expect(zip(one.stops, one.stops.dropFirst()).allSatisfy { $0.position <= $1.position })
    }

    @Test func gradientRadiiAreNeverZeroNegativeOrHuge() throws {
        for radii in [#","centerX":0.5,"centerY":0.5,"radiusX":0,"radiusY":0"#, #","centerX":0.5,"centerY":0.5,"radiusX":-3,"radiusY":-0.0001"#,
                      #","centerX":0.5,"centerY":0.5,"radiusX":1e12,"radiusY":1e12"#] {
            let g = try gradient("[\(stop("0")),\(stop("1"))]", radii)
            #expect(g.radiusX > 0 && g.radiusX <= 16 && g.radiusY > 0 && g.radiusY <= 16, "radii \(g.radiusX) \(g.radiusY)")
        }
        let far = try gradient("[\(stop("0")),\(stop("1"))]", #","centerX":1e9,"centerY":-1e9,"radiusX":1,"radiusY":1"#)
        #expect(abs(far.centerX) <= 8 && abs(far.centerY) <= 8)
    }

    @Test func aValidGradientIsUnchanged() throws {
        let g = Theme.fullScreen.mediaFallback
        let json = try JSONEncoder().encode(try #require(g))
        #expect(try JSONDecoder().decode(GradientBackground.self, from: json) == g)
    }

    // MARK: Plate and bar

    @Test func aPlateWithHostileValuesIsClamped() throws {
        let p = try decode(TextPlate.self, #"{"x":-5,"width":40,"bottomMargin":-9,"fill":{"red":0,"green":0,"blue":0,"alpha":12},"cornerRadius":-1,"paddingX":-30,"paddingY":1e12}"#)
        #expect(p.x == 0 && p.width == 1 && p.bottomMargin == 0 && p.fill.alpha == 1 && p.cornerRadius == 0 && p.paddingX == 0)
        #expect(p.paddingY <= 1000)
        let q = try decode(TextPlate.self, #"{"x":0,"width":0.5,"bottomMargin":1e12,"fill":\#(Self.white),"cornerRadius":1e12,"paddingX":1e12,"paddingY":0}"#)
        #expect(q.bottomMargin <= 2000 && q.cornerRadius <= 1000 && q.paddingX <= 1000)
    }

    @Test func anAccentBarWithHostileValuesIsClamped() throws {
        let b = try decode(AccentBar.self, #"{"width":-4,"gap":-8,"top":{"red":9,"green":0,"blue":0,"alpha":1},"bottom":\#(Self.white)}"#)
        #expect(b.width == 0 && b.gap == 0 && b.top.red == 1)
        let c = try decode(AccentBar.self, #"{"width":1e12,"gap":1e12,"top":\#(Self.white),"bottom":\#(Self.white)}"#)
        #expect(c.width <= 1000 && c.gap <= 1000)
    }

    @Test func aPlateWithABarDecodesAndEncodesAsBefore() throws {
        let p = try #require(Theme.lowerThird.plate)
        let json = try JSONEncoder().encode(p)
        #expect(try JSONDecoder().decode(TextPlate.self, from: json) == p)
    }

    // MARK: A whole theme

    @Test func aHostileThemeFromAStoredRowComesBackClamped() throws {
        let hostile = #"""
        {"id":"7E57F1A0-0000-4000-8000-0000000000F1","name":"Hostile",
         "background":{"gradient":{"_0":{"stops":[{"position":3,"color":\#(Self.white)}],"centerX":0.5,"centerY":0.5,"radiusX":0,"radiusY":0}}},
         "primary":{"style":{"fontName":"Inter","fontSize":40,"color":\#(Self.white),"outlineWidth":0,"outlineColor":\#(Self.white),"weight":99999,"lineHeight":1e9},
                    "frame":{"x":0,"y":0,"width":1,"height":1},"alignment":"center","verticalAlignment":"center"},
         "plate":{"x":0,"width":1,"bottomMargin":0,"fill":\#(Self.white),"cornerRadius":-5,"paddingX":0,"paddingY":0}}
        """#
        let t = try decode(Theme.self, hostile)
        #expect(t.primary.style.weight == 900 && (t.primary.style.lineHeight ?? 0) <= 4)
        #expect(t.plate?.cornerRadius == 0)
        if case .gradient(let g) = t.background { #expect(g.stops.count >= 2 && g.radiusX > 0 && g.radiusY > 0) } else { Issue.record("background decoded as \(t.background)") }
    }
}
