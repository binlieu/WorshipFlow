// FIX-J item 10 (UI-005h): the fill and key split, read and tested. A frame with a semi-transparent plate, antialiased plate edges and text over
// the plate, split in both alpha modes: the key is the frame's alpha, the fill is the colour in the mode asked for, both from the same frame, and
// keying the pair over any background gives back the picture the compositor drew. Implemented and Unit Tested only: no keyer has seen this.
import Testing
import Foundation
import Domain
import SDIEngine
@testable import RenderEngine

@Suite struct FIXJ_FillKeyTests {
    init() { #expect(UI005hFixtures.registerInter()) }

    static let width = 1920, height = 1080

    // MARK: Every premultiplied pixel, without a GPU

    @Test func everyPremultipliedPixelSplitsToTheRightFillAndKeyInBothModes() {
        // Every alpha with every colour value up to it (a premultiplied colour never exceeds its alpha), as 256 x 256 pixels of one frame.
        var bgra: [UInt8] = []
        for a in 0...255 { for c in 0...a { bgra += [UInt8(c), UInt8(c), UInt8(c), UInt8(a)] } }
        let pre = FillKeySplitter.split(bgra: bgra, fillAlphaMode: .premultiplied)
        let straight = FillKeySplitter.split(bgra: bgra, fillAlphaMode: .straight)
        var i = 0
        var worstRoundTrip = 0
        for a in 0...255 { for c in 0...a {
            // The key is the alpha as a grey level in B, G and R, and opaque.
            #expect(pre.key[i] == UInt8(a) && pre.key[i + 1] == UInt8(a) && pre.key[i + 2] == UInt8(a) && pre.key[i + 3] == 255)
            #expect(straight.key[i] == UInt8(a) && straight.key[i + 3] == 255)
            // The fill is opaque. Premultiplied: the colour as it is. Straight: the colour divided by alpha (rounded), zero where there is no alpha.
            #expect(pre.fill[i] == UInt8(c) && pre.fill[i + 3] == 255)
            let wantStraight = a == 0 ? 0 : min(255, (c * 255 + a / 2) / a)
            #expect(Int(straight.fill[i]) == wantStraight && straight.fill[i + 3] == 255, "a \(a) c \(c)")
            // Keying the straight fill with its key gives the colour back, to within one level.
            let back = Int((Double(straight.fill[i]) * Double(a) / 255).rounded())
            worstRoundTrip = max(worstRoundTrip, abs(back - c))
            i += 4
        } }
        #expect(worstRoundTrip <= 1, "straight fill keyed with its key is off by \(worstRoundTrip)")
    }

    // MARK: A real lower-third frame

    func lowerThird(_ slide: SlideContent = UI005hFixtures.lowerThirdSlide) throws -> RenderedFrame {
        let scene = SceneComposer.scene(for: .broadcast, state: UI005hFixtures.live(slide), theme: .lowerThird, look: .standard, props: [])
        return try Compositor().renderImage(scene: scene, width: Self.width, height: Self.height)
    }

    @Test func theSplitOfAPlateFrameIsTheSameFrameInBothModesAndEveryPixelIsConsistent() throws {
        let frame = try lowerThird()
        let pre = FillKeySplitter.split(bgra: frame.bgra, fillAlphaMode: .premultiplied)
        let straight = FillKeySplitter.split(bgra: frame.bgra, fillAlphaMode: .straight)
        #expect(pre.fill.count == frame.bgra.count && pre.key.count == frame.bgra.count && straight.fill.count == frame.bgra.count)
        var badKey = 0, badPre = 0, badStraight = 0, badOpaque = 0, badTransparent = 0, partial = 0, plateEdge = 0, textOnPlate = 0
        for p in 0..<(Self.width * Self.height) {
            let i = p * 4
            let a = Int(frame.bgra[i + 3])
            if pre.key[i] != frame.bgra[i + 3] || straight.key[i] != frame.bgra[i + 3] || pre.key[i + 1] != pre.key[i] || pre.key[i + 2] != pre.key[i] { badKey += 1 }
            if pre.fill[i + 3] != 255 || straight.fill[i + 3] != 255 || pre.key[i + 3] != 255 { badOpaque += 1 }
            for k in 0..<3 {
                if pre.fill[i + k] != frame.bgra[i + k] { badPre += 1 }
                let c = Int(frame.bgra[i + k])
                let back = Int((Double(straight.fill[i + k]) * Double(a) / 255).rounded())
                if abs(back - c) > 1 { badStraight += 1 }
            }
            if a == 0, (0..<3).contains(where: { pre.fill[i + $0] != 0 || straight.fill[i + $0] != 0 }) { badTransparent += 1 }
            if a > 0 && a < 255 { partial += 1 }
            if a >= 100 && a <= 219 { plateEdge += 1 }
            if a == 255 { textOnPlate += 1 }
        }
        #expect(badKey == 0 && badOpaque == 0 && badPre == 0 && badStraight == 0 && badTransparent == 0,
                "key \(badKey), opaque \(badOpaque), premultiplied fill \(badPre), straight fill \(badStraight), colour where no alpha \(badTransparent)")
        #expect(partial > 100_000, "the frame has a semi-transparent plate: \(partial) partly transparent pixels")
        #expect(plateEdge > 100_000 && textOnPlate > 3000)
    }

