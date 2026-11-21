// OUT-001 acceptance tests. Owned by the coordinator: do not modify.
import Testing
@testable import Domain

@Suite struct SlideContentTests {
    @Test func bilingualSlideKeepsBothLines() {
        let slide = SlideContent(primary: "Amazing grace, how sweet the sound",
                                 secondary: "Ân điển lạ lùng thay")
        #expect(slide.primary == "Amazing grace, how sweet the sound")
        #expect(slide.secondary == "Ân điển lạ lùng thay")
        #expect(slide.isBlank == false)
    }

    @Test func blankSlideIsBlank() {
        #expect(SlideContent(primary: "   ", secondary: nil).isBlank)
        #expect(SlideContent(primary: "", secondary: "\n").isBlank)
    }

    @Test func colorClampsComponents() {
        let c = ColorRGBA(red: 1.5, green: -1, blue: 0.25, alpha: 2)
        #expect(c.red == 1 && c.green == 0 && c.blue == 0.25 && c.alpha == 1)
    }

    @Test func normalizedRectIsTopLeftOrigin() {
        let lowerThird = NormalizedRect(x: 0.05, y: 0.75, width: 0.9, height: 0.2)
        let px = lowerThird.pixelRect(width: 1920, height: 1080)
        #expect(px.x == 96 && px.y == 810 && px.width == 1728 && px.height == 216)
    }
}
