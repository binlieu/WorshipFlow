// HWTEST-001: the nine steps. Each one measures, records what it measured, and states its pass criteria in the result.
// A step never claims more than it measured: a device that says it supports a mode has only said so (step 6), and a
// simulated card proves only that the kit works.
import Foundation
import SDIEngine

public enum HardwareTestSteps {
    static let mode = HardwareTestConfiguration.testMode

    /// The steps in the order they run, numbered as the tester's guide numbers them.
    public static func standard(_ c: HardwareTestConfiguration) -> [HardwareTestStep] {
        let d = c.durations
        func limit(_ seconds: Double) -> Double { max(180, seconds * 3 + 180) }
        return [
            HardwareTestStep(id: .environment, number: 1, title: "Environment", timeoutSeconds: 60, run: environment),
            HardwareTestStep(id: .devices, number: 2, title: "Devices", timeoutSeconds: 120, run: devices),
            HardwareTestStep(id: .outputRun, number: 3, title: "Output run", timeoutSeconds: limit(d.outputRunSeconds), needsDevice: true, run: outputRun),
            HardwareTestStep(id: .loopback, number: 4, title: "Loopback", timeoutSeconds: limit(d.loopbackSeconds), needsDevice: true,
                             skipReason: { $0.outputStartFailed ? "The output run could not start the output, so there is nothing to loop back." : nil }, run: loopback),
            HardwareTestStep(id: .fillKeyLoopback, number: 5, title: "Fill and key loopback", timeoutSeconds: limit(d.keyedSecondsPerMode * 2), needsDevice: true,
                             skipReason: keyedSkip, run: fillKeyLoopback),
            HardwareTestStep(id: .modeSweep, number: 6, title: "Mode sweep", timeoutSeconds: 120, needsDevice: true, run: modeSweep),
            HardwareTestStep(id: .fourOutputs, number: 7, title: "Four outputs at once", timeoutSeconds: limit(d.fourOutputSeconds), needsDevice: true,
                             skipReason: { ctx in
                                 (ctx.device?.info.connectorCount ?? 0) < 4 ? "The device has fewer than four connectors, so four outputs at once cannot be tested." : nil
                             }, run: fourOutputs),
            HardwareTestStep(id: .unplugReplug, number: 8, title: "Unplug and replug", timeoutSeconds: 240, needsDevice: true,
                             skipReason: { $0.configuration.includeUnplugTest ? nil : "This step was not selected: the tester did not choose the unplug test." }, run: unplugReplug),
            HardwareTestStep(id: .humanChecks, number: 9, title: "Human checks", timeoutSeconds: 300, needsDevice: true,
                             skipReason: { $0.configuration.includeHumanChecks ? nil : "This step was not selected: the tester did not choose the monitor checks." }, run: humanChecks),
        ]
    }

    static func keyedSkip(_ ctx: HardwareTestContext) -> String? {
        guard let info = ctx.device?.info else { return nil }
        if !info.supportsExternalKeying { return "The device does not report fill and key support, so there is nothing to test." }
        if info.connectorCount < 4 { return "Fill and key loopback needs four connectors (a pair out and a pair in); this device has \(info.connectorCount)." }
        if ctx.outputStartFailed { return "The output run could not start the output, so fill and key cannot be tested." }
        return nil
    }

    // MARK: shared helpers

    struct RunningOutput {
        let port: any SDIOutputPort
        let session: SDIOutputSession
        func stop() {
            session.stop()
            port.close()
        }
    }

    static func startOutput(_ device: HardwareTestDevice, connector: Int, keying: SDIKeying = .none, frames: @escaping SDIFrameProvider) throws -> RunningOutput {
        let port = try device.openOutput(connector)
        let session = SDIOutputSession(port: port, mode: mode, keying: keying, frameProvider: frames)
        do { try session.start() } catch {
            port.close()
            throw error
        }
        return RunningOutput(port: port, session: session)
    }

    static func describe(_ error: Error) -> String { (error as? SDIError)?.description ?? error.localizedDescription }

    static func m(_ name: String, _ value: String, _ unit: String? = nil) -> HardwareMeasurement { HardwareMeasurement(name: name, value: value, unit: unit) }

    static func healthNumber(_ h: SDIHealth) -> Double {
        switch h {
        case .ok: return 0
        case .degraded: return 1
        case .failing: return 2
        }
    }

    static func healthName(_ h: SDIHealth) -> String {
        switch h {
        case .ok: return "OK"
        case .degraded: return "degraded"
        case .failing: return "failing"
        }
    }

    static func yesNo(_ b: Bool) -> String { b ? "yes" : "no" }

    static func hz(_ v: Double) -> String { abs(v - v.rounded()) < 0.005 ? String(Int(v.rounded())) : String(format: "%.2f", v) }

