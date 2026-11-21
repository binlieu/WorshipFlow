// HWTEST-001: deterministic test patterns and the decoders that read them back from a captured frame.
import Testing
import Foundation
@testable import SDIEngine

@Suite struct HWTEST_PatternTests {
    private func px(_ f: SDIFrame, _ x: Int, _ y: Int) -> [UInt8] {
        let i = (y * f.width + x) * 4
        return Array(f.bgra[i..<(i + 4)])
    }

    /// 8-bit studio-range BT.709 4:2:2 and back, which is what an SDI path does to a picture.
    private func yuvRoundTrip(_ f: SDIFrame) -> SDIFrame {
        var out = f.bgra
        let w = f.width, h = f.height
        func clamp(_ v: Double) -> UInt8 { UInt8(max(0, min(255, v.rounded()))) }
        for y in 0..<h {
            var x = 0
            while x < w {
                var ys = [UInt8](repeating: 0, count: 2), cbs = 0.0, crs = 0.0
                for k in 0..<2 {
                    let i = (y * w + min(x + k, w - 1)) * 4
                    let b = Double(f.bgra[i]), g = Double(f.bgra[i + 1]), r = Double(f.bgra[i + 2])
                    ys[k] = clamp(16 + (0.2126 * r + 0.7152 * g + 0.0722 * b) * 219 / 255)
                    cbs += 128 + (-0.1146 * r - 0.3854 * g + 0.5 * b) * 224 / 255
                    crs += 128 + (0.5 * r - 0.4542 * g - 0.0458 * b) * 224 / 255
                }
                let cb = clamp(cbs / 2), cr = clamp(crs / 2)
                for k in 0..<2 where x + k < w {
                    let yy = (Double(ys[k]) - 16) * 255 / 219, u = (Double(cb) - 128) * 255 / 224, v = (Double(cr) - 128) * 255 / 224
                    let i = (y * w + x + k) * 4
                    out[i] = clamp(yy + 1.8556 * u)
                    out[i + 1] = clamp(yy - 0.1873 * u - 0.4681 * v)
                    out[i + 2] = clamp(yy + 1.5748 * v)
                    out[i + 3] = 255
                }
                x += 2
            }
        }
        return SDIFrame(width: w, height: h, bgra: out)
    }

    // MARK: colour bars

    @Test func colourBarsAreOpaqueEightBarsAndRepeatable() {
        let a = TestPattern.colorBars(width: 160, height: 90), b = TestPattern.colorBars(width: 160, height: 90)
        #expect(a == b)
        #expect(a.bgra.count == 160 * 90 * 4)
        #expect(stride(from: 3, to: a.bgra.count, by: 4).allSatisfy { a.bgra[$0] == 255 })
        let colours = (0..<8).map { px(a, $0 * 20 + 10, 5) }
        #expect(Set(colours.map { $0 }).count == 8)
        #expect(colours[0] == [191, 191, 191, 255])        // white at 75 %
        #expect(colours[7] == [0, 0, 0, 255])              // black
        #expect(colours[5] == [0, 0, 191, 255])            // red: BGRA order
    }

    // MARK: frame counter

    @Test func theFrameIndexRoundTrips() {
        for index: Int64 in [0, 1, 2, 59, 60, 1001, 12_345, 3_599_999, 2_147_483_647, 4_294_967_295] {
            let f = TestPattern.frameCounter(index: index, width: 320, height: 180)
            #expect(TestPattern.decodeFrameIndex(from: f) == index, "index \(index)")
        }
    }

    @Test func theCounterRidesOnColourBarsAtFullSize() {
        let f = TestPattern.colorBarsWithCounter(index: 987_654, width: 1920, height: 1080)
        #expect(TestPattern.decodeFrameIndex(from: f) == 987_654)
        #expect(px(f, 100, 100) == px(TestPattern.colorBars(width: 1920, height: 1080), 100, 100))   // bars untouched above the strip
    }

    @Test func aCounterSourceMakesTheSameFramesAsTheGenerators() {
        let source = CounterFrameSource(width: 320, height: 180)
        #expect(source.frame(index: 7) == TestPattern.colorBarsWithCounter(index: 7, width: 320, height: 180))
        #expect(TestPattern.decodeFrameIndex(from: source.frame(index: 4242)) == 4242)
    }

    @Test func theCounterSurvivesYUVConversion() {
        for index: Int64 in [0, 5, 1_000_003] {
            let f = yuvRoundTrip(TestPattern.colorBarsWithCounter(index: index, width: 320, height: 180))
            #expect(TestPattern.decodeFrameIndex(from: f) == index)
        }
    }

    @Test func theCounterSurvivesLevelShiftsNoiseAndAShift() {
        let base = TestPattern.colorBarsWithCounter(index: 31_337, width: 320, height: 180)
        for delta in [-40, -12, 12, 40] {
            var f = base
            f.bgra = base.bgra.enumerated().map { $0.offset % 4 == 3 ? $0.element : UInt8(max(0, min(255, Int($0.element) + delta))) }
            #expect(TestPattern.decodeFrameIndex(from: f) == 31_337, "level shift \(delta)")
        }
        var noisy = base
        var seed: UInt32 = 12345
        noisy.bgra = base.bgra.enumerated().map { item in
            seed = seed &* 1_664_525 &+ 1_013_904_223
            guard item.offset % 4 != 3 else { return item.element }
            return UInt8(max(0, min(255, Int(item.element) + Int(seed >> 28) - 8)))
        }
        #expect(TestPattern.decodeFrameIndex(from: noisy) == 31_337)
        // one pixel to the right, as the simulator's fault does
        var shifted = base.bgra
        let row = 320 * 4
        for y in 0..<180 { for i in stride(from: row - 1, through: 4, by: -1) { shifted[y * row + i] = base.bgra[y * row + i - 4] } }
        #expect(TestPattern.decodeFrameIndex(from: SDIFrame(width: 320, height: 180, bgra: shifted)) == 31_337)
    }

