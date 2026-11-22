// FIX-P items 3 and 4: the Stage canvas view cannot be run in a unit test; these guards keep its source honest about the three review findings
// (the layout a run belongs to, the window the resign observer watches, a press that was ended early).
import Testing
import Foundation

@Suite struct FIXP_CanvasSourceTests {
    private static var repoRoot: URL {
        URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
    }
    private func source(_ name: String) throws -> String { try String(contentsOf: Self.repoRoot.appendingPathComponent("App/Sources/\(name)"), encoding: .utf8) }

    @Test func theStageCanvasWritesARunToTheLayoutItBeganOnAndWatchesOnlyItsOwnWindow() throws {
        let text = try source("StageCanvasView.swift")
        #expect(text.contains("commit.layoutID ?? layout.id") || text.contains("c.layoutID ?? layoutID"), "a commit names the layout captured at the press or the first nudge")
        #expect(text.contains("layoutID: layout.id"), "the press and the nudge hand the current layout to the session")
        let resign = text.components(separatedBy: "\n").filter { $0.contains("didResignKeyNotification") }
        #expect(resign.count == 1)
        #expect(text.contains("keys.view?.window"), "the resign observer compares the notification's window with the canvas's own")
        #expect(text.contains("StageCanvasEditing.takesArrows"), "arrows go to the canvas only for a selection that is in the layout")
        #expect(text.contains("pointerState.interrupt()"), "a cut-short drag is interrupted, so the same gesture cannot restart it")
        #expect(text.contains("press(startedAt:"))
    }

    @Test func theEditCanvasIgnoresAnInterruptedGestureUntilItsEnd() throws {
        let text = try source("SlideObjectsEditor.swift")
        #expect(text.contains("PressGuard"))
        #expect(!text.contains("pressed = false }      // FIX-N item 6"), "an epoch change must interrupt the press, not clear it for the next event")
    }

    @Test func theEditorsMessageReachesTheOperator() throws {
        // FIX-P item 2: "Position restored on 2 of 3 slides; 1 was edited since." is of no use if nothing draws it.
        let text = try source("ContentView.swift")
        #expect(text.contains("slideEditor?.lastMessage"), "the workspace shows the slide editor's message in a bar the operator can dismiss")
        #expect(text.contains("slideEditor?.dismissMessage()"))
    }
}
