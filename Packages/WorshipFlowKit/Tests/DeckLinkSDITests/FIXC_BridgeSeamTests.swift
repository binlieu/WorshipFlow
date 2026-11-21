// FIX-C / S10, S11, S12, S13 (HW-003): the bridge's own logic against stand-ins for the SDK's objects
// (DeckLinkBridgeTesting.h). What this proves: the bridge calls the SDK in the order and with the arguments it intends and
// handles every HRESULT it is given. What it does not prove: how the real SDK or a real card behaves. Verification level:
// Unit Tested through a seam, never Hardware Verified.
import Testing
import Foundation
import DeckLinkC

/// Collects what the bridge reports, and lets a test wait for it with a watchdog.
private final class Reports: @unchecked Sendable {
    private let lock = NSLock()
    private let signal = DispatchSemaphore(value: 0)
    private var failures: [NSError] = []
    private var formats: [UInt32] = []
    var failureList: [NSError] { lock.withLock { failures } }
    var formatList: [UInt32] { lock.withLock { formats } }
    func failure(_ e: NSError) { lock.withLock { failures.append(e) }; signal.signal() }
    func format(_ m: UInt32) { lock.withLock { formats.append(m) }; signal.signal() }
    /// Waits for one report (a failure or a format), false after the watchdog.
    func wait(_ seconds: Double = 3) -> Bool { signal.wait(timeout: .now() + seconds) == .success }
}

private let hp59: UInt32 = 0x48703539        // an arbitrary display mode code; the stand-in accepts any
private let e_fail: Int32 = Int32(bitPattern: 0x80004005)

private func startedInput(bgra: Bool = true, yuv: Bool = true, converter: Bool = true) throws -> (DLBInput, DLBFakeInput, Reports) {
    DLBTesting.setConverterAvailable(converter)
    let fake = DLBFakeInput()
    fake.bgraSupported = bgra
    fake.yuvSupported = yuv
    let input = DLBTesting.input(withFake: fake)
    let reports = Reports()
    input.failureHandler = { reports.failure($0 as NSError) }
    input.formatHandler = { (mode: UInt32, _: Int32, _: Int32, _: Int64, _: Int64, _: Bool) in reports.format(mode) }
    try input.start(withInitialDisplayMode: hp59, detectFormat: true)
    fake.clearCalls()
    return (input, fake, reports)
}

@Suite(.serialized) struct FIXC_BridgeSeamTests {

    // MARK: S10 - every step of the format-change restart is checked

    @Test func aSuccessfulRestartRunsPauseEnableFlushStartAndReportsTheMode() throws {
        let (input, fake, reports) = try startedInput()
        fake.sendFormatChange(hp59, width: 1920, height: 1080, rgb444: false)
        #expect(reports.wait())
        #expect(fake.calls == ["PauseStreams", "EnableVideoInput(YUV)", "FlushStreams", "StartStreams"])
        #expect(reports.formatList == [hp59] && reports.failureList.isEmpty)
        #expect(input.isRunning)
        input.close()
    }

    @Test(arguments: [
        ("PauseStreams", "pause the input"), ("EnableVideoInput", "enable the new video mode"),
        ("FlushStreams", "flush the input"), ("StartStreams", "restart capture"),
    ])
    func aFailedStepIsReportedAndLeavesACleanStoppedInput(call: String, phrase: String) throws {
        let (input, fake, reports) = try startedInput()
        fake.failCall(call, withResult: e_fail)
        fake.sendFormatChange(hp59, width: 1920, height: 1080, rgb444: false)
        #expect(reports.wait())
        let failure = try #require(reports.failureList.first)
        #expect(failure.localizedDescription.contains(phrase), "\(failure.localizedDescription)")
        #expect(failure.localizedDescription.contains("0x80004005"))
        #expect(failure.userInfo[DLBErrorHRESULTKey] as? Int32 == e_fail)
        #expect(reports.formatList.isEmpty, "the new mode was reported although the restart failed")
        #expect(!input.isRunning)
        #expect(fake.calls.suffix(2) == ["StopStreams", "DisableVideoInput"] || fake.calls.contains("StopStreams"))
        #expect(fake.calls.contains("DisableVideoInput") && fake.calls.contains("SetCallback(null)"))
        #expect(!fake.callbackInstalled)
        input.close()
    }

    @Test func anRGBSignalIsCapturedAsBGRADirectlyWhenTheCardCan() throws {
        let (input, fake, reports) = try startedInput()
        fake.sendFormatChange(hp59, width: 1920, height: 1080, rgb444: true)
        #expect(reports.wait())
        #expect(fake.calls.contains("EnableVideoInput(BGRA)"))
        input.close()
    }

    @Test func anRGBSignalFallsBackToYCbCrAndConvertsWhenBGRAIsNotSupported() throws {
        let (input, fake, reports) = try startedInput(bgra: false)
        fake.sendFormatChange(hp59, width: 1920, height: 1080, rgb444: true)
        #expect(reports.wait())
        #expect(fake.calls.contains("EnableVideoInput(YUV)") && !fake.calls.contains("EnableVideoInput(BGRA)"))
        #expect(reports.failureList.isEmpty && reports.formatList == [hp59])
        input.close()
    }

