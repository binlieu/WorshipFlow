// OUT-001: ordinary resizable 16:9 window.
import AppKit
import Domain

@MainActor
public final class WindowOutput: MetalOutput {
    override public init(name: String = "Output window", sceneProvider: @escaping SceneProvider,
                         videoSource: (any VideoSourceFactory)? = nil) {
        super.init(name: name, sceneProvider: sceneProvider, videoSource: videoSource)
    }

    override func makeWindow() -> NSWindow {
        let w = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 960, height: 540),
                         styleMask: [.titled, .closable, .miniaturizable, .resizable], backing: .buffered, defer: false)
        w.title = name
        w.contentAspectRatio = NSSize(width: 16, height: 9)
        w.contentMinSize = NSSize(width: 320, height: 180)
        w.backgroundColor = .black
        w.center()
        return w
    }

    override var closeReason: String { "\(name) was closed." }
}
