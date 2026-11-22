// UI-005h (OUT, KEY, STAGE): the built-in looks carry the numbers of docs/UI/mockups/07-output-looks.html, measured with
// scripts/design-rects at 1920 x 1080 (a panel's cqw is its content width / 100: the stage has 4 % padding, so its cqw is 17.664 px).
// Sizes in points at the 1080-line reference height, which is the output's own pixels at 1920 x 1080.
import Testing
import Foundation
import Domain

enum D {
    static let w = 1920.0, h = 1080.0
    static func rgb(_ r: Int, _ g: Int, _ b: Int, _ a: Double = 1) -> ColorRGBA { ColorRGBA(red: Double(r) / 255, green: Double(g) / 255, blue: Double(b) / 255, alpha: a) }
    static let yellow = rgb(255, 209, 123)          // #ffd17b
    static let muted = rgb(159, 178, 199)           // #9fb2c7
    static let cyan = rgb(73, 211, 195)             // #49d3c3
    static let onBrand = rgb(6, 33, 56)             // #062138
    static let plate = rgb(7, 19, 33, 0.86)
    static func near(_ a: Double, _ b: Double, _ tolerance: Double = 0.01) -> Bool { abs(a - b) <= tolerance }
    static func same(_ a: ColorRGBA, _ b: ColorRGBA, _ tolerance: Double = 0.003) -> Bool {
        near(a.red, b.red, tolerance) && near(a.green, b.green, tolerance) && near(a.blue, b.blue, tolerance) && near(a.alpha, b.alpha, tolerance)
    }
}

@Suite struct UI005h_DesignNumbersTests {
    // MARK: Audience

    @Test func theAudienceThemeIsTheDesignsFullScreenLyrics() throws {
        let t = Theme.fullScreen
        #expect(t.id == Theme.fullScreenID && t.name == "Full screen")
        #expect(t.background == .media)                      // the shared loop still plays over the gradient, as before
        let g = try #require(t.mediaFallback)                // radial-gradient(110% 100% at 80% 90%, #2d7d6c 0, #123b52 50%, #050f1c 100%)
        #expect(g.stops.map(\.position) == [0, 0.5, 1])
        #expect(D.same(g.stops[0].color, D.rgb(0x2d, 0x7d, 0x6c)) && D.same(g.stops[1].color, D.rgb(0x12, 0x3b, 0x52)) && D.same(g.stops[2].color, D.rgb(0x05, 0x0f, 0x1c)))
        #expect(D.near(g.centerX, 0.8) && D.near(g.centerY, 0.9) && D.near(g.radiusX, 1.1) && D.near(g.radiusY, 1.0))

        let p = t.primary.style
        #expect(p.fontName == "InterVariable" && D.near(p.fontSize, 119.04) && p.weight == 600 && p.lineHeight == 1.2)
        #expect(p.opticalSize == 14 && p.fontFeatures == ["cv11"])     // the pictures show Inter's text cut with the single-storey a
        #expect(D.same(p.color, .white) && p.outlineWidth == 0)
        let shadow = try #require(p.shadow)                  // 0 .3cqw 1.2cqw rgba(0,0,0,.6)
        #expect(D.near(shadow.offsetX, 0) && D.near(shadow.offsetY, 5.76) && D.near(shadow.blur, 23.04) && D.near(shadow.color.alpha, 0.6) && shadow.color.red == 0)
        let s = try #require(t.secondary).style
        #expect(s.fontName == "InterVariable" && D.near(s.fontSize, 78.72) && s.weight == 500 && s.lineHeight == 1.3)
        #expect(D.same(s.color, D.yellow) && s.outlineWidth == 0 && s.shadow == shadow)
        #expect(t.primary.alignment == .center && t.secondary?.alignment == .center)
        // The two blocks are one group centred on the frame: primary line boxes end at 547.85, 65.28 below them the second language starts.
        // Both frames are 90 % wide (the title-safe area).
        #expect(D.near(t.primary.frame.x, 0.05) && D.near(t.primary.frame.width, 0.9))
        #expect(D.near((t.primary.frame.y + t.primary.frame.height) * D.h, 547.85, 0.2))
        #expect(D.near((t.secondary?.frame.y ?? 0) * D.h, 613.13, 0.2))
        #expect(t.primary.verticalAlignment == .bottom && t.secondary?.verticalAlignment == .top)
        #expect(t.plate == nil)
    }

    // MARK: Lower third

    @Test func theLowerThirdThemeIsTheDesignsPlateAndBar() throws {
        let t = Theme.lowerThird
        #expect(t.id == Theme.lowerThirdID && t.name == "Lower third" && t.background == .transparent)
        let plate = try #require(t.plate)
        #expect(D.near(plate.x, 0.06) && D.near(plate.width, 0.88))      // 6 % .. 94 %
        #expect(D.near(plate.bottomMargin, 96))                           // padding-bottom 5 % of the width
        #expect(D.same(plate.fill, D.plate) && D.near(plate.cornerRadius, 19.2))
        #expect(D.near(plate.paddingX, 46.08) && D.near(plate.paddingY, 30.72))   // 2.4cqw, 1.6cqw
        let bar = try #require(plate.bar)
        #expect(D.near(bar.width, 11.52) && D.near(bar.gap, 38.4))        // .6cqw, a 2cqw gap
        #expect(D.same(bar.top, D.rgb(0x42, 0xd9, 0xb8)) && D.same(bar.bottom, D.rgb(0x4d, 0x99, 0xed)))
        #expect(bar.top.alpha == 1 && bar.bottom.alpha == 1)              // the bar is opaque: it is white in the key
        let p = t.primary.style, s = try #require(t.secondary).style
        #expect(p.fontName == "InterVariable" && D.near(p.fontSize, 67.2) && p.weight == 600 && p.lineHeight == 1.25 && D.same(p.color, .white))
        #expect(s.fontName == "InterVariable" && D.near(s.fontSize, 49.92) && s.weight == 500 && s.lineHeight == 1.3 && D.same(s.color, D.yellow))
        #expect(p.outlineWidth == 0 && s.outlineWidth == 0 && p.shadow == nil && s.shadow == nil)   // the plate gives the contrast
        #expect(t.primary.alignment == .leading && t.secondary?.alignment == .leading)
        #expect(t.primary.frame.y >= 0.6)
    }

