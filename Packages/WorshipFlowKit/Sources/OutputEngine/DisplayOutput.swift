// OUT-001: borderless window covering one display, above the menu bar and Dock.
import AppKit
import Domain

@MainActor
public final class DisplayOutput: MetalOutput {
    public let displayID: CGDirectDisplayID

    public init(screen: NSScreen, name: String? = nil, sceneProvider: @escaping SceneProvider,
                videoSource: (any VideoSourceFactory)? = nil) {
        self.displayID = Self.displayID(of: screen)
        super.init(name: name ?? "Display \(screen.localizedName)", sceneProvider: sceneProvider, videoSource: videoSource)
    }

    public static func displayID(of screen: NSScreen) -> CGDirectDisplayID {
        let key = NSDeviceDescriptionKey("NSScreenNumber")
        return (screen.deviceDescription[key] as? NSNumber)?.uint32Value ?? 0
    }

    private func screen() -> NSScreen? {
        NSScreen.screens.first { Self.displayID(of: $0) == displayID }
    }

    override func makeWindow() -> NSWindow {
        let target = screen() ?? NSScreen.main
        let frame = target?.frame ?? NSRect(x: 0, y: 0, width: 1920, height: 1080)
        let w = NSWindow(contentRect: frame, styleMask: [.borderless], backing: .buffered, defer: false, screen: target)
        w.setFrame(frame, display: false)
        w.level = NSWindow.Level(rawValue: Int(CGShieldingWindowLevel()))   // above the menu bar, Dock and full-screen apps
        w.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        w.backgroundColor = .black
        w.isOpaque = true
        w.hasShadow = false
        w.ignoresMouseEvents = true
        w.title = name
        return w
    }

    override func availabilityProblem() -> String? {
        screen() == nil ? "The display for \(name) was disconnected. The output has stopped." : nil
    }

    override var closeReason: String { "The window for \(name) was closed." }
}
