// FIX-I (debug builds only): `UI_SNAPSHOT_FIXI=1` with the ui-snapshots hook sends REAL key events (NSApp.sendEvent, so they pass the
// app's own key monitor and the window's responder chain) after real mouse events: at launch, after a click in the slide grid, the
// sidebar, the inspector and the media bin, and after a sheet closes. For each it logs what had focus, what the router decided and
// what the keys did to the show. Nothing here runs without the flag, and it only ever opens a window output, never a display.
#if DEBUG
import AppKit
import Domain
import OperatorCore

extension AppModel {
    func runFixIKeyScenario(note: @MainActor (String) -> Void, capture: @MainActor (String) async -> Void) async {
        guard let workspace, let window = Self.operatorWindow else { note("fixi: no workspace or window"); return }

        @MainActor func chain() -> String {
            var names: [String] = []
            var responder: NSResponder? = window.firstResponder
            while let r = responder, names.count < 6 { names.append(String(describing: type(of: r))); responder = r.nextResponder }
            return names.joined(separator: " > ")
        }
        @MainActor func key(_ code: UInt16, _ chars: String, shift: Bool = false) {
            for type in [NSEvent.EventType.keyDown, .keyUp] {
                guard let event = NSEvent.keyEvent(with: type, location: .zero, modifierFlags: shift ? [.shift] : [], timestamp: ProcessInfo.processInfo.systemUptime,
                                                   windowNumber: window.windowNumber, context: nil, characters: chars, charactersIgnoringModifiers: chars,
                                                   isARepeat: false, keyCode: code) else { continue }
                NSApp.sendEvent(event)
            }
        }
        @MainActor func rect(_ id: String) -> CGRect? {
            DesignProbe.dump(window: window).first { ($0["id"] as? String) == id }.flatMap {
                guard let x = $0["x"] as? Double, let y = $0["y"] as? Double, let w = $0["w"] as? Double, let h = $0["h"] as? Double else { return nil }
                return CGRect(x: x, y: y, width: w, height: h)
            }
        }
        @MainActor func click(_ id: String, double: Bool = false) -> Bool {
            guard let r = rect(id) else { note("fixi: no rectangle named \(id)"); return false }
            let point = NSPoint(x: r.midX, y: window.frame.height - r.midY)       // probe rectangles are top-left, the window is bottom-left
            for count in 1...(double ? 2 : 1) {
                for type in [NSEvent.EventType.leftMouseDown, .leftMouseUp] {
                    guard let event = NSEvent.mouseEvent(with: type, location: point, modifierFlags: [], timestamp: ProcessInfo.processInfo.systemUptime,
                                                         windowNumber: window.windowNumber, context: nil, eventNumber: 0, clickCount: count,
                                                         pressure: type == .leftMouseDown ? 1 : 0) else { continue }
                    NSApp.sendEvent(event)
                }
            }
            return true
        }
        @MainActor func state() -> String {
            let bg = media?.layers.background.flatMap { media?.asset($0.selection.assetID)?.name } ?? "-"
            let bin = ui.binSelection.flatMap { media?.asset($0)?.name } ?? "-"
            return "live \(show.liveIndex.map(String.init) ?? "-") selected \(show.selectedIndex) bin \(bin) liveBackground \(bg)"
        }
        @MainActor func probe(_ label: String, keys: [(String, UInt16, String, Bool)]) async {
            try? await Task.sleep(for: .milliseconds(500))
            let focus = Self.keyFocus(window: window, ui: ui)
            note("fixi[\(label)]: section \(effectiveKeySection); focusedControl \(String(describing: ui.focusedControl)); router focus \(focus); sheet \(ui.anySheetOpen); columns grid \(ui.gridColumns) bin \(ui.binColumns)")
            for (name, code, chars, shift) in keys {
                let before = state()
                key(code, chars, shift: shift)
                try? await Task.sleep(for: .milliseconds(450))
                note("fixi[\(label)]: \(name): \(before) -> \(state())")
            }
        }
        let right = ("Right", UInt16(124), "\u{F703}", false), left = ("Left", UInt16(123), "\u{F702}", false), down = ("Down", UInt16(125), "\u{F701}", false)
        let space = ("Space", UInt16(49), " ", false), shiftSpace = ("Shift-Space", UInt16(49), " ", true), ret = ("Return", UInt16(36), "\r", false)
        @MainActor func resetGrid() async {
            media?.dropBackgroundOverride()
            workspace.selectSlide(1)
            await workspace.goLive()
            workspace.selectSlide(1)
            try? await Task.sleep(for: .milliseconds(200))
        }

        workspace.setMode(.show)
        // The slide grid has the arrows: Right and Left move the selection only; Return takes the selection live; Space is Next.
        let gridKeys = [right, right, left, down, ret, space, shiftSpace]
        await resetGrid()
        await probe("launch", keys: gridKeys)
        if click("main.cell.1") { await resetGrid(); await probe("after a click in the slide grid", keys: gridKeys) }
        if click("sb.song.0") { await resetGrid(); await probe("after a click in the sidebar (grid was last)", keys: gridKeys) }
        if click("insp.mon.0.thumb") { await resetGrid(); await probe("after a click in the inspector (grid was last)", keys: gridKeys) }
        // The media bin: one click on a tile (the dock acts on a single click) makes the bin the keyboard's section.
        if click("dock.tile.0") {
            await resetGrid()
            let binKeys = [right, right, left, left, down, ret, space]
            await probe("after a click in the media bin", keys: binKeys)
            if click("sb.song.0") { await probe("after a click in the sidebar (bin was last)", keys: [right, left]) }
            if click("insp.mon.0.thumb") { await probe("after a click in the inspector (bin was last)", keys: [right, left]) }
            if click("main.cell.1") { await resetGrid(); await probe("after a click back in the slide grid", keys: [right, left]) }
        }
        if ProcessInfo.processInfo.environment["UI_SNAPSHOT_FIXI_BG"] != nil { await runFixIBackgroundScenario(note: note, capture: capture) }
        ui.showSectionOrders = true
        try? await Task.sleep(for: .milliseconds(800))
        note("fixi: a sheet is open: \(ui.anySheetOpen)")
        key(124, "\u{F703}")
        try? await Task.sleep(for: .milliseconds(300))
        note("fixi: Right with the sheet open: \(state())")
        ui.showSectionOrders = false
        try? await Task.sleep(for: .milliseconds(800))
        await resetGrid()
        await probe("after closing a sheet", keys: gridKeys)
    }
}

