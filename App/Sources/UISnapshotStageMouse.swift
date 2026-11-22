// UI-005e / FIX-K (debug builds only): drives the running Stage editor with real mouse events (mouse down, dragged, up sent to the window,
// the same path a hand takes) and reports what moved. `UI_SNAPSHOT_STAGE_DRAG=1` with the Stage scenario. Reads the canvas boxes from the
// design probe (`st.cv.el.N`), the frames from the model, and counts the model's publish calls (a write) during and after each drag.
#if DEBUG
import AppKit
import Domain
import OperatorCore

extension AppModel {
    @MainActor private func stageEvent(_ type: NSEvent.EventType, _ p: CGPoint, _ window: NSWindow, count: Int, flags: NSEvent.ModifierFlags = []) {
        let location = NSPoint(x: p.x, y: window.frame.height - p.y)
        guard let e = NSEvent.mouseEvent(with: type, location: location, modifierFlags: flags, timestamp: ProcessInfo.processInfo.systemUptime,
                                         windowNumber: window.windowNumber, context: nil, eventNumber: count, clickCount: 1, pressure: 1) else { return }
        window.sendEvent(e)
    }

    @MainActor private func stageKey(_ code: UInt16, _ chars: String, _ window: NSWindow, shift: Bool = false) {
        for type in [NSEvent.EventType.keyDown, .keyUp] {
            guard let e = NSEvent.keyEvent(with: type, location: .zero, modifierFlags: shift ? [.shift] : [], timestamp: ProcessInfo.processInfo.systemUptime,
                                           windowNumber: window.windowNumber, context: nil, characters: chars, charactersIgnoringModifiers: chars,
                                           isARepeat: false, keyCode: code) else { continue }
            NSApp.sendEvent(e)
        }
    }

    @MainActor private func stageProbe(_ id: String, _ window: NSWindow) -> CGRect? {
        DesignProbe.dump(window: window).first { ($0["id"] as? String) == id }.flatMap {
            guard let x = $0["x"] as? Double, let y = $0["y"] as? Double, let w = $0["w"] as? Double, let h = $0["h"] as? Double else { return nil }
            return CGRect(x: x, y: y, width: w, height: h)
        }
    }

