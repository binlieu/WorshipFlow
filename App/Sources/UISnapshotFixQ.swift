// FIX-Q (measuring builds only: Debug, or Release built with the WF_MEASURE compilation condition; none of this is in the packaged app):
// `UI_SNAPSHOT_FIXQ=1` with the ui-snapshots hook, against a temporary library and no sound. With 200 slides and 100 bin items it repeats each
// transport gesture and reports, per gesture: the model call's main-thread time, the longest main-thread stall around it (2 ms heartbeat, 700 ms
// after), the time from the command to the moment the screens were handed the new scene (`PhaseProbe`), and where the main-thread time of the
// call went by phase. Median and worst over the runs. Drops are measured by `UISnapshotFixM` (scripts/measure-drags.sh), MIDI by `UISnapshotFixP`.
#if DEBUG || WF_MEASURE
import AppKit
import Darwin
import Domain
import OperatorCore

extension AppModel {
    func runFixQScenario(note: @MainActor (String) -> Void) async {
        guard let workspace, let window = Self.operatorWindow, let media else { note("fixq: no workspace, window or media"); return }
        let meter = MainThreadMeter.shared
        meter.install()
        func mainCPU() -> Double { meter.cpu() }
        let runs = Int(ProcessInfo.processInfo.environment["UI_SNAPSHOT_FIXQ_RUNS"] ?? "") ?? 20
        let text = (1...200).map { "Line \($0) of the long song" }.joined(separator: "\n\n")
        guard let big = await workspace.importLyrics(title: "Two hundred", primaryText: text, secondaryText: nil, maxLines: 1) else { note("fixq: import failed"); return }
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
        workspace.setMode(.show)
        workspace.selectSlide(0)
        try? await Task.sleep(for: .seconds(2))
        let screens = profiles.filter(\.isEnabled).map { "\($0.role)" }.joined(separator: ", ")
        note("fixq setup: \(workspace.slides.count) slides, \(media.assets.count) bin items, screens enabled: [\(screens)], runs per gesture \(runs)")

        func pct(_ a: [Double], _ q: Double) -> Double { let s = a.sorted(); return s.isEmpty ? 0 : s[min(s.count - 1, Int(Double(s.count) * q))] }
        /// One gesture, `runs` times. `work` is the command; `viaPublication` waits for the screens to be handed a scene after it.
        func gesture(_ label: String, repeats: Int = runs, waitsForPublication: Bool = false, prepare: @MainActor (Int) async -> Void = { _ in }, _ work: @MainActor (Int) async -> Void) async {
            var calls: [Double] = [], stalls: [Double] = [], c2p: [Double] = [], cpus: [Double] = [], bursts: [Double] = [], phases: [String] = []
            for n in 0..<repeats {
                await prepare(n)
                try? await Task.sleep(for: .milliseconds(500))
                var longest = 0.0, stop = false
                let ticker = Task { @MainActor in
                    var last = ContinuousClock.now
                    while !stop { try? await Task.sleep(for: .milliseconds(2)); let now = ContinuousClock.now; longest = max(longest, RealPointer.ms(now - last) - 2); last = now }
                }
                try? await Task.sleep(for: .milliseconds(20))
                PhaseProbe.reset(); BodyProbe.reset()
                let published = PhaseProbe.publications
                let cpu0 = mainCPU()
                meter.resetBurst()
                let t0 = ContinuousClock.now
                PhaseProbe.commandStart = t0
                await work(n)
                calls.append(RealPointer.ms(ContinuousClock.now - t0))
                if waitsForPublication {
                    var waited = 0
                    while PhaseProbe.publications == published, waited < 200 { try? await Task.sleep(for: .milliseconds(5)); waited += 1 }
                }
                try? await Task.sleep(for: .milliseconds(700))
                stop = true; _ = await ticker.value
                cpus.append(mainCPU() - cpu0)
                bursts.append(meter.longestBurst)
                stalls.append(longest)
                if let d = PhaseProbe.commandToPublication() { c2p.append(d) }
                phases.append(PhaseProbe.summary() + " | bodies: " + (BodyProbe.summary().isEmpty ? "-" : BodyProbe.summary()))
            }
            func stat(_ a: [Double]) -> String { a.isEmpty ? "n/a" : String(format: "median %.1f / worst %.1f", pct(a, 0.5), a.max() ?? 0) }
            note("fixq[\(label)]: \(repeats) runs; call ms \(stat(calls)); main-thread CPU ms in the call and the 0.7 s after \(stat(cpus)); longest CPU burst in one run-loop pass ms \(stat(bursts)); longest stall ms (includes waits) \(stat(stalls)); command to publication ms \(stat(c2p)) (published in \(c2p.count) runs)")
            for n in [0, repeats / 2, repeats - 1] where n < phases.count { note("fixq[\(label)] phases ms and view bodies run, run \(n + 1): \(phases[n].isEmpty ? "-" : phases[n])") }
        }

        // Profiling aid: UI_SNAPSHOT_FIXQ_LOOP=next repeats Next and Previous (60 ms apart) so `sample` can see where the main thread spends the time.
        if let loop = ProcessInfo.processInfo.environment["UI_SNAPSHOT_FIXQ_LOOP"] {
            workspace.goLive(at: 40)
            try? await Task.sleep(for: .seconds(2))
            note("fixq loop \(loop) starts")
            let loops = Int(ProcessInfo.processInfo.environment["UI_SNAPSHOT_FIXQ_LOOPS"] ?? "") ?? 300
            if loop == "idle" { try? await Task.sleep(for: .seconds(20)); note("fixq loop done"); return }      // no command at all: what the window does by itself
            for n in 0..<loops {
                if loop == "golive" { workspace.selectSlide(60 + n % 40); await workspace.goLive() }
                else if n % 2 == 0 { await workspace.next() } else { await workspace.previous() }
                try? await Task.sleep(for: .milliseconds(60))
            }
            note("fixq loop done")
            return
        }
        // Go Live on the 100th slide first, so Next and Previous have room on both sides.
        workspace.goLive(at: 20)
        try? await Task.sleep(for: .seconds(2))
        if ProcessInfo.processInfo.environment["UI_SNAPSHOT_FIXQ_ONLY_NEXT"] != nil {
            await gesture("Next") { _ in await workspace.next() }
            await gesture("Previous") { _ in await workspace.previous() }
        } else if ProcessInfo.processInfo.environment["UI_SNAPSHOT_FIXQ_ONLY_MODES"] == nil {
            await gesture("Go Live (a slide of the grid)", prepare: { n in workspace.selectSlide(30 + n) }) { n in await workspace.goLive() }
            await gesture("Next") { _ in await workspace.next() }
            await gesture("Previous") { _ in await workspace.previous() }
            await gesture("Next (command path: key or MIDI)", waitsForPublication: true) { _ in self.next(from: .midi) }
            await gesture("Previous (command path)", waitsForPublication: true) { _ in self.previous(from: .midi) }
            await gesture("Blackout on", prepare: { _ in if self.show.isBlackedOut { workspace.blackout() } }) { _ in workspace.blackout() }
            await gesture("Blackout off", prepare: { _ in if !self.show.isBlackedOut { workspace.blackout() } }) { _ in workspace.blackout() }
            await gesture("Clear", prepare: { _ in workspace.goLive(at: 20) }) { _ in workspace.clear() }
            await gesture("Go Live after Clear", prepare: { _ in workspace.clear() }) { _ in workspace.goLive(at: 20) }
        }
        // Where does the stall come from? The same Next in each mode (the mode decides which views are on screen).
        if ProcessInfo.processInfo.environment["UI_SNAPSHOT_FIXQ_MODES"] != nil {
            workspace.goLive(at: 20)
            for mode in WorkspaceMode.allCases {
                workspace.setMode(mode)
                try? await Task.sleep(for: .seconds(2))
                note("fixq: \(mode.title): window visible \(window.occlusionState.contains(.visible)), key \(window.isKeyWindow), app active \(NSApp.isActive), screen locked \((CGSessionCopyCurrentDictionary() as? [String: Any])?["CGSSessionScreenIsLocked"] as? Bool ?? false)")
                await gesture("Idle in \(mode.title) (no command: the heartbeat alone)", repeats: 5) { _ in }
                await gesture("Next in \(mode.title)", repeats: 10) { _ in await workspace.next() }
            }
            workspace.setMode(.show)
        }
        workspace.stop()
        note("fixq: done")
    }
}
/// The main thread's own CPU time and the longest uninterrupted burst of it inside one run-loop pass (from waking to going back to sleep): work the thread
/// had to finish before it could answer the next event. Time spent blocked (a display commit waiting for the next frame of a locked screen) is not counted.
/// Shared by the FIX-Q gestures and the FIX-M drop replays.
@MainActor final class MainThreadMeter {
    static let shared = MainThreadMeter()
    private let thread = pthread_mach_thread_np(pthread_self())
    private(set) var longestBurst = 0.0
    private var burstStart = 0.0
    private var observer: CFRunLoopObserver?

