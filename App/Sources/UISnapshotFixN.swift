// FIX-N (debug builds only): `UI_SNAPSHOT_FIXN=1` with the ui-snapshots hook sends REAL mouse and key events (NSApp.sendEvent, so they pass the
// app's own key monitor and the window's responder chain) in Edit, Stage and Screens: after a click on a canvas box, after a drag, after a
// sheet closes and after a mode change. For each case it logs what had focus and what Right, Space, Return, B, B and Escape did to the show.
// Nothing here runs without the flag, and it only ever opens a window output, never a display.
#if DEBUG || WF_MEASURE
import AppKit
import Domain
import OperatorCore

extension AppModel {
    func runFixNKeyScenario(note: @MainActor (String) -> Void, capture: @MainActor (String) async -> Void) async {
        guard let workspace, let stage, let editor = slideEditor, let window = Self.operatorWindow else { note("fixn: no workspace, stage, editor or window"); return }
        let pointer = RealPointer(window: window)
        NSApp.activate(ignoringOtherApps: true)
        window.makeKeyAndOrderFront(nil)
        try? await Task.sleep(for: .milliseconds(600))
        note("fixn: app active \(NSApp.isActive), window key \(window.isKeyWindow), size \(Int(window.frame.width)) x \(Int(window.frame.height))")
        func fmt(_ f: NormalizedRect?) -> String { f.map { String(format: "x %.4f y %.4f", $0.x, $0.y) } ?? "-" }

        // A Stage layout whose boxes do not overlap, opened by the Stage mode.
        guard let band = stage.createLayout(name: "Band") else { note("fixn: no layout"); return }
        let ids = band.elements.map(\.id)
        if ids.count >= 4 {
            stage.setFrame(ids[0], in: band.id, x: 0.04, y: 0.09, width: 0.66, height: 0.42)
            stage.setFrame(ids[1], in: band.id, x: 0.04, y: 0.60, width: 0.66, height: 0.22)
            stage.setFrame(ids[2], in: band.id, x: 0.74, y: 0.09, width: 0.22, height: 0.15)
            stage.setFrame(ids[3], in: band.id, x: 0.74, y: 0.32, width: 0.22, height: 0.19)
        }
        StageDesignSeed.openLayoutName = "Band"
        func stageFrame() -> NormalizedRect? { stage.layout(withID: band.id)?.elements[2].frame }

        @MainActor func state(_ extra: String) -> String {
            "live \(show.liveIndex.map { String($0 + 1) } ?? "-") selected \(show.selectedIndex + 1) mode \(mode) \(extra)"
        }
        @MainActor func resetShow() async {
            workspace.selectSlide(0)
            await workspace.goLive()
            workspace.selectSlide(3)
            try? await Task.sleep(for: .milliseconds(250))
        }
        @MainActor func keys(_ label: String, box: () -> String) async {
            try? await Task.sleep(for: .milliseconds(400))
            note("fixn[\(label)]: first responder \(window.firstResponder.map { String(describing: type(of: $0)) } ?? "none"); router focus \(Self.keyFocus(window: window, ui: ui)); sheet \(ui.anySheetOpen)")
            let sequence: [(String, UInt16, String)] = [("Right", 124, "\u{F703}"), ("Return", 36, "\r"), ("Space", 49, " "), ("B", 11, "b"), ("B again", 11, "b"), ("Escape", 53, "\u{1B}")]
            for (name, code, chars) in sequence {
                let before = state(box())
                pointer.key(code, chars)
                try? await Task.sleep(for: .milliseconds(400))
                note("fixn[\(label)]: \(name): \(before) -> \(state(box()))")
            }
        }
        @MainActor func sheetCycle() async {
            ui.showSectionOrders = true
            try? await Task.sleep(for: .milliseconds(700))
            pointer.key(49, " ")
            try? await Task.sleep(for: .milliseconds(300))
            note("fixn: Space with the sheet open: \(state("")) (must not move the show)")
            ui.showSectionOrders = false
            try? await Task.sleep(for: .milliseconds(700))
        }

        // MARK: Edit
        workspace.setMode(.edit)
        try? await Task.sleep(for: .milliseconds(900))
        for scenario in ["click", "drag", "sheet", "mode"] {
            await resetShow()
            guard let id = editor.add(.textBox) else { note("fixn: no Edit object"); continue }
            editor.select(nil)
            try? await Task.sleep(for: .milliseconds(500))
            guard let f = editor.objects.first(where: { $0.id == id })?.frame else { continue }
            func box() -> String { "object \(fmt(editor.objects.first { $0.id == id }?.frame)) selected \(editor.selectedObjectID == id)" }
            // The press: what the box's gesture does first (select, mark the canvas as clicked last); a drag then begins, moves and ends the interaction.
            editor.select(id)
            ui.canvasLastClicked = true
            if scenario == "drag" {
                editor.beginInteraction()
                for step in 1...10 { editor.move(id, from: f, dx: 0.04 * Double(step) / 10, dy: 0.02 * Double(step) / 10); try? await Task.sleep(for: .milliseconds(20)) }
                editor.endInteraction()
            }
            if scenario == "sheet" { await sheetCycle() }
            if scenario == "mode" {
                workspace.setMode(.show); try? await Task.sleep(for: .milliseconds(500))
                workspace.setMode(.edit); try? await Task.sleep(for: .milliseconds(700))
            }
            await keys("Edit, after \(scenario)", box: box)
            editor.delete(id)
        }
        // Item 8: a button has keyboard focus, the canvas was clicked last: the arrows still nudge the selected box. The button's focus is reported the
        // way every drawn button reports its own (`wfFocusReport`).
        do {
            await resetShow()
            if let id = editor.add(.rectangle) {
                editor.select(id); ui.canvasLastClicked = true
                let buttonID = UUID()
                ui.controlFocus(id: buttonID, .button, true)
                let before = editor.objects.first { $0.id == id }?.frame
                pointer.key(124, "\u{F703}"); pointer.key(125, "\u{F701}", shift: true)
                try? await Task.sleep(for: .milliseconds(400))
                let after = editor.objects.first { $0.id == id }?.frame
                note("fixn[Edit, button focused, canvas clicked last]: router focus \(Self.keyFocus(window: window, ui: ui)); Right then Shift-Down: \(fmt(before)) -> \(fmt(after)); selected slide \(show.selectedIndex + 1)")
                pointer.key(49, " ")
                try? await Task.sleep(for: .milliseconds(300))
                note("fixn[Edit, button focused]: Space goes to the button, not the show: \(state(""))")
                ui.controlFocus(id: buttonID, .button, false)
                editor.delete(id)
            }
        }

        // MARK: Stage
        workspace.setMode(.stage)
        try? await Task.sleep(for: .milliseconds(1500))
        for scenario in ["click", "drag", "sheet", "mode"] {
            await resetShow()
            guard let el = pointer.rect("st.cv.el.2") else { note("fixn: no Stage box rectangle"); break }
            await fixNStagePress(box: el, drag: scenario == "drag" ? CGSize(width: -40, height: 20) : nil)
            note("fixn: Stage \(scenario): box selected with handles drawn \(pointer.rect("st.cv.handle.0") != nil); canvas registered \(StageCanvasDebug.isRegistered); box rect \(Int(el.minX)),\(Int(el.minY)) \(Int(el.width))x\(Int(el.height)); layout editable \(stage.isEditable(band.id))")
            if scenario == "sheet" { await sheetCycle() }
            if scenario == "mode" {
                workspace.setMode(.show); try? await Task.sleep(for: .milliseconds(500))
                workspace.setMode(.stage); try? await Task.sleep(for: .milliseconds(1200))
            }
            await keys("Stage, after \(scenario)") { "box \(fmt(stageFrame()))" }
        }
        // Item 5 and item 8 on the Stage: a held arrow (30 auto-repeats), then release; and a button focused with the canvas clicked last.
        if let el = pointer.rect("st.cv.el.2") {
            await resetShow()
            await fixNStagePress(box: el, drag: nil)
            var count = 0
            let previous = stage.onChange
            stage.onChange = { count += 1; previous?() }
            let publishes = debugPublishCount
            let before = stageFrame()
            for i in 0..<30 { pointer.key(124, "\u{F703}", isRepeat: i > 0, up: false) }
            try? await Task.sleep(for: .milliseconds(150))
            let held = stageFrame()
            pointer.key(124, "\u{F703}", isRepeat: false, up: true, down: false)
            try? await Task.sleep(for: .milliseconds(300))
            note("fixn[Stage, held Right x30]: stored box while held \(fmt(held)) (was \(fmt(before))); after release \(fmt(stageFrame())); stage writes \(count), screens republished \(debugPublishCount - publishes)")
            stage.onChange = previous
            let buttonID = UUID()
            ui.controlFocus(id: buttonID, .button, true)
            ui.canvasLastClicked = true
            let b2 = stageFrame()
            pointer.key(125, "\u{F701}", shift: true)
            try? await Task.sleep(for: .milliseconds(900))
            note("fixn[Stage, button focused, canvas clicked last]: router focus \(Self.keyFocus(window: window, ui: ui)); Shift-Down: \(fmt(b2)) -> \(fmt(stageFrame()))")
            ui.controlFocus(id: buttonID, .button, false)
        }

        // MARK: Screens (no canvas box: a click on a screen row and a drag over the signal map)
        workspace.setMode(.screens)
        try? await Task.sleep(for: .milliseconds(1200))
        for scenario in ["click", "drag", "sheet", "mode"] {
            await resetShow()
            // Screens has no canvas box: the press is a click on the first screen's row (it selects that screen).
            ui.selectedScreenID = profiles.first?.id
            ui.canvasLastClicked = false
            if scenario == "sheet" { await sheetCycle() }
            if scenario == "mode" {
                workspace.setMode(.show); try? await Task.sleep(for: .milliseconds(500))
                workspace.setMode(.screens); try? await Task.sleep(for: .milliseconds(800))
            }
            await keys("Screens, after \(scenario)") { "" }
        }
        // MARK: FIX-V item 1: a macro's function key (F5 selects the Worship Look), real key events in every mode, in the operator window and in another one.
        if let cue {
            for name in ["Worship", "Sermon"] { addLook(); if let last = looks.last { renameLook(last.id, to: name) } }
            if let worship = looks.first(where: { $0.name == "Worship" }), let sermon = looks.first(where: { $0.name == "Sermon" }),
               let macro = await cue.createMacro(name: "F5 test") {
                await cue.setSteps([.selectLook(worship.id)], of: macro.id)
                await cue.setKey(.f5, for: macro.id)
                @MainActor func f5(_ label: String, in target: RealPointer, shift: Bool = false, isRepeat: Bool = false, expectRun: Bool) async {
                    selectLook(sermon.id)
                    let before = cue.activity.count
                    target.key(96, "\u{F708}", shift: shift, isRepeat: isRepeat)
                    try? await Task.sleep(for: .milliseconds(500))
                    await cue.settled()
                    let ran = currentLook?.name == "Worship"
                    let lines = cue.activity.last.map { "\($0.source.label): \($0.text)" } ?? "none"; _ = before
                    note("fixv[\(label)]: F5 \(ran ? "ran the macro" : "did nothing") (expected \(expectRun ? "ran" : "nothing")); last activity line \(lines) \(ran == expectRun ? "OK" : "MISMATCH")")
                }
                for mode in WorkspaceMode.allCases {
                    workspace.setMode(mode)
                    try? await Task.sleep(for: .milliseconds(900))
                    await f5("mode \(mode)", in: pointer, expectRun: mode == .show || mode == .cues)
                }
                workspace.setMode(.show)
                try? await Task.sleep(for: .milliseconds(700))
                let buttonID = UUID()
                ui.controlFocus(id: buttonID, .toggle, true)
                await f5("Show, a toggle focused", in: pointer, expectRun: true)
                ui.controlFocus(id: buttonID, .toggle, false)
                await f5("Show, Shift held", in: pointer, shift: true, expectRun: false)
                await f5("Show, key repeat", in: pointer, isRepeat: true, expectRun: false)
                ui.showSectionOrders = true
                try? await Task.sleep(for: .milliseconds(700))
                await f5("Show, a sheet open", in: pointer, expectRun: false)
                ui.showSectionOrders = false
                try? await Task.sleep(for: .milliseconds(700))
                let other = NSWindow(contentRect: NSRect(x: 200, y: 200, width: 300, height: 200), styleMask: [.titled, .closable], backing: .buffered, defer: false)
                other.isReleasedWhenClosed = false
                other.title = "Other window"
                other.makeKeyAndOrderFront(nil)
                try? await Task.sleep(for: .milliseconds(400))
                await f5("another window (not the operator window)", in: RealPointer(window: other), expectRun: false)
                other.close()
                window.makeKeyAndOrderFront(nil)
                try? await Task.sleep(for: .milliseconds(300))
                await f5("Show, back in the operator window", in: pointer, expectRun: true)
            } else { note("fixv: no macro") }
        }
        workspace.setMode(.show)
        await resetShow()
        note("fixn: done")
    }
}
#endif