    @Test func aFormatNoSupportedPixelFormatCanCaptureFailsWithAClearReason() throws {
        let (input, fake, reports) = try startedInput()
        fake.bgraSupported = false                         // after the start: the card cannot take the detected format at all
        fake.yuvSupported = false
        fake.sendFormatChange(hp59, width: 1920, height: 1080, rgb444: true)
        #expect(reports.wait())
        let failure = try #require(reports.failureList.first)
        #expect(failure.localizedDescription.contains("cannot capture it in a format the app can use"), "\(failure.localizedDescription)")
        #expect(reports.formatList.isEmpty && !input.isRunning)
        #expect(!fake.calls.contains("PauseStreams"), "the running capture was disturbed although nothing could be captured")
        input.close()
    }

    @Test func aYCbCrOnlyFormatWithoutAConverterFailsWithAClearReason() throws {
        let (input, fake, reports) = try startedInput(converter: false)
        fake.sendFormatChange(hp59, width: 1920, height: 1080, rgb444: false)
        #expect(reports.wait())
        let failure = try #require(reports.failureList.first)
        #expect(failure.localizedDescription.contains("converter"), "\(failure.localizedDescription)")
        #expect(reports.formatList.isEmpty)
        input.close()
    }

    // MARK: S12 - close() always removes the callback and breaks the cycle

    @Test func closeAfterARemovalStillRemovesTheCallbackAndBreaksTheCycle() throws {
        let baseline = DLBTesting.liveInputCallbackCount()
        let (input, fake, _) = try startedInput()
        #expect(DLBTesting.liveInputCallbackCount() == baseline + 1)
        DLBTesting.remove(input)                     // the card is gone: the input is no longer "running"
        #expect(!input.isRunning)
        input.close()
        #expect(!fake.callbackInstalled, "close() left the callback installed after a removal")
        #expect(DLBTesting.liveInputCallbackCount() == baseline, "the callback object leaked")
    }

    @Test func closeOfARunningInputRemovesTheCallbackAndReleasesIt() throws {
        let baseline = DLBTesting.liveInputCallbackCount()
        let (input, fake, _) = try startedInput()
        input.close()
        #expect(!fake.callbackInstalled)
        #expect(DLBTesting.liveInputCallbackCount() == baseline)
        input.close()                                     // repeating is harmless
        #expect(input.isClosed)
    }

    @Test func closeAfterAFailedRestartLeavesNothingBehind() throws {
        let baseline = DLBTesting.liveInputCallbackCount()
        let (input, fake, reports) = try startedInput()
        fake.failCall("FlushStreams", withResult: e_fail)
        fake.sendFormatChange(hp59, width: 1920, height: 1080, rgb444: false)
        #expect(reports.wait())
        input.close()
        #expect(!fake.callbackInstalled)
        #expect(DLBTesting.liveInputCallbackCount() == baseline)
    }

    // MARK: S11 - SetLevel is checked, and the device's minimum preroll is passed on

    @Test func aRefusedKeyerLevelFailsTheEnableAndLeavesNothingOn() throws {
        let fake = DLBFakeOutput()
        fake.setLevelResult = e_fail
        let output = DLBTesting.output(withFake: fake, minimumPrerollFrames: 3)
        var thrown: NSError?
        do {
            try output.enableDisplayMode(hp59, width: 1920, height: 1080, frameDuration: 1001, timeScale: 60000, keying: true, keyerLevel: 255)
        } catch { thrown = error as NSError }
        let error = try #require(thrown, "enable succeeded although SetLevel failed")
        #expect(error.localizedDescription.contains("keyer level") && error.localizedDescription.contains("0x80004005"))
        #expect(!output.isEnabled)
        #expect(fake.calls.contains("Keyer.SetLevel(255)") && fake.calls.contains("Keyer.Disable") && fake.calls.contains("DisableVideoOutput"))
    }

    @Test func aKeyedEnableThatSucceedsSetsTheLevel() throws {
        let fake = DLBFakeOutput()
        let output = DLBTesting.output(withFake: fake, minimumPrerollFrames: 3)
        try output.enableDisplayMode(hp59, width: 1920, height: 1080, frameDuration: 1001, timeScale: 60000, keying: true, keyerLevel: 200)
        #expect(output.isEnabled)
        #expect(fake.calls.contains("Keyer.SetLevel(200)"))
        output.close()
    }

    @Test func theDevicesMinimumPrerollIsAvailableFromTheOutput() {
        #expect(DLBTesting.output(withFake: DLBFakeOutput(), minimumPrerollFrames: 5).minimumPrerollFrames == 5)
        #expect(DLBTesting.output(withFake: DLBFakeOutput(), minimumPrerollFrames: -1).minimumPrerollFrames == -1)
    }

    // MARK: S13 - nothing is enumerated inside the profile callback

    @Test func theProfileCallbackRecordsTheEventAndRefreshesOnAQueue() throws {
        let fake = DLBFakeDevice()
        let device = DLBTesting.device(withFake: fake)
        #expect(fake.callbackInstalled)
        let before = fake.getProfilesCalls
        let handled = DispatchSemaphore(value: 0)
        let seenAfterRefresh = Box()
        device.profileChangeHandler = { seenAfterRefresh.set(fake.getProfilesCalls); handled.signal() }
        fake.sendProfileActivated()
        #expect(fake.getProfilesCallsInsideCallback == 0, "profiles were enumerated inside the SDK's profile callback")
        #expect(handled.wait(timeout: .now() + 3) == .success)
        #expect(seenAfterRefresh.value > before, "the device information was never refreshed")
        #expect(fake.getProfilesCallsInsideCallback == 0)
    }
}

private final class Box: @unchecked Sendable {
    private let lock = NSLock(); private var v = 0
    func set(_ n: Int) { lock.withLock { v = n } }
    var value: Int { lock.withLock { v } }
}
