// UI-001 (debug builds only): `--ui-snapshots <dir>` imports a sample bilingual song, puts the audience screen in a window,
// goes live, and writes one picture of the operator window per mode plus one with Blackout on. It also sends the real key
// events for Command-1 to 6 and B through the app's own menu and key monitor and logs what happened. Pictures are drawn by
// the window's own views (no screen capture), so a locked screen does not matter. Nothing here runs without the flag.
#if DEBUG || WF_MEASURE
import AppKit
import Domain
import OperatorCore

extension AppModel {
    static var snapshotDirectory: String? {
        // UI-003: `UI_SNAPSHOT_DIR` is the same thing as `--ui-snapshots <dir>`. On this macOS an extra path argument on the
        // command line stopped the main window from opening at all, so the environment is the safer way to pass it.
        if let dir = ProcessInfo.processInfo.environment["UI_SNAPSHOT_DIR"], !dir.isEmpty { return dir }
        guard let i = CommandLine.arguments.firstIndex(of: "--ui-snapshots"), i + 1 < CommandLine.arguments.count else { return nil }
        return CommandLine.arguments[i + 1]
    }

    func app_dockTab(_ tab: MediaDockTab) { ui.dockTab = tab }
    var app_isCleared: Bool { show.isCleared }

    func runUISnapshotsIfRequested() {
        guard let dir = Self.snapshotDirectory, let workspace else { return }
        Task { @MainActor in
            var log: [String] = []
            @MainActor func note(_ text: String) { log.append(text); FileHandle.standardError.write(Data("[ui-snapshots] \(text)\n".utf8)) }
            try? FileManager.default.createDirectory(atPath: dir, withIntermediateDirectories: true)
            while !workspaceLoaded { try? await Task.sleep(for: .milliseconds(100)) }
            try? await Task.sleep(for: .seconds(1.5))
            for _ in 0..<60 where NSApp.windows.isEmpty { try? await Task.sleep(for: .milliseconds(250)) }
            let window = Self.operatorWindow
            note("policy \(NSApp.activationPolicy().rawValue) active \(NSApp.isActive) windows: \(NSApp.windows.map { "\($0.title)|\($0.identifier?.rawValue ?? "-")|vis=\($0.isVisible)" })")
            window?.setContentSize(NSSize(width: 1440, height: 860))
            window?.center()
            window?.orderFrontRegardless()

            if let choice = ProcessInfo.processInfo.environment["UI_SNAPSHOT_APPEARANCE"].flatMap(AppearanceChoice.init(rawValue:)) { setAppearance(choice) }

            // Sample content: a bilingual song with sections, in the playlist.
            let song = """
            Verse 1:
            Amazing grace, how sweet the sound
            That saved a wretch like me
            I once was lost, but now am found
            Was blind, but now I see

            Chorus:
            Through many dangers, toils and snares
            'Tis grace has brought me safe thus far
            The Lord has promised good to me
            And grace will lead me home

            Ending:
            Amazing grace, amazing grace
            """
            let viet = """
            Verse 1:
            Ân điển lạ lùng thay
            Đã cứu vớt tôi
            Tôi từng lạc mất, nay được tìm thấy
            Từng mù lòa, nay tôi thấy

            Chorus:
            Qua bao hiểm nguy, gian khó thử thách
            Ân điển đưa tôi bình an đến nay
            Chúa đã hứa ban phước lành cho tôi
            Và ân điển sẽ dẫn tôi về nhà

            Ending:
            Ân điển lạ lùng, ân điển lạ lùng
            """
            let designMode = ProcessInfo.processInfo.environment["UI_SNAPSHOT_DESIGN"] != nil
            if let p = await workspace.importLyrics(title: "Amazing Grace", primaryText: designMode ? Self.designSong : song, secondaryText: designMode ? Self.designSongVI : viet, maxLines: 2) {
                _ = await workspace.importLyrics(title: "Be Thou My Vision", primaryText: "Be Thou my vision, O Lord of my heart\nNaught be all else to me", secondaryText: nil, maxLines: 2)
                await workspace.openPresentation(p.id)
                if ProcessInfo.processInfo.environment["UI_SNAPSHOT_SDI"] != nil {
                    await workspace.addHeader("Pre-service")
                    await workspace.addCountdown(CountdownSpec(label: "Starting soon", mode: .duration(seconds: 300)))
                    await workspace.addHeader("Worship")
                }
                await workspace.addToPlaylist(p.id)
            } else { note("import failed: \(workspace.lastError ?? "?")") }
            // UI-003: several files in the bin (comma separated paths); the first video becomes the background that plays.
            if let list = designMode ? Self.designMediaList(in: dir) : ProcessInfo.processInfo.environment["UI_SNAPSHOT_MEDIA"] {
                addMedia(list.split(separator: ",").map { URL(fileURLWithPath: String($0)) })
                try? await Task.sleep(for: .seconds(2.5))
                if let asset = media?.assets.first(where: { $0.kind == .video }) { media?.setBackground(asset.id) }
            }
            // UI-003: a prop (image), timers (service elapsed running, sermon countdown stopped) and a stage message.
            if let path = designMode ? Self.designPropPath(in: dir) : ProcessInfo.processInfo.environment["UI_SNAPSHOT_PROP"] { addProp(URL(fileURLWithPath: path)) }
            if ProcessInfo.processInfo.environment["UI_SNAPSHOT_TIMERS"] != nil || designMode, let stage {
                if let service = stage.addElapsed(name: "Service") { stage.startTimer(service.id) }
                _ = stage.addCountdown(name: "Sermon", minutes: 25, seconds: 0)
            }
            // Window outputs only: never a display.
            for var profile in profiles where profile.role != .broadcast {
                profile.destination = .window
                updateProfile(profile)
            }
            // UI-002: the simulated SDI card, a keyed broadcast screen with a mirror, and the audience screen on a plain connector.
            if ProcessInfo.processInfo.environment["UI_SNAPSHOT_SDI"] != nil {
                setShowSimulatedSDIDevice(true)
                try? await Task.sleep(for: .seconds(1))
                for var profile in profiles {
                    switch profile.role {
                    case .broadcast:
                        profile.isEnabled = true
                        profile.name = "Livestream graphics"
                        profile.destination = .sdi(deviceID: Self.simulatedCardID, connector: 1, keying: true, fillAlphaMode: .premultiplied)
                        profile.mirrors = [.window]
                        profile.setConnectedNote("Switcher key input", mirror: nil)
                        profile.setConnectedNote("Monitor wall", mirror: 0)
                        updateProfile(profile)
                        ui.selectedScreenID = profile.id
                    case .audience:
                        profile.destination = .sdi(deviceID: Self.simulatedCardID, connector: 3, keying: false, fillAlphaMode: .premultiplied)
                        updateProfile(profile)
                    case .stage: break
                    }
                }
                try? await Task.sleep(for: .seconds(1))
                startScreens()
            }
            try? await Task.sleep(for: .seconds(0.5))
            workspace.selectSlide(2)
            await workspace.goLive()
            workspace.selectSlide(3)
            try? await Task.sleep(for: .seconds(2))
            note("live after goLive: \(show.liveIndex.map(String.init) ?? "none"), screensOn: \(screensOn)")

            @MainActor func capture(_ name: String) async {
                try? await Task.sleep(for: .seconds(1.2))
                for _ in 0..<3 {
                    window?.contentView?.superview?.layoutSubtreeIfNeeded()
                    window?.displayIfNeeded()
                    try? await Task.sleep(for: .milliseconds(400))
                }
                guard let view = window?.contentView?.superview ?? window?.contentView else { note("no window to capture"); return }
                // The first draw primes lazily rendered layers (scroll views, glass); the second one is kept.
                for _ in 0..<2 {
                    if let warm = view.bitmapImageRepForCachingDisplay(in: view.bounds) { view.cacheDisplay(in: view.bounds, to: warm) }
                    try? await Task.sleep(for: .milliseconds(600))
                }
                // The layer tree is drawn directly: scroll views and glass draw into layers that cacheDisplay can miss.
                let scale = 2
                let width = Int(view.bounds.width) * scale, height = Int(view.bounds.height) * scale
                guard let layer = view.layer, let space = CGColorSpace(name: CGColorSpace.sRGB),
                      let ctx = CGContext(data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0, space: space,
                                          bitmapInfo: CGImageAlphaInfo.premultipliedFirst.rawValue | CGBitmapInfo.byteOrder32Little.rawValue) else {
                    note("no layer to capture"); return
                }
                ctx.scaleBy(x: CGFloat(scale), y: CGFloat(scale))
                layer.render(in: ctx)
                // UI-005j: the rectangles of every tagged view, for scripts/compare-rects.py.
                if let window { DesignProbe.write(window: window, to: URL(fileURLWithPath: dir).appendingPathComponent("\(ProcessInfo.processInfo.environment["UI_SNAPSHOT_PREFIX"] ?? "UI-001")-\(name).rects.json")) }
                guard let image = ctx.makeImage() else { note("no image"); return }
                let rep = NSBitmapImageRep(cgImage: image)
                if let data = rep.representation(using: .png, properties: [:]) {
                    try? data.write(to: URL(fileURLWithPath: dir).appendingPathComponent("\(ProcessInfo.processInfo.environment["UI_SNAPSHOT_PREFIX"] ?? "UI-001")-\(name).png"))
                    note("wrote \(name).png \(rep.pixelsWide)x\(rep.pixelsHigh)")
                }
            }

            @MainActor func key(_ code: UInt16, _ chars: String, command: Bool = false, shift: Bool = false) {
                guard let window else { return }
                var flags: NSEvent.ModifierFlags = command ? [.command] : []
                if shift { flags.insert(.shift) }
                for type in [NSEvent.EventType.keyDown, .keyUp] {
                    guard let event = NSEvent.keyEvent(with: type, location: .zero, modifierFlags: flags, timestamp: ProcessInfo.processInfo.systemUptime,
                                                       windowNumber: window.windowNumber, context: nil, characters: shift ? chars.uppercased() : chars,
                                                       charactersIgnoringModifiers: shift ? chars.uppercased() : chars, isARepeat: false, keyCode: code) else { continue }
                    if command, type == .keyDown { _ = NSApp.mainMenu?.performKeyEquivalent(with: event) } else { NSApp.sendEvent(event) }
                }
            }

            // Extra Looks so the compact row has something to hold.
            // UI-005b: in the design capture the throw-away library is new, so the app has seeded the design's four Looks itself (Full is
            // selected); nothing is renamed or added here any more.
            if ProcessInfo.processInfo.environment["UI_SNAPSHOT_SDI"] != nil, ProcessInfo.processInfo.environment["UI_SNAPSHOT_DESIGN"] == nil {
                for name in ["Notes", "Lower 3rd", "BG only", "Sermon"] { addLook(); if let last = looks.last { renameLook(last.id, to: name) } }
            }
            if ProcessInfo.processInfo.environment["UI_SNAPSHOT_STAGEMSG"] != nil { stage?.sendMessage("Wrap up in 2 min") }

            // CUE-002b: the cue wiring in the running app (macro, slide action, schedule, MIDI note, remote request), then out.
            if ProcessInfo.processInfo.environment["UI_SNAPSHOT_CUES"] != nil {
                await runCuesScenario(note: { note($0) }, capture: { await capture($0) })
                try? "\(log.joined(separator: "\n"))\n".write(toFile: dir + "/ui-snapshots.log", atomically: true, encoding: .utf8)
                await flushWorkspace()
                await stopCue()
                shutdown()
                exit(0)
            }
            // UI-005f: the Screens mode's design picture (one registered block; the scenario lives in ScreensSnapshot.swift).
            if ProcessInfo.processInfo.environment["UI_SNAPSHOT_SCREENS"] != nil {
                await runScreensScenario(note: { note($0) }, capture: { await capture($0) }, window: window)
                try? "\(log.joined(separator: "\n"))\n".write(toFile: dir + "/ui-snapshots.log", atomically: true, encoding: .utf8)
                await flushWorkspace(); await stopCue(); shutdown(); exit(0)
            }
            // UI-005e: the Stage mode picture (the scenario is in UISnapshotStage.swift; this is the only line of it outside that file).
            if ProcessInfo.processInfo.environment["UI_SNAPSHOT_STAGE"] != nil {
                await runStageDesignScenario(note: { note($0) }, capture: { await capture($0) }, window: window)
                try? "\(log.joined(separator: "\n"))\n".write(toFile: dir + "/ui-snapshots.log", atomically: true, encoding: .utf8)
                await flushWorkspace(); await stopCue(); shutdown(); exit(0)
            }
            // FIX-K: real mouse and key events on the Edit canvas and the app's other drags (one added block; the same shape as the others).
            if ProcessInfo.processInfo.environment["UI_SNAPSHOT_FIXK"] != nil {
                await runFixKScenario(note: { note($0) }, capture: { await capture($0) })
                try? "\(log.joined(separator: "\n"))\n".write(toFile: dir + "/ui-snapshots.log", atomically: true, encoding: .utf8)
                await flushWorkspace()
                await stopCue()
                shutdown()
                exit(0)
            }
            // FIX-N: real mouse and key events in Edit, Stage and Screens (one added block; the same shape as the others).
            if ProcessInfo.processInfo.environment["UI_SNAPSHOT_FIXN"] != nil {
                await runFixNKeyScenario(note: { note($0) }, capture: { await capture($0) })
                try? "\(log.joined(separator: "\n"))\n".write(toFile: dir + "/ui-snapshots.log", atomically: true, encoding: .utf8)
                await flushWorkspace()
                await stopCue()
                shutdown()
                exit(0)
            }
            // FIX-O: Go Live, Next, Previous, Blackout and Clear in every mode, looking for views that did not follow (one added block).
            if ProcessInfo.processInfo.environment["UI_SNAPSHOT_FIXO_MODES"] != nil {
                await runFixOModesScenario(note: { note($0) })
                try? "\(log.joined(separator: "\n"))\n".write(toFile: dir + "/ui-snapshots.log", atomically: true, encoding: .utf8)
                await flushWorkspace()
                await stopCue()
                shutdown()
                exit(0)
            }
            // FIX-Q: Next, Previous, Go Live, Blackout and Clear repeated with 200 slides, phase by phase (one added block; the same shape as the others).
            if ProcessInfo.processInfo.environment["UI_SNAPSHOT_FIXQ"] != nil {
                await runFixQScenario(note: { note($0) })
                try? "\(log.joined(separator: "\n"))\n".write(toFile: dir + "/ui-snapshots.log", atomically: true, encoding: .utf8)
                await flushWorkspace()
                await stopCue()
                shutdown()
                exit(0)
            }
            // FIX-P: grid focus after a mode change, a drag whose window resigns key, and MIDI latency under load (one added block).
            if ProcessInfo.processInfo.environment["UI_SNAPSHOT_FIXP"] != nil {
                await runFixPScenario(note: { note($0) })
                try? "\(log.joined(separator: "\n"))\n".write(toFile: dir + "/ui-snapshots.log", atomically: true, encoding: .utf8)
                await flushWorkspace()
                await stopCue()
                shutdown()
                exit(0)
            }
            // FIX-M: drag sessions replayed through the window's drag-destination entry points (one added block; the same shape as the others).
            if ProcessInfo.processInfo.environment["UI_SNAPSHOT_FIXM"] != nil {
                await runFixMScenario(note: { note($0) })
                try? "\(log.joined(separator: "\n"))\n".write(toFile: dir + "/ui-snapshots.log", atomically: true, encoding: .utf8)
                await flushWorkspace()
                await stopCue()
                shutdown()
                exit(0)
            }
            // UI-005d: the Media mode in the state of the design picture (the one line this slice adds to this shared file).
            if ProcessInfo.processInfo.environment["UI_SNAPSHOT_UIMEDIA"] != nil {
                await runMediaDesignScenario(note: { note($0) }, capture: { await capture($0) }, window: window)
                try? "\(log.joined(separator: "\n"))\n".write(toFile: dir + "/ui-snapshots.log", atomically: true, encoding: .utf8)
                await flushWorkspace()
                await stopCue()
                shutdown()
                exit(0)
            }
            // UI-005g: the Cues design pictures (cues-dark, cues-light) with their rectangle dumps (one added block; the same shape as the others).
            if ProcessInfo.processInfo.environment["UI_SNAPSHOT_CUESDESIGN"] != nil {
                await runCuesDesignScenario(note: { note($0) }, capture: { await capture($0) }, window: window)
                try? "\(log.joined(separator: "\n"))\n".write(toFile: dir + "/ui-snapshots.log", atomically: true, encoding: .utf8)
                await flushWorkspace(); await stopCue(); shutdown(); exit(0)
            }
            // UI-005a: the five design pictures (Show dark, Quick edit, Show light, components dark and light), at 1440 x 900 points.
            if ProcessInfo.processInfo.environment["UI_SNAPSHOT_DESIGN"] != nil {
                await runDesignScenario(note: { note($0) }, capture: { await capture($0) }, window: window)
                try? "\(log.joined(separator: "\n"))\n".write(toFile: dir + "/ui-snapshots.log", atomically: true, encoding: .utf8)
                await flushWorkspace()
                await stopCue()
                shutdown()
                exit(0)
            }
            // UI-004: the rounded controls (mode switcher, role pills, media controller pill) in dark and light.
            if ProcessInfo.processInfo.environment["UI_SNAPSHOT_UI004"] != nil {
                await runUI004Scenario(note: { note($0) }, capture: { await capture($0) })
                try? "\(log.joined(separator: "\n"))\n".write(toFile: dir + "/ui-snapshots.log", atomically: true, encoding: .utf8)
                await flushWorkspace()
                await stopCue()
                shutdown()
                exit(0)
            }
            // MEDIA-010: the live media control in the running app (bin player, live override, clears, hot folder, slide background).
            if ProcessInfo.processInfo.environment["UI_SNAPSHOT_MEDIA010"] != nil {
                await runMedia010Scenario(note: { note($0) }, capture: { await capture($0) })
                try? "\(log.joined(separator: "\n"))\n".write(toFile: dir + "/ui-snapshots.log", atomically: true, encoding: .utf8)
                await flushWorkspace()
                await stopCue()
                shutdown()
                exit(0)
            }
            // FIX-I: real key events after real clicks in each region.
            if ProcessInfo.processInfo.environment["UI_SNAPSHOT_FIXI"] != nil {
                await runFixIKeyScenario(note: { note($0) }, capture: { await capture($0) })
                try? "\(log.joined(separator: "\n"))\n".write(toFile: dir + "/ui-snapshots.log", atomically: true, encoding: .utf8)
                await flushWorkspace()
                await stopCue()
                shutdown()
                exit(0)
            }
            // LIB-004c: the Scripture view in the running app (Command-J, an empty library, a typed reference, two translations), then out.
            if ProcessInfo.processInfo.environment["UI_SNAPSHOT_SCRIPTURE"] != nil {
                await runScriptureScenario(note: { note($0) }, capture: { await capture($0) },
                                           key: { code, chars, command, shift in key(code, chars, command: command, shift: shift) })
                try? "\(log.joined(separator: "\n"))\n".write(toFile: dir + "/ui-snapshots.log", atomically: true, encoding: .utf8)
                await flushWorkspace()
                await stopCue()
                shutdown()
                exit(0)
            }
            // Command-1 to 6 through the real menu, then a picture of each mode.
            let digitCodes: [UInt16] = [18, 19, 20, 21, 23, 22]
            for (i, mode) in WorkspaceMode.allCases.enumerated() {
                key(digitCodes[i], "\(i + 1)", command: true)
                try? await Task.sleep(for: .milliseconds(300))
                note("Command-\(i + 1) -> mode \(workspace.mode.title) (expected \(mode.title))")
                await capture(mode.rawValue)
            }
            // UI-003: Show with a clip over the words, with a sound, with the Quick edit tab, with the dock folded, and in light.
            if ProcessInfo.processInfo.environment["UI_SNAPSHOT_EXTRAS"] != nil {
                workspace.setMode(.show)
                if let clip = media?.assets.filter({ $0.kind == .video }).dropFirst().first {
                    media?.playForeground(clip.id)
                    media?.setForegroundLoops(true)
                    try? await Task.sleep(for: .seconds(1.5))
                    note("clip controller: foreground \(media?.foregroundReadout()?.name ?? "none"), loops \(media?.foregroundLoops ?? false)")
                    await capture("show-clip")
                    // The loop choice: near the end of the 20 s clip, wait past it; a looping clip must still be playing, from the start.
                    media?.seek(to: max(0, (media?.foregroundReadout()?.duration ?? 20) - 1.5))
                    try? await Task.sleep(for: .seconds(3.2))
                    let r = media?.foregroundReadout()
                    note("looping clip after its end: still there \(r != nil), playing \(r?.isPlaying ?? false), position \(r.map { String(format: "%.1f", $0.position) } ?? "-") (expected a few seconds in)")
                    media?.stopForeground()
                }
                if let sound = media?.assets.first(where: { $0.kind == .audio }) {
                    audio?.play(sound.id)
                    try? await Task.sleep(for: .seconds(1.5))
                    note("sound controller: \(audio?.currentID != nil) position \(audio?.currentID.flatMap { audio?.readout(for: $0)?.position } ?? -1)")
                    app_dockTab(.audio)
                    await capture("show-sound")
                    if let id = audio?.currentID { audio?.stop(id) }
                    app_dockTab(.backgrounds)
                }
                // Search through the real keys: Command-F focuses the sidebar field, typing filters, Escape clears and returns to the grid.
                workspace.setMode(.show)
                key(3, "f", command: true)
                try? await Task.sleep(for: .milliseconds(700))
                note("Command-F -> search field focused: \(ui.searchHasFocus) (expected true)")
                for (code, ch) in [(5, "g"), (15, "r"), (0, "a"), (8, "c"), (14, "e")] { key(UInt16(code), ch); try? await Task.sleep(for: .milliseconds(80)) }
                try? await Task.sleep(for: .milliseconds(700))
                note("typed 'grace': results \(workspace.searchResults.map(\.title)) (expected the two songs only if lyrics match)")
                await capture("show-search")
                key(53, "\u{1B}")
                try? await Task.sleep(for: .milliseconds(700))
                note("Escape in search -> focused \(ui.searchHasFocus) (expected false), results \(workspace.searchResults.count) (expected 0)")
                workspace.selectSlide(3)
                // Command-E through the real menu: the tab opens on the SELECTED slide; typing goes into its first field.
                key(14, "e", command: true)
                try? await Task.sleep(for: .milliseconds(700))
                note("Command-E -> tab open \(ui.tabs.quickEditIsOpen), selected \(ui.tabs.selected.rawValue), live slide \(workspace.show.liveSlide?.primary.prefix(12) ?? "-")")
                let before = workspace.slides[3].content.primary
                let liveWords = workspace.show.liveSlide?.primary
                key(7, "x")
                try? await Task.sleep(for: .milliseconds(500))
                note("typed x in the tab: selected slide changed \(workspace.slides[3].content.primary != before) (expected true), live slide changed \(workspace.show.liveSlide?.primary != liveWords) (expected false)")
                await capture("show-quick-edit")
                key(53, "\u{1B}")
                try? await Task.sleep(for: .milliseconds(600))
                note("Escape in the tab -> tab open \(ui.tabs.quickEditIsOpen) (expected false), show cleared \(app_isCleared)")
                // The live-edit shortcut, tried the ways a keyboard can describe Option-Command-E (the menu must pick the right item).
                for (chars, ignoring) in [("´", "e"), ("e", "e")] {
                    guard let window else { break }
                    let before = ui.liveQuickEditRequests
                    let wasOpen = ui.tabs.quickEditIsOpen
                    for type in [NSEvent.EventType.keyDown, .keyUp] {
                        guard let event = NSEvent.keyEvent(with: type, location: .zero, modifierFlags: [.command, .option], timestamp: ProcessInfo.processInfo.systemUptime,
                                                           windowNumber: window.windowNumber, context: nil, characters: chars,
                                                           charactersIgnoringModifiers: ignoring, isARepeat: false, keyCode: 14) else { continue }
                        if type == .keyDown { _ = NSApp.mainMenu?.performKeyEquivalent(with: event) } else { NSApp.sendEvent(event) }
                    }
                    note("Option-Command-E as characters '\(chars)' ignoring '\(ignoring)': live edit requests \(before) -> \(ui.liveQuickEditRequests), tab open \(wasOpen) -> \(ui.tabs.quickEditIsOpen)")
                    ui.tabs.closeQuickEdit()
                }
                ui.showLiveQuickEdit = false
                openQuickEdit()
                try? await Task.sleep(for: .milliseconds(300))
                closeQuickEdit()
                note("quick edit closed: \(!ui.tabs.quickEditIsOpen), tabs \(ui.tabs.visible.map(\.rawValue))")
                setMediaDock(collapsed: true)
                await capture("show-dock-collapsed")
                setMediaDock(collapsed: false)
                setAppearance(.light)
                await capture("show-light")
                setAppearance(.dark)
            }
            // B through the real key monitor, from a non-Show mode (transport keys work in every mode).
            workspace.setMode(.screens)
            key(11, "b")
            try? await Task.sleep(for: .milliseconds(300))
            note("B in Screens -> blackedOut \(show.isBlackedOut) (expected true)")
            workspace.setMode(.show)
            try? await Task.sleep(for: .milliseconds(1500))
            note("first responder in Show: \(String(describing: window?.firstResponder.map { type(of: $0) }))")
            if ProcessInfo.processInfo.environment["UI_SNAPSHOT_DUMP"] != nil, let root = window?.contentView?.superview {
                @MainActor func dump(_ v: NSView, _ depth: Int) {
                    if depth > 9 { return }
                    if v.frame.width > 250 { note(String(repeating: " ", count: depth) + "\(type(of: v)) \(Int(v.frame.minX)),\(Int(v.frame.minY)) \(Int(v.frame.width))x\(Int(v.frame.height)) hidden=\(v.isHidden)") }
                    for sub in v.subviews { dump(sub, depth + 1) }
                }
                dump(root, 0)
            }
            if ProcessInfo.processInfo.environment["UI_SNAPSHOT_DUMP"] != nil, let root = window?.contentView {
                @MainActor func walk(_ e: Any, _ depth: Int) {
                    guard depth < 16, let obj = e as? NSObject else { return }
                    let label = obj.value(forKey: "accessibilityLabel") as? String ?? ""
                    if label.hasPrefix("Slide ") || label.hasPrefix("Library ") {
                        let frame = (obj.value(forKey: "accessibilityFrame") as? NSValue)?.rectValue ?? .zero
                        note("AX \(label.prefix(30)) frame \(NSStringFromRect(frame))")
                    }
                    for c in obj.value(forKey: "accessibilityChildren") as? [Any] ?? [] { walk(c, depth + 1) }
                }
                walk(root, 0)
            }
            await capture("blackout")
            key(11, "b")
            try? await Task.sleep(for: .milliseconds(300))
            note("B again -> blackedOut \(show.isBlackedOut) (expected false)")
            workspace.setMode(.screens)
            let before = show.liveIndex
            key(124, "\u{F703}")
            try? await Task.sleep(for: .milliseconds(500))
            note("Right arrow in Screens: live \(before.map(String.init) ?? "-") -> \(show.liveIndex.map(String.init) ?? "-")")

            // UI-002: the countdown item live, then ticking.
            if let countdown = workspace.playlistItems.first(where: { if case .countdown = $0.kind { true } else { false } }) {
                workspace.setMode(.show)
                await workspace.openPlaylistItem(countdown.id)
                await workspace.goLive()
                try? await Task.sleep(for: .seconds(2.2))
                workspace.countdownTick()
                note("countdown live: \(workspace.show.liveSlide?.primary ?? "none")")
                await capture("countdown")
            }
            // Stop clears the stage message (it was sent at the start of the run).
            let messageBeforeStop = stage?.stageMessage
            stopShow()
            note("stage message before Stop \(messageBeforeStop ?? "none"), after Stop \(stage?.stageMessage ?? "none") (expected none)")
            try? "\(log.joined(separator: "\n"))\n".write(toFile: dir + "/ui-snapshots.log", atomically: true, encoding: .utf8)
            await flushWorkspace()
            await stopCue()
            shutdown()
            exit(0)
        }
    }
}
#else
extension AppModel { func runUISnapshotsIfRequested() {} }
#endif
