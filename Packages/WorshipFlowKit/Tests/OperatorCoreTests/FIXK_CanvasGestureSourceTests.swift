// FIX-K item 3: why the Edit canvas's objects could not be dragged. A box that follows the pointer moves its own coordinate space: a drag gesture
// measured in the box's LOCAL space then sees the pointer travel only half as far (the box has already moved under it), so a drag converges on half
// the distance and the box lags and stops. Every drag gesture on the canvas (object, handle, lyric box) must be measured in the canvas's own, fixed
// space. A unit test of the model cannot see this (the model is given the translation); the running app can, and this guard keeps the source honest.
// The real-mouse check is in the report (UI_SNAPSHOT_FIXK).
import Testing
import Foundation

@Suite struct FIXK_CanvasGestureSourceTests {
    private static var repoRoot: URL {
        URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
    }

    @Test func everyDragGestureOnTheEditCanvasIsMeasuredInTheCanvasSpace() throws {
        let url = Self.repoRoot.appendingPathComponent("App/Sources/SlideObjectsEditor.swift")
        let text = try String(contentsOf: url, encoding: .utf8)
        var found = 0
        var offenders: [String] = []
        for (number, line) in text.split(separator: "\n", omittingEmptySubsequences: false).enumerated() where line.contains("DragGesture(") {
            found += 1
            if !line.contains("coordinateSpace: .named(") { offenders.append("line \(number + 1)") }
        }
        #expect(found >= 2, "the canvas has an object drag and a handle drag at least")
        #expect(offenders.isEmpty, "drag gestures measured in a local space: \(offenders)")
        #expect(text.contains(".coordinateSpace(name:"), "the canvas must name the space its gestures use")
    }
}