    @Test func plateInteriorEdgeAndTextHaveTheExpectedFillAndKeyValuesInBothModes() throws {
        let frame = try lowerThird()
        let pre = FillKeySplitter.split(bgra: frame.bgra, fillAlphaMode: .premultiplied)
        let straight = FillKeySplitter.split(bgra: frame.bgra, fillAlphaMode: .straight)
        func at(_ s: FillKeyFrames, _ x: Int, _ y: Int) -> (r: Int, g: Int, b: Int, key: Int) {
            let i = (y * Self.width + x) * 4
            return (Int(s.fill[i + 2]), Int(s.fill[i + 1]), Int(s.fill[i]), Int(s.key[i]))
        }
        // Plate interior: #071321 at 86 %. The key is 219 (the design's grey). Premultiplied fill: colour x 0.86. Straight fill: the plate's own colour.
        let inside = (x: 130, y: 800)
        let p = at(pre, inside.x, inside.y), s = at(straight, inside.x, inside.y)
        #expect(abs(p.key - 219) <= 1 && abs(s.key - 219) <= 1)
        #expect(abs(p.r - 6) <= 1 && abs(p.g - 16) <= 1 && abs(p.b - 28) <= 1, "premultiplied \(p)")
        #expect(abs(s.r - 7) <= 2 && abs(s.g - 19) <= 2 && abs(s.b - 33) <= 2, "straight \(s)")
        // Antialiased plate edge: the corner ring has partial key, and the straight fill there is still the plate's colour (not darker).
        var ring = 0, ringColourKept = 0
        for y in 774..<800 { for x in 115..<140 {
            let e = at(straight, x, y)
            if e.key > 20 && e.key < 200 { ring += 1; if abs(e.r - 7) <= 6 && abs(e.g - 19) <= 6 && abs(e.b - 33) <= 6 { ringColourKept += 1 } }
        } }
        #expect(ring >= 5 && ringColourKept >= ring * 8 / 10, "corner ring pixels \(ring), colour kept in \(ringColourKept)")
        // Text over the plate: white and opaque in both modes where the matte is full.
        var whiteBoth = 0, solid = 0
        for y in 810..<880 { for x in 211..<700 where at(pre, x, y).key == 255 {
            solid += 1
            let a = at(pre, x, y), b = at(straight, x, y)
            if a.r >= 252 && a.g >= 252 && a.b >= 252 && b.r >= 252 && b.g >= 252 && b.b >= 252 { whiteBoth += 1 }
        } }
        #expect(solid > 500 && whiteBoth == solid, "solid \(solid), white in both modes \(whiteBoth)")
        // Where the glyphs' antialiased edges meet the plate the key lies between the plate's and the text's, and the straight fill blends plate and white.
        var blended = 0
        for y in 810..<880 { for x in 211..<700 {
            let e = at(straight, x, y)
            if e.key > 225 && e.key < 252 && e.r > 20 && e.r < 235 { blended += 1 }
        } }
        #expect(blended > 100, "glyph edge pixels over the plate: \(blended)")
    }

