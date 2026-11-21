// OUT-001: ordinary resizable 16:9 window.
import AppKit
import Domain

@MainActor
public final class WindowOutput: MetalOutput {
    private let cascadeIndex: Int

    /// `mediaSource` supplies the frames of chosen background and foreground media (MEDIA-002).
    /// `cascadeIndex` offsets the window so several output windows do not open on top of each other.
    public init(name: String = "Output window", sceneProvider: @escaping SceneProvider,
                videoSource: (any VideoSourceFactory)? = nil, cascadeIndex: Int = 0,
                mediaSource: (any MediaFrameSource)? = nil) {
        self.cascadeIndex = cascadeIndex
        super.init(name: name, sceneProvider: sceneProvider, videoSource: videoSource, mediaSource: mediaSource)
    }

    override func makeWindow() -> NSWindow {
        let w = OutputWindow(contentRect: NSRect(x: 0, y: 0, width: 960, height: 540),
                             styleMask: [.titled, .closable, .miniaturizable, .resizable], backing: .buffered, defer: false)
        w.applyOutputPolicy()
        w.title = name
        w.contentAspectRatio = NSSize(width: 16, height: 9)
        w.contentMinSize = NSSize(width: 320, height: 180)
        w.backgroundColor = .black
        w.center()
        if cascadeIndex > 0 {
            let o = w.frame.origin
            w.setFrameOrigin(NSPoint(x: o.x + Double(cascadeIndex) * 48, y: o.y - Double(cascadeIndex) * 48))
        }
        return w
    }

    override var closeReason: String { "\(name) was closed." }
}