extension AppModel {
    /// FIX-I items 4, 5, 6 and 7 in the running app: thumbnails with backgrounds (and what 200 of them cost), Clear background dropping a bin
    /// choice, the thumbnail menu's actions, and the fault card fading on an injected clock.
    func runFixIBackgroundScenario(note: @MainActor (String) -> Void, capture: @MainActor (String) async -> Void) async {
        guard let workspace, let media, let editor = slideEditor else { note("fixi-bg: no models"); return }
        func resident() -> Int {
            var info = mach_task_basic_info(); var count = mach_msg_type_number_t(MemoryLayout<mach_task_basic_info>.size / MemoryLayout<natural_t>.size)
            let result = withUnsafeMutablePointer(to: &info) { $0.withMemoryRebound(to: integer_t.self, capacity: Int(count)) { task_info(mach_task_self_, task_flavor_t(MACH_TASK_BASIC_INFO), $0, &count) } }
            return result == KERN_SUCCESS ? Int(info.resident_size) : 0
        }
        guard let video = media.assets.first(where: { $0.kind == .video }), let pictures = Optional(media.assets.filter { $0.kind == .image }), pictures.count >= 2 else { note("fixi-bg: need a video and two pictures"); return }
        workspace.setMode(.show)
        media.dropBackgroundOverride()
        // Item 5: own backgrounds on slides 1 (video), 2 (picture) and 3 (picture); the others have the theme's.
        editor.setBackground(MediaSelection(asset: video), forSlide: workspace.slides[1].id)
        editor.setBackground(MediaSelection(asset: pictures[0]), forSlide: workspace.slides[2].id)
        editor.setBackground(MediaSelection(asset: pictures[1]), forSlide: workspace.slides[3].id)
        for i in 0..<5 {
            let resolved = thumbnailBackground(for: workspace.slides[i].content)
            note("fixi-bg: slide \(i + 1) thumbnail background \(resolved), film mark \(resolved.showsFilmMark)")
        }
        await capture("thumbs")
        note("fixi-bg: stills taken from files \(thumbnailStills.loadCount) (3 files, 3 slides), players opened by thumbnails \(thumbnailStills.openedPlayers)")

        // Item 4: a bin choice goes live, Clear background drops it, Next does not bring it back.
        workspace.selectSlide(0)
        await workspace.goLive()
        media.setBackground(pictures[0].id)
        note("fixi-bg: bin background live \(media.hasLiveBackgroundOverride) (expected true)")
        clearBackground(from: .key)
        try? await Task.sleep(for: .milliseconds(400))
        note("fixi-bg: after Clear background: bin override \(media.hasLiveBackgroundOverride) (expected false), hidden \(show.isBackgroundCleared) (expected true)")
        await workspace.next()
        try? await Task.sleep(for: .milliseconds(300))
        note("fixi-bg: after Next: bin override \(media.hasLiveBackgroundOverride) (expected false), hidden \(show.isBackgroundCleared) (expected false), live slide \(show.liveIndex.map(String.init) ?? "-") with its own background \(workspace.slides[1].content.background != nil)")

        // Item 6: the thumbnail menu's actions: one undo step each, nothing goes live.
        let liveBefore = show.liveIndex
        let target = workspace.slides[2].id
        setSlideBackgroundFromMenu(nil, slideID: target)
        note("fixi-bg: Clear this slide's background on slide 3: own background \(workspace.slides[2].content.background != nil) (expected false), live place \(show.liveIndex.map(String.init) ?? "-") (was \(liveBefore.map(String.init) ?? "-"))")
        editor.undo()
        note("fixi-bg: Undo: slide 3 own background back \(workspace.slides[2].content.background != nil) (expected true)")
        setSlideBackgroundFromMenu(MediaSelection(asset: pictures[1]), slideID: workspace.slides[4].id)
        note("fixi-bg: Set background from the bin on slide 5: \(workspace.slides[4].content.background != nil) (expected true)")
        editor.undo()
        note("fixi-bg: Undo: slide 5 own background \(workspace.slides[4].content.background != nil) (expected false)")

        // Item 5 cost: 200 slides, one render each through the thumbnail path (still, then Compositor at 320 x 180, cached by scene and still).
        let own = [MediaSelection(asset: video), MediaSelection(asset: pictures[0]), nil, MediaSelection(asset: pictures[1])]
        let contents: [SlideContent] = (0..<200).map { i in var c = SlideContent(primary: "Slide \(i + 1) words"); c.background = own[i % 4]; return c }
        let memoryBefore = resident()
        let loadsBefore = thumbnailStills.loadCount
        @MainActor func pass() async -> Double {
            let start = ContinuousClock.now
            for c in contents {
                if let selection = c.background, let asset = media.asset(selection.assetID) { _ = await thumbnailStills.ensure(asset) }
                let scene = thumbnailScene(for: c)
                let variant = c.background.flatMap { thumbnailStills.loadedKey(for: $0.assetID) }
                _ = await PreviewRenderer.shared.image(for: scene, width: 320, height: 180, cached: true, frames: scene.backgroundMedia != nil ? thumbnailStills : nil, variant: variant)
            }
            let elapsed = ContinuousClock.now - start
            return Double(elapsed.components.seconds) * 1000 + Double(elapsed.components.attoseconds) / 1e15
        }
        let cold = await pass()
        let memoryAfter = resident()
        let warm = await pass()
        note(String(format: "fixi-bg: 200 thumbnails with backgrounds: first pass %.0f ms (%.1f ms each), second pass from the cache %.0f ms; stills taken from files %d; players opened %d; resident memory %+.1f MB",
                    cold, cold / 200, warm, thumbnailStills.loadCount - loadsBefore, thumbnailStills.openedPlayers, Double(memoryAfter - memoryBefore) / 1_048_576))

        // Item 7: a faulted output's card on an injected clock.
        if ProcessInfo.processInfo.environment["UI_SNAPSHOT_SDI"] != nil {
            var offset: TimeInterval = 0
            let base = Date()
            faultClock = { base.addingTimeInterval(offset) }
            simulateSDIUnplug()
            try? await Task.sleep(for: .milliseconds(1500))
            refreshFaultVisibility()
            note("fixi-bg: fault cards \(faultCards.map(\.name)), shown \(shownFaultCards.map(\.name)), pills \(rolePills.map { "\($0.abbreviation) \($0.statusWord)" })")
            offset += 4; refreshFaultVisibility()
            note("fixi-bg: 4 s later shown \(shownFaultCards.count) (expected \(faultCards.count))")
            offset += 2; refreshFaultVisibility()
            note("fixi-bg: 6 s later shown \(shownFaultCards.count) (expected 0), still faulted \(!faultCards.isEmpty), pills \(rolePills.map { "\($0.abbreviation) \($0.statusWord)" })")
            if let role = faultCards.first.flatMap({ card in readouts.first { $0.id == card.screenID }?.role }) {
                showFaultCards(for: role)
                note("fixi-bg: pill clicked: shown \(shownFaultCards.count) (expected: the cards of that role only)")
                if let id = faultCards.first?.screenID {
                    faultCardPointer(true, screenID: id)
                    offset += 30; refreshFaultVisibility()
                    note("fixi-bg: pointer over for 30 s: shown \(shownFaultCards.count) (expected \(faultCards.count))")
                    faultCardPointer(false, screenID: id)
                    note("fixi-bg: pointer left: shown \(shownFaultCards.count) (expected 0)")
                }
            }
            simulateSDIReplug()
        }
    }
}
#endif
