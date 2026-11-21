// HWTEST-001 / FIX-D: a simulated card with PROFILES, so the kit can be shown what it does when the card's layout changes
// under it (S1), when two connectors are wired the other way round inside the card (S4) and when cables are crossed (S7).
// It lives here, behind the kit's own `HardwareTestDevice` and `HardwareTestProvider`, and not in SDIEngine: it models
// nothing about any real card beyond what the vendor manual's table says. SIMULATED: it proves the kit's logic, never a card.
import Foundation
import SDIEngine

/// What a simulated profile call can go wrong with.
struct SimulatedProfileError: Error, LocalizedError {
    var text: String
    var errorDescription: String? { text }
}

/// A four-connector card, modelled on the manual's table for a DeckLink Duo 2: in its half-duplex profile every connector
/// can send or receive; in the full-duplex keying profile the lower connector of the pair is an input (or the key) and
/// the upper one an output (or the fill). Fill goes out on the second connector of the pair and the key on the first.
/// `@unchecked Sendable`: `profiles` and `faults` are only touched while holding `lock`.
public final class SimulatedProfileCard: @unchecked Sendable {
    public enum Profile: UInt32, Sendable {
        case halfDuplex = 1
        case keying = 2
        public var name: String { self == .halfDuplex ? "half duplex" : "one sub-device, full duplex" }
    }

    /// Whether changing one pair's profile also changes the other (the SDK applies a profile to a sub-device, and which
    /// sub-devices share a profile is the card's business).
    public enum Scope: Sendable { case onePair, bothPairs }

    public struct Faults: Equatable, Sendable {
        /// The restore call throws.
        public var restoreFails = false
        /// The restore call returns normally and the card does not change.
        public var restoreHasNoEffect = false
        /// The switch to the keying profile throws.
        public var switchFails = false
        /// Two logical outputs whose pictures really leave by each other's connector, like a wrong sub-device-to-connector
        /// table: `[2, 4]` swaps outputs 2 and 4. It shows in the cables: a cable from connector 2 carries output 4's picture.
        public var swappedOutputs: [Int] = []
        public init(restoreFails: Bool = false, restoreHasNoEffect: Bool = false, switchFails: Bool = false, swappedOutputs: [Int] = []) {
            self.restoreFails = restoreFails
            self.restoreHasNoEffect = restoreHasNoEffect
            self.switchFails = switchFails
            self.swappedOutputs = swappedOutputs
        }
        public static let none = Faults()
    }

    public static let deviceID = "simulated-sdi-duo2-profiles"
    public static let modelName = "Simulated SDI Duo 2 card (4 connectors, profiles)"

    public let device: SimulatedSDIDevice
    public let scope: Scope
    private let lock = NSLock()
    private var profiles: [Profile]
    private var faults: Faults

    public init(scope: Scope = .onePair, start: [Profile] = [.halfDuplex, .halfDuplex], faults: Faults = .none) {
        var base = SDIDeviceInfo.simulatedDuo2WithReversedKeyRoute
        base.displayName = Self.modelName
        self.device = SimulatedSDIDevice(info: base)
        self.scope = scope
        self.profiles = start.count == 2 ? start : [.halfDuplex, .halfDuplex]
        self.faults = faults
    }

    public func setFaults(_ f: Faults) { lock.withLock { faults = f } }
    public func profile(ofPair pair: Int) -> Profile { lock.withLock { profiles[pair] } }
    var currentProfiles: [Profile] { lock.withLock { profiles } }

    // MARK: what the card says about itself now

