// FIX-S (KI-193): the slide grid, the slide list and the Edit film strip crashed with "Index out of range" (build 139, owner clicked a playlist item
// a few seconds after launch). A lazy container runs a cell's closure later than the body that made the cell, and runs the closures of cells that are
// leaving once more when the model's slide list was replaced; the closure indexed `workspace.slides[position]` live, so a position of the old,
// longer list was asked of the new, shorter one. The cure is that a cell carries its slide (`CellSlot`) and no lazy closure reads the model's list
// by a position. Reproduced in a Debug build driven through the app's own open path (AI/reports/FIX-S-report.md).
import Testing
import Foundation
import Observation
import Domain
@testable import OperatorCore

@MainActor
@Suite struct FIXS_CellSlotTests {
    private func slides(_ n: Int, prefix: String = "Line") -> [Slide] {
        let presentation = UUID()
        return (0..<n).map { Slide(presentationID: presentation, sortOrder: $0, content: SlideContent(primary: "\(prefix) \($0)")) }
    }

    @Test func aSlotHoldsTheSlideItShowsSoALaterListCannotChangeIt() {
        var model = slides(12)
        let keys = SlideCellKey.keys(for: model.map(\.id))
        let made = (0..<12).compactMap { CellSlot(at: $0, slides: model, keys: keys) }
        #expect(made.count == 12)
        model = slides(8, prefix: "Short")        // the presentation is replaced by a shorter one after the slots were made
        for slot in made { #expect(slot.slide.content.primary == "Line \(slot.index)", "the slot at \(slot.index) still shows its own slide") }
        #expect(made[8].index == 8 && made[11].isLast && !made[10].isLast)
        #expect(model.count == 8)       // the new list has no position 8 or 11; no slot ever asks it
    }

    @Test func aPositionTheListDoesNotHaveMakesNoSlot() {
        let list = slides(5)
        let keys = SlideCellKey.keys(for: list.map(\.id))
        #expect(CellSlot(at: 5, slides: list, keys: keys) == nil)
        #expect(CellSlot(at: -1, slides: list, keys: keys) == nil)
        #expect(CellSlot(at: 4, slides: list, keys: keys)?.isLast == true)
        // A run built from other data (twelve positions) against this list of five: only the five positions that exist come back.
        #expect((0..<12).compactMap { CellSlot(at: $0, slides: list, keys: keys) }.map(\.index) == [0, 1, 2, 3, 4])
        // Keys made from a shorter list than the slides: a slot needs both.
        #expect(CellSlot(at: 3, slides: list, keys: Array(keys.prefix(3))) == nil)
        #expect(CellSlot(at: 0, slides: [], keys: []) == nil)
    }

    @Test func aSlotIsKeyedBySlideAndOccurrenceSoARepeatedSlideKeepsTwoCells() {
        let one = slides(2)
        let list = [one[0], one[1], one[0]]       // an arrangement plays a section twice
        let keys = SlideCellKey.keys(for: list.map(\.id))
        let made = (0..<3).compactMap { CellSlot(at: $0, slides: list, keys: keys) }
        #expect(Set(made.map(\.id)).count == 3)
    }

    /// The grid's body is run again when the list is replaced by one of another length: it reads `slides`, which depends on every change to the
    /// list. (Shown by `withObservationTracking`; the cause is not a missed invalidation of the grid's body.)
    @Test func replacingTheListWithAShorterOneNotifiesTheReaderOfTheWholeList() {
        let list = ObservedSlideList()
        list.set(slides(12))
        let fired = FIXO_Flag()
        withObservationTracking({ _ = list.all }, onChange: { fired.fired = true })
        list.set(slides(8, prefix: "Short"))
        #expect(fired.fired)
        #expect(list.current.count == 8)
    }

    // MARK: Source rules (a lazy closure is not run by a unit test)

    private func root() -> URL {
        var url = URL(fileURLWithPath: #filePath)
        for _ in 0..<5 { url.deleteLastPathComponent() }
        return url
    }
    private func source(_ name: String) throws -> String { try String(contentsOf: root().appendingPathComponent("App/Sources/\(name)"), encoding: .utf8) }

    @Test func noLazyClosureOfTheGridTheListOrTheFilmStripReadsTheModelsSlidesByAPosition() throws {
        let centre = try source("CentrePane.swift")
        let grid = try #require(centre.components(separatedBy: "struct SlideGrid: View").last?.components(separatedBy: "struct SlideList: View").first)
        let list = try #require(centre.components(separatedBy: "struct SlideList: View").last?.components(separatedBy: "// MARK: Editors").first)
        let edit = try source("EditMode.swift")
        let film = try #require(edit.components(separatedBy: "private var filmstrip: some View").last?.components(separatedBy: "// MARK: Object bar").first)
        for (name, text) in [("SlideGrid", grid), ("SlideList", list), ("the Edit film strip", film)] {
            #expect(!text.contains("workspace.slides["), "\(name) indexes the model's slide list by a position")
            #expect(!text.contains("workspace.slides.indices"), "\(name) checks a position against the live list: carry the slide in a CellSlot instead")
            #expect(text.contains("CellSlot(at:"), "\(name) makes its cells from slots that carry their slide")
        }
        #expect(!edit.contains("filmCell(_ i: Int)") && !centre.contains("row(_ i: Int"), "a cell is drawn from its slot, not from a position")
    }
}