    /// Waits `seconds` of test time one second at a time, calling `body(sampleNumber, elapsed)` after each. `body` returns
    /// false to end early. Returns the elapsed test time.
    @discardableResult
    static func timedLoop(_ ctx: HardwareTestContext, title: String, seconds: Double, body: (Int, Double) throws -> Bool) async throws -> Double {
        var elapsed = 0.0
        var n = 0
        while elapsed < seconds {
            let dt = min(1, seconds - elapsed)
            try await ctx.clock.wait(seconds: dt)
            elapsed += dt
            n += 1
            ctx.progress(step: title, elapsed: elapsed, total: seconds)
            if try !body(n, elapsed) { break }
        }
        return elapsed
    }

    // MARK: connector identity (FIX-D S4)

    /// Reads which output a captured picture came from. Each output's picture carries its connector number in the top bits
    /// of the frame counter, which has its own check bits, so a wrongly cabled or wrongly mapped connector is seen.
    enum ConnectorIdentity {
        static let shift: Int64 = 28
        static func frameIndex(connector: Int, counter: Int64) -> Int64 { Int64(connector) << shift | (counter & 0x0FFF_FFFF) }
        static func decode(_ frame: SDIFrame) -> Int? {
            guard let value = TestPattern.decodeFrameIndex(from: frame) else { return nil }
            let c = Int(value >> shift)
            return (1...15).contains(c) ? c : nil
        }
    }

    /// The colour bars with the connector number in the counter.
    struct IdentityFrameSource: Sendable {
        let connector: Int
        let base: CounterFrameSource
        func frame(index: Int64) -> SDIFrame { base.frame(index: ConnectorIdentity.frameIndex(connector: connector, counter: index)) }
    }

    /// Counts which output each received picture came from. `@unchecked Sendable`: `seen` and `total` are only touched while holding `lock`.
    final class IdentityCollector: @unchecked Sendable {
        private let lock = NSLock()
        private var seen: [Int: Int] = [:]
        private var total = 0
        func receive(_ captured: SDICapturedFrame) {
            let id = ConnectorIdentity.decode(captured.frame)
            lock.withLock {
                total += 1
                if let id { seen[id, default: 0] += 1 }
            }
        }
        var frames: Int { lock.withLock { total } }
        /// The output most pictures came from, when at least three pictures agree; nil otherwise.
        var identity: Int? {
            lock.withLock { seen.max { $0.value < $1.value }.flatMap { $0.value >= 3 ? $0.key : nil } }
        }
    }

    // MARK: asking for a keying profile (FIX-D S1)

    enum KeyingProfileOutcome {
        case ready(event: String?)
        case stop(HardwareStepOutput)
    }

    /// Makes sure the pair that starts at `first` can send fill and key. A change of profile is asked for once; after the tester
    /// said yes the same consent covers the later steps of the same run that need the keying profile. Whatever this changes is
    /// put back by the runner after the step, without asking.
    static func ensureKeyingProfile(_ ctx: HardwareTestContext, _ device: HardwareTestDevice, first: Int, criteria: String) async -> KeyingProfileOutcome {
        let outcome = await SDIKeyingProfile.ensure(info: device.info, activate: device.activateKeyingProfile, firstConnector: first) { change in
            if ctx.keyingConsent { return true }
            let a = await ctx.ask(HardwarePrompt(kind: .changeProfile, title: "Change the card's profile?", message: change.question,
                                                 primaryLabel: "Change the profile", canSkip: true))
            let yes = a == .proceed || a == .yes
            if yes { ctx.keyingConsent = true }
            return yes
        }
        switch outcome {
        case .notNeeded:
            return .ready(event: nil)
        case .switched(let change):
            ctx.noteProfileSwitched()
            let text = "The card's profile was changed from \"\(change.fromName ?? "unknown")\" to \"\(change.toName)\" so connectors \(first) and \(first + 1) can send fill and key. It is put back after this step."
            ctx.log.add(text)
            return .ready(event: text)
        case .declined(let change):
            return .stop(HardwareStepOutput(outcome: .skipped, summary: "Fill and key needs the card's profile changed to \"\(change.toName)\", and the profile was not changed, so this step was skipped.", passCriteria: criteria))
        case .failed(let change, let reason):
            // A change that was started and failed may have left the card half changed: the runner checks and says so.
            if change != nil, device.activateKeyingProfile != nil { ctx.noteProfileSwitched() }
            return .stop(HardwareStepOutput(outcome: .failed, summary: "The card's profile could not be changed for fill and key: \(reason)", passCriteria: criteria))
        }
    }

    // MARK: 1. environment

