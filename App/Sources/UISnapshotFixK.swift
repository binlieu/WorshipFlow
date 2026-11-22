// FIX-K (debug builds only): `UI_SNAPSHOT_FIXK=1` with the ui-snapshots hook drives the running app with REAL mouse events (NSApp.sendEvent:
// mouse down, mouse dragged, mouse up, so they pass the window's hit test and SwiftUI's gestures, as a pointer's do) and real key events,
// and logs what moved. Items 3 and 7 of AI/specs/FIX-K-hands-on-build-115.md: the Edit canvas (an object, a handle, a lyric box, the arrow
// keys) and the other drags the app has (slide grid, filmstrip, bin tiles, playlist rows, scrubber). Nothing here runs without the flag.
// The synthetic events do not start AppKit's own drag session (that needs the system's drag loop), so the drag-and-drop kinds are measured at
// the point they run: the drop destination's and the move's handlers, and the model's counters. The report says which.
#if DEBUG || WF_MEASURE
import AppKit
import Domain
import OperatorCore

/// Real mouse and key events for the operator window, and per-event timing.
@MainActor struct RealPointer {
    let window: NSWindow

    func rect(_ id: String) -> CGRect? {
        let dump = DesignProbe.dump(window: window)
        // FIX-Q: a Release measuring build (WF_MEASURE) draws no design tags (they would slow it below the shipped app), so the dump is empty; the drop
        // targets the drag replays need are then found from the views that registered for drags.
        if dump.isEmpty { return dropViewRect(id) }
        return dump.first { ($0["id"] as? String) == id }.flatMap {
            guard let x = $0["x"] as? Double, let y = $0["y"] as? Double, let w = $0["w"] as? Double, let h = $0["h"] as? Double else { return nil }
            return CGRect(x: x, y: y, width: w, height: h)
        }
    }

    /// The views that accept drops, as rectangles in window points with a top-left origin, one per distinct frame.
    private func dropViewRects() -> [CGRect] {
        guard let content = window.contentView else { return [] }
        var found: [CGRect] = []
        func walk(_ v: NSView) {
            if !v.registeredDraggedTypes.isEmpty, !v.isHidden {
                let r = v.convert(v.bounds, to: nil)
                let top = CGRect(x: r.minX.rounded(), y: (window.frame.height - r.maxY).rounded(), width: r.width.rounded(), height: r.height.rounded())
                if !found.contains(top), top.width > 0, top.height > 0 { found.append(top) }
            }
            v.subviews.forEach(walk)
        }
        walk(content)
        return found
    }

    /// Stand-ins for the tagged views: "main.cell.k" is the k-th slide cell of the Show grid and "ed.fs.cell.k" the k-th filmstrip cell (row by row, as on
    /// screen), "dock" the media dock, "media.grid" the Media bin. Any other id is not found.
    private func dropViewRect(_ id: String) -> CGRect? {
        let all = dropViewRects()
        func order(_ a: CGRect, _ b: CGRect) -> Bool { abs(a.minY - b.minY) > 4 ? a.minY < b.minY : a.minX < b.minX }
        if id.hasPrefix("main.cell."), let k = Int(id.dropFirst("main.cell.".count)), !id.dropFirst("main.cell.".count).contains(".") {
            let cells = all.filter { (90...330).contains($0.width) && (50...280).contains($0.height) && $0.minX > 200 && $0.minY > 40 }.sorted(by: order)
            return cells.indices.contains(k) ? cells[k] : nil
        }
        if id.hasPrefix("ed.fs.cell."), let k = Int(id.dropFirst("ed.fs.cell.".count)) {
            let cells = all.filter { (120...200).contains($0.width) && (60...160).contains($0.height) && $0.minX < 230 }.sorted(by: order)
            return cells.indices.contains(k) ? cells[k] : nil
        }
        if id == "dock" { return all.filter { $0.width > 450 && $0.minY > window.frame.height * 0.55 }.max { $0.width * $0.height < $1.width * $1.height } }
        if id == "media.grid" { return all.filter { $0.width > 300 && $0.height > 200 }.max { $0.width * $0.height < $1.width * $1.height } }
        return nil
    }

    /// Window points, top-left origin, to the event's bottom-left origin.
    func location(_ p: CGPoint) -> NSPoint { NSPoint(x: p.x, y: window.frame.height - p.y) }

