// FIX-M (debug builds only): `UI_SNAPSHOT_FIXM=1` with the ui-snapshots hook replays drag-and-drop sessions through the window's real
// drag-destination entry points (NSDraggingDestination: draggingEntered, draggingUpdated, draggingExited, performDragOperation on the
// view AppKit would pick under the pointer). SwiftUI's own `dropDestination`, `isTargeted` and `onMove` code runs for each call, as in a
// real drag. What cannot be replayed without a hand: the drag source's image (AppKit builds it when the user starts dragging) and the
// system's own cursor and autoscroll loop. Each replay reports the main-thread cost per hover update, the drop's synchronous cost, the
// longest main-thread stall around the drop, database commits and output publications.
#if DEBUG || WF_MEASURE
import AppKit
import Domain
import OperatorCore

/// A drag the way AppKit hands it to a destination: a pasteboard, a location in window coordinates and the allowed operations.
final class ReplayedDrag: NSObject, NSDraggingInfo {
    let window: NSWindow
    var point: NSPoint
    let pasteboard: NSPasteboard
    init(window: NSWindow, point: NSPoint, pasteboard: NSPasteboard) { self.window = window; self.point = point; self.pasteboard = pasteboard }
    var draggingDestinationWindow: NSWindow? { window }
    var draggingSourceOperationMask: NSDragOperation { [.copy, .move, .generic] }
    var draggingLocation: NSPoint { point }
    var draggedImageLocation: NSPoint { point }
    var draggedImage: NSImage? { nil }
    var draggingPasteboard: NSPasteboard { pasteboard }
    var draggingSource: Any? { nil }
    var draggingSequenceNumber: Int { 1 }
    var draggingFormation: NSDraggingFormation = .default
    var animatesToDestination = false
    var numberOfValidItemsForDrop = 1
    var springLoadingHighlight: NSSpringLoadingHighlight { .none }
    func resetSpringLoading() {}
    func slideDraggedImage(to screenPoint: NSPoint) {}
    func enumerateDraggingItems(options enumOpts: NSDraggingItemEnumerationOptions = [], for view: NSView?, classes classArray: [AnyClass],
                                searchOptions: [NSPasteboard.ReadingOptionKey: Any] = [:], using block: @escaping (NSDraggingItem, Int, UnsafeMutablePointer<ObjCBool>) -> Void) {}
}

struct DropReplayResult {
    var hover: [Double]
    var accepted: Bool
    var dropSync: Double
    var stall: Double
    var settle: Double
    var hoverCommits: Int
    var hoverPublishes: Int
    var dropCommits: Int
    var dropPublishes: Int
    /// FIX-O: how many times each probed view body ran during the drop and the 1.5 s after it (`BodyProbe`).
    var bodies = ""
    /// FIX-Q: the main thread's own CPU time from the drop to the end of the settle time, and its longest uninterrupted burst in one run-loop pass
    /// (`MainThreadMeter`): the stall number above also counts time spent waiting (a display commit waiting for a frame of a locked screen).
    var cpu = 0.0
    var burst = 0.0
    var line: String {
        let s = hover.sorted()
        func pct(_ q: Double) -> Double { s.isEmpty ? 0 : s[min(s.count - 1, Int(Double(s.count) * q))] }
        return String(format: "hover %d updates: median %.2f / 95th %.2f / max %.2f ms, over 8 ms: %d, commits %d, publications %d | drop accepted %@: handler call %.2f ms, longest main-thread stall %.1f ms (includes waits), main-thread CPU %.1f ms, longest CPU burst %.1f ms, last commit %.0f ms after the drop, commits %d, publications %d | bodies: %@",
                      s.count, pct(0.5), pct(0.95), s.last ?? 0, s.filter { $0 > 8 }.count, hoverCommits, hoverPublishes, accepted ? "yes" : "no", dropSync, stall, cpu, burst, settle, dropCommits, dropPublishes, bodies.isEmpty ? "-" : bodies)
    }
}

