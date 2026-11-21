// SLIDE-001b: placing new boxes in free space (written by the implementer).
import Testing
import Foundation
@testable import Domain

@Suite struct FreeSpaceTests {
    func overlaps(_ a: NormalizedRect, _ b: NormalizedRect) -> Bool { FreeSpace.overlap(a, b) > 0 }

    @Test func anEmptySlideGivesThePreferredSpot() {
        let f = FreeSpace.place(width: 0.3, height: 0.2, avoiding: [], preferred: (0.35, 0.4))
        #expect(f == NormalizedRect(x: 0.35, y: 0.4, width: 0.3, height: 0.2))
    }

    @Test func aTakenSpotMovesToTheNearestFreeOne() {
        let taken = NormalizedRect(x: 0.3, y: 0.3, width: 0.4, height: 0.4)
        let f = FreeSpace.place(width: 0.3, height: 0.2, avoiding: [taken], preferred: (0.35, 0.4))
        #expect(!overlaps(f, taken))
        #expect(f.width == 0.3 && f.height == 0.2)
        #expect(f.x >= 0 && f.y >= 0 && f.x + f.width <= 1.0000001 && f.y + f.height <= 1.0000001)
        // Close to where it was asked for: moved by well under half the slide.
        #expect(abs(f.x - 0.35) + abs(f.y - 0.4) < 0.5)
    }

    @Test func manyBoxesStillLeaveAFreeCorner() {
        let boxes = [NormalizedRect(x: 0, y: 0, width: 1, height: 0.5), NormalizedRect(x: 0, y: 0.5, width: 0.6, height: 0.5)]
        let f = FreeSpace.place(width: 0.3, height: 0.3, avoiding: boxes)
        #expect(boxes.allSatisfy { !overlaps($0, f) })                 // the free part is the bottom right
        #expect(f.x >= 0.6 - 1e-9 && f.y >= 0.5 - 1e-9)
    }

    @Test func aFullSlideOverlapsAsLittleAsPossibleAndStaysOnScreen() {
        let all = NormalizedRect(x: 0, y: 0, width: 1, height: 1)
        let f = FreeSpace.place(width: 0.5, height: 0.5, avoiding: [all])
        #expect(f.x >= 0 && f.y >= 0 && f.x + f.width <= 1.0000001 && f.y + f.height <= 1.0000001)
        #expect(f.width == 0.5 && f.height == 0.5)
    }

    @Test func aBoxAsBigAsTheSlideIsKeptOnTheSlide() {
        let f = FreeSpace.place(width: 1, height: 1, avoiding: [NormalizedRect(x: 0.2, y: 0.2, width: 0.2, height: 0.2)])
        #expect(f == NormalizedRect(x: 0, y: 0, width: 1, height: 1))
        let big = FreeSpace.place(width: 3, height: .nan, avoiding: [])
        #expect(big.width == 1 && big.x == 0 && big.y >= 0 && big.y + big.height <= 1.0000001)
    }

    @Test func nonsensePreferredPositionsAreHandled() {
        let f = FreeSpace.place(width: 0.2, height: 0.2, avoiding: [], preferred: (.nan, 9))
        #expect(f.x == 0 && abs(f.y - 0.8) < 1e-9)
    }

    @Test func touchingEdgesDoNotCountAsOverlap() {
        let a = NormalizedRect(x: 0, y: 0, width: 0.5, height: 0.5)
        let b = NormalizedRect(x: 0.5, y: 0, width: 0.5, height: 0.5)
        #expect(FreeSpace.overlap(a, b) == 0)
        #expect(FreeSpace.place(width: 0.5, height: 0.5, avoiding: [a], preferred: (0.5, 0)) == b)
    }
}
