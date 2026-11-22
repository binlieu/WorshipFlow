// FIX-T item 1 (SYS): a stored or imported text style with an absurd number (a program package's theme, a hand-edited library) reaches the render
// thread. The bitmap padding converted it to an Int and trapped; a style is now held to sane sizes when it is made or decoded, and the padding is total.
import Testing
import Foundation
import Domain
@testable import RenderEngine

@Suite struct FIXT_TextStyleNumbersTests {
    private let white = ColorRGBA(red: 1, green: 1, blue: 1, alpha: 1)

    @Test func aStyleDecodedWithAnAbsurdSizeIsHeldToASaneOne() throws {
        let good = TextStyle(fontName: "Helvetica", fontSize: 48, color: white)
        var json = try #require(try JSONSerialization.jsonObject(with: JSONEncoder().encode(good)) as? [String: Any])
        for bad in [1e300, -1e300, 1e19] {
            json["fontSize"] = bad
            json["outlineWidth"] = bad
            let style = try JSONDecoder().decode(TextStyle.self, from: JSONSerialization.data(withJSONObject: json))
            #expect(style.fontSize >= 0 && style.fontSize <= TextStyle.largestFontSize)
            #expect(style.outlineWidth >= 0 && style.outlineWidth <= TextStyle.largestFontSize)
            _ = TextRasterizer.padding(for: style)
        }
    }

    @Test func thePaddingOfAnAbsurdStyleDoesNotTrap() {
        var style = TextStyle(fontName: "Helvetica", fontSize: 48, color: white)
        let awkward: [Double] = [.nan, .infinity, -.infinity, 1e300, -1e300]
        for v in awkward {
            style.fontSize = v
            style.outlineWidth = v
            style.shadow = TextShadow(offsetX: v, offsetY: v, blur: v)
            let p = TextRasterizer.padding(for: style)
            #expect(p.x >= 0 && p.y >= 0)
        }
    }

    @Test func anOrdinaryStyleIsNotChanged() {
        let style = TextStyle(fontName: "Helvetica", fontSize: 96, color: white, outlineWidth: 4)
        #expect(style.fontSize == 96 && style.outlineWidth == 4)
        let p = TextRasterizer.padding(for: style)
        #expect(p.x == Int((4 + 96 * 0.12 + 2).rounded(.up)) && p.y == Int((4 + 96 * 0.45 + 2).rounded(.up)))
    }
}