    @Test func framesWithoutACounterDecodeToNil() {
        #expect(TestPattern.decodeFrameIndex(from: TestPattern.colorBars(width: 320, height: 180)) == nil)
        #expect(TestPattern.decodeFrameIndex(from: SDIFrame(width: 320, height: 180, bgra: [UInt8](repeating: 0, count: 320 * 180 * 4))) == nil)
        #expect(TestPattern.decodeFrameIndex(from: SDIFrame(width: 320, height: 180, bgra: [UInt8](repeating: 255, count: 320 * 180 * 4))) == nil)
        #expect(TestPattern.decodeFrameIndex(from: SDIFrame(width: 4, height: 2, bgra: [UInt8](repeating: 0, count: 32))) == nil)
    }

    @Test func aDamagedCellFailsTheCheck() {
        var f = TestPattern.frameCounter(index: 77, width: 320, height: 180)
        // invert the first data cell (bit 31) completely
        let cell = 320 / TestPattern.counterCells
        let top = 180 - TestPattern.counterStripHeight(forHeight: 180)
        for y in top..<180 { for x in 0..<cell {
            let i = (y * 320 + x) * 4
            let v: UInt8 = f.bgra[i] > 128 ? 0 : 255
            f.bgra[i] = v; f.bgra[i + 1] = v; f.bgra[i + 2] = v
        } }
        #expect(TestPattern.decodeFrameIndex(from: f) == nil)
    }

    // MARK: alpha patterns (premultiplied BGRA)

    @Test func theAlphaWindowHasAnOpaqueBoxAHalfBoxAndATransparentSurround() {
        let f = TestPattern.alphaWindow(width: 200, height: 100)
        let r = TestPattern.alphaWindowRegions(width: 200, height: 100)
        #expect(px(f, r.opaque.centerX, r.opaque.centerY) == [0, 128, 255, 255])      // orange, opaque
        #expect(px(f, r.half.centerX, r.half.centerY) == [128, 128, 128, 128])        // white at 50 %, premultiplied
        #expect(px(f, 1, 1) == [0, 0, 0, 0])
        #expect(px(f, 199, 99) == [0, 0, 0, 0])
        #expect(r.opaque.x + r.opaque.width <= r.half.x)                              // the boxes do not overlap
    }

    @Test func theAlphaRampRisesFromZeroTo255() {
        let f = TestPattern.alphaRamp(width: 256, height: 8)
        let alphas = (0..<256).map { px(f, $0, 3)[3] }
        #expect(alphas.first == 0 && alphas.last == 255)
        #expect(zip(alphas, alphas.dropFirst()).allSatisfy { $0 <= $1 })
        #expect(px(f, 100, 0) == [100, 100, 100, 100])                                // premultiplied white
        #expect(px(f, 100, 7) == px(f, 100, 0))                                       // constant down a column
    }

    // MARK: grid

    @Test func theGridIsOnePixelWide() {
        let f = TestPattern.grid(width: 130, height: 70, spacing: 32)
        #expect(px(f, 32, 5) == [255, 255, 255, 255])
        #expect(px(f, 33, 5) == [0, 0, 0, 255])
        #expect(px(f, 31, 5) == [0, 0, 0, 255])
        #expect(px(f, 5, 64) == [255, 255, 255, 255])
        #expect(px(f, 5, 63) == [0, 0, 0, 255])
        #expect(px(f, 5, 65) == [0, 0, 0, 255])
        #expect(px(f, 0, 0) == [255, 255, 255, 255])
    }

    // MARK: comparison

    @Test func identicalFramesCompareEqual() {
        let a = TestPattern.colorBars(width: 64, height: 32)
        let c = TestPattern.compare(a, a, tolerance: 0)
        #expect(c.sizesMatch && c.maxChannelError == 0 && c.meanChannelError == 0 && c.firstDifference == nil && c.pixelsOverTolerance == 0)
    }

    @Test func aSmallDifferenceIsMeasuredAndLocated() {
        let a = TestPattern.colorBars(width: 64, height: 32)
        var b = a
        let i = (5 * 64 + 9) * 4 + 1                        // pixel (9, 5), green channel
        b.bgra[i] = b.bgra[i] &+ 7
        let strict = TestPattern.compare(a, b, tolerance: 0)
        #expect(strict.maxChannelError == 7)
        #expect(strict.firstDifference == PixelPosition(x: 9, y: 5))
        #expect(strict.pixelsOverTolerance == 1)
        #expect(abs(strict.meanChannelError - 7.0 / Double(64 * 32 * 3)) < 1e-12)
        let loose = TestPattern.compare(a, b, tolerance: 10)
        #expect(loose.maxChannelError == 7 && loose.firstDifference == nil && loose.pixelsOverTolerance == 0)
    }

    @Test func alphaIsIgnoredUnlessAsked() {
        let a = SDIFrame(width: 2, height: 1, bgra: [1, 2, 3, 255, 4, 5, 6, 255])
        var b = a
        b.bgra[3] = 0
        #expect(TestPattern.compare(a, b).maxChannelError == 0)
        #expect(TestPattern.compare(a, b, includeAlpha: true).maxChannelError == 255)
    }

    @Test func differentSizesAreReportedNotCompared() {
        let c = TestPattern.compare(TestPattern.colorBars(width: 64, height: 32), TestPattern.colorBars(width: 32, height: 32))
        #expect(!c.sizesMatch)
        #expect(c.firstDifference == nil)
    }
}
