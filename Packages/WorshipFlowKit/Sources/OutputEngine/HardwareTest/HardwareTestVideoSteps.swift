// HWTEST-001: the steps that need cables or a person: loopback (4), fill and key loopback (5), unplug and replug (8)
// and human checks (9).
import Foundation
import SDIEngine

extension HardwareTestSteps {
    // MARK: 4. loopback

    static func loopback(_ ctx: HardwareTestContext) async throws -> HardwareStepOutput {
        guard let device = ctx.currentDevice() else { return HardwareStepOutput(outcome: .skipped, summary: "No device was found, so this step could not run.") }
        guard let wiring = HardwareTestLayout.loopback(device.info, preferOutput: ctx.configuration.outputConnector, preferInput: ctx.configuration.loopbackInputConnector) else {
            return HardwareStepOutput(outcome: .skipped, summary: "In the card's profile as it is now no connector can send plain output and another receive it, so the loopback could not be wired.",
                                      passCriteria: "An output connector and an input connector that can receive exist.")
        }
        let outC = wiring.output, inC = wiring.input
        let seconds = ctx.configuration.durations.loopbackSeconds
        let t = CaptureCollector.pixelTolerance
        let criteria = "Signal detected on SDI \(inC) within 5 seconds in \(mode.name); no missing, repeated or out-of-order frames; every frame's counter readable; at least 90% of the expected frames received; largest pixel error against the pattern sent at most \(t) levels (of 255) and mean at most 3.0. The delay in frames is reported, not judged."
        let answer = await ctx.ask(HardwarePrompt(
            kind: .connectLoopbackCable, title: "Connect one cable",
            message: "Connect one BNC cable from SDI \(outC) to SDI \(inC) on the card. Then press Continue. If you have no cable, press Skip.",
            primaryLabel: "Continue", canSkip: true, cables: [HardwareCable(output: outC, input: inC)]))
        if answer == .skip { return HardwareStepOutput(outcome: .skipped, summary: "Skipped by the tester: no cable from SDI \(outC) to SDI \(inC).", passCriteria: criteria) }

        let source = CounterFrameSource(width: mode.width, height: mode.height)
        let outPort: any SDIOutputPort, input: any SDIInputPort
        do {
            outPort = try device.openOutput(outC)
        } catch { return HardwareStepOutput(outcome: .failed, summary: "SDI \(outC) could not be opened for output: \(describe(error))", passCriteria: criteria) }
        do { input = try device.openInput(inC) } catch {
            outPort.close()
            return HardwareStepOutput(outcome: .failed, summary: "SDI \(inC) could not be opened for input: \(describe(error))", passCriteria: criteria)
        }
        let session = SDIOutputSession(port: outPort, mode: mode) { source.frame(index: $0) }
        let collector = CaptureCollector(source: source, processed: {
            let s = session.statistics.scheduler
            return s.completed + s.late + s.dropped
        })
        defer {
            session.stop()
            outPort.close()
            input.disable()
            input.close()
        }
        input.onFrameReceived = { collector.receive($0) }
        input.onSignalChange = { collector.signalChanged($0) }
        do {
            try input.enable(mode: nil)
            try session.start()
        } catch {
            return HardwareStepOutput(outcome: .failed, summary: "Could not start the loopback: \(describe(error))", passCriteria: criteria)
        }

        var waited = 0.0
        while collector.snapshot.detectedMode == nil, waited < 5 {
            try await ctx.clock.wait(seconds: 0.25)
            waited += 0.25
        }
        guard collector.snapshot.detectedMode != nil else {
            return HardwareStepOutput(
                outcome: .failed,
                summary: "No signal reached SDI \(inC) in 5 seconds. Check the cable from SDI \(outC) to SDI \(inC) and that both ends are pushed in.",
                passCriteria: criteria, measurements: [m("Signal detected", "no"), m("Output", "SDI \(outC)"), m("Input", "SDI \(inC)")])
        }

        var series: [String: [Double]] = [:]
        let before = collector.snapshot.received
        let elapsed = try await timedLoop(ctx, title: "Loopback", seconds: seconds) { _, _ in
            let s = collector.snapshot
            series["received", default: []].append(Double(s.received))
            series["missing", default: []].append(Double(s.missing))
            series["pixelErrorMax", default: []].append(Double(s.maxPixelError))
            return true
        }
        let s = collector.snapshot
        let expected = elapsed * mode.framesPerSecond
        let during = s.received - before
        let modeOK = s.detectedMode == mode
        let clean = s.missing == 0 && s.repeated == 0 && s.outOfOrder == 0 && s.unreadable == 0
        let enough = Double(during) >= 0.9 * expected
        let meanError = s.comparedFrames > 0 ? s.meanErrorSum / Double(s.comparedFrames) : 0
        let pixelsOK = s.comparedFrames > 0 && s.maxPixelError <= t && meanError <= 3.0
        let ok = modeOK && clean && enough && pixelsOK
        var ms = [
            m("Signal detected", "yes"), m("Detected mode", s.detectedMode?.name ?? "unknown"), m("Mode sent", mode.name),
            m("Output", "SDI \(outC)"), m("Input", "SDI \(inC)"), m("Test length", hz(elapsed), "s"),
            m("Frames received", "\(s.received)"), m("Frames expected", "\(Int(expected.rounded()))"),
            m("Missing frames", "\(s.missing)"), m("Repeated frames", "\(s.repeated)"), m("Out-of-order frames", "\(s.outOfOrder)"),
            m("Frames with no readable counter", "\(s.unreadable)"), m("Gaps in the capture clock", "\(s.timestampGaps)"),
        ]
        if let med = CaptureMath.median(s.delays) {
            ms.append(m("Delay (median)", "\(med) frames"))
            ms.append(m("Delay (smallest)", "\(s.delays.min() ?? med) frames"))
            ms.append(m("Delay (largest)", "\(s.delays.max() ?? med) frames"))
        } else { ms.append(m("Delay (median)", "not measured")) }
        ms.append(m("Frames compared pixel by pixel", "\(s.comparedFrames)"))
        ms.append(m("Largest pixel error", "\(s.maxPixelError)"))
        ms.append(m("Mean pixel error", String(format: "%.3f", meanError)))
        if let f = s.firstDifference { ms.append(m("First differing pixel", "x=\(f.x), y=\(f.y)")) }
        var summary: String
        if ok {
            summary = "SDI \(outC) to SDI \(inC): \(during) frames received over \(hz(elapsed)) s, none missing, repeated or out of order, largest pixel error \(s.maxPixelError)."
        } else {
            var why: [String] = []
            if !modeOK { why.append("the input detected \(s.detectedMode?.name ?? "no mode") instead of \(mode.name)") }
            if s.missing > 0 { why.append("\(s.missing) frames were missing") }
            if s.repeated > 0 { why.append("\(s.repeated) frames were repeated") }
            if s.outOfOrder > 0 { why.append("\(s.outOfOrder) frames arrived out of order") }
            if s.unreadable > 0 { why.append("\(s.unreadable) frames had no readable counter") }
            if !enough { why.append("only \(during) of about \(Int(expected.rounded())) expected frames arrived") }
            if s.comparedFrames == 0 { why.append("no frame could be compared with the pattern") }
            else if !pixelsOK { why.append("the picture differed from what was sent (largest pixel error \(s.maxPixelError), limit \(t))") }
            summary = "Problems between SDI \(outC) and SDI \(inC): " + why.joined(separator: "; ") + "."
        }
        return HardwareStepOutput(outcome: ok ? .passed : .failed, summary: summary, passCriteria: criteria, measurements: ms, samples: series, sampleIntervalSeconds: 1)
    }