    @Test func theClassicThemesAreTheLooksBeforeThisSlide() throws {
        let c = Theme.classicFullScreen, l = Theme.classicLowerThird
        #expect(c.id == Theme.classicFullScreenID && l.id == Theme.classicLowerThirdID)
        #expect(Set([c.id, l.id, Theme.fullScreenID, Theme.lowerThirdID]).count == 4)
        #expect(c.name == "Classic full screen" && l.name == "Classic lower third")
        #expect(Theme.classic == [c, l] && !Theme.builtIn.contains(c) && !Theme.builtIn.contains(l))
        #expect(c.background == .media && c.mediaFallback == nil && c.plate == nil)
        #expect(c.primary.style == TextStyle(fontName: "Helvetica Neue", fontSize: 84, color: .white, outlineWidth: 4, outlineColor: .black))
        #expect(c.secondary?.style == TextStyle(fontName: "Helvetica Neue", fontSize: 64, color: ColorRGBA(red: 1, green: 0.86, blue: 0.4), outlineWidth: 3, outlineColor: .black))
        #expect(c.primary.frame == NormalizedRect(x: 0.06, y: 0.18, width: 0.88, height: 0.32) && c.secondary?.frame == NormalizedRect(x: 0.06, y: 0.52, width: 0.88, height: 0.28))
        #expect(l.background == .transparent && l.plate == nil)
        #expect(l.primary.style == TextStyle(fontName: "Helvetica Neue", fontSize: 60, color: .white, outlineWidth: 3, outlineColor: .black))
        #expect(l.secondary?.style == TextStyle(fontName: "Helvetica Neue", fontSize: 44, color: ColorRGBA(red: 1, green: 0.86, blue: 0.4), outlineWidth: 2, outlineColor: .black))
        #expect(l.primary.alignment == .center && l.primary.verticalAlignment == .bottom)
    }

    // MARK: Old definitions stay old

    @Test func aThemeSavedBeforeTheNewFieldsDecodesAsTheOldLookAndEncodesAsBefore() throws {
        // What the store held for a church's theme at schema v12 (sorted keys, no weight, no plate, no gradient).
        let stored = #"{"background":{"color":{"_0":{"alpha":1,"blue":0.4,"green":0.12,"red":0.05}}},"id":"7E57F1A0-0000-4000-8000-000000000001","name":"Sunday blue","primary":{"alignment":"center","frame":{"height":0.35,"width":0.9,"x":0.05,"y":0.15},"style":{"color":{"alpha":1,"blue":1,"green":1,"red":1},"fontName":"Helvetica Neue","fontSize":90,"outlineColor":{"alpha":1,"blue":0,"green":0,"red":0},"outlineWidth":5},"verticalAlignment":"bottom"}}"#
        let decoded = try JSONDecoder().decode(Theme.self, from: Data(stored.utf8))
        #expect(decoded.primary.style.weight == nil && decoded.primary.style.lineHeight == nil && decoded.primary.style.letterSpacing == nil)
        #expect(decoded.plate == nil && decoded.mediaFallback == nil && decoded.secondary == nil)
        let encoder = JSONEncoder(); encoder.outputFormatting = [.sortedKeys]
        let text = String(decoding: try encoder.encode(decoded), as: UTF8.self)
        for key in ["weight", "lineHeight", "letterSpacing", "plate", "mediaFallback", "inPlate", "gradient"] { #expect(!text.contains("\"\(key)\"")) }
        #expect(try JSONDecoder().decode(Theme.self, from: Data(text.utf8)) == decoded)
    }

    @Test func aStageLayoutSavedBeforeTheNewFieldsDecodesWithoutThem() throws {
        let element = StageElement(id: UUID(), kind: .currentSlide, frame: NormalizedRect(x: 0.04, y: 0.08, width: 0.92, height: 0.5),
                                   style: TextStyle(fontName: "Helvetica Neue", fontSize: 96, color: .white), alignment: .leading)
        let layout = StageLayout(id: UUID(), name: "Mine", background: ColorRGBA(red: 0.02, green: 0.02, blue: 0.02), elements: [element])
        let encoder = JSONEncoder(); encoder.outputFormatting = [.sortedKeys]
        let text = String(decoding: try encoder.encode(layout), as: UTF8.self)
        for key in ["secondLanguage", "label", "messageBand", "weight", "lineHeight"] { #expect(!text.contains("\"\(key)\"")) }
        let back = try JSONDecoder().decode(StageLayout.self, from: Data(text.utf8))
        #expect(back == layout && back.messageBand == nil && back.elements[0].secondLanguage == nil && back.elements[0].label == nil)
    }
}