    @discardableResult
    func send(_ type: NSEvent.EventType, at p: CGPoint, clicks: Int = 1, flags: NSEvent.ModifierFlags = []) -> Double {
        guard let event = NSEvent.mouseEvent(with: type, location: location(p), modifierFlags: flags, timestamp: ProcessInfo.processInfo.systemUptime,
                                             windowNumber: window.windowNumber, context: nil, eventNumber: 0, clickCount: clicks,
                                             pressure: type == .leftMouseUp ? 0 : 1) else { return 0 }
        let start = ContinuousClock.now
        NSApp.sendEvent(event)
        return Self.ms(ContinuousClock.now - start)
    }

    /// A click as a hand makes it: down, a short pause, up.
    func click(at p: CGPoint, clicks: Int = 1) async {
        send(.leftMouseDown, at: p, clicks: clicks)
        try? await Task.sleep(for: .milliseconds(60))
        send(.leftMouseUp, at: p, clicks: clicks)
        try? await Task.sleep(for: .milliseconds(250))
    }

    func key(_ code: UInt16, _ chars: String, shift: Bool = false, isRepeat: Bool = false, up: Bool = true, down: Bool = true) {
        for type in [NSEvent.EventType.keyDown, .keyUp] {
            if type == .keyDown, !down { continue }
            if type == .keyUp, !up { continue }
            guard let event = NSEvent.keyEvent(with: type, location: .zero, modifierFlags: shift ? [.shift] : [], timestamp: ProcessInfo.processInfo.systemUptime,
                                               windowNumber: window.windowNumber, context: nil, characters: chars, charactersIgnoringModifiers: chars,
                                               isARepeat: isRepeat, keyCode: code) else { continue }
            NSApp.sendEvent(event)
        }
    }

    static func ms(_ d: Duration) -> Double { Double(d.components.seconds) * 1000 + Double(d.components.attoseconds) / 1e15 }

    /// Mouse down at `from`, `steps` dragged events along the straight line to `to` (one every `gap` ms), mouse up. Returns, for each dragged
    /// event, the main thread's cost: the time inside sendEvent plus how late the next wake-up was (the run loop was busy drawing).
    func drag(from: CGPoint, to: CGPoint, steps: Int = 30, gap: Int = 16, flags: NSEvent.ModifierFlags = []) async -> DragTiming {
        var costs: [Double] = []
        let down = send(.leftMouseDown, at: from, flags: flags)
        try? await Task.sleep(for: .milliseconds(gap))
        for i in 1...steps {
            let t = Double(i) / Double(steps)
            let p = CGPoint(x: from.x + (to.x - from.x) * t, y: from.y + (to.y - from.y) * t)
            let sync = send(.leftMouseDragged, at: p, flags: flags)
            let before = ContinuousClock.now
            try? await Task.sleep(for: .milliseconds(gap))
            let late = max(0, Self.ms(ContinuousClock.now - before) - Double(gap))
            costs.append(sync + late)
        }
        let up = send(.leftMouseUp, at: to, flags: flags)
        try? await Task.sleep(for: .milliseconds(120))
        return DragTiming(events: costs, down: down, up: up)
    }
}

struct DragTiming {
    var events: [Double]
    var down: Double
    var up: Double
    var summary: String {
        let sorted = events.sorted()
        func pct(_ q: Double) -> Double { sorted.isEmpty ? 0 : sorted[min(sorted.count - 1, Int(Double(sorted.count) * q))] }
        return String(format: "%d events, main-thread cost per event: median %.2f ms, 95th %.2f ms, max %.2f ms, over 8 ms: %d; mouse down %.2f ms, mouse up %.2f ms",
                      events.count, pct(0.5), pct(0.95), sorted.last ?? 0, events.filter { $0 > 8 }.count, down, up)
    }
}

extension AppModel {
    func runFixKScenario(note: @MainActor (String) -> Void, capture: @MainActor (String) async -> Void) async {
        guard let workspace, let editor = slideEditor, let window = Self.operatorWindow else { note("fixk: no workspace, editor or window"); return }
        let pointer = RealPointer(window: window)
        let only = ProcessInfo.processInfo.environment["UI_SNAPSHOT_FIXK"] ?? "1"
        func wants(_ part: String) -> Bool { only == "1" || only.split(separator: ",").contains(Substring(part)) }
        if wants("edit") { await runFixKEditDrags(pointer: pointer, workspace: workspace, editor: editor, note: note, capture: capture) }
        if wants("clear") { await runFixKClearIcons(workspace: workspace, note: note, capture: capture) }
        if wants("drags") { await runFixKDragMeasurements(pointer: pointer, workspace: workspace, editor: editor, note: note) }
    }

