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

    // MARK: 1. environment

    static func environment(_ ctx: HardwareTestContext) async throws -> HardwareStepOutput {
        let src = ctx.environment
        let sys = src.system()
        let displays = src.displays()
        let driver = ctx.provider.driver()
        let info = HardwareEnvironmentInfo(
            appVersion: src.appVersion, appBuild: src.appBuild, osVersion: sys.osVersion, osBuild: sys.osBuild, macModel: sys.macModel,
            chip: sys.chip, memoryGB: (Double(sys.memoryBytes) / 1_073_741_824 * 10).rounded() / 10, processorCount: sys.processorCount,
            displays: displays, driver: driver, collectedAt: HardwareTestClockText.iso(src.now()))
        ctx.environmentInfo = info
        var ms = [
            m("WORSHIPFLOW", "\(src.appVersion) (build \(src.appBuild))"),
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
        guard let device = ctx.device else { return HardwareStepOutput(outcome: .skipped, summary: "No device was found, so this step could not run.") }
        let connector = ctx.configuration.outputConnector
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
        guard let device = ctx.device else { return HardwareStepOutput(outcome: .skipped, summary: "No device was found, so this step could not run.") }
        let criteria = "The device says it supports 1080p59.94 for output, and, when it reports fill and key, with fill and key too. This step asks the device and runs no video, so a \"supported\" is only what the device said."
        var ms: [HardwareMeasurement] = []
        var plain: [SDIVideoMode: Bool] = [:], keyed: [SDIVideoMode: Bool] = [:]
        do {
            let port = try device.openOutput(1)
            for mode in SDIVideoMode.allKnown {
                plain[mode] = port.supports(mode: mode, keying: .none)
                keyed[mode] = port.supports(mode: mode, keying: .external(fillAlphaMode: .premultiplied))
            }
            port.close()
        } catch {
            return HardwareStepOutput(outcome: .failed, summary: "SDI 1 could not be opened to ask about modes: \(describe(error))", passCriteria: criteria)
        }
        var second: [SDIVideoMode: Bool] = [:]
        if device.info.connectorCount >= 4, let port = try? device.openOutput(3) {
            for mode in SDIVideoMode.allKnown { second[mode] = port.supports(mode: mode, keying: .external(fillAlphaMode: .premultiplied)) }
            port.close()
        }
        for mode in SDIVideoMode.allKnown {
            ms.append(m("\(mode.name) output", plain[mode] == true ? "supported" : "not supported"))
            ms.append(m("\(mode.name) with fill and key", keyed[mode] == true ? "supported" : "not supported"))
            if !second.isEmpty { ms.append(m("\(mode.name) with fill and key (second pair, SDI 3 and 4)", second[mode] == true ? "supported" : "not supported")) }
        }
        let target = HardwareTestConfiguration.testMode
        let plainOK = plain[target] == true, keyedOK = keyed[target] == true
        let finding = "UNV-02: the device says \(target.name) is \(plainOK ? "supported" : "not supported") for output and \(keyedOK ? "supported" : "not supported") with fill and key. This is the device's own answer; no video was run."
        let ok = plainOK && keyedOK
        var summary = "Asked the device about \(SDIVideoMode.allKnown.count) modes without running video. "
        summary += ok ? "It says \(target.name) works for output and for fill and key." :
            !plainOK ? "It says \(target.name) is not supported for output." : "It says \(target.name) is supported, but not together with fill and key."
        return HardwareStepOutput(outcome: ok ? .passed : .failed, summary: summary, passCriteria: criteria, measurements: ms, findings: [finding])
    }

    // MARK: 7. four outputs

    static func fourOutputs(_ ctx: HardwareTestContext) async throws -> HardwareStepOutput {
        guard let device = ctx.device else { return HardwareStepOutput(outcome: .skipped, summary: "No device was found, so this step could not run.") }
        let seconds = ctx.configuration.durations.fourOutputSeconds
        let criteria = "On every one of the four connectors: zero dropped and zero late frames, at least 90% of the expected frames completed, and the output still running. Memory and CPU of this app are recorded every second as evidence for UNV-04; they have no pass limit."
        let source = CounterFrameSource(width: mode.width, height: mode.height)
        var outputs: [RunningOutput] = []
        defer { outputs.forEach { $0.stop() } }
        for c in 1...4 {
            do { outputs.append(try startOutput(device, connector: c) { source.frame(index: $0) }) } catch {
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
        for (i, out) in outputs.enumerated() {
            let st = out.session.statistics
            ms.append(m("Connector \(i + 1) completed", "\(st.scheduler.completed)"))
            ms.append(m("Connector \(i + 1) late", "\(st.scheduler.late)"))
            ms.append(m("Connector \(i + 1) dropped", "\(st.scheduler.dropped)"))
            ms.append(m("Connector \(i + 1) health", healthName(out.session.health)))
            if st.scheduler.late > 0 || st.scheduler.dropped > 0 { bad.append("SDI \(i + 1) had \(st.scheduler.dropped) dropped and \(st.scheduler.late) late frames") }
            if Double(st.scheduler.completed) < 0.9 * expected { bad.append("SDI \(i + 1) completed only \(st.scheduler.completed) of about \(Int(expected.rounded())) frames") }
            if let r = out.session.stopReason { bad.append("SDI \(i + 1) stopped: \(r)") }
        }
        if peak > 0 { ms.append(m("Peak memory", "\(Int((Double(peak) / 1_048_576).rounded())) MB")) }
        if !cpuValues.isEmpty {
            ms.append(m("CPU load, mean", String(format: "%.1f", cpuValues.reduce(0, +) / Double(cpuValues.count)), "% of one core"))
            ms.append(m("CPU load, highest second", String(format: "%.1f", cpuValues.max() ?? 0), "% of one core"))
        }
        let finding = "UNV-04: four outputs at \(mode.name) ran for \(hz(elapsed)) s with \(bad.isEmpty ? "no dropped or late frames" : "problems (see the details)")"
            + (peak > 0 ? ", peak memory \(Int((Double(peak) / 1_048_576).rounded())) MB" : "")
            + ". This is output only, with no stream encoding and no fill and key, and one short run does not settle it."
        return HardwareStepOutput(outcome: bad.isEmpty ? .passed : .failed,
                                  summary: bad.isEmpty ? "All four connectors ran together for \(hz(elapsed)) s with no dropped or late frames." : bad.joined(separator: "; ") + ".",
                                  passCriteria: criteria, measurements: ms, findings: [finding], events: events, samples: series, sampleIntervalSeconds: 1)
    }
}