    // MARK: 5. fill and key loopback

    private struct PhaseResult {
        var fillInput: CaptureCollector.Totals
        var keyInput: CaptureCollector.Totals
    }

    private static func runKeyedPhase(_ ctx: HardwareTestContext, _ device: HardwareTestDevice, plan: HardwareKeyedPlan, alphaMode: AlphaMode, frame: SDIFrame,
                                       seconds: Double, title: String) async throws -> Result<PhaseResult, KeyedSetupError> {
        let outC = plan.first
        let a = CaptureCollector(source: nil, keepLastFrame: true), b = CaptureCollector(source: nil, keepLastFrame: true)
        var ports: [any SDIInputPort] = []
        defer { ports.forEach { $0.disable(); $0.close() } }
        for (connector, collector) in [(plan.inputA, a), (plan.inputB, b)] {
            do {
                let p = try device.openInput(connector)
                ports.append(p)
                p.onFrameReceived = { collector.receive($0) }
                p.onSignalChange = { collector.signalChanged($0) }
                try p.enable(mode: nil)
            } catch { return .failure(KeyedSetupError(text: "SDI \(connector) could not be opened for input: \(describe(error))")) }
        }
        let out: RunningOutput
        do { out = try startOutput(device, connector: outC, keying: .external(fillAlphaMode: alphaMode)) { _ in frame } } catch {
            return .failure(KeyedSetupError(text: "Fill and key could not be started on SDI \(outC) and \(outC + 1): \(describe(error))"))
        }
        defer { out.stop() }
        var waited = 0.0
        while (a.snapshot.detectedMode == nil || b.snapshot.detectedMode == nil), waited < 5 {
            try await ctx.clock.wait(seconds: 0.25)
            waited += 0.25
        }
        try await timedLoop(ctx, title: title, seconds: seconds) { _, _ in true }
        return .success(PhaseResult(fillInput: a.snapshot, keyInput: b.snapshot))
    }

    private struct KeyedSetupError: Error { var text: String }

    /// "fill", "key" or "unclear", from what arrived at the middle of the opaque orange box.
    private static func role(of frame: SDIFrame?) -> String {
        guard let frame else { return "no signal" }
        let r = TestPattern.alphaWindowRegions(width: frame.width, height: frame.height)
        let p = CaptureMath.block(frame, x: r.opaque.centerX, y: r.opaque.centerY)
        let spread = max(p.b, p.g, p.r) - min(p.b, p.g, p.r)
        if spread <= 24 && p.r >= 200 { return "key" }
        if p.r >= 200 && p.b <= 60 && (90...170).contains(p.g) { return "fill" }
        return "unclear"
    }

