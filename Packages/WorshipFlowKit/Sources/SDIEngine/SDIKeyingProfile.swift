// HW-004 / KI-054: what to do when a keyed output is wanted on a card whose current profile cannot key. Pure decision
// logic plus one orchestration function that takes the operator's answer as a closure, so it is tested with a fake device
// and used unchanged by the app and by the hardware test kit. Nothing is ever switched without a yes.
import Foundation

public enum SDIKeyingProfileDecision: Equatable, Sendable {
    /// Keying works as things are (or the device says nothing about profiles): carry on.
    case notNeeded
    /// Keying cannot be had on this pair, in any profile the card reports. The text says why, for the operator.
    case unavailable(String)
    /// Keying needs this change. Ask first.
    case askOperator(SDIProfileChange)
}

public enum SDIProfileOutcome: Equatable, Sendable {
    case notNeeded
    case declined(SDIProfileChange)
    case switched(SDIProfileChange)
    case failed(SDIProfileChange?, reason: String)

    /// True when the keyed output may go on and try to start.
    public var mayProceed: Bool {
        switch self {
        case .notNeeded, .switched: return true
        case .declined, .failed: return false
        }
    }

    /// One calm sentence for the operator or the log.
    public var message: String {
        switch self {
        case .notNeeded: return "The card can already send fill and key."
        case .declined(let c): return "The card's profile was left as it is, so connectors \(c.firstConnector) and \(c.firstConnector + 1) cannot send fill and key."
        case .switched(let c): return "The card now uses the profile \"\(c.toName)\", and connectors \(c.firstConnector) and \(c.firstConnector + 1) can send fill and key."
        case .failed(_, let reason): return "The card's profile could not be changed: \(reason)"
        }
    }
}

public enum SDIKeyingProfile {
    public static func decision(for info: SDIDeviceInfo, firstConnector: Int) -> SDIKeyingProfileDecision {
        guard info.supportsExternalKeying else { return .unavailable("This card cannot send a fill and key pair.") }
        guard let state = info.profileState(forPair: firstConnector) else { return .notNeeded }
        if state.keyingAvailableNow { return .notNeeded }
        if let change = state.keyingChange { return .askOperator(change) }
        return .unavailable("This card has no profile that sends a fill and key pair on connectors \(firstConnector) and \(firstConnector + 1).")
    }

    /// Decides, asks if needed, switches, and says how it went. `ask` is only called when a change is needed.
    public static func ensure(device: SDIProvidedDevice, firstConnector: Int,
                              ask: @Sendable (SDIProfileChange) async -> Bool) async -> SDIProfileOutcome {
        await ensure(info: device.info, activate: device.activateKeyingProfile, firstConnector: firstConnector, ask: ask)
    }

    /// The same for a caller that holds the pieces rather than a provided device (the hardware test kit).
    public static func ensure(info: SDIDeviceInfo, activate: (@Sendable (Int) async throws -> Void)?, firstConnector: Int,
                              ask: @Sendable (SDIProfileChange) async -> Bool) async -> SDIProfileOutcome {
        switch decision(for: info, firstConnector: firstConnector) {
        case .notNeeded:
            return .notNeeded
        case .unavailable(let why):
            return .failed(nil, reason: why)
        case .askOperator(let change):
            guard let activate else {
                return .failed(change, reason: "This card cannot change its profile from WorshipFlow. Change it in Blackmagic Desktop Video Setup.")
            }
            guard await ask(change) else { return .declined(change) }
            do {
                try await activate(firstConnector)
                return .switched(change)
            } catch {
                return .failed(change, reason: (error as? LocalizedError)?.errorDescription ?? error.localizedDescription)
            }
        }
    }
}