    public var info: SDIDeviceInfo {
        let now = currentProfiles
        var connectors: [SDIConnectorInfo] = []
        var states: [SDIProfileState] = []
        var routes: [SDIKeyRoute] = []
        for pair in 0..<2 {
            let first = 2 * pair + 1
            let p = now[pair]
            routes.append(SDIKeyRoute(firstConnector: first, fillConnector: first + 1, keyConnector: first, source: .simulator))
            switch p {
            case .halfDuplex:
                connectors.append(SDIConnectorInfo(connector: first, canOutput: true, canInput: true))
                connectors.append(SDIConnectorInfo(connector: first + 1, canOutput: true, canInput: true))
                states.append(SDIProfileState(firstConnector: first, activeName: p.name, keyingAvailableNow: false,
                                              keyingChange: SDIProfileChange(firstConnector: first, fromName: p.name, toName: Profile.keying.name, interruptedConnectors: [1, 2, 3, 4])))
            case .keying:
                connectors.append(SDIConnectorInfo(connector: first, canOutput: false, canInput: true, keyRole: .key))
                connectors.append(SDIConnectorInfo(connector: first + 1, canOutput: true, canInput: false, keyRole: .fill))
                states.append(SDIProfileState(firstConnector: first, activeName: p.name, keyingAvailableNow: true, keyingChange: nil))
            }
        }
        return SDIDeviceInfo(displayName: Self.modelName, connectorCount: 4, supportsExternalKeying: true, isSimulated: true,
                             keyRoutes: routes, connectors: connectors, profiles: states)
    }

    var profileDescription: String { record().text }

    func record() -> HardwareProfileRecord {
        HardwareProfileRecord(pairs: currentProfiles.enumerated().map {
            HardwareProfileRecord.Pair(firstConnector: 2 * $0.offset + 1, name: $0.element.name, identifier: $0.element.rawValue)
        })
    }

    // MARK: changes

    func activateKeying(firstConnector: Int) async throws {
        if lock.withLock({ faults.switchFails }) { throw SimulatedProfileError(text: "the simulated card refused to change profile") }
        let pair = (firstConnector - 1) / 2
        lock.withLock {
            if scope == .bothPairs { profiles = [.keying, .keying] } else if profiles.indices.contains(pair) { profiles[pair] = .keying }
        }
    }

    func restore(_ record: HardwareProfileRecord) async throws {
        let f = lock.withLock { faults }
        if f.restoreFails { throw SimulatedProfileError(text: "the simulated card would not go back to its earlier profile") }
        if f.restoreHasNoEffect { return }
        lock.withLock {
            for pair in record.pairs {
                let index = (pair.firstConnector - 1) / 2
                if profiles.indices.contains(index), let id = pair.identifier, let p = Profile(rawValue: id) { profiles[index] = p }
            }
        }
    }

    // MARK: connectors

    /// Which logical output really feeds a cable plugged into `connector`: the connector itself, or its swapped partner.
    func wireSource(ofConnector connector: Int) -> Int {
        let list = lock.withLock { faults.swappedOutputs }
        guard list.count == 2 else { return connector }
        return connector == list[0] ? list[1] : (connector == list[1] ? list[0] : connector)
    }

    func canOutput(_ connector: Int) -> Bool { HardwareTestLayout.canOutput(info, connector) }
    func pairIsKeying(_ connector: Int) -> Bool { connector % 2 == 1 && currentProfiles[(connector - 1) / 2] == .keying }

    func openOutput(_ connector: Int) throws -> any SDIOutputPort {
        let inner = try device.openOutput(connector: connector)
        return ProfileGatedPort(inner: inner, logical: connector, card: self)
    }

    func openInput(_ connector: Int) throws -> any SDIInputPort {
        guard HardwareTestLayout.canInput(info, connector) else { throw SDIError.connectorUnavailable(connector) }
        return try device.openInput(connector: connector)
    }

    /// The card as the kit sees it, built afresh each time so `info` is the layout now.
    public func testDevice() -> HardwareTestDevice {
        HardwareTestDevice(
            id: Self.deviceID, info: info, supportedModes: SDIVideoMode.allKnown, profile: profileDescription,
            isConnected: { [device] in device.isConnected },
            openOutput: { [self] in try openOutput($0) },
            openInput: { [self] in try openInput($0) },
            activateKeyingProfile: { [self] in try await activateKeying(firstConnector: $0) },
            captureProfiles: { [self] in record() },
            restoreProfiles: { [self] in try await restore($0) })
    }

    public func provider() -> HardwareTestProvider {
        let driver = HardwareDriverStatus(isInstalled: false, message: "Simulated card: no Blackmagic driver is involved.")
        return HardwareTestProvider(isSimulated: true, devices: { [self] in [testDevice()] }, driver: { driver })
    }
}

