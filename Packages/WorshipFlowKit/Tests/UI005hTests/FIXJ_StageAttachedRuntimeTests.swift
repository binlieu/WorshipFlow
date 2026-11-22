// FIX-J item 5 (UI-005h): the second-language line and the NEXT label belong to the element they are drawn with: they move and scale with it.
// Old API only (element.move/resize, the composer's layers, JSON), so these could be run red first.
import Testing
import Foundation
import Domain

@Suite struct FIXJ_StageAttachedRuntimeTests {
    func layers(_ layout: StageLayout) -> [TextLayer] {
        StageComposer.scene(layout: layout, context: StageContext(state: UI005hFixtures.live(), now: 0, timeOfDayText: "", timers: [], message: nil, notes: nil)).textLayers
    }
    func layer(_ layout: StageLayout, _ text: String) -> TextLayer? { layers(layout).first { $0.text == text } }

    static let secondText = "Xi\u{1EC1}ng x\u{00ED}ch \u{0111}\u{00E3} tan \u{00B7} T\u{00F4}i \u{0111}\u{01B0}\u{1EE3}c t\u{1EF1} do"

    func close(_ a: NormalizedRect, _ b: NormalizedRect, _ tol: Double = 1e-9) -> Bool {
        abs(a.x - b.x) < tol && abs(a.y - b.y) < tol && abs(a.width - b.width) < tol && abs(a.height - b.height) < tol
    }

    @Test func movingTheCurrentElementMovesItsSecondLanguageLine() throws {
        var layout = StageLayout.standard
        let before = try #require(layer(layout, Self.secondText)).frame
        layout.elements[0].move(dx: 0.03, dy: 0.1)
        let after = try #require(layer(layout, Self.secondText)).frame
        #expect(abs(after.x - before.x - 0.03) < 1e-9 && abs(after.y - before.y - 0.1) < 1e-9, "second line moved from \(before) to \(after)")
        #expect(abs(after.width - before.width) < 1e-9 && abs(after.height - before.height) < 1e-9)
    }

    @Test func movingTheNextElementMovesItsNEXTLabel() throws {
        var layout = StageLayout.standard
        let i = try #require(layout.elements.firstIndex { $0.kind == .nextSlide })
        let before = try #require(layer(layout, "NEXT")).frame
        layout.elements[i].move(dx: 0.02, dy: -0.2)
        let after = try #require(layer(layout, "NEXT")).frame
        #expect(abs(after.x - before.x - 0.02) < 1e-9 && abs(after.y - before.y + 0.2) < 1e-9, "label moved from \(before) to \(after)")
    }

    @Test func resizingTheElementScalesTheAttachedLineWithIt() throws {
        var layout = StageLayout.standard
        let frame = layout.elements[0].frame
        let before = try #require(layer(layout, Self.secondText)).frame
        layout.elements[0].resize(width: frame.width / 2, height: frame.height * 1.5)
        let after = try #require(layer(layout, Self.secondText)).frame
        // Offsets and sizes keep their proportion of the element.
        #expect(abs((after.x - frame.x) - (before.x - frame.x) / 2) < 1e-9, "x \(before.x) -> \(after.x)")
        #expect(abs(after.width - before.width / 2) < 1e-9)
        #expect(abs((after.y - frame.y) - (before.y - frame.y) * 1.5) < 1e-9)
        #expect(abs(after.height - before.height * 1.5) < 1e-9)
    }

    @Test func aDragFromTheStartFrameKeepsThePartsWhereTheyBelong() throws {
        // The editor puts the drag's start frame back and moves from it every time the pointer moves.
        var layout = StageLayout.standard
        let start = layout.elements[0].frame
        let home = try #require(layer(layout, Self.secondText)).frame
        for step in 1...5 {
            layout.elements[0].frame = start
            layout.elements[0].move(dx: -Double(step) * 0.005, dy: 0)
        }
        let after = try #require(layer(layout, Self.secondText)).frame
        #expect(abs(after.x - home.x + 0.025) < 1e-9 && abs(after.y - home.y) < 1e-9, "moved \(after.x - home.x)")
        layout.elements[0].frame = start
        #expect(close(try #require(layer(layout, Self.secondText)).frame, home))
    }

    @Test func aLayoutSavedBeforeThisFixIsReadWhereItWasDrawn() throws {
        // The built-in layout as an earlier build stored it when an operator duplicated it: the parts carry absolute frames.
        let layout = StageLayout.standard
        let encoded = try #require(try JSONSerialization.jsonObject(with: JSONEncoder().encode(layout)) as? [String: Any])
        var object = encoded
        var elements = try #require(object["elements"] as? [[String: Any]])
        let current = layout.elements[0], next = layout.elements[1]
        let secondFrame = try #require(layer(layout, Self.secondText)).frame
        let nextLabelFrame = try #require(layer(layout, "NEXT")).frame
        func absolute(_ f: NormalizedRect) -> [String: Any] { ["x": f.x, "y": f.y, "width": f.width, "height": f.height] }
        var second = try #require(elements[0]["secondLanguage"] as? [String: Any])
        second.removeValue(forKey: "relativeFrame")
        second["frame"] = absolute(secondFrame)
        elements[0]["secondLanguage"] = second
        var label = try #require(elements[1]["label"] as? [String: Any])
        label.removeValue(forKey: "relativeFrame")
        label["frame"] = absolute(nextLabelFrame)
        elements[1]["label"] = label
        object["elements"] = elements
        let legacy = try JSONDecoder().decode(StageLayout.self, from: JSONSerialization.data(withJSONObject: object))
        #expect(close(try #require(layer(legacy, Self.secondText)).frame, secondFrame))
        #expect(close(try #require(layer(legacy, "NEXT")).frame, nextLabelFrame))
        _ = (current, next)
    }

    @Test func aLayoutIsStoredWithItsPartsRelativeToTheirElement() throws {
        let json = String(decoding: try JSONEncoder().encode(StageLayout.standard), as: UTF8.self)
        #expect(json.contains("relativeFrame"))
        let back = try JSONDecoder().decode(StageLayout.self, from: JSONEncoder().encode(StageLayout.standard))
        #expect(back == StageLayout.standard)
    }
}