    func driveStageMouse(note: @MainActor (String) -> Void, window: NSWindow?) async {
        guard let stage, let window, let layout = stage.customLayouts.first(where: { $0.name == "Band" }) else { note("mouse: no Band layout"); return }
        let previous = stage.onChange
        var writes = 0
        stage.onChange = { writes += 1; previous?() }
        defer { stage.onChange = previous }
        func frame(_ i: Int) -> String {
            guard let f = stage.layout(withID: layout.id)?.elements[i].frame else { return "?" }
            return String(format: "x%.3f y%.3f w%.3f h%.3f", f.x, f.y, f.width, f.height)
        }
        var n = 0
        NSApp.activate(ignoringOtherApps: true); window.makeKeyAndOrderFront(nil)      // focus only follows a key window
        window.undoManager?.groupsByEvent = false      // each release is its own event in a hand; here they share one run-loop pass, so group them by hand
        func pause(_ ms: Int = 60) async { try? await Task.sleep(for: .milliseconds(ms)) }
        func drag(_ label: String, element i: Int, grab: (CGRect) -> CGPoint, by d: CGSize) async {
            guard let box = stageProbe("st.cv.el.\(i)", window) else { note("mouse \(label): box not drawn"); return }
            let start = grab(box)
            let before = frame(i)
            let writesBefore = writes
            n += 1; stageEvent(.leftMouseDown, start, window, count: n)
            await pause()
            var midFrameChanged = false
            for step in 1...8 {
                let p = CGPoint(x: start.x + d.width * Double(step) / 8, y: start.y + d.height * Double(step) / 8)
                n += 1; stageEvent(.leftMouseDragged, p, window, count: n)
                await pause(40)
                if step == 4, let moved = stageProbe("st.cv.el.\(i)", window), abs(moved.minX - box.minX) + abs(moved.minY - box.minY) + abs(moved.width - box.width) + abs(moved.height - box.height) > 0.5 { midFrameChanged = true }
            }
            let writesDuring = writes - writesBefore
            window.undoManager?.beginUndoGrouping()
            n += 1; stageEvent(.leftMouseUp, CGPoint(x: start.x + d.width, y: start.y + d.height), window, count: n)
            window.undoManager?.endUndoGrouping()
            await pause(400)
            note("mouse \(label): before \(before) after \(frame(i)); box drawn moving mid-drag: \(midFrameChanged); writes during drag \(writesDuring), after release \(writes - writesBefore - writesDuring)")
        }
        // The harness itself: a click on another layout's card must change the element list (Band has six rows, Speaker four).
        func rows() -> Int { DesignProbe.dump(window: window).filter { ($0["id"] as? String ?? "").hasPrefix("st.insp.el.") && !($0["id"] as? String ?? "").dropFirst(11).contains(".") }.count }
        if let card = stageProbe("st.side.card.1", window) {
            let p = CGPoint(x: card.midX, y: card.midY)
            let r0 = rows()
            n += 1; stageEvent(.leftMouseDown, p, window, count: n); await pause(); n += 1; stageEvent(.leftMouseUp, p, window, count: n)
            await pause(500)
            let r1 = rows()
            if let back = stageProbe("st.side.card.0", window) {
                let q = CGPoint(x: back.midX, y: back.midY)
                n += 1; stageEvent(.leftMouseDown, q, window, count: n); await pause(); n += 1; stageEvent(.leftMouseUp, q, window, count: n)
                await pause(500)
            }
            note("mouse harness: element rows before click \(r0), after clicking the Speaker card \(r1), after clicking Band again \(rows())")
        }
        if let box = stageProbe("st.cv.el.2", window), let root = window.contentView?.superview {
            let hit = root.hitTest(NSPoint(x: box.midX, y: window.frame.height - box.midY))
            var chain: [String] = []
            var v = hit
            while let node = v, chain.count < 6 { chain.append(String(describing: type(of: node))); v = node.superview }
            note("mouse hit test at the clock box centre: \(chain.joined(separator: " < "))")
        }
        // A click on a box: the inspector's heading (st.insp.h) changes width with the selected element's name.
        if let box = stageProbe("st.cv.el.2", window), let h0 = stageProbe("st.insp.h", window) {
            let p = CGPoint(x: box.midX, y: box.midY)
            n += 1; stageEvent(.leftMouseDown, p, window, count: n); await pause(); n += 1; stageEvent(.leftMouseUp, p, window, count: n)
            await pause(500)
            note("mouse click on the clock box: inspector heading width \(h0.width) -> \(stageProbe("st.insp.h", window)?.width ?? -1) (changes if the click selected it)")
        }
        // Select, then move (a). Current slide: grab inside its box.
        await drag("move current", element: 0, grab: { CGPoint(x: $0.midX, y: $0.midY - 20) }, by: CGSize(width: 60, height: 40))
        await drag("move next", element: 1, grab: { CGPoint(x: $0.midX, y: $0.maxY - 15) }, by: CGSize(width: -40, height: -30))
        await drag("move clock", element: 2, grab: { CGPoint(x: $0.midX, y: $0.midY) }, by: CGSize(width: -50, height: 20))
        func handle(_ i: Int) -> (CGRect) -> CGPoint {
            { _ in self.stageProbe("st.cv.handle.\(i)", window).map { CGPoint(x: $0.midX, y: $0.midY) } ?? .zero }
        }
        let centre: (CGRect) -> CGPoint = { CGPoint(x: $0.midX, y: $0.midY - 20) }
        // The clock is selected (last drag): its eight handles are drawn. Handles are numbered TL, T, TR, L, R, BL, B, BR.
        await drag("resize clock from handle 7 (bottom-right)", element: 2, grab: handle(7), by: CGSize(width: 30, height: 20))
        await drag("resize clock from handle 0 (top-left)", element: 2, grab: handle(0), by: CGSize(width: 20, height: 10))
        await drag("select current (a click)", element: 0, grab: centre, by: .zero)
        await drag("resize current from handle 4 (right)", element: 0, grab: handle(4), by: CGSize(width: -40, height: 0))
        await drag("resize current from handle 1 (top)", element: 0, grab: handle(1), by: CGSize(width: 0, height: 25))
        await drag("select next (a click)", element: 1, grab: { CGPoint(x: $0.midX, y: $0.maxY - 15) }, by: .zero)
        await drag("resize next from handle 6 (bottom)", element: 1, grab: handle(6), by: CGSize(width: 0, height: -20))
        await drag("resize next from handle 5 (bottom-left)", element: 1, grab: handle(5), by: CGSize(width: 25, height: -5))
        // Keys: the canvas has focus after a press; nudge the selected element (next) with the arrow keys, then undo the last nudge.
        let keyBefore = frame(1)
        note("mouse key focus before the arrows: control focus \(String(describing: ui.focusedControl)), first responder \(window.firstResponder.map { String(describing: type(of: $0)) } ?? "none")")
        window.undoManager?.beginUndoGrouping()
        stageKey(123, String(UnicodeScalar(NSLeftArrowFunctionKey)!), window)
        window.undoManager?.endUndoGrouping()
        await pause(200)
        let afterOne = frame(1)
        window.undoManager?.beginUndoGrouping()
        stageKey(125, String(UnicodeScalar(NSDownArrowFunctionKey)!), window, shift: true)
        window.undoManager?.endUndoGrouping()
        await pause(300)
        let afterTwo = frame(1)
        NSApp.sendAction(Selector(("undo:")), to: nil, from: nil)
        await pause(300)
        note("mouse arrows on the selected element (next): before \(keyBefore); after Left \(afterOne); after Shift+Down \(afterTwo); after one Undo \(frame(1))")
        // The element under a drag is the one picked: a press on the empty canvas clears the selection.
        // The built-in layout: select its card, press on the lyric box and drag; nothing may change or be written.
        if let card = stageProbe("st.side.card.3", window) {
            let p = CGPoint(x: card.midX, y: card.midY)
            n += 1; stageEvent(.leftMouseDown, p, window, count: n); await pause(); n += 1; stageEvent(.leftMouseUp, p, window, count: n)
            await pause(600)
            let standardBefore = StageLayout.standard.elements[0].frame
            if let box = stageProbe("st.cv.el.0", window) {
                let start = CGPoint(x: box.midX, y: box.midY)
                let writesBefore = writes
                n += 1; stageEvent(.leftMouseDown, start, window, count: n)
                for step in 1...6 { n += 1; stageEvent(.leftMouseDragged, CGPoint(x: start.x + 10 * Double(step), y: start.y + 6 * Double(step)), window, count: n); await pause(40) }
                let moved = stageProbe("st.cv.el.0", window)
                n += 1; stageEvent(.leftMouseUp, CGPoint(x: start.x + 60, y: start.y + 36), window, count: n)
                await pause(300)
                note("mouse built-in Standard: lyric box drawn at x \(box.minX) -> \(moved?.minX ?? -1) during the drag, \(stageProbe("st.cv.el.0", window)?.minX ?? -1) after; stored frame unchanged: \(stage.layout(withID: StageLayout.standardID)?.elements[0].frame == standardBefore); writes \(writes - writesBefore); note shown: \(stageProbe("st.cv.caption", window) != nil)")
            }
        }
        note("mouse: done")
    }
}
#endif