    static func environment(_ ctx: HardwareTestContext) async throws -> HardwareStepOutput {
        let src = ctx.environment
        let sys = src.system()
        let displays = src.displays()
        let driver = ctx.provider.driver()
        let info = HardwareEnvironmentInfo(
            appVersion: src.appVersion, appBuild: src.appBuild, osVersion: sys.osVersion, osBuild: sys.osBuild, macModel: sys.macModel,
            chip: sys.chip, memoryGB: (Double(sys.memoryBytes) / 1_073_741_824 * 10).rounded() / 10, processorCount: sys.processorCount,
            displays: displays, driver: driver, collectedAt: HardwareTestClockText.iso(src.now()), appBuildDetail: src.buildDetail)
        ctx.environmentInfo = info
        var ms = [
            m("WorshipFlow", "\(src.appVersion) (build \(src.appBuild))" + (src.buildDetail.map { ", \($0)" } ?? "")),
            m("macOS", "\(sys.osVersion) (\(sys.osBuild))"),
            m("Mac model", sys.macModel),
            m("Chip", sys.chip),
            m("Memory", "\(Int(info.memoryGB.rounded())) GB"),
            m("Processor cores", "\(sys.processorCount)"),
        ]
        for (i, d) in displays.enumerated() {
            let rate = d.refreshRateHz.map { ", \(hz($0)) Hz" } ?? ""
            ms.append(m("Display \(i + 1)", "\(d.name), \(d.pixelWidth) x \(d.pixelHeight) pixels\(rate)"))
        }
        if displays.isEmpty { ms.append(m("Displays", "none reported")) }
        ms.append(m("Blackmagic driver", driver.isInstalled ? "installed" : "not installed"))
        if let v = driver.apiVersion { ms.append(m("Driver API version", v)) }
        if let v = driver.driverVersion { ms.append(m("Driver version", v)) }
        let loadable: String
        switch driver.frameworkLoadable {
        case true?: loadable = "yes"
        case false?: loadable = "no: the framework's files are on this Mac but loading them was refused (an entitlement or library validation problem, KI-055)"
        case nil: loadable = driver.isInstalled ? "yes (the driver answered)" : "unknown: no driver was found"
        }
        ms.append(m("Framework can be loaded (entitlement check)", loadable))
        ms.append(m("Driver message", driver.message))
        // The key route the device reports, so the report shows what the app planned from before anything is measured.
        if let card = ctx.device ?? ctx.allDevices.first {
            var first = 1
            while first + 1 <= card.info.connectorCount {
                let text = card.info.keyRoute(firstConnector: first).map { "fill on SDI \($0.fillConnector), key on SDI \($0.keyConnector)" } ?? "none reported"
                ms.append(m("Key route reported by the device (connectors \(first) and \(first + 1))", text))
                first += 2
            }
        } else {
            ms.append(m("Key route reported by the device", "no device found"))
        }
        let usable = !sys.osVersion.isEmpty && sys.osVersion != "unknown"
        return HardwareStepOutput(
            outcome: usable ? .passed : .failed,
            summary: usable ? "Recorded the machine, the displays and the driver state. No user name, file path under the home folder, or serial number is recorded."
                            : "The operating system version could not be read.",
            passCriteria: "Information only. It passes when the operating system version can be read.", measurements: ms)
    }

    // MARK: 2. devices

    static func devices(_ ctx: HardwareTestContext) async throws -> HardwareStepOutput {
        let driver = ctx.provider.driver()
        let all = ctx.allDevices
        guard !all.isEmpty else {
            return HardwareStepOutput(
                outcome: .failed,
                summary: "No DeckLink device was found. \(driver.message)",
                passCriteria: "At least one connected device is reported.",
                measurements: [m("Devices found", "0"), m("Blackmagic driver", driver.isInstalled ? "installed" : "not installed")])
        }
        var ms: [HardwareMeasurement] = [m("Devices found", "\(all.count)")]
        for (i, d) in all.enumerated() {
            let p = "Device \(i + 1)"
            ms.append(m(p, d.info.displayName))
            ms.append(m("\(p) simulated", yesNo(d.info.isSimulated)))
            ms.append(m("\(p) connected", yesNo(d.isConnected())))
            ms.append(m("\(p) connectors", "\(d.info.connectorCount)"))
            ms.append(m("\(p) fill and key", yesNo(d.info.supportsExternalKeying)))
            ms.append(m("\(p) profile", d.profile ?? "not reported by this provider"))
            ms.append(m("\(p) modes the provider lists", d.supportedModes.map(\.name).joined(separator: ", ")))
            for c in 1...max(1, d.info.connectorCount) where d.info.connectorCount > 0 {
                ms.append(m("\(p) connector \(c) output modes", outputModes(d, connector: c)))
                ms.append(m("\(p) connector \(c) input modes", inputModes(d, connector: c)))
            }
        }
        let connected = all.filter { $0.isConnected() }
        return HardwareStepOutput(
            outcome: connected.isEmpty ? .failed : .passed,
            summary: connected.isEmpty ? "A device was listed but it is not connected. \(driver.message)"
                                       : "Found \(all.count) device\(all.count == 1 ? "" : "s"): " + all.map(\.info.displayName).joined(separator: ", ") + ".",
            passCriteria: "At least one connected device is reported. Everything the device says about itself is recorded below.", measurements: ms)
    }

