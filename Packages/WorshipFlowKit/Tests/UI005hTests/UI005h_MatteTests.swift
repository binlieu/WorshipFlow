// UI-005h item 3, the risky part: the key matte of a lower third with a plate. The matte is the alpha of the composed frame, so the
// plate's shape and opacity, the bar and the text over the plate must all be in that alpha, the same size and position as the fill,
// with premultiplied and straight alpha both right. These are pure tests of rendered pixels and of FillKeySplitter: Implemented and
// Unit Tested. No keyer, ATEM or SDI signal has seen this picture.
import Testing
import Foundation
import Domain
import SDIEngine
@testable import RenderEngine

@Suite struct UI005h_MatteTests {
    static let width = 1920, height = 1080
    // The plate's pixel rectangle at 1920 x 1080 (x 115.2..1804.8, y 773.66..984): whole pixels, so its straight edges are crisp.
    static let plate = (left: 115, top: 774, right: 1805, bottom: 984)
    static let bar = (left: 161, top: 804, right: 173, bottom: 953)     // 161.28 .. 172.8, 804.38 .. 953.28

    let compositor: Compositor
    let frame: RenderedFrame
    init() throws {
        #expect(UI005hFixtures.registerInter())
        compositor = try Compositor()
        frame = try Self.render(UI005hFixtures.lowerThirdSlide, compositor: compositor)
    }

    static func render(_ slide: SlideContent, theme: Theme = .lowerThird, compositor: Compositor) throws -> RenderedFrame {
        let scene = SceneComposer.scene(for: .broadcast, state: UI005hFixtures.live(slide), theme: theme, look: .standard, props: [])
        return try compositor.renderImage(scene: scene, width: width, height: height)
    }
    func a(_ x: Int, _ y: Int, _ f: RenderedFrame? = nil) -> Int { Int((f ?? frame).pixel(x: x, y: y).alpha) }

    // MARK: Plate interior, edge, outside

    @Test func thePlateInteriorHasThePlatesOpacityInTheMatte() {
        // Left of the bar, right of the text, between the lines' margins: nothing but plate. 86 % of 255 = 219 = #dbdbdb, the design's grey.
        for (x, y) in [(130, 800), (130, 960), (1700, 800), (1700, 960), (1500, 880), (1790, 779)] {
            #expect(abs(a(x, y) - 219) <= 1, "alpha at \(x),\(y) = \(a(x, y))")
        }
        let key = FillKeySplitter.split(bgra: frame.bgra, fillAlphaMode: .premultiplied).key
        let i = (800 * Self.width + 130) * 4
        #expect(abs(Int(key[i]) - 219) <= 1 && key[i] == key[i + 1] && key[i + 1] == key[i + 2] && key[i + 3] == 255)   // grey in B, G and R, opaque
    }

