// UI-006f (SC-21): "Identify screens". For three seconds every connected DISPLAY shows a label saying which WorshipFlow screen is set to it
// (or that it is the operator's display, or that no screen uses it). Labels are plain overlay windows that ignore the mouse. Only displays are
// labelled: an SDI connector has no display, and nothing here sends video to a card. Offered only while the screens are closed (the labels
// would cover what the outputs are showing). The hide is one scheduled call, not a timer: nothing runs while no labels are shown.
import SwiftUI
import AppKit
import Domain
import OperatorCore
import OutputEngine

@MainActor
final class ScreensIdentifier {
    static let shared = ScreensIdentifier()
    private var windows: [NSWindow] = []
    private var hide: Task<Void, Never>?
    private(set) var isShowing = false

    static let duration: Duration = .seconds(3)

    func show(profiles: [ScreenProfile], operatorDisplay: UInt32?) {
        dismiss()
        let screens = NSScreen.screens
        let labels = ScreenIdentify.labels(displays: screens.map { (DisplayOutput.displayID(of: $0), $0.localizedName) },
                                           profiles: profiles, operatorDisplay: operatorDisplay)
        for (screen, label) in zip(screens, labels) {
            let window = NSWindow(contentRect: screen.frame, styleMask: [.borderless], backing: .buffered, defer: false, screen: screen)
            window.isReleasedWhenClosed = false
            window.level = .statusBar
            window.isOpaque = false
            window.backgroundColor = .clear
            window.ignoresMouseEvents = true
            window.hasShadow = false
            window.collectionBehavior = [.canJoinAllSpaces, .transient, .ignoresCycle, .fullScreenAuxiliary]
            window.setAccessibilityLabel("Screen label: \(label.title). \(label.detail)")
            window.contentView = NSHostingView(rootView: IdentifyLabelView(label: label))
            window.setFrame(screen.frame, display: true)
            window.orderFrontRegardless()
            windows.append(window)
        }
        isShowing = !windows.isEmpty
        hide = Task { [weak self] in
            try? await Task.sleep(for: Self.duration)
            guard !Task.isCancelled else { return }
            self?.dismiss()
        }
    }

    func dismiss() {
        hide?.cancel()
        hide = nil
        for window in windows { window.orderOut(nil); window.close() }
        windows = []
        isShowing = false
    }

    /// The display the operator window is on (the app's own rule: the visible operator window's display, else the first).
    static func operatorDisplayID() -> UInt32? {
        let window = AppModel.operatorWindow.flatMap { $0.isVisible ? $0 : nil }
        guard let screen = window?.screen ?? NSScreen.screens.first else { return nil }
        return DisplayOutput.displayID(of: screen)
    }
}

private struct IdentifyLabelView: View {
    let label: ScreenIdentifyLabel
    var body: some View {
        VStack(spacing: 10) {
            Text(label.title).font(.wf(64, .bold)).multilineTextAlignment(.center).minimumScaleFactor(0.4)
            Text(label.detail).font(.wf(22, .medium)).multilineTextAlignment(.center).opacity(0.85)
        }
        .foregroundStyle(.white)
        .padding(40)
        .frame(maxWidth: 1100)
        .background(.black.opacity(0.78), in: RoundedRectangle(cornerRadius: 24))
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(.black.opacity(0.25))
    }
}
