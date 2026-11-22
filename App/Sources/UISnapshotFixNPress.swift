// FIX-N (debug builds only): the Stage canvas's press for the real-key run. In a session whose screen is locked the app cannot become active, and the
// window swallows a synthetic mouse click as the activating click, so the press is made by calling the canvas's own press, move and release functions
// (`StageCanvasDebug`, registered by the canvas view): they are what its gesture calls. What follows (the keys) is real events through the app's key monitor.
#if DEBUG || WF_MEASURE
import AppKit
import OperatorCore

extension AppModel {
    /// A press in the middle of the box whose probe rectangle is `box` (window points), optionally dragged by `drag`, then released.
    @MainActor func fixNStagePress(box: CGRect, drag: CGSize?) async {
        guard StageCanvasDebug.isRegistered, let window = Self.operatorWindow else { return }
        let canvas = RealPointer(window: window).rect("st.cv") ?? .zero
        let size = canvas.size
        let point = CGPoint(x: box.midX - canvas.minX, y: box.midY - canvas.minY)
        StageCanvasDebug.press(at: point, in: size)
        if let drag {
            for step in 1...10 {
                StageCanvasDebug.move(dx: drag.width * Double(step) / 10, dy: drag.height * Double(step) / 10, in: size)
                try? await Task.sleep(for: .milliseconds(20))
            }
        }
        StageCanvasDebug.release()
        try? await Task.sleep(for: .milliseconds(300))
    }
}
#endif