    /// Main-thread CPU time, user plus system, in milliseconds.
    func cpu() -> Double {
        var info = thread_basic_info()
        var count = mach_msg_type_number_t(MemoryLayout<thread_basic_info_data_t>.size / MemoryLayout<integer_t>.size)
        let result = withUnsafeMutablePointer(to: &info) { $0.withMemoryRebound(to: integer_t.self, capacity: Int(count)) { thread_info(thread, thread_flavor_t(THREAD_BASIC_INFO), $0, &count) } }
        guard result == KERN_SUCCESS else { return 0 }
        return Double(info.user_time.seconds + info.system_time.seconds) * 1000 + Double(info.user_time.microseconds + info.system_time.microseconds) / 1000
    }

    func install() {
        guard observer == nil else { return }
        burstStart = cpu()          // a pass that is already running when the observer is added counts from here, not from the process's start
        let made = CFRunLoopObserverCreateWithHandler(nil, CFRunLoopActivity.afterWaiting.rawValue | CFRunLoopActivity.beforeWaiting.rawValue, true, Int(Int32.max)) { _, activity in      // last in line, so it ends after the display flush (Core Animation's own observer runs at 2,000,000)
            MainActor.assumeIsolated {
                let meter = MainThreadMeter.shared
                if activity == .afterWaiting { meter.burstStart = meter.cpu() } else { meter.longestBurst = max(meter.longestBurst, meter.cpu() - meter.burstStart) }
            }
        }
        CFRunLoopAddObserver(CFRunLoopGetMain(), made, .commonModes)
        observer = made
    }

    func resetBurst() { longestBurst = 0 }
}
#endif
