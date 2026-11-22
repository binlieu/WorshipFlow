// UI-005j tool 2 (debug builds only): names the views that stand for an element of a design mockup, so the window can be dumped as a
// list of rectangles and joined to the mockup's own (scripts/design-rects, scripts/compare-rects.py, scripts/design-map-show.json).
// `.wfRect("sb.libs.row.0")` puts an invisible, non-hit-testable NSView behind the view; the dump asks each live probe for its frame in
// window coordinates (points, top-left origin, the window's frame including the title bar, as the design's 1440 x 900 includes its toolbar).
// The identifier is a name for the dump only: it is not an accessibility identifier and never replaces an accessibility label.
// Optional `size`, `weight` and `radius` are the values the code declares at the tag site (they are not read back from drawing).
// Release builds compile this to nothing.
import SwiftUI

#if DEBUG || WF_MEASURE
import AppKit

final class DesignProbeView: NSView {
    var probeID = ""
    var size: Double?
    var weight: Double?
    var radius: Double?
    /// The frame SwiftUI laid the view out with, in its own window-content coordinates (fractional). An NSView frame is rounded to whole points.
    var exact: CGRect?
    override func hitTest(_ point: NSPoint) -> NSView? { nil }
    override func isAccessibilityElement() -> Bool { false }
    override func viewDidMoveToWindow() { super.viewDidMoveToWindow(); if window != nil { DesignProbe.register(self) } }
}

struct DesignProbeRepresentable: NSViewRepresentable {
    let id: String
    let size: Double?
    let weight: Double?
    let radius: Double?
    let exact: CGRect
    func makeNSView(context: Context) -> DesignProbeView { DesignProbeView() }
    func updateNSView(_ view: DesignProbeView, context: Context) {
        view.probeID = id; view.size = size; view.weight = weight; view.radius = radius; view.exact = exact
    }
}

@MainActor enum DesignProbe {
    private static let views = NSHashTable<DesignProbeView>.weakObjects()
    static func register(_ view: DesignProbeView) { views.add(view) }

    /// Every live, visible probe of `window` as rectangles in the window's top-left coordinates.
    static func dump(window: NSWindow) -> [[String: Any]] {
        var out: [[String: Any]] = []
        let height = window.frame.height
        for view in views.allObjects where view.window === window && !view.probeID.isEmpty {
            var hidden = false
            var node: NSView? = view
            while let n = node { if n.isHidden { hidden = true }; node = n.superview }
            if hidden { continue }
            let r = view.convert(view.bounds, to: nil)
            var (x, y, w, h) = (Double(r.minX), Double(height - r.maxY), Double(r.width), Double(r.height))
            if let e = view.exact {
                // The whole-point origin of the hosting view is the rounded difference; the fractions come from SwiftUI's own layout.
                let ox = (x - Double(e.minX)).rounded(), oy = (y - Double(e.minY)).rounded()
                (x, y, w, h) = (Double(e.minX) + ox, Double(e.minY) + oy, Double(e.width), Double(e.height))
            }
            if w <= 0 || h <= 0 { continue }      // an empty view (no tag drawn) is not an element
            var row: [String: Any] = ["id": view.probeID, "x": x, "y": y, "w": w, "h": h]
            if let s = view.size { row["fontSize"] = s }
            if let w = view.weight { row["fontWeight"] = w }
            if let rad = view.radius { row["radius"] = rad }
            out.append(row)
        }
        return out.sorted { ($0["id"] as? String ?? "") < ($1["id"] as? String ?? "") }
    }

    static func write(window: NSWindow, to url: URL) {
        let payload: [String: Any] = ["window": ["w": Double(window.frame.width), "h": Double(window.frame.height)], "rects": dump(window: window)]
        if let data = try? JSONSerialization.data(withJSONObject: payload, options: [.prettyPrinted, .sortedKeys]) { try? data.write(to: url) }
    }
}

#endif

#if DEBUG
// FIX-Q: the tags are active in Debug only. A Release measuring build (WF_MEASURE) keeps the dump functions so the hooks compile, but draws no tags: the
// probe puts a GeometryReader and an NSView behind every tagged view (several per slide cell), which the shipped app does not have and which made
// a Release measuring build slower than the real one.
extension View {
    func wfRect(_ id: String, size: Double? = nil, weight: Double? = nil, radius: Double? = nil) -> some View {
        background(GeometryReader { g in DesignProbeRepresentable(id: id, size: size, weight: weight, radius: radius, exact: g.frame(in: .global)) })
    }
}
#else
extension View {
    @inline(__always) func wfRect(_ id: String, size: Double? = nil, weight: Double? = nil, radius: Double? = nil) -> some View { self }
}
#endif