    private static func outputModes(_ d: HardwareTestDevice, connector: Int) -> String {
        do {
            let port = try d.openOutput(connector)
            defer { port.close() }
            let ok = SDIVideoMode.allKnown.filter { port.supports(mode: $0, keying: .none) }
            return ok.isEmpty ? "none" : ok.map(\.name).joined(separator: ", ")
        } catch { return "could not be opened (\(describe(error)))" }
    }

    private static func inputModes(_ d: HardwareTestDevice, connector: Int) -> String {
        do {
            let port = try d.openInput(connector)
            defer { port.close() }
            let ok = SDIVideoMode.allKnown.filter { port.supports(mode: $0) }
            return ok.isEmpty ? "none" : ok.map(\.name).joined(separator: ", ")
        } catch { return "could not be opened (\(describe(error)))" }
    }

    // MARK: 3. output run

    static func outputRun(_ ctx: HardwareTestContext) async throws -> HardwareStepOutput {
        guard let device = ctx.currentDevice() else { return HardwareStepOutput(outcome: .skipped, summary: "No device was found, so this step could not run.") }
        guard let connector = HardwareTestLayout.plainOutput(device.info, prefer: ctx.configuration.outputConnector) else {
            ctx.outputStartFailed = true
            return HardwareStepOutput(outcome: .skipped, summary: "No connector can send plain output in the card's profile as it is now, so the output run could not start.",
                                      passCriteria: "A connector that can send output exists.")
        }
        let seconds = ctx.configuration.durations.outputRunSeconds
        let criteria = "Pass needs zero dropped and zero late frames over the whole run, at least 90% of the expected frames completed, and the output still running at the end. Anything else is reported with the times it happened."
        let source = CounterFrameSource(width: mode.width, height: mode.height)
        let out: RunningOutput
        do { out = try startOutput(device, connector: connector) { source.frame(index: $0) } } catch {
            ctx.outputStartFailed = true
            return HardwareStepOutput(outcome: .failed, summary: "The output could not be started on SDI \(connector): \(describe(error))", passCriteria: criteria,
                                      measurements: [m("Connector", "SDI \(connector)"), m("Video mode", mode.name)])
        }
        defer { out.stop() }

        var series: [String: [Double]] = [:]
        var events: [String] = []
        var previous = SDISessionStatistics()
        var lowestBuffered = Int.max
        let elapsed = try await timedLoop(ctx, title: "Output run", seconds: seconds) { _, t in
            let st = out.session.statistics
            let buffered = out.port.bufferedFrameCount
            lowestBuffered = min(lowestBuffered, buffered)
            series["scheduled", default: []].append(Double(st.scheduler.scheduled))
            series["completed", default: []].append(Double(st.scheduler.completed))
            series["late", default: []].append(Double(st.scheduler.late))
            series["dropped", default: []].append(Double(st.scheduler.dropped))
            series["repeated", default: []].append(Double(st.repeatedFrames))
            series["buffered", default: []].append(Double(buffered))
            series["health", default: []].append(healthNumber(out.session.health))
            let late = st.scheduler.late - previous.scheduler.late, dropped = st.scheduler.dropped - previous.scheduler.dropped
            if late > 0 || dropped > 0 {
                events.append("\(Int(t.rounded())) s: \(late) late and \(dropped) dropped in this second (total \(st.scheduler.late) late, \(st.scheduler.dropped) dropped)")
            }
            previous = st
            if case .stopped(let reason) = out.session.state {
                events.append("\(Int(t.rounded())) s: the output stopped (\(reason))")
                return false
            }
            return true
        }
        let st = out.session.statistics
        let stopped = out.session.stopReason
        let expected = elapsed * mode.framesPerSecond
        let enough = Double(st.scheduler.completed) >= 0.9 * expected
        let clean = st.scheduler.dropped == 0 && st.scheduler.late == 0
        let ok = clean && enough && stopped == nil
        let ms = [
            m("Connector", "SDI \(connector)"), m("Video mode", mode.name), m("Test length", hz(elapsed), "s"),
            m("Frames scheduled", "\(st.scheduler.scheduled)"), m("Frames completed", "\(st.scheduler.completed)"),
            m("Late frames", "\(st.scheduler.late)"), m("Dropped frames", "\(st.scheduler.dropped)"),
            m("Repeated frames", "\(st.repeatedFrames)"), m("Final health", healthName(out.session.health)),
            m("Fewest frames buffered", lowestBuffered == Int.max ? "n/a" : "\(lowestBuffered)"),
            m("Expected frames", "\(Int(expected.rounded()))"),
        ]
        var summary: String
        if ok {
            summary = "Ran \(hz(elapsed)) s on SDI \(connector) at \(mode.name): \(st.scheduler.completed) frames completed, 0 dropped, 0 late."
        } else {
            var why: [String] = []
            if st.scheduler.dropped > 0 { why.append("\(st.scheduler.dropped) frames were dropped") }
            if st.scheduler.late > 0 { why.append("\(st.scheduler.late) frames were late") }
            if !enough { why.append("only \(st.scheduler.completed) of about \(Int(expected.rounded())) expected frames completed") }
            if let stopped { why.append("the output stopped: \(stopped)") }
            summary = "Problems on SDI \(connector): " + why.joined(separator: "; ") + ". The times are listed below."
        }
        return HardwareStepOutput(outcome: ok ? .passed : .failed, summary: summary, passCriteria: criteria, measurements: ms,
                                  events: events, samples: series, sampleIntervalSeconds: 1)
    }

