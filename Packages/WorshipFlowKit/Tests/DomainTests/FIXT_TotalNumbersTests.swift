// FIX-T item 1 (SYS): every conversion of a stored or measured number to an integer for display or arithmetic is total: no Double and
// no Int64 makes it trap. A library that already holds a bad value opens and shows "–:–".
import Testing
import Foundation
@testable import Domain

@Suite struct FIXT_TotalNumbersTests {
    static let awkward: [Double] = [.nan, .infinity, -.infinity, 1e300, -1e300, 1e19, -1e19, .greatestFiniteMagnitude, -.greatestFiniteMagnitude,
                                    9.223372036854775807e18, -9.223372036854775808e18, 0, -0.0, -1, 0.4999, 59.5, 3599.5, 1e9, 4.9e-324]

    @Test func saturatingIntegerConversionNeverTraps() {
        for v in Self.awkward { _ = Int(saturating: v) }
        #expect(Int(saturating: .nan) == 0)
        #expect(Int(saturating: .infinity) == Int.max)
        #expect(Int(saturating: -.infinity) == Int.min)
        #expect(Int(saturating: 1e300) == Int.max)
        #expect(Int(saturating: 2.6) == 2)
        #expect(Int(saturating: -2.6) == -2)
    }

    @Test func theLengthClockIsTotalAndShowsADashForANumberThatIsNoLength() {
        for v in Self.awkward { #expect(!MediaClock.length(v).isEmpty) }
        #expect(MediaClock.length(.nan) == "–:–")
        #expect(MediaClock.length(1e300) == "–:–")
        #expect(MediaClock.length(-1e300) == "–:–")
        #expect(MediaClock.length(-1) == "–:–")
        #expect(MediaClock.length(0) == "0:00")
        #expect(MediaClock.length(59.5) == "1:00")
        #expect(MediaClock.length(3725) == "1:02:05")
        #expect(MediaClock.length(185) == "3:05")
    }

    @Test func theCueAndTenthsReadoutsAreTotal() {
        for v in Self.awkward { #expect(!MediaClock.cue(v).isEmpty); #expect(!MediaClock.tenths(v).isEmpty) }
        #expect(MediaClock.cue(125) == "02:05")
        #expect(MediaClock.cue(-4) == "00:00")
        #expect(MediaClock.tenths(11.46) == "00:11.4")
        #expect(MediaClock.tenths(.nan) == "00:00.0")
    }

    @Test func percentTextIsTotal() {
        for v in Self.awkward { #expect(!MediaClock.percent(v).isEmpty) }
        #expect(MediaClock.percent(0.456) == "46%")
        #expect(MediaClock.percent(.nan) == "0%")
    }

    @Test func aPixelRectOfAnAbsurdFrameDoesNotTrap() {
        for v in Self.awkward {
            let r = NormalizedRect(x: v, y: v, width: v, height: v).pixelRect(width: 1920, height: 1080)
            _ = r.width * r.height * 4
        }
        let r = NormalizedRect(x: 0.5, y: 0.25, width: 0.5, height: 0.5).pixelRect(width: 1920, height: 1080)
        #expect(r.x == 960 && r.y == 270 && r.width == 960 && r.height == 540)
    }

    @Test func aCountdownOfAnAbsurdLengthDoesNotTrap() {
        for seconds in [Int.max, Int.min, 1 << 62, 4_000_000_000_000_000_000] {
            let run = CountdownRun(spec: CountdownSpec(label: "x", mode: .duration(seconds: seconds)), startedAt: Date())
            _ = run.remaining(at: Date())
            _ = run.isFinished(at: Date().addingTimeInterval(5))
        }
    }
}
