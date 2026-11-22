// UI-005j: the operator window has no title bar of its own: the app draws the design's 52 pt toolbar at the top of the window
// (ContentView.operatorToolbar). These two helpers keep what a title bar gives: dragging the window by the bar, and the three window
// buttons, which the system still draws, set where the design puts its three dots (centres 20, 40 and 60 pt from the left, 25.5 pt down).
import SwiftUI
import AppKit

/// Dragging the bar's empty parts moves the window (buttons and fields on top keep their own clicks).
struct WindowDragArea: View {
    var body: some View { Color.clear.contentShape(Rectangle()).gesture(WindowDragGesture()) }
}

/// Puts the window's close, minimise and zoom buttons where the toolbar leaves room for them, now and after every resize.
struct WindowChrome: NSViewRepresentable {
    func makeNSView(context: Context) -> PlacingView { PlacingView() }
    func updateNSView(_ view: PlacingView, context: Context) { view.place() }

    final class PlacingView: NSView {
        private var observers: [NSObjectProtocol] = []

        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            observers.forEach(NotificationCenter.default.removeObserver)
            observers = []
            guard let window else { return }
            // The content runs under the (transparent, untitled) title bar, so the app's bar is the top 52 pt of the window.
            window.styleMask.insert(.fullSizeContentView)
            window.titlebarAppearsTransparent = true
            window.titleVisibility = .hidden
            window.toolbar = nil
            for name in [NSWindow.didResizeNotification, NSWindow.didBecomeKeyNotification, NSWindow.didResignKeyNotification,
                         NSWindow.didExitFullScreenNotification, NSWindow.didEndLiveResizeNotification] {
                observers.append(NotificationCenter.default.addObserver(forName: name, object: window, queue: .main) { [weak self] _ in
                    MainActor.assumeIsolated { self?.place() }
                })
            }
            DispatchQueue.main.async { [weak self] in self?.place() }
        }

        override func layout() { super.layout(); place() }

        func place() {
            guard let window, !window.styleMask.contains(.fullScreen) else { return }
            let types: [NSWindow.ButtonType] = [.closeButton, .miniaturizeButton, .zoomButton]
            for (i, type) in types.enumerated() {
                guard let button = window.standardWindowButton(type), let host = button.superview else { continue }
                let centre = host.convert(NSPoint(x: 20 + 20 * CGFloat(i), y: window.frame.height - 25.5), from: nil)
                button.setFrameOrigin(NSPoint(x: centre.x - button.frame.width / 2, y: centre.y - button.frame.height / 2))
            }
        }

        override func viewWillMove(toWindow newWindow: NSWindow?) {
            super.viewWillMove(toWindow: newWindow)
            if newWindow == nil { observers.forEach(NotificationCenter.default.removeObserver); observers = [] }
        }
    }
}