    // MARK: 6. mode sweep

    static func modeSweep(_ ctx: HardwareTestContext) async throws -> HardwareStepOutput {
        guard var device = ctx.currentDevice() else { return HardwareStepOutput(outcome: .skipped, summary: "No device was found, so this step could not run.") }
        let criteria = "The device says it supports 1080p59.94 for output, and, when it reports fill and key, with fill and key too. This step asks the device and runs no video, so a \"supported\" is only what the device said, in the profile it was in when asked."
        var ms: [HardwareMeasurement] = []
        var events: [String] = []
        // The fill and key answer is only meaningful on a pair that is in the keying profile. After the tester agreed to one change
        // in this run, the same agreement covers this one (the runner puts the profile back after the step).
        let keyable = HardwareTestLayout.keyablePairs(device.info, prefer: ctx.configuration.outputConnector)
        if let first = keyable.first, ctx.keyingConsent {
            switch await ensureKeyingProfile(ctx, device, first: first, criteria: criteria) {
            case .ready(let event): if let event { events.append(event) }
            case .stop(let out): return out
            }
            device = ctx.currentDevice() ?? device
        }
        let info = device.info
        var plain: [SDIVideoMode: Bool] = [:], keyed: [SDIVideoMode: Bool] = [:]
        let plainConnector = HardwareTestLayout.plainOutput(info, prefer: ctx.configuration.outputConnector)
        if let c = plainConnector {
            do {
                let port = try device.openOutput(c)
                for mode in SDIVideoMode.allKnown { plain[mode] = port.supports(mode: mode, keying: .none) }
                port.close()
            } catch {
                return HardwareStepOutput(outcome: .failed, summary: "SDI \(c) could not be opened to ask about modes: \(describe(error))", passCriteria: criteria)
            }
        }
        // The keyed answer: the first pair that is keying now, else (nothing keying) the first that could be.
        let keyingNow = keyable.filter { info.profileState(forPair: $0)?.keyingAvailableNow ?? true }
        var keyedConnector: Int?
        var keyedNotAsked: String?
        if let first = keyingNow.first {
            keyedConnector = first
            if let port = try? device.openOutput(first) {
                for mode in SDIVideoMode.allKnown { keyed[mode] = port.supports(mode: mode, keying: .external(fillAlphaMode: .premultiplied)) }
                port.close()
            }
        } else if let first = keyable.first, let state = info.profileState(forPair: first) {
            keyedNotAsked = "not asked: the card is in the profile \"\(state.activeName ?? "unknown")\", which cannot send fill and key (it can in \"\(state.keyingChange?.toName ?? "another profile")\")"
        } else if !info.supportsExternalKeying {
            keyedNotAsked = nil          // the device says it cannot: "not supported" is its own answer
        }
        var second: [SDIVideoMode: Bool] = [:]
        let secondFirst = keyingNow.first { $0 != keyedConnector }
        if let c = secondFirst, let port = try? device.openOutput(c) {
            for mode in SDIVideoMode.allKnown { second[mode] = port.supports(mode: mode, keying: .external(fillAlphaMode: .premultiplied)) }
            port.close()
        }
        for mode in SDIVideoMode.allKnown {
            ms.append(m("\(mode.name) output", plainConnector == nil ? "not asked: no connector can send plain output in this profile" : (plain[mode] == true ? "supported" : "not supported")))
            ms.append(m("\(mode.name) with fill and key", keyedNotAsked ?? (keyed[mode] == true ? "supported" : "not supported")))
            if let c = secondFirst, !second.isEmpty { ms.append(m("\(mode.name) with fill and key (second pair, SDI \(c) and \(c + 1))", second[mode] == true ? "supported" : "not supported")) }
        }
        let target = HardwareTestConfiguration.testMode
        let plainOK = plain[target] == true, keyedOK = keyed[target] == true
        let askedPlain = plainConnector != nil, askedKeyed = keyedNotAsked == nil
        let finding = "UNV-02: the device says \(target.name) is \(askedPlain ? (plainOK ? "supported" : "not supported") : "not asked") for output and \(askedKeyed ? (keyedOK ? "supported" : "not supported") : "not asked") with fill and key. This is the device's own answer, in the profile it was in when asked; no video was run."
        var summary = "Asked the device about \(SDIVideoMode.allKnown.count) modes without running video. "
        let outcome: HardwareTestOutcome
        if !askedPlain {
            summary += "No connector can send plain output in the card's profile as it is now, so output was not asked."
            outcome = .partial
        } else if !plainOK {
            summary += "It says \(target.name) is not supported for output."
            outcome = .failed
        } else if !askedKeyed {
            summary += "It says \(target.name) works for output. Fill and key was not asked: the card was in a profile that cannot send it."
            outcome = .partial
        } else if !keyedOK {
            summary += "It says \(target.name) is supported, but not together with fill and key."
            outcome = .failed
        } else {
            summary += "It says \(target.name) works for output and for fill and key."
            outcome = .passed
        }
        return HardwareStepOutput(outcome: outcome, summary: summary, passCriteria: criteria, measurements: ms, findings: [finding], events: events)
    }

