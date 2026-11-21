// R4 / R5: what every output window must and must not do, as small pure pieces that tests can reach without a screen.
import AppKit

/// Window used by every output. It stays visible when the operator hides the app (Command-H, Hide Others), does not hide
/// when the app is deactivated, and cannot be closed from the keyboard (Command-W): an output is stopped from the
/// operator window, not by a stray keystroke. The title-bar close button of a `WindowOutput` still works.
final class OutputWindow: NSWindow {
    /// Applies the policy. Called once by each output right after it creates the window.
    func applyOutputPolicy() {
        canHide = false
        hidesOnDeactivate = false
    }

    /// False for a keyboard-driven close (Command-W reaches `performClose` with a key event current).
    static func allowsClose(during event: NSEvent.EventType?) -> Bool {
        event != .keyDown && event != .keyUp
    }

    override func performClose(_ sender: Any?) {
        guard Self.allowsClose(during: NSApp?.currentEvent?.type) else { return }
        super.performClose(sender)
    }
}

/// Where a display's window should be and what to do when it is not (R5).
public struct DisplayGeometry: Sendable, Equatable {
    public var id: UInt32
    public var frame: CGRect
    public init(id: UInt32, frame: CGRect) {
        self.id = id
        self.frame = frame
    }
}

public enum OutputWindowFit {
    public enum Action: Sendable, Equatable {
        /// The window exactly covers its display.
        case none
        /// Put the window back on this frame (the display moved or changed size, or something moved the window).
        case reframe(CGRect)
        /// The output cannot be kept on its display; stop it and tell the operator why.
        case fault(String)
    }

    /// Frames are compared to half a point: displays report whole-point frames, and a window set to one can differ by
    /// rounding only.
    static func sameFrame(_ a: CGRect, _ b: CGRect) -> Bool {
        abs(a.minX - b.minX) < 0.5 && abs(a.minY - b.minY) < 0.5 && abs(a.width - b.width) < 0.5 && abs(a.height - b.height) < 0.5
    }

    /// Decides what a display output does after the screen parameters changed.
    /// - `target`: the output's own display as the system now describes it, nil when it is gone.
    /// - `windowDisplayID`: the display the window is on (`NSWindow.screen`), nil when none.
    /// - `afterReframe`: the window was already put back once and this checks the result; a mismatch that survives is a fault.
    public static func decide(windowFrame: CGRect, windowDisplayID: UInt32?, target: DisplayGeometry?, name: String,
                              afterReframe: Bool = false) -> Action {
        guard let target else { return .fault("The display for \(name) was disconnected. The output has stopped.") }
        let framed = sameFrame(windowFrame, target.frame)
        let onTarget = windowDisplayID == target.id
        if framed && onTarget { return .none }
        if afterReframe {
            return .fault("\(name) could not be kept on its display after the screens changed. Restart this screen.")
        }
        return .reframe(target.frame)
    }
}