extension AppModel {
    func runFixMScenario(note: @MainActor (String) -> Void) async {
        guard let workspace, let editor = slideEditor, let window = Self.operatorWindow, let store = libraryStore, let media else { note("fixm: no workspace, editor, window or store"); return }
        let pointer = RealPointer(window: window)
        NSApp.activate(ignoringOtherApps: true)
        window.makeKeyAndOrderFront(nil)
        // 200 slides, 100 bin items (pictures in a scratch folder), as FIX-K.
        let text = (1...200).map { "Line \($0) of the long song" }.joined(separator: "\n\n")
        guard let big = await workspace.importLyrics(title: "Two hundred", primaryText: text, secondaryText: nil, maxLines: 1) else { note("fixm: import failed"); return }
        await workspace.openPresentation(big.id)
        await workspace.addToPlaylist(big.id)
        let folder = URL(fileURLWithPath: Self.snapshotDirectory ?? NSTemporaryDirectory()).appendingPathComponent("bin100", isDirectory: true)
        try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        var urls: [URL] = []
        for n in 0..<100 {
            let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: 320, pixelsHigh: 180, bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
            NSGraphicsContext.saveGraphicsState()
            NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
            NSColor(hue: CGFloat(n % 20) / 20, saturation: 0.6, brightness: 0.7, alpha: 1).setFill()
            NSRect(x: 0, y: 0, width: 320, height: 180).fill()
            NSGraphicsContext.restoreGraphicsState()
            let url = folder.appendingPathComponent(String(format: "pic-%03d.png", n))
            try? rep.representation(using: .png, properties: [:])?.write(to: url)
            urls.append(url)
        }
        addMedia(urls)
        try? await Task.sleep(for: .seconds(6))
        note("fixm setup: \(workspace.slides.count) slides, \(media.assets.count) bin items, playlist items \(workspace.playlistItems.count)")

        let diagnose = false
        func counters() -> (commits: Int, publishes: Int) { (store.commitCount, debugPublishCount) }

        /// The view AppKit would deliver the drag to at `p` (window points, top-left origin): the deepest view under it that registered for drags.
        func destinations(at p: CGPoint) -> [NSView] {
            guard let content = window.contentView else { return [] }
            var all: [NSView] = []
            func walk(_ v: NSView) { if !v.registeredDraggedTypes.isEmpty { all.append(v) }; v.subviews.forEach(walk) }
            walk(content)
            let at = pointer.location(p)
            return all.filter { !$0.isHidden && $0.convert($0.bounds, to: nil).contains(at) }
                .sorted { $0.bounds.width * $0.bounds.height < $1.bounds.width * $1.bounds.height }
        }
        /// The innermost registered view that wants the drag (AppKit asks each in turn).
        func destination(at p: CGPoint, info: ReplayedDrag, entering: Bool) -> NSView? {
            let candidates = destinations(at: p)
            for view in candidates {
                if entering { if !view.draggingEntered(info).isEmpty { return view } } else { return view }
            }
            return nil
        }

        /// Replays one drag: enters at `path[0]`, updates along the path (16 ms apart), drops at the last point, or leaves without dropping.
        func replay(_ pb: NSPasteboard, path: [CGPoint], drop: Bool = true, settleMs: Int = 1500) async -> DropReplayResult {
            var hover: [Double] = []
            let start = counters()
            let info = ReplayedDrag(window: window, point: pointer.location(path[0]), pasteboard: pb)
            let enter = ContinuousClock.now
            var current = destination(at: path[0], info: info, entering: true)
            if diagnose { note("fixm diag: \(destinations(at: path[0]).count) candidate views, entered \(current != nil)") }
            hover.append(RealPointer.ms(ContinuousClock.now - enter))
            for p in path.dropFirst() {
                info.point = pointer.location(p)
                let t0 = ContinuousClock.now
                let inside = current.map { $0.convert($0.bounds, to: nil).contains(info.point) } ?? false
                if !inside { current?.draggingExited(info); current = destination(at: p, info: info, entering: true) }
                if let c = current { _ = c.draggingUpdated(info) }
                let sync = RealPointer.ms(ContinuousClock.now - t0)
                let before = ContinuousClock.now
                try? await Task.sleep(for: .milliseconds(16))
                hover.append(sync + max(0, RealPointer.ms(ContinuousClock.now - before) - 16))
            }
            let mid = counters()
            guard drop, let target = current else {
                current?.draggingExited(info)
                return DropReplayResult(hover: hover, accepted: false, dropSync: 0, stall: 0, settle: 0, hoverCommits: mid.commits - start.commits, hoverPublishes: mid.publishes - start.publishes, dropCommits: 0, dropPublishes: 0)
            }
            var longest = 0.0, stop = false
            var lastCommit = 0.0
            BodyProbe.reset()
            let meter = MainThreadMeter.shared
            meter.install(); meter.resetBurst()
            let cpu0 = meter.cpu()
            let t0 = ContinuousClock.now
            let ticker = Task { @MainActor in
                var last = ContinuousClock.now
                var seen = counters().commits
                while !stop {
                    try? await Task.sleep(for: .milliseconds(2))
                    let now = ContinuousClock.now
                    longest = max(longest, RealPointer.ms(now - last) - 2); last = now
                    if counters().commits != seen { seen = counters().commits; lastCommit = RealPointer.ms(now - t0) }
                }
            }
            let ready = target.prepareForDragOperation(info)
            if diagnose { note("fixm diag: prepare -> \(ready)") }
            let accepted = ready && target.performDragOperation(info)
            if accepted { target.concludeDragOperation(info) }
            let sync = RealPointer.ms(ContinuousClock.now - t0)
            try? await Task.sleep(for: .milliseconds(settleMs))
            let settle = lastCommit
            stop = true
            _ = await ticker.value
            let end = counters()
            return DropReplayResult(hover: hover, accepted: accepted, dropSync: sync, stall: longest, settle: settle, hoverCommits: mid.commits - start.commits, hoverPublishes: mid.publishes - start.publishes,
                                    dropCommits: end.commits - mid.commits, dropPublishes: end.publishes - mid.publishes, bodies: BodyProbe.summary(),
                                    cpu: meter.cpu() - cpu0, burst: meter.longestBurst)
        }

        func board(_ string: String) -> NSPasteboard {
            let pb = NSPasteboard(name: NSPasteboard.Name("fixm-\(UUID().uuidString)"))
            pb.clearContents(); pb.setString(string, forType: .string); return pb
        }
        func board(file url: URL) -> NSPasteboard {
            let pb = NSPasteboard(name: NSPasteboard.Name("fixm-\(UUID().uuidString)"))
            pb.clearContents(); pb.writeObjects([url as NSURL]); return pb
        }
        func centre(_ id: String) -> CGPoint? { pointer.rect(id).map { CGPoint(x: $0.midX, y: $0.midY) } }
        func visible(_ prefix: String, suffix: String = "") -> [(Int, CGPoint)] {
            (0..<400).compactMap { i in centre("\(prefix)\(i)\(suffix)").map { (i, $0) } }.sorted { $0.1.y == $1.1.y ? $0.1.x < $1.1.x : $0.1.y < $1.1.y }
        }
        func report(_ kind: String, _ r: DropReplayResult) { note("fixm[\(kind)]: \(r.line)") }
        func settle(_ s: Double = 2.5) async { try? await Task.sleep(for: .seconds(s)) }

        // ---- Show mode: the slide grid.
        workspace.setMode(.show)
        workspace.selectSlide(100)
        await settle(1.5)
        let cells = visible("main.cell.")
        note("fixm: \(cells.count) grid cells realised; first \(cells.first?.0 ?? -1), last \(cells.last?.0 ?? -1)")
        do {      // FIX-Q: what the window costs by itself over the same 1.5 s the drops are measured over
            let m = MainThreadMeter.shared
            m.install(); m.resetBurst()
            let c0 = m.cpu()
            try? await Task.sleep(for: .seconds(1.5))
            note(String(format: "fixm: idle 1.5 s, grid on screen, no drag: main-thread CPU %.1f ms, longest CPU burst %.1f ms", m.cpu() - c0, m.longestBurst))
        }
        // Profiling aid: UI_SNAPSHOT_FIXM_LOOP=background|reorder repeats one drop 120 times so `sample` can see where the main thread spends it.
        if let loop = ProcessInfo.processInfo.environment["UI_SNAPSHOT_FIXM_LOOP"], cells.count > 4 {
            let pics = media.assets.filter { $0.kind == .image }
            note("fixm loop \(loop) starts")
            let loops = Int(ProcessInfo.processInfo.environment["UI_SNAPSHOT_FIXM_LOOPS"] ?? "") ?? 120
            for n in 0..<loops {
                if loop == "background" { _ = await replay(board(SlideBackgroundDrop.dragText(for: pics[n % pics.count].id)), path: [cells[4].1, cells[4].1], settleMs: 20) }
                else { _ = await replay(board(n % 2 == 0 ? "149" : "10"), path: [cells[4].1, cells[4].1], settleMs: 20) }
                try? await Task.sleep(for: .milliseconds(60))
            }
            note("fixm loop done")
            return
        }
        func gridPath(_ n: Int = 24) -> [CGPoint] {
            guard cells.count > 3 else { return [] }
            return (0..<n).map { cells[($0 * 3 / 2 + 1) % cells.count].1 }     // across neighbouring cells, row by row
        }
        if let target = cells.dropFirst(2).first {
            var path = gridPath(); path.append(target.1)
            report("slide reorder in the grid (slide 150 to cell \(target.0 + 1))", await replay(board("149"), path: path))
        }
        await settle()
        if let pic = media.assets.first(where: { $0.kind == .image }), cells.count > 4 {
            var path = gridPath(); path.append(cells[4].1)
            report("bin tile onto a slide (grid)", await replay(board(SlideBackgroundDrop.dragText(for: pic.id)), path: path))
        }
        await settle()
        if cells.count > 5, let url = urls.first {
            var path = gridPath(); path.append(cells[5].1)
            report("file from Finder onto a slide (grid)", await replay(board(file: url), path: path))
        }
        await settle()
        // ---- Show mode: the dock (files onto the dock).
        if let dock = pointer.rect("dock"), let url = urls.dropFirst(1).first {
            let a = CGPoint(x: dock.minX + 40, y: dock.midY), b = CGPoint(x: dock.maxX - 40, y: dock.midY)
            let path = (0...24).map { CGPoint(x: a.x + (b.x - a.x) * Double($0) / 24, y: a.y) }
            report("files from Finder onto the dock", await replay(board(file: url), path: path))
        }
        await settle()
        // ---- Playlist: List.onMove calls the model; the table's own drag loop cannot be replayed, so this is the handler only.
        do {
            func timed(_ label: String, _ work: () async -> Void) async {
                var longest = 0.0, stop = false
                let ticker = Task { @MainActor in
                    var last = ContinuousClock.now
                    while !stop { try? await Task.sleep(for: .milliseconds(2)); let now = ContinuousClock.now; longest = max(longest, RealPointer.ms(now - last) - 2); last = now }
                }
                let before = counters(), t0 = ContinuousClock.now
                await work()
                let total = RealPointer.ms(ContinuousClock.now - t0)
                try? await Task.sleep(for: .milliseconds(300))
                stop = true; _ = await ticker.value
                let after = counters()
                note(String(format: "fixm[%@]: handler (model call) total %.1f ms, longest main-thread stall %.1f ms, commits %d, publications %d", label, total, longest, after.commits - before.commits, after.publishes - before.publishes))
            }
            if let song = workspace.presentations.first(where: { $0.id != big.id }) { await workspace.addToPlaylist(song.id) }
            await settle(1)
            await timed("playlist reorder (List onMove, model call)") { if let item = workspace.playlistItems.first { await workspace.movePlaylistItem(id: item.id, to: max(0, workspace.playlistItems.count - 1)) } }
        }
        // ---- Edit mode: the filmstrip.
        workspace.setMode(.edit)
        workspace.selectSlide(100)
        await settle(1.5)
        let strip = visible("ed.fs.cell.")
        note("fixm: \(strip.count) filmstrip cells realised")
        if strip.count > 4, let pic = media.assets.first(where: { $0.kind == .image }) {
            let path = (0..<24).map { strip[($0 + 1) % strip.count].1 } + [strip[3].1]
            report("bin tile onto a filmstrip cell", await replay(board(SlideBackgroundDrop.dragText(for: pic.id)), path: path))
            report("slide reorder text onto a filmstrip cell (refused)", await replay(board("12"), path: path))
        }
        await settle()
        // ---- Media mode: the bin.
        workspace.setMode(.media)
        await settle(1.5)
        if let grid = pointer.rect("media.grid"), let url = urls.dropFirst(2).first {
            let a = CGPoint(x: grid.minX + 40, y: grid.minY + 60), b = CGPoint(x: grid.maxX - 40, y: grid.minY + 200)
            let path = (0...24).map { CGPoint(x: a.x + (b.x - a.x) * Double($0) / 24, y: a.y + (b.y - a.y) * Double($0) / 24) }
            report("files from Finder onto the bin", await replay(board(file: url), path: path))
        } else { note("fixm: no media grid rectangle") }
        await settle()
        // ---- FIX-O: single gestures that change the show state. Each runs 5 times; main-thread time of the call, the longest stall around it, and
        // how many times each probed view body ran (BodyProbe). A cell body count is the number of grid cells drawn again.
        if ProcessInfo.processInfo.environment["UI_SNAPSHOT_FIXO"] != nil {
            workspace.setMode(.show); workspace.selectSlide(0); await settle(1.5)
            func gesture(_ label: String, repeats: Int = 5, _ work: @MainActor (Int) async -> Void) async {
                var rows: [String] = []
                for n in 0..<repeats {
                    var longest = 0.0, stop = false
                    BodyProbe.reset()
                    let ticker = Task { @MainActor in
                        var last = ContinuousClock.now
                        while !stop { try? await Task.sleep(for: .milliseconds(2)); let now = ContinuousClock.now; longest = max(longest, RealPointer.ms(now - last) - 2); last = now }
                    }
                    let t0 = ContinuousClock.now
                    await work(n)
                    let call = RealPointer.ms(ContinuousClock.now - t0)
                    try? await Task.sleep(for: .milliseconds(700))
                    stop = true; _ = await ticker.value
                    rows.append(String(format: "call %.1f ms, stall %.1f ms, bodies: %@", call, longest, BodyProbe.summary().isEmpty ? "-" : BodyProbe.summary()))
                    try? await Task.sleep(for: .milliseconds(300))
                }
                for (n, r) in rows.enumerated() { note("fixo[\(label)] run \(n + 1): \(r)") }
            }
            let slideIDs = workspace.slides.map(\.id)
            await gesture("selection change (a cell on screen)") { n in workspace.selectSlide(2 + n * 2) }
            await gesture("preview refresh (edit of a slide off screen)") { n in
                var c = workspace.slides[150].content; c.primary = "Edited \(n) of the long song"
                workspace.editSlide(id: slideIDs[150], content: c)
            }
            await gesture("preview refresh (edit of a slide on screen, not selected)") { n in
                var c = workspace.slides[8].content; c.primary = "Edited here \(n) of the long song"
                workspace.editSlide(id: slideIDs[8], content: c)
            }
            workspace.goLive(at: 3)
            await settle(2)
            await gesture("Next") { _ in await workspace.next() }
            await gesture("Previous") { _ in await workspace.previous() }
            await gesture("Blackout on and off") { _ in workspace.blackout(); try? await Task.sleep(for: .milliseconds(300)); workspace.blackout() }
            await gesture("Clear then Go Live") { _ in workspace.clear(); try? await Task.sleep(for: .milliseconds(300)); workspace.goLive(at: 3) }
            workspace.stop()
            await settle(1)
        }
        _ = editor; _ = big
    }
}
#endif