    /// Item 3: real mouse and key events on the Edit canvas.
    func runFixKEditDrags(pointer: RealPointer, workspace: WorkspaceModel, editor: SlideEditorModel, note: @MainActor (String) -> Void,
                          capture: @MainActor (String) async -> Void) async {
        NSApp.activate(ignoringOtherApps: true)
        pointer.window.makeKeyAndOrderFront(nil)
        workspace.setMode(.edit)
        workspace.selectSlide(1)
        try? await Task.sleep(for: .milliseconds(900))
        // Sanity: a real click on a filmstrip cell must select that slide (proves the events reach the window and its gestures).
        if let cell = pointer.rect("ed.fs.cell.3") {
            let p = CGPoint(x: cell.midX, y: cell.midY)
            pointer.send(.leftMouseDown, at: p); pointer.send(.leftMouseUp, at: p)
            try? await Task.sleep(for: .milliseconds(300))
            note("fixk: sanity click on filmstrip cell 4: selected slide \(workspace.show.selectedIndex + 1) (expected 4); app active \(NSApp.isActive), window key \(pointer.window.isKeyWindow)")
            workspace.selectSlide(1)
            try? await Task.sleep(for: .milliseconds(400))
        } else { note("fixk: no filmstrip cell rectangle") }
        guard let canvas = pointer.rect("ed.canvas") else { note("fixk: no Edit canvas rectangle"); return }
        note("fixk: canvas \(Int(canvas.width)) x \(Int(canvas.height)) at \(Int(canvas.minX)),\(Int(canvas.minY)); slide \(workspace.show.selectedIndex + 1); live \(workspace.show.liveIndex.map { String($0 + 1) } ?? "-")")
        func centre(of f: NormalizedRect) -> CGPoint { CGPoint(x: canvas.minX + (f.x + f.width / 2) * canvas.width, y: canvas.minY + (f.y + f.height / 2) * canvas.height) }
        func fmt(_ f: NormalizedRect?) -> String { f.map { String(format: "x %.3f y %.3f w %.3f h %.3f", $0.x, $0.y, $0.width, $0.height) } ?? "-" }
        let liveBefore = workspace.show.liveSlide?.primary

        // An added text box: mouse down in its middle, 30 dragged events, mouse up. Then an added shape.
        for (name, template) in [("text box", NewSlideObject.textBox), ("rectangle", .rectangle)] {
            guard let id = editor.add(template) else { continue }
            editor.select(nil)                                       // not selected: the first press must select it, as a person's does
            try? await Task.sleep(for: .milliseconds(500))
            let start = editor.objects.first { $0.id == id }?.frame
            guard let start else { continue }
            let canUndoBefore = editor.canUndo
            let timing = await pointer.drag(from: centre(of: start), to: CGPoint(x: centre(of: start).x + 150, y: centre(of: start).y + 60))
            let end = editor.objects.first { $0.id == id }?.frame
            note("fixk[object drag \(name)]: \(fmt(start)) -> \(fmt(end)); selected \(editor.selectedObjectID == id); undo steps recorded \(canUndoBefore ? "yes" : "n/a"); \(timing.summary)")
            // A handle: the bottom right one (index 7) and a side one (index 4, the right middle).
            for (handle, dx, dy) in [(7, 40.0, 30.0), (4, 30.0, 0.0), (0, 20.0, 20.0)] {
                guard let h = pointer.rect("ed.handle.\(handle)") else { note("fixk[handle \(handle) \(name)]: no handle rectangle (selected \(editor.selectedObjectID == id))"); continue }
                let before = editor.objects.first { $0.id == id }?.frame
                let mid = CGPoint(x: h.midX, y: h.midY)
                _ = await pointer.drag(from: mid, to: CGPoint(x: mid.x + dx, y: mid.y + dy), steps: 12)
                note("fixk[handle \(handle) \(name)]: \(fmt(before)) -> \(fmt(editor.objects.first { $0.id == id }?.frame))")
            }
            editor.delete(id)
        }
        if let id = editor.add(.rectangle) {
            for (steps, gap) in [(1, 16), (2, 16), (4, 16), (30, 16), (30, 60), (30, 1)] {
                editor.select(id)
                guard let f0 = editor.objects.first(where: { $0.id == id })?.frame else { continue }
                editor.setFrame(id, x: 0.1, y: 0.1, width: 0.2, height: 0.3)
                try? await Task.sleep(for: .milliseconds(300))
                let a = CGPoint(x: canvas.minX + 0.2 * canvas.width, y: canvas.minY + 0.25 * canvas.height)
                _ = await pointer.drag(from: a, to: CGPoint(x: a.x + 160, y: a.y), steps: steps, gap: gap)
                let f1 = editor.objects.first { $0.id == id }?.frame
                note("fixk[drag variants]: steps \(steps) gap \(gap) ms: moved \(String(format: "%.1f", ((f1?.x ?? 0) - 0.1) * canvas.width)) px of 160 (was \(fmt(f0)))")
            }
            editor.delete(id)
        }
        note("fixk: live words unchanged by editing: \(workspace.show.liveSlide?.primary == liveBefore)")
        await fixKLyricDrags(pointer: pointer, workspace: workspace, editor: editor, canvas: canvas, note: note, capture: capture)
    }

