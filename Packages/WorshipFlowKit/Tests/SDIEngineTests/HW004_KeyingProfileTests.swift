// HW-004 / KI-054: a keyed output on a card whose current profile cannot key. The decision, the question to the operator
// and the outcome are tested with a fake device: nothing is ever switched without a yes.
import Testing
import Foundation
import SDIEngine

private final class Switches: @unchecked Sendable {
    private let lock = NSLock()
    private var pairs: [Int] = []
    var failWith: String?
    func record(_ pair: Int) throws {
        lock.lock(); pairs.append(pair); let fail = failWith; lock.unlock()
        if let fail { throw SDIError.hardwareFault(detail: fail) }
    }
    var calls: [Int] { lock.lock(); defer { lock.unlock() }; return pairs }
}

private let keyingChange = SDIProfileChange(firstConnector: 1, fromName: "two sub-devices, half duplex", toName: "one sub-device, full duplex",
                                            interruptedConnectors: [1, 2, 3, 4])

private func info(keyingNow: Bool, change: SDIProfileChange?, supportsKeying: Bool = true) -> SDIDeviceInfo {
    var i = SDIDeviceInfo(displayName: "Fake Duo", connectorCount: 4, supportsExternalKeying: supportsKeying, isSimulated: true)
    i.profiles = [SDIProfileState(firstConnector: 1, activeName: keyingNow ? "one sub-device, full duplex" : "two sub-devices, half duplex",
                                  keyingAvailableNow: keyingNow, keyingChange: change)]
    return i
}

private func device(_ info: SDIDeviceInfo, _ switches: Switches, canActivate: Bool = true) -> SDIProvidedDevice {
    let activate: (@Sendable (Int) async throws -> Void)? = canActivate ? { @Sendable pair in try switches.record(pair) } : nil
    return SDIProvidedDevice(id: "fake", info: info, isConnected: { true },
                             openOutput: { throw SDIError.connectorUnavailable($0) }, openInput: { throw SDIError.connectorUnavailable($0) },
                             activateKeyingProfile: activate)
}

@Suite struct HW004_KeyingProfileDecisionTests {
    @Test func aCardThatCanKeyNowNeedsNothing() {
        #expect(SDIKeyingProfile.decision(for: info(keyingNow: true, change: nil), firstConnector: 1) == .notNeeded)
    }

    @Test func aCardWithNoProfileDataNeedsNothing() {
        let plain = SDIDeviceInfo.simulatedDuo2
        #expect(SDIKeyingProfile.decision(for: plain, firstConnector: 1) == .notNeeded)
    }

    @Test func aCardThatNeedsAProfileChangeAsksFirst() {
        let d = SDIKeyingProfile.decision(for: info(keyingNow: false, change: keyingChange), firstConnector: 1)
        #expect(d == .askOperator(keyingChange))
    }

    @Test func aCardThatCannotKeyInAnyProfileSaysSo() {
        guard case .unavailable(let why) = SDIKeyingProfile.decision(for: info(keyingNow: false, change: nil), firstConnector: 1) else {
            Issue.record("expected unavailable"); return
        }
        #expect(!why.isEmpty)
    }

    @Test func aCardWithoutKeyingAtAllSaysSo() {
        guard case .unavailable = SDIKeyingProfile.decision(for: info(keyingNow: false, change: nil, supportsKeying: false), firstConnector: 1) else {
            Issue.record("expected unavailable"); return
        }
    }

    @Test func theQuestionNamesTheProfilesAndWarnsAboutOtherConnectors() {
        let q = keyingChange.question
        #expect(q.contains("one sub-device, full duplex") && q.contains("two sub-devices, half duplex"))
        #expect(q.localizedCaseInsensitiveContains("interrupt"))
    }
}

@Suite struct HW004_KeyingProfileOutcomeTests {
    @Test func nothingIsSwitchedWithoutAYes() async {
        let s = Switches()
        let outcome = await SDIKeyingProfile.ensure(device: device(info(keyingNow: false, change: keyingChange), s), firstConnector: 1) { _ in false }
        #expect(outcome == .declined(keyingChange))
        #expect(s.calls.isEmpty)
    }

    @Test func aYesSwitchesThePairAndReportsSuccess() async {
        let s = Switches()
        let outcome = await SDIKeyingProfile.ensure(device: device(info(keyingNow: false, change: keyingChange), s), firstConnector: 1) { _ in true }
        #expect(outcome == .switched(keyingChange))
        #expect(s.calls == [1])
        #expect(outcome.message.contains("one sub-device, full duplex"))
    }

    @Test func aFailureCarriesTheReason() async {
        let s = Switches()
        s.failWith = "the card did not confirm the profile in time"
        let outcome = await SDIKeyingProfile.ensure(device: device(info(keyingNow: false, change: keyingChange), s), firstConnector: 1) { _ in true }
        guard case .failed(let change, let reason) = outcome else { Issue.record("expected failed, got \(outcome)"); return }
        #expect(change == keyingChange)
        #expect(reason.contains("did not confirm the profile"))
        #expect(outcome.message.contains("did not confirm the profile"))
    }

    @Test func noQuestionIsAskedWhenNothingIsNeeded() async {
        let s = Switches()
        let asked = Switches()
        let outcome = await SDIKeyingProfile.ensure(device: device(info(keyingNow: true, change: nil), s), firstConnector: 1) { _ in try? asked.record(0); return true }
        #expect(outcome == .notNeeded)
        #expect(asked.calls.isEmpty && s.calls.isEmpty)
    }

    @Test func aDeviceThatCannotSwitchReportsFailureWithoutAsking() async {
        let s = Switches()
        let asked = Switches()
        let outcome = await SDIKeyingProfile.ensure(device: device(info(keyingNow: false, change: keyingChange), s, canActivate: false), firstConnector: 1) { _ in try? asked.record(0); return true }
        guard case .failed = outcome else { Issue.record("expected failed, got \(outcome)"); return }
        #expect(asked.calls.isEmpty)
    }
}