/// A port that obeys the card's current profile: plain output only where the layout allows it, keyed output only on a pair
/// that is in the keying profile.
final class ProfileGatedPort: SDIOutputPort, @unchecked Sendable {
    private let inner: any SDIOutputPort
    private let logical: Int
    private unowned let card: SimulatedProfileCard

    init(inner: any SDIOutputPort, logical: Int, card: SimulatedProfileCard) {
        self.inner = inner
        self.logical = logical
        self.card = card
    }

    var connector: Int { logical }

    private func allowed(_ keying: SDIKeying) -> Bool {
        switch keying {
        case .none: return card.canOutput(logical)
        case .external: return card.pairIsKeying(logical)
        }
    }

    func supports(mode: SDIVideoMode, keying: SDIKeying) -> Bool { allowed(keying) && inner.supports(mode: mode, keying: keying) }
    func enable(mode: SDIVideoMode, keying: SDIKeying) throws {
        guard allowed(keying) else { throw SDIError.unsupportedMode(mode.name) }
        try inner.enable(mode: mode, keying: keying)
    }
    func disable() { inner.disable() }
    func schedule(_ frame: SDIFrame, atFrame frameIndex: Int64) throws { try inner.schedule(frame, atFrame: frameIndex) }
    func startPlayback(atFrame frameIndex: Int64) { inner.startPlayback(atFrame: frameIndex) }
    func stopPlayback() { inner.stopPlayback() }
    func close() { inner.close() }
    var bufferedFrameCount: Int { inner.bufferedFrameCount }
    var onFrameCompleted: (@Sendable (SDIFrameCompletion) -> Void)? { get { inner.onFrameCompleted } set { inner.onFrameCompleted = newValue } }
    var onFailure: (@Sendable (SDIError) -> Void)? { get { inner.onFailure } set { inner.onFailure = newValue } }
}

// MARK: faults for the headless run

/// `--inject-fault <name>`: what a coordinator can ask the simulated card to get wrong, to see the report catch it.
public enum HardwareTestInjection: String, CaseIterable, Sendable {
    /// Outputs 1 and 2 leave by each other's connector (S4): the picture sent on SDI 1 comes out of SDI 2 and the other way round.
    case swappedConnectors = "swapped-connectors"
    /// The card does not go back to its profile after the fill and key step (S1).
    case profileNotRestored = "profile-not-restored"
    /// The two fill and key cables are crossed and stay crossed after the tester confirms them (S7).
    case crossedCables = "crossed-cables"
}

extension HardwareTestRig {
    /// The profiled simulated card with its cables, clock and a tester who places the cables the prompts ask for.
    public static func simulatedCard(scope: SimulatedProfileCard.Scope = .onePair, faults: SimulatedFaults = .none,
                                     injecting: Set<HardwareTestInjection> = [], cabling: SimulatedInteraction.Cabling? = nil) -> HardwareTestRig {
        let card = SimulatedProfileCard(
            scope: scope,
            faults: SimulatedProfileCard.Faults(restoreFails: injecting.contains(.profileNotRestored),
                                                swappedOutputs: injecting.contains(.swappedConnectors) ? [1, 2] : []))
        return simulated(card: card, faults: faults, cabling: cabling ?? (injecting.contains(.crossedCables) ? .crossedAndStayingCrossed : .asInstructed))
    }

    public static func simulated(card: SimulatedProfileCard, faults: SimulatedFaults = .none, cabled: Bool = true,
                                 cabling: SimulatedInteraction.Cabling = .asInstructed) -> HardwareTestRig {
        card.device.setFaults(faults)
        let interaction = SimulatedInteraction(device: card.device, placesCables: true, cabling: cabling, wireSource: { card.wireSource(ofConnector: $0) })
        if cabled { interaction.place([HardwareCable(output: 1, input: 3), HardwareCable(output: 2, input: 4)], replacingOthers: false) }
        return HardwareTestRig(provider: card.provider(), clock: SimulatedHardwareTestClock(devices: [card.device]),
                               interaction: interaction, device: card.device)
    }
}