    private static func routeSource(_ source: SDIKeyRoute.Source) -> String {
        switch source {
        case .manualTable: return "the vendor manual's table, read by the bridge (the SDK has no attribute that says it): not a measurement"
        case .simulator: return "the simulated card's own implementation"
        case .assumed: return "the app's convention, assumed because nothing better is known for this model"
        }
    }

    static func fillKeyLoopback(_ ctx: HardwareTestContext) async throws -> HardwareStepOutput {
        guard var device = ctx.currentDevice() else { return HardwareStepOutput(outcome: .skipped, summary: "No device was found, so this step could not run.") }
        let cfg = ctx.configuration
        guard let outC = HardwareTestLayout.keyablePairs(device.info, prefer: cfg.outputConnector).first else {
            return HardwareStepOutput(outcome: .skipped, summary: "No pair of connectors on this card can send fill and key in any profile it reports, so there is nothing to test.")
        }
        let criteria = "Cables as stated in the prompt: the two connectors of the pair starting at SDI \(outC) go to two connectors that can receive. Pass needs a signal on both inputs; the fill and key on the connectors the device reports (UNV-03; with no reported route, the fill on SDI \(outC) and the key on SDI \(outC + 1)), measured with the cables as instructed, and compared with the device's report and the manual's table; if the result is the reverse of the report, the tester is asked to check the cables and the step runs once more, and both runs are kept; the key within 16 levels of the alpha sent at the centre of each box and the surround, with a mean error of at most 4 and fewer than 0.5% of pixels over 16 levels (tolerance stated here, not hidden); the fill premultiplied when configured premultiplied and straight when configured straight (the 50% box reads about 128 or about 255, within 24); and the alpha ramp followed within 24 levels. Both alpha modes are tried."

        // The cables are asked for first, from the layout as it is now, so a tester with no cables is not asked about the profile.
        func prompt(_ plan: HardwareKeyedPlan, kind: HardwarePromptKind) async -> HardwareAnswer {
            await ctx.ask(HardwarePrompt(
                kind: kind, title: kind == .moveCables ? "Move the cables" : "Connect two cables",
                message: "Connect two BNC cables: one from SDI \(plan.first) to SDI \(plan.inputA), and one from SDI \(plan.first + 1) to SDI \(plan.inputB). Then press Continue. If you only have one cable, press Skip.",
                primaryLabel: "Continue", canSkip: true, cables: plan.cables))
        }
        let provisional = HardwareTestLayout.keyed(device.info, first: outC, preferA: cfg.loopbackInputConnector, preferB: cfg.keyInputConnector)
        if case .success(let plan) = provisional {
            if await prompt(plan, kind: .connectKeyCables) == .skip { return HardwareStepOutput(outcome: .skipped, summary: "Skipped by the tester: fewer than two cables.", passCriteria: criteria) }
        }

        // KI-054: a card whose current profile cannot key is switched only after the tester says yes. The runner puts it back.
        var profileEvents: [String] = []
        switch await ensureKeyingProfile(ctx, device, first: outC, criteria: criteria) {
        case .ready(let event): if let event { profileEvents.append(event) }
        case .stop(let out): return out
        }
        device = ctx.currentDevice() ?? device

        // The connectors for the rest of the step come from the layout the card has now.
        let plan: HardwareKeyedPlan
        switch HardwareTestLayout.keyed(device.info, first: outC, preferA: cfg.loopbackInputConnector, preferB: cfg.keyInputConnector) {
        case .failure(let why):
            return HardwareStepOutput(outcome: .skipped, summary: "Fill and key could not be tested on this card as it is configured: \(why.text) Nothing was reported as failed.",
                                      passCriteria: criteria, events: profileEvents)
        case .success(let p):
            plan = p
            var same = false
            if case .success(let before) = provisional { same = before.cables == p.cables }
            if !same, await prompt(p, kind: provisional.isSuccess ? .moveCables : .connectKeyCables) == .skip {
                return HardwareStepOutput(outcome: .skipped, summary: "Skipped by the tester: the cables for the card's keying profile were not connected.", passCriteria: criteria, events: profileEvents)
            }
        }
        let outC2 = plan.first, inA = plan.inputA, inB = plan.inputB
        let reported = device.info.keyRoute(firstConnector: outC2)
        let manual = HardwareTestManual.keyRoute(modelName: device.info.displayName, firstConnector: outC2)

        let w = mode.width, h = mode.height
        let window = TestPattern.alphaWindow(width: w, height: h)
        let ramp = TestPattern.alphaRamp(width: w, height: h)
        let phaseSeconds = max(1, cfg.durations.keyedSecondsPerMode / 2)
        let regions = TestPattern.alphaWindowRegions(width: w, height: h)
        let expectedKey = SDIFrame(width: w, height: h, bgra: FillKeySplitter.split(bgra: window.bgra, fillAlphaMode: .premultiplied).key)

        func no(_ text: String, _ ms: [HardwareMeasurement] = []) -> HardwareStepOutput {
            HardwareStepOutput(outcome: .failed, summary: text, passCriteria: criteria, measurements: ms, events: profileEvents)
        }
        func describeRoute(fill: Int, key: Int) -> String { "fill on SDI \(fill), key on SDI \(key)" }
        // What the app plans from: the device's report, or with none, fill on the first connector (the old convention).
        let expected = reported.map { (fill: $0.fillConnector, key: $0.keyConnector) } ?? (fill: outC2, key: outC2 + 1)

        // Phase 1: the window with premultiplied fill. It also tells us which input got the fill and which the key.
        // S7: what this measures is where the signals ARRIVED with the cables as instructed. If that is the reverse of the
        // route the card reports, the tester is asked to check the cables, and the phase runs once more; both runs are kept.
        func windowRun() async throws -> Result<(result: PhaseResult, roleA: String, roleB: String, measured: (fill: Int, key: Int)?), KeyedSetupError> {
            switch try await runKeyedPhase(ctx, device, plan: plan, alphaMode: .premultiplied, frame: window, seconds: phaseSeconds, title: "Fill and key: window") {
            case .failure(let e): return .failure(e)
            case .success(let r):
                let a = role(of: r.fillInput.lastFrame), b = role(of: r.keyInput.lastFrame)
                let measured: (fill: Int, key: Int)? = a == "fill" && b == "key" ? (outC2, outC2 + 1) : (a == "key" && b == "fill" ? (outC2 + 1, outC2) : nil)
                return .success((r, a, b, measured))
            }
        }
        var runs: [(roleA: String, roleB: String, measured: (fill: Int, key: Int)?)] = []
        var firstRun: PhaseResult
        switch try await windowRun() {
        case .failure(let e): return no(e.text)
        case .success(let r): firstRun = r.result; runs.append((r.roleA, r.roleB, r.measured))
        }
        func signals(_ r: PhaseResult) -> (fill: Bool, key: Bool) { (r.fillInput.lastFrame != nil, r.keyInput.lastFrame != nil) }
        func noSignalOutput(_ r: PhaseResult) -> HardwareStepOutput? {
            let locked = signals(r)
            guard !locked.fill || !locked.key else { return nil }
            let missing = [locked.fill ? nil : "SDI \(inA)", locked.key ? nil : "SDI \(inB)"].compactMap { $0 }.joined(separator: " and ")
            return no("No signal on \(missing). Join SDI \(outC2) to SDI \(inA) and SDI \(outC2 + 1) to SDI \(inB) with the cables, then run again.",
                      [m("Signal on SDI \(inA)", yesNo(locked.fill)), m("Signal on SDI \(inB)", yesNo(locked.key))])
        }
        if let out = noSignalOutput(firstRun) { return out }
        var repeatNote: String?
        if let m1 = runs[0].measured, m1.fill != expected.fill {
            let confirm = await ctx.ask(HardwarePrompt(
                kind: .confirmCables, title: "Please check the cables",
                message: "Fill and key arrived the other way round from what the card reports. That can be the card, or two cables swapped. Please check the cables are exactly: SDI \(plan.first) to SDI \(plan.inputA), and SDI \(plan.first + 1) to SDI \(plan.inputB). Then press Continue and this part runs once more. Press Skip to keep the first result.",
                primaryLabel: "Continue", canSkip: true, cables: plan.cables))
            if confirm == .proceed || confirm == .yes {
                switch try await windowRun() {
                case .failure(let e): return no(e.text)
                case .success(let r):
                    firstRun = r.result
                    runs.append((r.roleA, r.roleB, r.measured))
                }
                if let out = noSignalOutput(firstRun) { return out }
                let second = runs[1].measured
                repeatNote = second == nil ? "The second run could not tell fill from key."
                    : (second!.fill == m1.fill ? "The second run, after the tester confirmed the cables, gave the same answer as the first." 
                                               : "The second run, after the tester checked the cables, gave the opposite answer to the first, so the first run was most likely a cabling mistake.")
            } else {
                repeatNote = "The tester did not confirm the cables, so the step was not repeated: the first result stands, and it depends on the cables being as instructed."
            }
        }
        let first = firstRun
        let roleOnFirst = runs.last!.roleA, roleOnSecond = runs.last!.roleB
        let measured = runs.last!.measured
        var ms: [HardwareMeasurement] = []
        if runs.count > 1 {
            ms.append(m("First run: SDI \(outC2) carries", runs[0].roleA)); ms.append(m("First run: SDI \(outC2 + 1) carries", runs[0].roleB))
            ms.append(m("First run: route measured", runs[0].measured.map { describeRoute(fill: $0.fill, key: $0.key) } ?? "could not be determined"))
        }
        ms += [
            m("SDI \(outC2) carries", roleOnFirst), m("SDI \(outC2 + 1) carries", roleOnSecond),
            m("Route reported by the device", reported.map { describeRoute(fill: $0.fillConnector, key: $0.keyConnector) } ?? "none reported"),
            m("Source of the reported route", reported.map { routeSource($0.source) } ?? "not applicable"),
            m("Route in the manual's table", manual.map { describeRoute(fill: $0.fill, key: $0.key) } ?? "no table for this model (the manual's table covers the DeckLink Duo 2 only)"),
            m("Route measured" + (runs.count > 1 ? " (second run)" : ""), measured.map { describeRoute(fill: $0.fill, key: $0.key) } ?? "could not be determined"),
            m("Cables as instructed", plan.cables.map(\.text).joined(separator: ", ")),
            m("Signal on SDI \(inA)", "yes"), m("Signal on SDI \(inB)", "yes"),
            m("Detected mode", first.fillInput.detectedMode?.name ?? "unknown"),
        ]
        var problems: [String] = []
        var findings: [String] = []
        let cableText = plan.cables.map(\.text).joined(separator: ", ")
        if let measured {
            // An observation that depends on the cabling, worded as one (S7).
            let fillInput = measured.fill == outC2 ? inA : inB, keyInput = measured.fill == outC2 ? inB : inA
            let fillOut = measured.fill == outC2 ? outC2 : outC2 + 1, keyOut = measured.fill == outC2 ? outC2 + 1 : outC2
            var observation = "UNV-03: with the cables as instructed (\(cableText)), the fill arrived on SDI \(fillInput) and the key on SDI \(keyInput); "
            observation += "that is, SDI \(fillOut) carries the fill and SDI \(keyOut) carries the key if the cables are as shown. Two cables swapped would look the same."
            findings.append(observation)
            func agreement(_ what: String, _ other: (fill: Int, key: Int)) -> String {
                other.fill == measured.fill ? "agrees with \(what) (\(describeRoute(fill: other.fill, key: other.key)))"
                                            : "disagrees with \(what) (\(describeRoute(fill: other.fill, key: other.key)))"
            }
            var sentence = "Observed \(describeRoute(fill: measured.fill, key: measured.key)), with the cables as instructed: that "
            if let reported { sentence += agreement("the device's report", (reported.fillConnector, reported.keyConnector)) }
            else { sentence += "has no device report to compare with, because the device reports no route, so it is compared with the app's convention: " + agreement("it", (outC2, outC2 + 1)) }
            sentence += "; "
            if let manual { sentence += agreement("the manual's table", manual) } else { sentence += "the manual has no table for this model" }
            sentence += ". If the cables are as shown, the app's old assumption (fill on the first connector) " + (measured.fill == outC2 ? "holds for this device." : "is wrong for this device, and the planner follows the route the device reports.")
            findings.append(sentence)
            if let repeatNote { findings.append("UNV-03: \(repeatNote) Both runs are in the measurements.") }
            if measured.fill != expected.fill {
                problems.append("fill and key are reversed compared with \(reported == nil ? "the app's convention" : "what the device reports") (with the cables as instructed, SDI \(measured.fill == outC2 ? outC2 : outC2 + 1) carried the fill, but the expected fill connector is SDI \(expected.fill))")
            }
        } else {
            findings.append("UNV-03: could not be determined: SDI \(outC2) read as \(roleOnFirst) and SDI \(outC2 + 1) as \(roleOnSecond).")
            problems.append("could not tell which connector carries the fill and which the key")
        }
        if first.fillInput.detectedMode != mode { problems.append("the inputs detected \(first.fillInput.detectedMode?.name ?? "no mode") instead of \(mode.name)") }

        func tolerant(_ v: Int, _ target: Int, _ tol: Int) -> Bool { abs(v - target) <= tol }

        // Looks at one phase's two inputs: finds the key and fill frames by what they show, whatever the cabling.
        func inspect(_ r: PhaseResult, alphaMode: AlphaMode, label: String) {
            let frames = [r.fillInput.lastFrame, r.keyInput.lastFrame].compactMap { $0 }
            guard let keyFrame = frames.first(where: { role(of: $0) == "key" }), let fillFrame = frames.first(where: { role(of: $0) == "fill" }) else {
                ms.append(m("Key matches the alpha (\(label))", "no"))
                ms.append(m(alphaMode == .premultiplied ? "Fill is premultiplied when configured so" : "Fill is straight when configured so", "no"))
                problems.append("with \(label) alpha, one of the two inputs did not show a clear fill or key")
                return
            }
            let cmp = TestPattern.compare(keyFrame, expectedKey, tolerance: 16)
            let kOpaque = CaptureMath.block(keyFrame, x: regions.opaque.centerX, y: regions.opaque.centerY).r
            let kHalf = CaptureMath.block(keyFrame, x: regions.half.centerX, y: regions.half.centerY).r
            let kOut = CaptureMath.block(keyFrame, x: w * 3 / 100, y: h * 3 / 100).r
            let keyOK = cmp.sizesMatch && tolerant(kOpaque, 255, 16) && tolerant(kHalf, 128, 16) && kOut <= 16
                && cmp.meanChannelError <= 4 && cmp.pixelsOverTolerance <= (w * h) / 200
            ms.append(m("Key matches the alpha (\(label))", yesNo(keyOK)))
            ms.append(m("Key at opaque box / 50% box / surround (\(label))", "\(kOpaque) / \(kHalf) / \(kOut)", "of 255"))
            ms.append(m("Key mean error (\(label))", String(format: "%.2f", cmp.meanChannelError)))
            if !keyOK { problems.append("the key does not match the alpha with \(label) alpha") }
            let half = CaptureMath.block(fillFrame, x: regions.half.centerX, y: regions.half.centerY)
            let opaque = CaptureMath.block(fillFrame, x: regions.opaque.centerX, y: regions.opaque.centerY)
            let surround = CaptureMath.block(fillFrame, x: w * 3 / 100, y: h * 3 / 100)
            let target = alphaMode == .premultiplied ? 128 : 255
            let fillOK = tolerant(half.r, target, 24) && tolerant(half.g, target, 24) && tolerant(half.b, target, 24)
                && tolerant(opaque.r, 255, 24) && tolerant(opaque.g, 128, 24) && opaque.b <= 24 && max(surround.r, surround.g, surround.b) <= 24
            ms.append(m(alphaMode == .premultiplied ? "Fill is premultiplied when configured so" : "Fill is straight when configured so", yesNo(fillOK)))
            ms.append(m("Fill at the 50% box (\(label))", "\(half.r)", "of 255; about 128 means premultiplied, about 255 means straight"))
            if !fillOK { problems.append("the fill is not \(label) when configured \(label)") }
        }
        inspect(first, alphaMode: .premultiplied, label: "premultiplied")

        // Phase 2: the alpha ramp, read off whichever input showed the key.
        switch try await runKeyedPhase(ctx, device, plan: plan, alphaMode: .premultiplied, frame: ramp, seconds: phaseSeconds, title: "Fill and key: ramp") {
        case .failure(let e): problems.append(e.text); ms.append(m("Alpha ramp follows the key", "no"))
        case .success(let r):
            let candidates = [r.fillInput.lastFrame, r.keyInput.lastFrame].compactMap { $0 }
            // The ramp is white at alpha a, so the key input reads a at every column and the fill input reads a too
            // (premultiplied white): pick the input that was the key in the window phase.
            let keyFrame = roleOnFirst == "key" ? r.fillInput.lastFrame : (roleOnSecond == "key" ? r.keyInput.lastFrame : candidates.first)
            var worst = 0
            if let keyFrame {
                for percent in [10, 25, 50, 75, 90] {
                    let x = w * percent / 100
                    worst = max(worst, abs(CaptureMath.block(keyFrame, x: x, y: h / 2).r - TestPattern.alphaRampValue(x: x, width: w)))
                }
            } else { worst = 255 }
            let rampOK = worst <= 24
            ms.append(m("Alpha ramp follows the key", yesNo(rampOK)))
            ms.append(m("Alpha ramp largest error", "\(worst)", "of 255"))
            if !rampOK { problems.append("the key does not follow the alpha ramp (largest error \(worst))") }
        }

        // Phase 3: straight alpha.
        switch try await runKeyedPhase(ctx, device, plan: plan, alphaMode: .straight, frame: window, seconds: phaseSeconds, title: "Fill and key: straight alpha") {
        case .failure(let e): problems.append(e.text)
        case .success(let r): inspect(r, alphaMode: .straight, label: "straight")
        }

        let ok = problems.isEmpty
        let repeatSuffix: String = repeatNote.map { " " + $0 } ?? ""
        let fillArrived: Int = measured?.fill == outC2 ? inA : inB
        let keyArrived: Int = measured?.fill == outC2 ? inB : inA
        var summary: String
        if ok {
            summary = "With the cables as instructed, fill arrived on SDI \(fillArrived) and key on SDI \(keyArrived), as the device reports. "
            summary += "The key matched the alpha and the fill behaved as configured in both alpha modes." + repeatSuffix
        } else {
            summary = "Problems with fill and key: " + problems.joined(separator: "; ") + "." + repeatSuffix
        }
        return HardwareStepOutput(outcome: ok ? .passed : .failed, summary: summary, passCriteria: criteria, measurements: ms, findings: findings,
                                  events: profileEvents)
    }

    // MARK: 8. unplug and replug

    static func unplugReplug(_ ctx: HardwareTestContext) async throws -> HardwareStepOutput {
        guard let device = ctx.currentDevice() else { return HardwareStepOutput(outcome: .skipped, summary: "No device was found, so this step could not run.") }
        let criteria = "After the device is unplugged during an output run: the engine reports the failure within 10 seconds, and the app answers within 1 second (so it stayed responsive). After replugging: the device is found again within 10 seconds and an output starts and runs for 2 seconds. PASSED needs both halves measured; if the replug was skipped, or the app's response time could not be measured, the step says what was measured and what was not."
        guard let connector = HardwareTestLayout.plainOutput(device.info, prefer: ctx.configuration.outputConnector) else {
            return HardwareStepOutput(outcome: .skipped, summary: "No connector can send plain output in the card's profile as it is now, so the unplug test could not start an output.", passCriteria: criteria)
        }
        let source = CounterFrameSource(width: mode.width, height: mode.height)
        let out: RunningOutput
        do { out = try startOutput(device, connector: connector) { source.frame(index: $0) } } catch {
            return HardwareStepOutput(outcome: .failed, summary: "The output could not be started before the unplug: \(describe(error))", passCriteria: criteria)
        }
        defer { out.stop() }
        try await ctx.clock.wait(seconds: 2)
        let before = await ctx.responsiveness.measure()
        let answer = await ctx.ask(HardwarePrompt(
            kind: .unplugDevice, title: "Unplug the card",
            message: "The output is running. Unplug the Thunderbolt cable (or power) from the card now, wait a few seconds, then press Done. If you would rather not, press Skip.",
            primaryLabel: "Done", canSkip: true))
        if answer == .skip || answer == .unavailable {
            return HardwareStepOutput(outcome: .skipped, summary: answer == .skip ? "Skipped by the tester." : "A person is needed to unplug the card; nobody was available.", passCriteria: criteria)
        }
        var reported: SDIStopReason?
        var waited = 0.0
        while waited < 10 {
            if case .stopped = out.session.state { break }
            try await ctx.clock.wait(seconds: 0.25)
            waited += 0.25
        }
        if case .stopped(let reason) = out.session.state { reported = reason }
        let during = await ctx.responsiveness.measure()
        var ms: [HardwareMeasurement] = []
        if let before { ms.append(m("App response time before", String(format: "%.0f", before), "ms")) }
        if let during { ms.append(m("App response time after unplug", String(format: "%.0f", during), "ms")) }
        let responsive: Bool? = during.map { $0 < 1000 }
        ms.append(m("App responsive during unplug", responsive.map(yesNo) ?? "not measured"))
        var problems: [String] = []
        switch reported {
        case .failed(let error):
            ms.append(m("Engine reported", describe(error)))
            ms.append(m("Seconds until reported", hz(waited), "s"))
        case .requested:
            ms.append(m("Engine reported", "stopped without an error"))
            problems.append("the engine stopped without reporting a failure")
        case nil:
            ms.append(m("Engine reported", "nothing"))
            problems.append("the engine did not report any failure within 10 seconds of the unplug")
        }
        if responsive == false { problems.append("the app took too long to answer while the card was missing") }
        guard problems.isEmpty else {
            return HardwareStepOutput(outcome: .failed, summary: "Unplug: " + problems.joined(separator: "; ") + ".", passCriteria: criteria, measurements: ms)
        }
        out.stop()
        // What was measured so far, and what was not, said in the order the step does them (S3).
        var notMeasured: [String] = []
        if responsive == nil { notMeasured.append("whether the app stayed responsive (the app could not measure its own response time)") }

        let replug = await ctx.ask(HardwarePrompt(
            kind: .replugDevice, title: "Plug the card back in",
            message: "Plug the card back in and wait until it has started up (a few seconds), then press Done. Press Skip if you cannot.",
            primaryLabel: "Done", canSkip: true))
        guard replug == .proceed else {
            ms.append(m("Device back after replug", "NOT MEASURED: the replug was skipped"))
            ms.append(m("Output restarted after replug", "NOT MEASURED: the replug was skipped"))
            notMeasured.append("the replug (the tester skipped it)")
            return HardwareStepOutput(
                outcome: .partial,
                summary: "The unplug was measured: the engine reported it and the app " + (responsive == true ? "stayed responsive" : "was not measured for responsiveness") + ". Not measured: " + notMeasured.joined(separator: "; ") + ". This step is not PASSED because the replug was not tested.",
                passCriteria: criteria, measurements: ms)
        }
        var back = false
        waited = 0
        while waited < 10 {
            if ctx.provider.devices().contains(where: { $0.id == device.id && $0.isConnected() }) { back = true; break }
            try await ctx.clock.wait(seconds: 0.25)
            waited += 0.25
        }
        ms.append(m("Device back after replug", yesNo(back)))
        var restarted = false
        if back, let fresh = ctx.provider.devices().first(where: { $0.id == device.id }) {
            if let again = try? startOutput(fresh, connector: connector, frames: { source.frame(index: $0) }) {
                defer { again.stop() }
                try await ctx.clock.wait(seconds: 2)
                restarted = again.session.statistics.scheduler.completed > 0 && again.session.stopReason == nil
            }
        }
        ms.append(m("Output restarted after replug", yesNo(restarted)))
        if !(back && restarted) {
            return HardwareStepOutput(
                outcome: .failed,
                summary: back ? "The device came back after the replug, but an output could not be run on it." : "The device was not found again within 10 seconds of the replug.",
                passCriteria: criteria, measurements: ms)
        }
        if !notMeasured.isEmpty {
            return HardwareStepOutput(
                outcome: .partial,
                summary: "The engine reported the unplug and the output ran again after the replug. Not measured: " + notMeasured.joined(separator: "; ") + ".",
                passCriteria: criteria, measurements: ms)
        }
        return HardwareStepOutput(outcome: .passed, summary: "The engine reported the unplug, the app stayed responsive, and the output ran again after the replug.",
                                  passCriteria: criteria, measurements: ms)
    }

    // MARK: 9. human checks

    static func humanChecks(_ ctx: HardwareTestContext) async throws -> HardwareStepOutput {
        guard var device = ctx.currentDevice() else { return HardwareStepOutput(outcome: .skipped, summary: "No device was found, so this step could not run.") }
        let criteria = "A person looks at a monitor or switcher and answers. Every question answered yes passes; any no fails. PASSED needs every question the step has to ask to have been asked and answered yes: a question that was skipped, could not be asked, or could not be shown makes the step only partly measured."
        var ms: [HardwareMeasurement] = []
        var events: [String] = []
        var answers: [(name: String, answer: HardwareAnswer)] = []
        var notAsked: [String] = []
        var photos = 0

        func offerPhoto(_ what: String) async {
            let a = await ctx.ask(HardwarePrompt(kind: .photo, title: "Attach a photo?", message: "If you can, take a photo of the screen showing the \(what) and attach it. Press Skip to go on without one.",
                                                 primaryLabel: "Attach a photo…", canSkip: true))
            if case .attachment(let path) = a {
                if let name = ctx.attach(URL(fileURLWithPath: path)) {
                    photos += 1
                    ms.append(m("Photo \(photos)", name))
                } else { ms.append(m("Photo", "could not be attached")) }
            }
        }

        // Colour bars, on a connector that can send them in the layout the card has now.
        let source = CounterFrameSource(width: mode.width, height: mode.height)
        guard let connector = HardwareTestLayout.plainOutput(device.info, prefer: ctx.configuration.outputConnector) else {
            return HardwareStepOutput(outcome: .skipped, summary: "No connector can send plain output in the card's profile as it is now, so the colour bars could not be sent.", passCriteria: criteria)
        }
        do {
            let out = try startOutput(device, connector: connector) { source.frame(index: $0) }
            defer { out.stop() }
            let a = await ctx.ask(HardwarePrompt(kind: .humanBars, title: "Look at the monitor",
                                                 message: "The card is sending colour bars on SDI \(connector). Do you see colour bars filling the screen?",
                                                 primaryLabel: "Yes", secondaryLabel: "No", canSkip: true))
            answers.append(("Colour bars fill the screen", a))
            if a == .yes || a == .no { await offerPhoto("colour bars") }
        } catch {
            return HardwareStepOutput(outcome: .failed, summary: "The colour bars could not be sent on SDI \(connector): \(describe(error))", passCriteria: criteria)
        }

        // The keyed window over a camera picture.
        let keyName = "White box edges are clean over camera"
        if device.info.supportsExternalKeying, device.info.connectorCount >= 2 {
            let pair = HardwareTestLayout.keyablePairs(device.info, prefer: ctx.configuration.outputConnector).first
            var ready = pair != nil
            if let pair {
                switch await ensureKeyingProfile(ctx, device, first: pair, criteria: criteria) {
                case .ready(let event): if let event { events.append(event) }
                case .stop: ready = false
                }
                device = ctx.currentDevice() ?? device
            }
            let window = TestPattern.alphaWindow(width: mode.width, height: mode.height)
            if ready, let pair, let out = try? startOutput(device, connector: pair, keying: .external(fillAlphaMode: .premultiplied), frames: { _ in window }) {
                defer { out.stop() }
                let route = HardwareTestLayout.route(device.info, first: pair)
                let a = await ctx.ask(HardwarePrompt(kind: .humanKeyEdges, title: "Look at the switcher",
                                                     message: "The card is sending a keyed picture: fill on SDI \(route.fill) and key on SDI \(route.key): a white box and an orange box on a transparent background. With the switcher keying it over a camera picture, are the edges of the white box clean?",
                                                     primaryLabel: "Yes", secondaryLabel: "No", canSkip: true))
                answers.append((keyName, a))
                if a == .yes || a == .no { await offerPhoto("keyed box over the camera picture") }
            } else {
                let why = "fill and key could not be started in the profile the card is in now (the profile was not changed)"
                ms.append(m(keyName, "NOT ASKED: \(why)"))
                notAsked.append(keyName)
            }
        } else {
            ms.append(m(keyName, "not asked: the device does not report fill and key"))
        }

        for (name, a) in answers {
            switch a {
            case .yes: ms.insert(m(name, "yes"), at: 0)
            case .no: ms.insert(m(name, "no"), at: 0)
            case .unavailable: ms.insert(m(name, "could not be asked"), at: 0)
            default: ms.insert(m(name, "skipped"), at: 0)
            }
        }
        let yes = answers.filter { $0.answer == .yes }.count
        let outcome: HardwareTestOutcome
        if answers.contains(where: { $0.answer == .no }) { outcome = .failed }
        else if !answers.isEmpty, yes == answers.count, notAsked.isEmpty { outcome = .passed }
        else if yes > 0 { outcome = .partial }
        else if answers.contains(where: { $0.answer == .unavailable }) { outcome = .needsHuman }
        else if !notAsked.isEmpty { outcome = .partial }
        else { outcome = .skipped }
        let summary: String
        switch outcome {
        case .passed: summary = "The tester saw what was expected."
        case .failed: summary = "The tester reported a problem: " + answers.filter { $0.answer == .no }.map(\.name).joined(separator: "; ") + "."
        case .needsHuman: summary = "These checks need a person looking at a monitor; nobody was available to answer."
        case .skipped: summary = "The tester skipped the checks."
        case .partial:
            let said = answers.filter { $0.answer == .yes }.map(\.name).joined(separator: "; ")
            let missing = (answers.filter { $0.answer != .yes }.map(\.name) + notAsked).joined(separator: "; ")
            summary = "Only part of this was checked. Answered yes: \(said.isEmpty ? "nothing" : said). Not checked: \(missing)."
        }
        return HardwareStepOutput(outcome: outcome, summary: summary, passCriteria: criteria, measurements: ms, events: events)
    }
}
