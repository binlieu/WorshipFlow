// FIX-U: which window-level views must not read the holds and the live place, from the source (a view body's run count cannot be seen from a unit
// test; the running-app numbers come from scripts/fixq-run.sh and are in AI/reports/FIX-U-report.md).
import Testing
import Foundation

@Suite struct FIXU_ViewSourceTests {
    private func root() -> URL {
        var url = URL(fileURLWithPath: #filePath)
        for _ in 0..<5 { url.deleteLastPathComponent() }
        return url
    }
    private func source(_ name: String) throws -> String { try String(contentsOf: root().appendingPathComponent("App/Sources/\(name)"), encoding: .utf8) }

    @Test func theWindowsOwnBodyDoesNotReadTheTwoHoldsTheToolbarTagDoes() throws {
        // Blackout and Clear used to run `WorkspaceView`'s body (the whole window: toolbar, mode, transport bar, sheets) because it read the holds for the
        // toolbar's amber word. The word is a view of its own now.
        let text = try source("ContentView.swift")
        let start = try #require(text.range(of: "struct WorkspaceView: View"))
        let end = try #require(text.range(of: "private struct ToolbarStateTag: View"))
        let workspace = String(text[start.lowerBound..<end.lowerBound])
        for pattern in ["isBlackedOut", "isCleared", "showParts", "ShowStateTag.text"] {
            #expect(!workspace.contains(pattern), "WorkspaceView reads `\(pattern)`: Blackout, Clear or a Go Live that lifts one would run the whole window's body")
        }
        #expect(workspace.contains("ToolbarStateTag(app: app)"))
        #expect(text.contains("ShowStateTag.text(isBlackedOut: app.showParts.isBlackedOut, isCleared: app.showParts.isCleared)"))
    }

    @Test func theInspectorsOwnBodyDoesNotDecideWhetherThePinnedRowShows() throws {
        // `hasLiveWords` changes with Clear; the pinned row (Edit live slide, the override, Configure) is a view of its own that reads it.
        let inspector = try source("ShowInspector.swift")
        let head = try #require(inspector.components(separatedBy: "private struct PreviewMonitor").first)
        #expect(!head.contains("hasLiveWords") && !head.contains("hasLiveBackgroundOverride"), "ShowInspector reads what the pinned row shows")
        #expect(head.contains("ShowSlimRow(app: app, workspace: workspace)"))
        let row = try source("ShowSlimRow.swift")
        #expect(row.contains("workspace.showParts.hasLiveWords") && row.contains("app.media?.hasLiveBackgroundOverride"))
    }

    @Test func theTransportBarsButtonsDoNotReadTheWordsOrTheMode() throws {
        // The headline, the detail line and the state badge change with every Next and every Clear; the buttons do not.
        let text = try source("TransportBar.swift")
        let start = try #require(text.range(of: "struct TransportBar: View"))
        let end = try #require(text.range(of: "private struct TransportText: View"))
        let bar = String(text[start.lowerBound..<end.lowerBound])
        for pattern in ["app.mode", "liveSlide", "livePositionLine", "textBlockWidth", "InterFont"] {
            #expect(!bar.contains(pattern), "TransportBar reads `\(pattern)`: every Next would run the whole bar")
        }
        // fixedSize: as one child of the bar, the badge and the text block must keep their own widths (found with `scripts/compare-rects.py`: without it
        // the badge was squeezed from 45.7 to 18 pt and the text block moved 27 pt left).
        #expect(bar.contains("TransportText(app: app, workspace: workspace).fixedSize(horizontal: true, vertical: false)"))
        let words = String(text[end.lowerBound...])
        #expect(words.contains("app.mode") && words.contains("workspace.showParts.liveSlide") && words.contains("livePositionLine"))
    }
}