    @Test func nothingOutsideThePlateIsInTheMatte() {
        let outside = [(0, 0), (1919, 1079), (1919, 0), (0, 1079), (960, 300), (960, 700), (50, 900), (100, 880), (1810, 880), (1900, 900),
                       (960, 1040), (960, 1079), (960, 770), (115, 773), (1805, 984)]
        for (x, y) in outside { #expect(a(x, y) == 0, "alpha at \(x),\(y) = \(a(x, y))") }
        var bounds = (minX: Self.width, minY: Self.height, maxX: -1, maxY: -1)
        for y in 0..<Self.height { for x in 0..<Self.width where a(x, y) != 0 {
            bounds = (min(bounds.minX, x), min(bounds.minY, y), max(bounds.maxX, x), max(bounds.maxY, y))
        } }
        #expect(bounds.minX >= Self.plate.left && bounds.maxX < Self.plate.right && bounds.minY >= Self.plate.top && bounds.maxY < Self.plate.bottom, "bounds \(bounds)")
        #expect(bounds.minX == Self.plate.left && bounds.maxX == Self.plate.right - 1 && bounds.minY == Self.plate.top && bounds.maxY == Self.plate.bottom - 1, "bounds \(bounds)")
    }

    @Test func theStraightEdgesAreCrispAndTheRoundedCornersAreAntialiased() {
        // Straight edges sit on whole pixels: full plate opacity on the inside row, nothing on the outside row.
        #expect(abs(a(500, Self.plate.top) - 219) <= 1 && a(500, Self.plate.top - 1) == 0)
        #expect(abs(a(500, Self.plate.bottom - 1) - 219) <= 1 && a(500, Self.plate.bottom) == 0)
        #expect(abs(a(Self.plate.left, 880) - 219) <= 1 && a(Self.plate.left - 1, 880) == 0)
        #expect(abs(a(Self.plate.right - 1, 880) - 219) <= 1 && a(Self.plate.right, 880) == 0)
        // Each corner (radius 19.2 px) has a ring of partial coverage and a nearly empty outer corner pixel.
        let corners = [(Self.plate.left, Self.plate.top, 1, 1), (Self.plate.right - 1, Self.plate.top, -1, 1),
                       (Self.plate.left, Self.plate.bottom - 1, 1, -1), (Self.plate.right - 1, Self.plate.bottom - 1, -1, -1)]
        for (cx, cy, dx, dy) in corners {
            #expect(a(cx, cy) < 40, "corner pixel \(cx),\(cy) = \(a(cx, cy))")
            var partial = 0, full = 0
            for j in 0..<21 { for i in 0..<21 {
                let v = a(cx + dx * i, cy + dy * j)
                if v > 8 && v < 211 { partial += 1 } else if abs(v - 219) <= 1 { full += 1 }
            } }
            #expect(partial >= 10 && partial <= 60 && full > 200, "corner \(cx),\(cy): partial \(partial), full \(full)")
            // Coverage grows from the corner along the top edge to the full opacity, never the other way.
            var last = -1
            for i in 0..<24 { let v = a(cx + dx * i, cy); #expect(v >= last - 1, "row not monotonic at \(i): \(v) after \(last)"); last = v }
            #expect(abs(last - 219) <= 1)
        }
    }

    // MARK: Text over the plate, and the bar

    @Test func textOverThePlateIsOpaqueInTheMatteAndWhiteInTheFill() {
        let key = FillKeySplitter.split(bgra: frame.bgra, fillAlphaMode: .premultiplied)
        var solid = 0, edge = 0, whiteSolid = 0
        for y in 810..<880 { for x in 211..<1320 {
            let v = a(x, y)
            if v == 255 { solid += 1; let i = (y * Self.width + x) * 4; if key.fill[i] >= 252 && key.fill[i + 1] >= 252 && key.fill[i + 2] >= 252 { whiteSolid += 1 } }
            else if v > 222 && v < 253 { edge += 1 }
        } }
        #expect(solid > 2000 && whiteSolid == solid, "solid \(solid), white \(whiteSolid)")       // the glyphs' inner pixels: matte 255
        #expect(edge > 200, "edge pixels \(edge)")                                               // antialiased glyph edges lie between the plate and white
        // Between the glyphs it is still the plate: the pixel just right of the text block's last line.
        #expect(abs(a(1600, 840) - 219) <= 1)
        // The second language is yellow in the fill and opaque in the matte, over the same plate.
        var yellow = 0
        for y in 890..<950 { for x in 211..<800 where a(x, y) == 255 {
            let i = (y * Self.width + x) * 4
            if abs(Int(key.fill[i]) - 123) <= 2 && abs(Int(key.fill[i + 1]) - 209) <= 2 && abs(Int(key.fill[i + 2]) - 255) <= 2 { yellow += 1 }
        } }
        #expect(yellow > 500, "yellow pixels \(yellow)")
    }

    @Test func theAccentBarIsOpaqueAndAGradientInTheFillAndWhiteInTheMatte() {
        let key = FillKeySplitter.split(bgra: frame.bgra, fillAlphaMode: .premultiplied)
        func fill(_ x: Int, _ y: Int) -> (r: Int, g: Int, b: Int) { let i = (y * Self.width + x) * 4; return (Int(key.fill[i + 2]), Int(key.fill[i + 1]), Int(key.fill[i])) }
        for y in [815, 880, 940] { #expect(a(167, y) == 255 && Int(key.key[(y * Self.width + 167) * 4]) == 255, "bar matte at \(y)") }
        // #42d9b8 at the top, #4d99ed at the bottom, a straight blend between.
        let top = fill(167, 812), bottom = fill(167, 946), middle = fill(167, 879)
        #expect(abs(top.r - 0x42) <= 10 && abs(top.g - 0xd9) <= 10 && abs(top.b - 0xb8) <= 10, "top \(top)")
        #expect(abs(bottom.r - 0x4d) <= 10 && abs(bottom.g - 0x99) <= 10 && abs(bottom.b - 0xed) <= 10, "bottom \(bottom)")
        #expect(abs(middle.g - (0xd9 + 0x99) / 2) <= 12 && middle.g < top.g && middle.g > bottom.g)
        // The bar's rounded ends are antialiased against the plate, and nothing of it leaks left of it or right of it.
        #expect(abs(a(Self.bar.left - 1, 880) - 219) <= 1 && abs(a(Self.bar.right, 880) - 219) <= 1)
        #expect(a(Self.bar.left, 880) == 255 && a(Self.bar.right - 1, 880) == 255)
    }

    // MARK: Fill and key stay the same size and position

    @Test func fillAndKeyAreTheSameSizeAndPositionFrameForFrame() throws {
        let slides = [UI005hFixtures.lowerThirdSlide, SlideContent(primary: "Only English"), UI005hFixtures.sampleSlide,
                      SlideContent(primary: String(repeating: "Amazing grace how sweet the sound ", count: 6), secondary: "\u{1EB4}")]
        for slide in slides {
            let f = try Self.render(slide, compositor: compositor)
            let split = FillKeySplitter.split(bgra: f.bgra, fillAlphaMode: .premultiplied)
            #expect(split.fill.count == f.bgra.count && split.key.count == f.bgra.count)
            var fillBox = (minX: Int.max, minY: Int.max, maxX: -1, maxY: -1), keyBox = fillBox
            var mismatch = 0
            for y in 0..<Self.height { for x in 0..<Self.width {
                let i = (y * Self.width + x) * 4
                if split.key[i] != f.bgra[i + 3] { mismatch += 1 }                              // the key is the frame's alpha, pixel for pixel
                if split.fill[i] != 0 || split.fill[i + 1] != 0 || split.fill[i + 2] != 0 { fillBox = (min(fillBox.minX, x), min(fillBox.minY, y), max(fillBox.maxX, x), max(fillBox.maxY, y)) }
                if split.key[i] != 0 { keyBox = (min(keyBox.minX, x), min(keyBox.minY, y), max(keyBox.maxX, x), max(keyBox.maxY, y)) }
            } }
            #expect(mismatch == 0)
            #expect(fillBox == keyBox, "fill \(fillBox) key \(keyBox)")                          // the colour exists exactly where the matte does
            #expect(keyBox.minX == Self.plate.left && keyBox.maxX == Self.plate.right - 1 && keyBox.maxY == Self.plate.bottom - 1)
        }
        let again = try Self.render(UI005hFixtures.lowerThirdSlide, compositor: compositor)
        #expect(again.bgra == frame.bgra)                                      // the same slide gives the same frame, twice
    }

    // MARK: Premultiplied and straight alpha

    @Test func premultipliedAndStraightFillsBothCarryThePlatesColour() {
        let pre = FillKeySplitter.split(bgra: frame.bgra, fillAlphaMode: .premultiplied)
        let straight = FillKeySplitter.split(bgra: frame.bgra, fillAlphaMode: .straight)
        let i = (800 * Self.width + 130) * 4
        // Premultiplied: the plate's colour times 0.86 (#071321 -> 6, 16, 28). Straight: the plate's own colour back (7, 19, 33).
        #expect(abs(Int(pre.fill[i + 2]) - 6) <= 1 && abs(Int(pre.fill[i + 1]) - 16) <= 1 && abs(Int(pre.fill[i]) - 28) <= 1)
        #expect(abs(Int(straight.fill[i + 2]) - 7) <= 2 && abs(Int(straight.fill[i + 1]) - 19) <= 2 && abs(Int(straight.fill[i]) - 33) <= 2)
        #expect(pre.key == straight.key)                                                          // the matte does not depend on the fill's mode
        // Straight keeps white text white and yellow text yellow, over the plate; and antialiased plate pixels keep the plate colour.
        var checked = 0
        for y in 774..<984 { for x in 115..<400 {
            let alpha = a(x, y); guard alpha >= 100 && alpha <= 219 else { continue }
            let j = (y * Self.width + x) * 4
            if abs(Int(straight.fill[j + 2]) - 7) <= 4 && abs(Int(straight.fill[j + 1]) - 19) <= 4 && abs(Int(straight.fill[j]) - 33) <= 4 { checked += 1 }
        } }
        #expect(checked > 30, "plate-coloured partial pixels \(checked)")
        var whiteSeen = false
        for y in 820..<880 { for x in 211..<400 where a(x, y) == 255 { let j = (y * Self.width + x) * 4; if straight.fill[j] == 255 && straight.fill[j + 1] == 255 && straight.fill[j + 2] == 255 { whiteSeen = true } } }
        #expect(whiteSeen)
    }

    // MARK: A lower third without a plate keeps the matte it always had

    @Test func aThemeWithoutAPlateKeepsTheGlyphOnlyMatte() throws {
        let f = try Self.render(UI005hFixtures.lowerThirdSlide, theme: UI005hFixtures.userThemes[2], compositor: compositor)
        #expect(a(130, 800, f) == 0 && a(1700, 960, f) == 0 && a(960, 300, f) == 0)           // no plate: nothing but the glyphs and their outline
        var ink = 0
        for y in 0..<Self.height { for x in 0..<Self.width where a(x, y, f) != 0 { ink += 1 } }
        #expect(ink > 3000 && ink < 200_000)
    }
}
