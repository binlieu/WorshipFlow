// R4: the operator window must not close while the screens are open (the red button and Command-W both end at
// `windowShouldClose`). SwiftUI owns the window's delegate, so this one stands in front of it: it answers
// `windowShouldClose` itself and hands every other delegate message on to SwiftUI's own delegate.
import SwiftUI
import AppKit
import OperatorCore

// `original` is only read on the main thread (AppKit sends delegate messages there); `responds` and `forwardingTarget`
// are nonisolated overrides, hence `nonisolated(unsafe)`.
final class OperatorWindowCloseGuard: NSObject, NSWindowDelegate {
    private nonisolated(unsafe) weak var original: (any NSWindowDelegate)?

    @MainActor init(original: (any NSWindowDelegate)?) {
        self.original = original
        super.init()
    }

    override func responds(to selector: Selector!) -> Bool {
        super.responds(to: selector) || (original as AnyObject?)?.responds(to: selector) == true
    }

    override func forwardingTarget(for selector: Selector!) -> Any? {
        (original as AnyObject?)?.responds(to: selector) == true ? original : nil
    }

    @MainActor func windowShouldClose(_ sender: NSWindow) -> Bool {
        if let original, original.responds(to: #selector(NSWindowDelegate.windowShouldClose(_:))),
           original.windowShouldClose?(sender) == false { return false }
        switch AppModel.shared.quitDecision(for: .operatorWindowClose) {
        case .allow:
            return true
        case .confirm, .refuse:
            // Refused: say why, in a sheet on this window, never on an output.
            let message: String
            if case .refuse(let text) = AppModel.shared.quitDecision(for: .operatorWindowClose) { message = text } else { message = "" }
            let alert = NSAlert()
            alert.messageText = "The screens are still open"
            alert.informativeText = message
            alert.addButton(withTitle: "OK")
            alert.beginSheetModal(for: sender)
            return false
        }
    }
}

/// Put in the operator window's background; installs the guard once, when the view reaches its window.
struct OperatorWindowGuardInstaller: NSViewRepresentable {
    func makeNSView(context: Context) -> InstallerView { InstallerView() }
    func updateNSView(_ view: InstallerView, context: Context) {}

    final class InstallerView: NSView {
        private var guardObject: OperatorWindowCloseGuard?

        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            guard let window, guardObject == nil else { return }
            MainActor.assumeIsolated {
                let object = OperatorWindowCloseGuard(original: window.delegate)
                guardObject = object          // the window holds its delegate weakly: this view keeps it alive
                window.delegate = object
            }
        }
    }
}