    @Test func keyingTheSplitPairOverABackgroundGivesThePictureTheCompositorDrew() throws {
        let frame = try lowerThird()
        let pre = FillKeySplitter.split(bgra: frame.bgra, fillAlphaMode: .premultiplied)
        let straight = FillKeySplitter.split(bgra: frame.bgra, fillAlphaMode: .straight)
        // A receiving keyer over a background colour: premultiplied fill adds to the background's share; straight fill is scaled by the key first.
        for background in [(r: 0, g: 0, b: 0), (r: 200, g: 120, b: 40), (r: 255, g: 255, b: 255)] {
            let bg = [background.b, background.g, background.r]
            var worstPre = 0, worstStraight = 0
            var p = 0
            while p < Self.width * Self.height {
                let i = p * 4
                let a = Double(frame.bgra[i + 3]) / 255
                for k in 0..<3 {
                    // The compositor's own "over": premultiplied colour plus the background through the remaining alpha.
                    let direct = Double(frame.bgra[i + k]) + Double(bg[k]) * (1 - a)
                    let viaPre = Double(pre.fill[i + k]) + Double(bg[k]) * (1 - Double(pre.key[i]) / 255)
                    let viaStraight = Double(straight.fill[i + k]) * Double(straight.key[i]) / 255 + Double(bg[k]) * (1 - Double(straight.key[i]) / 255)
                    worstPre = max(worstPre, Int(abs(direct - viaPre).rounded()))
                    worstStraight = max(worstStraight, Int(abs(direct - viaStraight).rounded()))
                }
                p += 7      // every seventh pixel: the whole frame's variety, a seventh of the time
            }
            #expect(worstPre == 0, "premultiplied pair over \(background) differs by \(worstPre)")
            #expect(worstStraight <= 1, "straight pair over \(background) differs by \(worstStraight)")
        }
    }

    @Test func fillAndKeyOfOneFrameChangeTogetherWhenTheFrameChanges() throws {
        let a = try lowerThird(), b = try lowerThird(SlideContent(primary: "A different line on the plate", secondary: nil))
        let sa = FillKeySplitter.split(bgra: a.bgra, fillAlphaMode: .premultiplied), sb = FillKeySplitter.split(bgra: b.bgra, fillAlphaMode: .premultiplied)
        let fillChanged = sa.fill != sb.fill, keyChanged = sa.key != sb.key
        #expect(fillChanged && keyChanged, "a new frame changes both signals")
        // The same frame splits to the same pair, twice.
        let again = FillKeySplitter.split(bgra: a.bgra, fillAlphaMode: .premultiplied)
        let same = again == sa
        #expect(same)
    }

    @Test func aFrameWithNoWordsHasNothingInEitherSignal() throws {
        var state = ShowState()
        state.apply(.load(ShowDeck(presentationID: UUID(), slides: [SlideContent(primary: "")])))
        state.apply(.trigger(index: 0))
        let scene = SceneComposer.scene(for: .broadcast, state: state, theme: .lowerThird, look: .standard, props: [])
        let frame = try Compositor().renderImage(scene: scene, width: 640, height: 360)
        for mode in [AlphaMode.premultiplied, .straight] {
            let s = FillKeySplitter.split(bgra: frame.bgra, fillAlphaMode: mode)
            let emptyKey = !s.key.enumerated().contains { $0.offset % 4 != 3 && $0.element != 0 }
            let emptyFill = !s.fill.enumerated().contains { $0.offset % 4 != 3 && $0.element != 0 }
            #expect(emptyKey && emptyFill, "no words, no plate: nothing keyed in \(mode)")
        }
    }
}