    // MARK: 7. four outputs

    /// One output's identity as seen on an input (FIX-D S4).
    struct IdentityCheck {
        var output: Int
        var input: Int?
        var seen: Int?
        var note: String?
    }

    /// Runs the outputs of `cables` with their own identity pictures and reads each cable's input. Returns nil with a reason
    /// when the outputs or inputs could not be set up.
    private static func identityPhase(_ ctx: HardwareTestContext, _ device: HardwareTestDevice, cables: [HardwareCable], seconds: Double) async throws -> [IdentityCheck] {
        var outputs: [RunningOutput] = []
        var inputs: [any SDIInputPort] = []
        defer {
            outputs.forEach { $0.stop() }
            inputs.forEach { $0.disable(); $0.close() }
        }
        var collectors: [IdentityCollector] = []
        let base = CounterFrameSource(width: mode.width, height: mode.height)
        var results = cables.map { IdentityCheck(output: $0.output, input: $0.input) }
        for (i, cable) in cables.enumerated() {
            do {
                let collector = IdentityCollector()
                let p = try device.openInput(cable.input)
                inputs.append(p)
                p.onFrameReceived = { collector.receive($0) }
                try p.enable(mode: nil)
                collectors.append(collector)
            } catch {
                results[i].note = "SDI \(cable.input) could not be opened for input: \(describe(error))"
                collectors.append(IdentityCollector())
            }
        }
        for (i, cable) in cables.enumerated() {
            let source = IdentityFrameSource(connector: cable.output, base: base)
            do { outputs.append(try startOutput(device, connector: cable.output) { source.frame(index: $0) }) } catch {
                results[i].note = "SDI \(cable.output) could not be started: \(describe(error))"
            }
        }
        var waited = 0.0
        while collectors.contains(where: { $0.frames < 3 }), waited < 5 {
            try await ctx.clock.wait(seconds: 0.25)
            waited += 0.25
        }
        try await timedLoop(ctx, title: "Four outputs: which picture arrives where", seconds: seconds) { _, _ in true }
        for i in results.indices where results[i].note == nil {
            results[i].seen = collectors[i].identity
            if results[i].seen == nil {
                results[i].note = collectors[i].frames == 0 ? "no signal reached SDI \(cables[i].input)" : "SDI \(cables[i].input) received pictures, but none could be read"
            }
        }
        return results
    }

