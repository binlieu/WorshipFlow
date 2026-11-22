// FIX-P (debug builds only): `UI_SNAPSHOT_FIXP=1` with the ui-snapshots hook, against a temporary library and no sound:
//  1. L3: after the slide grid had keyboard focus and the mode changed to Stage, what the grid-focus flag and the key router say;
//  2. M4: a Stage drag whose window resigns key, with the gesture's events still arriving (REAL mouse events through the window), once with the
//     canvas's own window and once with another window resigning: where the box ends up and how many events reached the gesture after the resign;
//  3. item 7: the delay from a MIDI message arriving on the app's own virtual port to its command having run, with no load and under a UI load
//     (a 200-slide grid scrolling by the display, a 1080p59.94 clip playing as the background and a Next on every message).
// Nothing here runs without the flag.
#if DEBUG || WF_MEASURE
import AppKit
import CoreMIDI
import Domain
import OperatorCore
import CueEngine
import MIDIIO

extension AppModel {
    func runFixPScenario(note: @MainActor (String) -> Void) async {
        guard let workspace, let stage, let cue, let window = Self.operatorWindow else { note("fixp: no workspace, stage, cue or window"); return }
        let pointer = RealPointer(window: window)
        NSApp.activate(ignoringOtherApps: true)
        window.makeKeyAndOrderFront(nil)
        try? await Task.sleep(for: .milliseconds(800))
        note("fixp: app active \(NSApp.isActive), window key \(window.isKeyWindow), screen locked or not: events go through the window")
        func fmt(_ f: NormalizedRect?) -> String { f.map { String(format: "x %.4f y %.4f", $0.x, $0.y) } ?? "-" }
        let only = ProcessInfo.processInfo.environment["UI_SNAPSHOT_FIXP"] ?? "1"
        func wants(_ part: String) -> Bool { only == "1" || only.split(separator: ",").contains(Substring(part)) }

        // A Stage layout whose boxes do not overlap.
        guard let band = stage.createLayout(name: "Band") else { note("fixp: no layout"); return }
        let ids = band.elements.map(\.id)
        if ids.count >= 4 {
            stage.setFrame(ids[0], in: band.id, x: 0.04, y: 0.09, width: 0.66, height: 0.42)
            stage.setFrame(ids[1], in: band.id, x: 0.04, y: 0.60, width: 0.66, height: 0.22)
            stage.setFrame(ids[2], in: band.id, x: 0.74, y: 0.09, width: 0.22, height: 0.15)
            stage.setFrame(ids[3], in: band.id, x: 0.74, y: 0.32, width: 0.22, height: 0.19)
        }
        StageDesignSeed.openLayoutName = "Band"

        if wants("focus") {
            // 1. L3.
            workspace.setMode(.show)
            try? await Task.sleep(for: .milliseconds(900))
            note("fixp[L3]: in Show: grid flag \(ui.gridHasFocus), router focus \(Self.keyFocus(window: window, ui: ui))")
            workspace.setMode(.stage)
            try? await Task.sleep(for: .milliseconds(1400))
            note("fixp[L3]: after the mode changed to Stage: grid flag \(ui.gridHasFocus) (a stale true here is the finding)")
            if let el = pointer.rect("st.cv.el.2") {
                await fixNStagePress(box: el, drag: nil)
                note("fixp[L3]: after a click on a Stage box: grid flag \(ui.gridHasFocus), first responder \(window.firstResponder.map { String(describing: type(of: $0)) } ?? "none"), router focus \(Self.keyFocus(window: window, ui: ui)), tracker says \(String(describing: ui.controlFocusTracker.current(gridHasFocus: ui.gridHasFocus)))")
                let before = stage.layout(withID: band.id)?.elements[2].frame
                let slide = show.selectedIndex
                pointer.key(124, "\u{F703}")
                try? await Task.sleep(for: .milliseconds(1700))
                note("fixp[L3]: Right arrow: box \(fmt(before)) -> \(fmt(stage.layout(withID: band.id)?.elements[2].frame)), selected slide \(slide + 1) -> \(show.selectedIndex + 1) (the box moves and the slide does not)")
            } else { note("fixp[L3]: no Stage box rectangle") }
        }

        if wants("resign") {
            // 2. M4. Real mouse events through the window.
            workspace.setMode(.stage)
            try? await Task.sleep(for: .milliseconds(1200))
            guard let canvas = pointer.rect("st.cv"), let el = pointer.rect("st.cv.el.2") else { note("fixp[M4]: no canvas"); return }
            func box() -> NormalizedRect? { stage.layout(withID: band.id)?.elements[2].frame }
            for (label, own) in [("the canvas's own window resigns key", true), ("another window resigns key", false)] {
                guard let start = box() else { continue }
                StageCanvasDebug.ignoredEvents = 0
                let from = CGPoint(x: el.midX, y: el.midY)
                pointer.send(.leftMouseDown, at: from)
                for i in 1...5 { pointer.send(.leftMouseDragged, at: CGPoint(x: from.x - 10 * Double(i), y: from.y + 5 * Double(i))); try? await Task.sleep(for: .milliseconds(30)) }
                let other = NSWindow(contentRect: .zero, styleMask: [], backing: .buffered, defer: true)
                NotificationCenter.default.post(name: NSWindow.didResignKeyNotification, object: own ? window : other)
                try? await Task.sleep(for: .milliseconds(100))
                let mid = box()
                for i in 6...10 { pointer.send(.leftMouseDragged, at: CGPoint(x: from.x - 10 * Double(i), y: from.y + 5 * Double(i))); try? await Task.sleep(for: .milliseconds(30)) }
                pointer.send(.leftMouseUp, at: CGPoint(x: from.x - 100, y: from.y + 50))
                try? await Task.sleep(for: .milliseconds(400))
                let end = box()
                func pts(_ f: NormalizedRect?) -> String { f.map { String(format: "%.1f, %.1f", ($0.x - start.x) * canvas.width, ($0.y - start.y) * canvas.height) } ?? "-" }
                note("fixp[M4]: \(label): after 5 drag events and the resign the box has moved \(pts(mid)) pt; after 5 more events and the release \(pts(end)) pt (own window: the drag ended at the resign, so the box must stay near -50, 25, never reach -150, 75 or -100, 50 plus a jump); events that reached the gesture after the resign and were ignored: \(StageCanvasDebug.ignoredEvents)")
                // put it back for the next case
                if let b = box() { stage.setFrame(ids[2], in: band.id, x: start.x, y: start.y, width: b.width, height: b.height) }
                try? await Task.sleep(for: .milliseconds(500))
            }
        }

        if wants("midi") { await fixPMIDILatency(note: note) }
        workspace.setMode(.show)
        note("fixp: done")
    }

