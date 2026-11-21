// UI-001 (debug builds only): `--ui-snapshots <dir>` imports a sample bilingual song, puts the audience screen in a window,
// goes live, and writes one picture of the operator window per mode plus one with Blackout on. It also sends the real key
// events for Command-1 to 6 and B through the app's own menu and key monitor and logs what happened. Pictures are drawn by
// the window's own views (no screen capture), so a locked screen does not matter. Nothing here runs without the flag.
#if DEBUG
import AppKit
import Domain
import OperatorCore

extension AppModel {
    static var snapshotDirectory: String? {
        guard let i = CommandLine.arguments.firstIndex(of: "--ui-snapshots"), i + 1 < CommandLine.arguments.count else { return nil }
        return CommandLine.arguments[i + 1]
    }

    func runUISnapshotsIfRequested() {
        guard let dir = Self.snapshotDirectory, let workspace else { return }
        Task { @MainActor in
            var log: [String] = []
            @MainActor func note(_ text: String) { log.append(text); FileHandle.standardError.write(Data("[ui-snapshots] \(text)\n".utf8)) }
            try? FileManager.default.createDirectory(atPath: dir, withIntermediateDirectories: true)
            while !workspaceLoaded { try? await Task.sleep(for: .milliseconds(100)) }
            try? await Task.sleep(for: .seconds(1.5))
            let window = Self.operatorWindow
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
            My chains are gone, I've been set free
            My God, my Savior has ransomed me
            And like a flood His mercy reigns
            Unending love, amazing grace

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
            Xiềng xích đã tan, tôi được tự do
            Chúa tôi, Cứu Chúa tôi đã chuộc tôi
            Như dòng nước lũ ơn thương xót
            Tình yêu vô tận, ân điển lạ lùng

            Ending:
            Ân điển lạ lùng, ân điển lạ lùng
            """
            if let p = await workspace.importLyrics(title: "Amazing Grace", primaryText: song, secondaryText: viet, maxLines: 2) {
                _ = await workspace.importLyrics(title: "Be Thou My Vision", primaryText: "Be Thou my vision, O Lord of my heart\nNaught be all else to me", secondaryText: nil, maxLines: 2)
                await workspace.openPresentation(p.id)
                if ProcessInfo.processInfo.environment["UI_SNAPSHOT_SDI"] != nil {
                    await workspace.addHeader("Pre-service")
                    await workspace.addCountdown(CountdownSpec(label: "Starting soon", mode: .duration(seconds: 300)))
                    await workspace.addHeader("Worship")
                }
                await workspace.addToPlaylist(p.id)
            } else { note("import failed: \(workspace.lastError ?? "?")") }
            if let path = ProcessInfo.processInfo.environment["UI_SNAPSHOT_MEDIA"] {
                addMedia([URL(fileURLWithPath: path)])
                try? await Task.sleep(for: .seconds(1.5))
                if let asset = media?.assets.first { media?.setBackground(asset.id) }
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
                guard let image = ctx.makeImage() else { note("no image"); return }
                let rep = NSBitmapImageRep(cgImage: image)
                if let data = rep.representation(using: .png, properties: [:]) {
                    try? data.write(to: URL(fileURLWithPath: dir).appendingPathComponent("\(ProcessInfo.processInfo.environment["UI_SNAPSHOT_PREFIX"] ?? "UI-001")-\(name).png"))
                    note("wrote \(name).png \(rep.pixelsWide)x\(rep.pixelsHigh)")
                }
            }

            @MainActor func key(_ code: UInt16, _ chars: String, command: Bool = false) {
                guard let window else { return }
                let flags: NSEvent.ModifierFlags = command ? [.command] : []
                for type in [NSEvent.EventType.keyDown, .keyUp] {
                    guard let event = NSEvent.keyEvent(with: type, location: .zero, modifierFlags: flags, timestamp: ProcessInfo.processInfo.systemUptime,
                                                       windowNumber: window.windowNumber, context: nil, characters: chars,
                                                       charactersIgnoringModifiers: chars, isARepeat: false, keyCode: code) else { continue }
                    if command, type == .keyDown { _ = NSApp.mainMenu?.performKeyEquivalent(with: event) } else { NSApp.sendEvent(event) }
                }
            }

            // Command-1 to 6 through the real menu, then a picture of each mode.
            let digitCodes: [UInt16] = [18, 19, 20, 21, 23, 22]
            for (i, mode) in WorkspaceMode.allCases.enumerated() {
                key(digitCodes[i], "\(i + 1)", command: true)
                try? await Task.sleep(for: .milliseconds(300))
                note("Command-\(i + 1) -> mode \(workspace.mode.title) (expected \(mode.title))")
                await capture(mode.rawValue)
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
            try? "\(log.joined(separator: "\n"))\n".write(toFile: dir + "/ui-snapshots.log", atomically: true, encoding: .utf8)
            await flushWorkspace()
            shutdown()
            exit(0)
        }
    }
}
#else
extension AppModel { func runUISnapshotsIfRequested() {} }
#endif