    func fixKLyricDrags(pointer: RealPointer, workspace: WorkspaceModel, editor: SlideEditorModel, canvas: CGRect, note: @MainActor (String) -> Void,
                        capture: @MainActor (String) async -> Void) async {
        func fmt(_ f: NormalizedRect?) -> String { f.map { String(format: "x %.3f y %.3f w %.3f h %.3f", $0.x, $0.y, $0.width, $0.height) } ?? "-" }
        func centre(of f: NormalizedRect) -> CGPoint { CGPoint(x: canvas.minX + (f.x + f.width / 2) * canvas.width, y: canvas.minY + (f.y + f.height / 2) * canvas.height) }
        workspace.selectSlide(1)
        editor.select(nil)
        try? await Task.sleep(for: .milliseconds(700))
        let liveBefore = workspace.show.liveSlide
        let others = workspace.slides.enumerated().filter { $0.offset != 1 }.map { $0.element.content.textFrames }
        guard let first = editor.lyricFrame(.primary) else { note("fixk[lyric]: no lyric box on slide 2"); return }
        note("fixk[lyric]: boxes \(editor.lyricBoxes.keys.map(\.rawValue).sorted()); primary \(fmt(first)); second \(fmt(editor.lyricFrame(.secondary)))")
        // Mouse down in the middle of the first-language box, 30 dragged events, mouse up.
        let from = centre(of: first)
        let timing = await pointer.drag(from: from, to: CGPoint(x: from.x + 120, y: from.y + 60))
        let moved = editor.lyricFrame(.primary)
        note("fixk[lyric drag]: \(fmt(first)) -> \(fmt(moved)); selected \(editor.selectedLyricBox?.rawValue ?? "-"); slide 2 own frame \(workspace.slides[1].content.textFrames?.primary != nil); expected dx 0.150 dy 0.133; \(timing.summary)")
        // A handle of the lyric box (index 7: bottom right), a side one (4) and the top left (0).
        for (handle, dx, dy) in [(7, -40.0, -30.0), (4, 30.0, 0.0), (0, 20.0, 20.0)] {
            guard let h = pointer.rect("ed.handle.\(handle)") else { note("fixk[lyric handle \(handle)]: no handle rectangle"); continue }
            let before = editor.lyricFrame(.primary)
            let mid = CGPoint(x: h.midX, y: h.midY)
            _ = await pointer.drag(from: mid, to: CGPoint(x: mid.x + dx, y: mid.y + dy), steps: 12)
            note("fixk[lyric handle \(handle)]: \(fmt(before)) -> \(fmt(editor.lyricFrame(.primary))) (pointer moved \(Int(dx)) x \(Int(dy)) px = \(String(format: "%.3f", dx / canvas.width)) x \(String(format: "%.3f", dy / canvas.height)))")
        }
        // The arrow keys: real key events through the app's key monitor. Right is 1 point, Shift-Down 10.
        let beforeKeys = editor.lyricFrame(.primary)
        pointer.key(124, "\u{F703}")
        pointer.key(125, "\u{F701}", shift: true)
        try? await Task.sleep(for: .milliseconds(300))
        let afterKeys = editor.lyricFrame(.primary)
        note("fixk[lyric nudge]: Right then Shift-Down: \(fmt(beforeKeys)) -> \(fmt(afterKeys)) (expected x +\(String(format: "%.5f", 1.0 / 1920)), y +\(String(format: "%.5f", 10.0 / 1080))); slide still \(workspace.show.selectedIndex + 1) (expected 2)")
        // Other slides and Live.
        let othersAfter = workspace.slides.enumerated().filter { $0.offset != 1 }.map { $0.element.content.textFrames }
        note("fixk[lyric]: other slides untouched \(others == othersAfter); live slide unchanged \(workspace.show.liveSlide == liveBefore) (live words \(workspace.show.liveSlide?.primary.prefix(20) ?? "-"))")
        await capture("lyric-moved")
        // Context menu action and undo.
        editor.resetLyricFrame(.primary)
        note("fixk[lyric]: after Reset to theme position own frame \(editor.hasOwnFrame(.primary)), box \(fmt(editor.lyricFrame(.primary)))")
        editor.undo()
        note("fixk[lyric]: Undo of the reset brings the frame back: \(editor.hasOwnFrame(.primary))")
        // Click away deselects; a click on blank canvas selects nothing.
        editor.resetLyricFrame(.primary)
        editor.undo()
        // Clicks: on an unselected lyric box, on an added object over a lyric box, on blank canvas.
        editor.select(nil)
        await pointer.click(at: centre(of: editor.lyricFrame(.secondary) ?? first))
        note("fixk[click]: on the second-language box selects \(editor.selectedLyricBox?.rawValue ?? "nothing") (expected secondary)")
        if let id = editor.add(.rectangle) {
            editor.selectLyric(.primary)
            try? await Task.sleep(for: .milliseconds(500))
            if let f = editor.objects.first(where: { $0.id == id })?.frame {
                await pointer.click(at: centre(of: f))
                note("fixk[click]: on an added object selects \(editor.selectedObjectID == id ? "the object" : (editor.selectedLyricBox.map { "lyric \($0.rawValue)" } ?? "nothing")) (expected the object)")
            }
            editor.delete(id)
        }
        await pointer.click(at: CGPoint(x: canvas.minX + canvas.width + 30, y: canvas.minY + 20))
        note("fixk[click]: on the empty area beside the canvas selects \(editor.selectedLyricBox?.rawValue ?? "nothing")")
    }