    @MainActor private func fixPMIDILatency(note: @MainActor (String) -> Void) async {
        guard let workspace, let cue, let window = Self.operatorWindow else { return }
        let text = (1...200).map { "Slide \($0) first line\nsecond line of the words" }.joined(separator: "\n\n")
        guard let song = await workspace.importLyrics(title: "Two hundred", primaryText: text, secondaryText: nil, maxLines: 2) else { note("fixp[MIDI]: import failed"); return }
        await workspace.openPresentation(song.id)
        workspace.setMode(.show)
        try? await Task.sleep(for: .milliseconds(1500))
        note("fixp[MIDI]: \(workspace.slides.count) slides open; a clip playing as the background: \(media?.layers.background != nil)")
        cue.midiPortsFactory = { try CoreMIDIPorts(clientName: "WorshipFlow fixp run", virtualDestinationName: "WF fixp run In", virtualSourceName: "WF fixp run Out") }
        await cue.saveBinding(MIDIBinding(name: "any note", pattern: MIDIPattern(kind: .noteOn), command: .transport(.next)))
        await cue.setMIDIEnabled(true)
        await cue.setVirtualPorts(true)
        try? await Task.sleep(for: .milliseconds(800))
        workspace.goLive(at: 0)
        try? await Task.sleep(for: .milliseconds(500))

        var client = MIDIClientRef(), port = MIDIPortRef()
        guard MIDIClientCreate("WorshipFlow fixp sender" as CFString, nil, nil, &client) == noErr, MIDIOutputPortCreate(client, "out" as CFString, &port) == noErr else { note("fixp[MIDI]: no sender"); return }
        defer { MIDIClientDispose(client) }
        var destination: MIDIEndpointRef = 0
        for i in 0..<MIDIGetNumberOfDestinations() {
            let d = MIDIGetDestination(i)
            var cfName: Unmanaged<CFString>?
            if MIDIObjectGetStringProperty(d, kMIDIPropertyName, &cfName) == noErr, let name = cfName?.takeRetainedValue() as String?, name == "WF fixp run In" { destination = d }
        }
        guard destination != 0 else { note("fixp[MIDI]: virtual destination not found"); return }

        // The grid's scroll view: the tallest one in the window.
        func scrollViews(_ v: NSView) -> [NSScrollView] { ((v as? NSScrollView).map { [$0] } ?? []) + v.subviews.flatMap(scrollViews) }
        let grid = scrollViews(window.contentView ?? NSView()).max { ($0.documentView?.frame.height ?? 0) < ($1.documentView?.frame.height ?? 0) }
        note("fixp[MIDI]: grid scroll view found \(grid != nil), content height \(Int(grid?.documentView?.frame.height ?? 0)) pt")

        var samples: [Double] = []
        MIDIRouter.debugLatencyProbe = { samples.append($0 * 1000) }
        defer { MIDIRouter.debugLatencyProbe = nil }
        func sendBurst(count: Int, gapMicros: UInt32) async {
            let box = SendBox(port: port, destination: destination, count: count, gapMicros: gapMicros)
            await withCheckedContinuation { (c: CheckedContinuation<Void, Never>) in
                DispatchQueue.global(qos: .userInitiated).async { box.run(); c.resume() }
            }
            try? await Task.sleep(for: .milliseconds(1500))        // let the last ones arrive
        }
        func report(_ label: String, sent: Int) {
            let s = samples.sorted()
            func pct(_ q: Double) -> Double { s.isEmpty ? 0 : s[min(s.count - 1, Int(Double(s.count) * q))] }
            note(String(format: "fixp[MIDI] %@: sent %d, ran %d, median %.1f ms, 95th %.1f ms, max %.1f ms, over 50 ms: %d, over 200 ms: %d", label, sent, s.count, pct(0.5), pct(0.95), s.last ?? 0, s.filter { $0 > 50 }.count, s.filter { $0 > 200 }.count))
        }
        samples = []; workspace.goLive(at: 0)
        await sendBurst(count: 100, gapMicros: 30_000)
        report("idle (nothing else running)", sent: 100)

        // The load: the grid scrolled continuously (a timer on the main run loop, like a trackpad), the clip playing.
        var offset = 0.0, direction = 1.0
        let scroller = Timer.scheduledTimer(withTimeInterval: 1.0 / 60.0, repeats: true) { _ in
            MainActor.assumeIsolated {
                guard let grid, let doc = grid.documentView else { return }
                let maxY = max(1, doc.frame.height - grid.contentView.bounds.height)
                offset += 40 * direction
                if offset > maxY || offset < 0 { direction = -direction; offset = min(max(offset, 0), maxY) }
                grid.contentView.scroll(to: NSPoint(x: 0, y: offset))
                grid.reflectScrolledClipView(grid.contentView)
            }
        }
        try? await Task.sleep(for: .milliseconds(1500))
        samples = []; workspace.goLive(at: 0)
        await sendBurst(count: 200, gapMicros: 30_000)
        report("under load: 200-slide grid scrolling, clip playing, a Next per message", sent: 200)
        samples = []; workspace.goLive(at: 0)
        await sendBurst(count: 200, gapMicros: 5_000)
        report("under load, a fast burst (5 ms apart)", sent: 200)
        scroller.invalidate()
        note("fixp[MIDI]: live slide after the runs \(show.liveIndex.map { String($0 + 1) } ?? "-") of \(workspace.slides.count)")
        await cue.setMIDIEnabled(false)
    }
}

/// Sends note-on and note-off pairs from a plain thread (so the sender's own timing does not depend on the main thread), each stamped with its own host time.
private final class SendBox: @unchecked Sendable {
    let port: MIDIPortRef, destination: MIDIEndpointRef, count: Int, gapMicros: UInt32
    init(port: MIDIPortRef, destination: MIDIEndpointRef, count: Int, gapMicros: UInt32) { self.port = port; self.destination = destination; self.count = count; self.gapMicros = gapMicros }
    func run() {
        var buffer = [UInt8](repeating: 0, count: 256)
        for i in 0..<count {
            let n = UInt8(i % 100 + 10)
            for status in [UInt8(0x90), UInt8(0x80)] {
                let bytes: [UInt8] = [status, n, status == 0x90 ? 100 : 0]
                buffer.withUnsafeMutableBytes { raw in
                    let list = raw.baseAddress!.assumingMemoryBound(to: MIDIPacketList.self)
                    let packet = MIDIPacketListInit(list)
                    _ = MIDIPacketListAdd(list, 256, packet, mach_absolute_time(), 3, bytes)
                    MIDISend(port, destination, list)
                }
                usleep(status == 0x90 ? 2_000 : gapMicros)
            }
        }
    }
}
#endif