    static func fourOutputs(_ ctx: HardwareTestContext) async throws -> HardwareStepOutput {
        guard let device = ctx.currentDevice() else { return HardwareStepOutput(outcome: .skipped, summary: "No device was found, so this step could not run.") }
        let seconds = ctx.configuration.durations.fourOutputSeconds
        let criteria = "On every one of the four connectors: zero dropped and zero late frames, at least 90% of the expected frames completed, and the output still running. Each connector counts as PASSED only when its own picture (its connector number is in the picture) was seen on an input; a connector that ran without being looked at says \"ran, identity not checked\" and the step is then only partly measured. Memory and CPU of this app are recorded every second as evidence for UNV-04; they have no pass limit."
        let info = device.info
        let senders = HardwareTestLayout.outputs(info)
        guard info.connectorCount >= 4, (1...info.connectorCount).allSatisfy({ senders.contains($0) }) else {
            let list = senders.map(String.init).joined(separator: ", ")
            return HardwareStepOutput(outcome: .skipped,
                                      summary: "In the card's profile as it is now only SDI \(list.isEmpty ? "none" : list) can send output, so four outputs at once cannot be tested.",
                                      passCriteria: criteria)
        }

        // Which picture arrives where: the outputs in turn, with the tester moving the cables between two halves of the card.
        var checks: [Int: IdentityCheck] = [:]
        var notes: [String] = []
        var cablesPlaced: [HardwareCable] = []
        if let halves = HardwareTestLayout.halves(info) {
            let count = min(halves.lower.count, halves.upper.count)
            let first = (0..<count).map { HardwareCable(output: halves.lower[$0], input: halves.upper[$0]) }
            let second = (0..<count).map { HardwareCable(output: halves.upper[$0], input: halves.lower[$0]) }
            func cableText(_ c: [HardwareCable]) -> String { c.map(\.text).joined(separator: ", and ") }
            let identitySeconds = 3.0
            let lowerCanSend = first.allSatisfy { HardwareTestLayout.canInput(info, $0.input) }
            let upperCanSend = second.allSatisfy { HardwareTestLayout.canInput(info, $0.input) }
            let a = lowerCanSend ? await ctx.ask(HardwarePrompt(
                kind: .connectLoopbackCable, title: "Check each connector's picture (1 of 2)",
                message: "To check that each connector sends its own picture, connect \(count) BNC cable\(count == 1 ? "" : "s"): \(cableText(first)). Then press Continue. Press Skip to run the four outputs without checking which picture comes out of which connector.",
                primaryLabel: "Continue", canSkip: true, cables: first)) : .skip
            if !lowerCanSend { notes.append("the connectors of the upper half cannot receive in the card's profile as it is now") }
            if a == .proceed {
                cablesPlaced = first
                for r in try await identityPhase(ctx, device, cables: first, seconds: identitySeconds) { checks[r.output] = r }
                let b = upperCanSend ? await ctx.ask(HardwarePrompt(
                    kind: .moveCables, title: "Check each connector's picture (2 of 2)",
                    message: "Now move the cables so they go the other way: \(cableText(second)). Then press Continue. Press Skip to leave the other connectors unchecked.",
                    primaryLabel: "Continue", canSkip: true, cables: second)) : .skip
                if b == .proceed {
                    cablesPlaced = second
                    for r in try await identityPhase(ctx, device, cables: second, seconds: identitySeconds) { checks[r.output] = r }
                } else {
                    notes.append(upperCanSend ? "the tester skipped the second set of cables" : "the connectors of the lower half cannot receive in the card's profile as it is now")
                }
                _ = await ctx.ask(HardwarePrompt(
                    kind: .removeCables, title: "Take the cables off",
                    message: "Take the cables off the card, so no output is joined to another. Then press Continue.",
                    primaryLabel: "Continue", canSkip: false, cables: cablesPlaced))
            } else if lowerCanSend {
                notes.append("the tester skipped the cables")
            }
        } else {
            notes.append("the card has no four-connector layout this check can use")
        }

        let source = CounterFrameSource(width: mode.width, height: mode.height)
        var outputs: [RunningOutput] = []
        defer { outputs.forEach { $0.stop() } }
        for c in 1...4 {
            let identity = IdentityFrameSource(connector: c, base: source)
            do { outputs.append(try startOutput(device, connector: c) { identity.frame(index: $0) }) } catch {
                return HardwareStepOutput(outcome: .failed, summary: "SDI \(c) could not be started with the others: \(describe(error))", passCriteria: criteria,
                                          measurements: [m("Outputs started", "\(outputs.count) of 4")])
            }
        }
        var series: [String: [Double]] = [:]
        var events: [String] = []
        var previousSample = ctx.resources.sample()
        var peak: UInt64 = previousSample?.residentBytes ?? 0
        var cpuValues: [Double] = []
        var previousStats = [SDISessionStatistics](repeating: SDISessionStatistics(), count: 4)
        let elapsed = try await timedLoop(ctx, title: "Four outputs", seconds: seconds) { _, t in
            for (i, out) in outputs.enumerated() {
                let st = out.session.statistics
                series["connector\(i + 1)Completed", default: []].append(Double(st.scheduler.completed))
                series["connector\(i + 1)Late", default: []].append(Double(st.scheduler.late))
                series["connector\(i + 1)Dropped", default: []].append(Double(st.scheduler.dropped))
                let late = st.scheduler.late - previousStats[i].scheduler.late, dropped = st.scheduler.dropped - previousStats[i].scheduler.dropped
                if late > 0 || dropped > 0 { events.append("\(Int(t.rounded())) s: SDI \(i + 1) had \(late) late and \(dropped) dropped in this second") }
                previousStats[i] = st
            }
            if let s = ctx.resources.sample() {
                series["residentMB", default: []].append((Double(s.residentBytes) / 1_048_576 * 10).rounded() / 10)
                peak = max(peak, s.residentBytes)
                var cpu = 0.0
                if let p = previousSample, s.wallSeconds > p.wallSeconds { cpu = max(0, (s.cpuSeconds - p.cpuSeconds) / (s.wallSeconds - p.wallSeconds) * 100) }
                series["cpuPercent", default: []].append((cpu * 10).rounded() / 10)
                cpuValues.append(cpu)
                previousSample = s
            }
            return true
        }
        let expected = elapsed * mode.framesPerSecond
        var ms: [HardwareMeasurement] = [m("Video mode", mode.name), m("Test length", hz(elapsed), "s")]
        var bad: [String] = []
        var unchecked: [Int] = []
        var wrong: [String] = []
        for (i, out) in outputs.enumerated() {
            let c = i + 1
            let st = out.session.statistics
            ms.append(m("Connector \(c) completed", "\(st.scheduler.completed)"))
            ms.append(m("Connector \(c) late", "\(st.scheduler.late)"))
            ms.append(m("Connector \(c) dropped", "\(st.scheduler.dropped)"))
            ms.append(m("Connector \(c) health", healthName(out.session.health)))
            var clean = true
            if st.scheduler.late > 0 || st.scheduler.dropped > 0 { bad.append("SDI \(c) had \(st.scheduler.dropped) dropped and \(st.scheduler.late) late frames"); clean = false }
            if Double(st.scheduler.completed) < 0.9 * expected { bad.append("SDI \(c) completed only \(st.scheduler.completed) of about \(Int(expected.rounded())) frames"); clean = false }
            if let r = out.session.stopReason { bad.append("SDI \(c) stopped: \(r)"); clean = false }
            // The identity: its own picture must be what arrived at the input its cable went to.
            let identity: String
            if let check = checks[c], let seen = check.seen, let input = check.input {
                if seen == c {
                    identity = "confirmed: SDI \(input) received SDI \(c)'s own picture"
                } else {
                    identity = "WRONG: SDI \(input) received the picture sent on SDI \(seen), not the one sent on SDI \(c)"
                    wrong.append("the cable from SDI \(c) to SDI \(input) carried the picture sent on SDI \(seen), so the card's connector numbering does not match the numbering this app uses for SDI \(c) and SDI \(seen)")
                }
            } else {
                unchecked.append(c)
                let why = checks[c]?.note ?? notes.first ?? "no cable was connected to it"
                identity = "ran, identity not checked (\(why))"
            }
            ms.append(m("Connector \(c) picture", identity))
            let verdict = !clean ? "FAILED" : (identity.hasPrefix("confirmed") ? "PASSED" : (identity.hasPrefix("WRONG") ? "FAILED" : "ran, identity not checked"))
            ms.append(m("Connector \(c) result", verdict))
        }
        if peak > 0 { ms.append(m("Peak memory", "\(Int((Double(peak) / 1_048_576).rounded())) MB")) }
        if !cpuValues.isEmpty {
            ms.append(m("CPU load, mean", String(format: "%.1f", cpuValues.reduce(0, +) / Double(cpuValues.count)), "% of one core"))
            ms.append(m("CPU load, highest second", String(format: "%.1f", cpuValues.max() ?? 0), "% of one core"))
        }
        let finding = "UNV-04: four outputs at \(mode.name) ran for \(hz(elapsed)) s with \(bad.isEmpty ? "no dropped or late frames" : "problems (see the details)")"
            + (peak > 0 ? ", peak memory \(Int((Double(peak) / 1_048_576).rounded())) MB" : "")
            + ". This is output only, with no stream encoding and no fill and key, and one short run does not settle it."
        let outcome: HardwareTestOutcome
        var summary: String
        if !bad.isEmpty || !wrong.isEmpty {
            outcome = .failed
            summary = (bad + wrong).joined(separator: "; ") + "."
        } else if !unchecked.isEmpty {
            outcome = .partial
            let list = unchecked.map { "SDI \($0)" }.joined(separator: ", ")
            summary = "All four connectors ran together for \(hz(elapsed)) s with no dropped or late frames. Only the connectors whose own picture was seen on an input are counted as passed: \(list) ran, identity not checked."
        } else {
            outcome = .passed
            summary = "All four connectors ran together for \(hz(elapsed)) s with no dropped or late frames, and each connector's own picture was seen on an input."
        }
        return HardwareStepOutput(outcome: outcome, summary: summary, passCriteria: criteria, measurements: ms, findings: [finding], events: events, samples: series, sampleIntervalSeconds: 1)
    }
}
