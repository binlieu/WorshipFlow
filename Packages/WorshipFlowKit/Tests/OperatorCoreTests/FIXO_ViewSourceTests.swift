// FIX-O: what the views must not depend on, read from the source (a view's body count cannot be seen from a unit test; the running-app
// numbers come from scripts/measure-drags.sh and are in AI/reports/FIX-O-report.md).
import Testing
import Foundation

@Suite struct FIXO_ViewSourceTests {
    private func root() -> URL {
        var url = URL(fileURLWithPath: #filePath)
        for _ in 0..<5 { url.deleteLastPathComponent() }
        return url
    }
    private func source(_ name: String) throws -> String { try String(contentsOf: root().appendingPathComponent("App/Sources/\(name)"), encoding: .utf8) }

    @Test func noViewReadsTheWholeShowStateOrTheWholeLayersForOnePart() throws {
        let folder = root().appendingPathComponent("App/Sources")
        let files = try FileManager.default.contentsOfDirectory(atPath: folder.path).filter { $0.hasSuffix(".swift") && !$0.hasPrefix("UISnapshot") && !$0.hasSuffix("DesignCapture.swift") }
        let banned = ["workspace.show.", "workspace?.show.", "app.show.", "workspace?.show\n", "(for: app.show)", "media.layers.foreground", "media.layers.background"]
        for name in files {
            let text = try source(name)
            for pattern in banned {
                #expect(!text.contains(pattern), "\(name) reads the whole state through `\(pattern)`; read the part (`showParts.<part>`, `layerParts.<layer>`)")
            }
        }
    }

    @Test func theShowInspectorsOwnBodyDoesNotReadTheSelectionTheLivePlaceOrTheMode() throws {
        let text = try source("ShowInspector.swift")
        let head = try #require(text.components(separatedBy: "private struct PreviewMonitor").first)
        let inspector = try #require(head.components(separatedBy: "struct ShowInspector: View").last)
        for pattern in ["selectedIndex", "liveIndex", "app.mode", "workspace.slides", "showParts.liveSlide", "liveSlideAtPlace"] {
            #expect(!inspector.contains(pattern), "ShowInspector reads \(pattern): Next, a selection or a drop would draw the whole inspector")
        }
        #expect(text.contains("private struct PreviewMonitor") && text.contains("private struct LiveMonitor"))
    }

    @Test func theGridGivesTheModeToTheLiveCellOnly() throws {
        // FIX-S: the rule is "only the live cell draws the mode", and since FIX-Q the cell decides it from its own live mark (as
        // `FIXQ_ViewSourceTests.eachCellAsksForItsOwnMarks` asserts for the marks). It used to assert a sentence kept in a comment.
        let cell = try source("SlideGridCell.swift")
        #expect(cell.contains("mode: live ? app.mode : .live"), "the cell takes the mode from app.mode only when its own live mark is set")
        #expect(!cell.contains("let mode: LiveMode") && !cell.contains("let liveMode"), "the grid gives the cell no mode")
        let text = try source("CentrePane.swift")
        #expect(!text.contains("mode: app.mode, color"), "the grid hands app.mode to every cell")
        let start = try #require(text.range(of: "struct SlideGrid: View"))
        let end = try #require(text.range(of: "/// FIX-I item 6: the background entries"))
        #expect(!String(text[start.lowerBound..<end.lowerBound]).contains("app.mode"), "the grid's own code reads the mode")
    }

    @Test func theToolbarTagReadsOnlyTheTwoHoldsAndTheModelKeepsTheWholeStateBehindTheParts() throws {
        #expect(try source("ContentView.swift").contains("ShowStateTag.text(isBlackedOut: app.showParts.isBlackedOut, isCleared: app.showParts.isCleared)"))
        let model = try source("AppModel.swift")
        #expect(model.contains("let showParts = ObservedShow()"))
        #expect(model.contains("var mode: LiveMode { showParts.isStopped"))
    }
}