    /// Item 1: which clear icon lights, to which layer a bin video goes, and what each glyph is (the rule printed here is the one in `MediaClearButtons`).
    func runFixKClearIcons(workspace: WorkspaceModel, note: @MainActor (String) -> Void, capture: @MainActor (String) async -> Void) async {
        guard let media, let video = media.assets.first(where: { $0.kind == .video }) else { note("fixk[clear]: no video in the bin"); return }
        workspace.setMode(.show)
        try? await Task.sleep(for: .milliseconds(600))
        func icons() -> String {
            let st = workspace.show
            let rule = ClearIconRule.describe(live: ClearLiveState(hasLiveWords: st.liveSlide != nil, backgroundKind: media.layers.background?.selection.kind,
                backgroundName: media.layers.background.flatMap { media.asset($0.selection.assetID)?.name }, foregroundKind: media.layers.foreground?.selection.kind,
                foregroundName: media.layers.foreground.flatMap { media.asset($0.selection.assetID)?.name }, musicName: audio?.activeCues.last.flatMap { media.asset($0.assetID)?.name }))
            // The rule MediaClearButtons used in build 115 (copied): lyric = a live slide; background = a background layer, or the show live and the background not cleared;
            // foreground = a clip over the words; music = a sound cue. Glyphs: lyric text.alignleft, background photo, foreground film, music note, all rectangle.slash.
            let oldBackground = media.layers.background != nil || (!st.isStopped && !st.isBackgroundCleared)
            let old = "build 115: lyric \(st.liveSlide != nil ? "ON" : "off"), background[photo glyph] \(oldBackground ? "ON" : "off"), foreground[film glyph] \(media.layers.foreground != nil ? "ON" : "off"), music \(!(audio?.activeCues.isEmpty ?? true) ? "ON" : "off")"
            return "\(old) | new: \(rule) | layers: background \(media.layers.background.map { "\($0.selection.kind)" } ?? "-"), foreground \(media.layers.foreground.map { "\($0.selection.kind)" } ?? "-"); \(rule)"
        }
        clearBackground(); clearForeground()
        try? await Task.sleep(for: .milliseconds(400))
        note("fixk[clear] 1 nothing on the layers: \(icons())")
        await capture("clear-1-empty")
        selectBinItem(video.id)
        try? await Task.sleep(for: .milliseconds(300))
        note("fixk[clear] 2 video \(video.name) selected in the bin (one click, not sent): \(icons())")
        await capture("clear-2-selected")
        performDockAction(MediaDock.action(for: video, layer: .background))
        try? await Task.sleep(for: .milliseconds(500))
        note("fixk[clear] 3 video sent live to the background layer: \(icons())")
        await capture("clear-3-background")
        clearBackground(); try? await Task.sleep(for: .milliseconds(300))
        performDockAction(MediaDock.action(for: video, layer: .foreground))
        try? await Task.sleep(for: .milliseconds(500))
        note("fixk[clear] 4 video sent live to the foreground layer: \(icons())")
        await capture("clear-4-foreground")
        clearForeground()
    }

    /// Item 7: every drag the app has, with 200 slides and 100 bin items. Drags made of plain gestures are driven with real mouse events and timed per event. The
    /// system's drag and drop (`.draggable`, `dropDestination`, the playlist's `onMove`) starts an AppKit drag session that synthetic events cannot drive, so the
    /// handlers that run at the drop are called directly and timed by a main-thread heartbeat; the drag image and the system's own hover loop are NOT measured.
    func runFixKDragMeasurements(pointer: RealPointer, workspace: WorkspaceModel, editor: SlideEditorModel, note: @MainActor (String) -> Void) async {
        guard let store = libraryStore, let media else { note("fixk[drag]: no store or media"); return }
        NSApp.activate(ignoringOtherApps: true)
        pointer.window.makeKeyAndOrderFront(nil)
        // 200 slides.
        let text = (1...200).map { "Line \($0) of the long song" }.joined(separator: "\n\n")
        guard let big = await workspace.importLyrics(title: "Two hundred", primaryText: text, secondaryText: nil, maxLines: 1) else { note("fixk[drag]: import failed"); return }
        await workspace.openPresentation(big.id)
        await workspace.addToPlaylist(big.id)
        // 100 bin items: small pictures written to a scratch folder next to the pictures.
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
        note("fixk[drag] setup: \(workspace.slides.count) slides, \(media.assets.count) bin items, playlist items \(workspace.playlistItems.count)")
        workspace.setMode(.show)
        workspace.selectSlide(100)
        try? await Task.sleep(for: .seconds(1.5))

        func counters() -> (commits: Int, publishes: Int) { (store.commitCount, debugPublishCount) }
        func report(_ kind: String, _ timing: DragTiming, _ before: (commits: Int, publishes: Int), extra: String = "") {
            let after = counters()
            note("fixk[drag \(kind)]: \(timing.summary); database commits during it \(after.commits - before.commits); output publications \(after.publishes - before.publishes)\(extra)")
        }
        let window = pointer.window
        // Column resize strips.
        let sidebar = CGPoint(x: ui.sidebarWidth, y: 480)
        var c = counters()
        var t = await pointer.drag(from: sidebar, to: CGPoint(x: sidebar.x + 60, y: sidebar.y), steps: 40)
        report("sidebar column resize", t, c, extra: "; width \(Int(ui.sidebarWidth)) (was 256)")
        let inspector = CGPoint(x: window.frame.width - ui.inspectorWidth, y: 480)
        c = counters()
        t = await pointer.drag(from: inspector, to: CGPoint(x: inspector.x - 50, y: inspector.y), steps: 40)
        report("inspector column resize", t, c, extra: "; width \(Int(ui.inspectorWidth)) (was 372)")
        // Dock height strip (top edge of the dock).
        if let dock = pointer.rect("dock") {
            c = counters()
            let from = CGPoint(x: dock.midX, y: dock.minY + 2)
            t = await pointer.drag(from: from, to: CGPoint(x: from.x, y: from.y - 60), steps: 40)
            report("media dock height strip", t, c, extra: "; dock \(Int(dock.height)) pt")
        }
        // The volume slider of the media controller.
        if let volume = pointer.rect("ctl.volume") {
            c = counters()
            t = await pointer.drag(from: CGPoint(x: volume.minX + 4, y: volume.midY), to: CGPoint(x: volume.maxX - 4, y: volume.midY), steps: 30)
            report("volume slider", t, c)
        }
        // Edit canvas with the 200 slides open.
        workspace.setMode(.edit)
        workspace.selectSlide(100)
        try? await Task.sleep(for: .seconds(1))
        if let canvas = pointer.rect("ed.canvas"), let first = editor.lyricFrame(.primary) {
            let from = CGPoint(x: canvas.minX + (first.x + first.width / 2) * canvas.width, y: canvas.minY + (first.y + first.height / 2) * canvas.height)
            c = counters()
            t = await pointer.drag(from: from, to: CGPoint(x: from.x + 100, y: from.y + 40), steps: 40)
            report("Edit lyric box drag", t, c)
            if let h = pointer.rect("ed.handle.7") {
                c = counters()
                t = await pointer.drag(from: CGPoint(x: h.midX, y: h.midY), to: CGPoint(x: h.midX - 60, y: h.midY - 30), steps: 40)
                report("Edit handle drag", t, c)
            }
            if let id = editor.add(.rectangle) {
                try? await Task.sleep(for: .milliseconds(600))
                if let f = editor.objects.first(where: { $0.id == id })?.frame {
                    let p = CGPoint(x: canvas.minX + (f.x + f.width / 2) * canvas.width, y: canvas.minY + (f.y + f.height / 2) * canvas.height)
                    c = counters()
                    t = await pointer.drag(from: p, to: CGPoint(x: p.x + 100, y: p.y + 40), steps: 40)
                    report("Edit object drag", t, c)
                }
                editor.delete(id)
            }
        }
        workspace.setMode(.show)
        try? await Task.sleep(for: .seconds(1))

        // Drops: the handlers, timed by a heartbeat on the main thread (the longest gap between 2 ms ticks while the operation ran).
        @MainActor func heartbeat(_ label: String, _ work: () async -> Void) async {
            var longest = 0.0
            var stop = false
            let ticker = Task { @MainActor in
                var last = ContinuousClock.now
                while !stop {
                    try? await Task.sleep(for: .milliseconds(2))
                    let now = ContinuousClock.now
                    longest = max(longest, RealPointer.ms(now - last) - 2)
                    last = now
                }
            }
            let before = counters()
            let start = ContinuousClock.now
            await work()
            let elapsed = RealPointer.ms(ContinuousClock.now - start)
            try? await Task.sleep(for: .milliseconds(150))
            stop = true
            _ = await ticker.value
            let after = counters()
            note(String(format: "fixk[drop %@]: total %.1f ms, longest main-thread stall %.1f ms; database commits %d; output publications %d", label, elapsed, longest, after.commits - before.commits, after.publishes - before.publishes))
        }
        await heartbeat("slide reorder (grid): slide 150 to 20") { await workspace.moveSlide(from: 149, to: 19) }
        await heartbeat("playlist item reorder") { if let item = workspace.playlistItems.first { await workspace.movePlaylistItem(id: item.id, to: max(0, workspace.playlistItems.count - 1)) } }
        if let song = workspace.presentations.first(where: { $0.id != big.id }) {
            await heartbeat("song into the playlist") { await workspace.addToPlaylist(song.id) }
        }
        if let pic = media.assets.first(where: { $0.kind == .image }), workspace.slides.indices.contains(60) {
            await heartbeat("bin tile onto a slide (own background)") { _ = self.setSlideBackground(mediaID: pic.id, slideID: workspace.slides[60].id) }
        }
        if let url = urls.first {
            let copy = folder.appendingPathComponent("dropped.png")
            try? FileManager.default.copyItem(at: url, to: copy)
            await heartbeat("file from Finder onto the bin") { self.addMedia([copy]); try? await Task.sleep(for: .milliseconds(800)) }
        }
        // Thumbnail layout: scrolling the 200-slide grid costs the same lazily; a layout of the whole grid is one width change.
        c = counters()
        t = await pointer.drag(from: sidebar, to: CGPoint(x: sidebar.x + 100, y: sidebar.y), steps: 40)
        report("sidebar resize again with the full bin", t, c)
    }
}
#endif
