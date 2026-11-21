// HW-003 / SCRN-11: how bridge results and SDIEngine requests translate into each other. Pure functions.
import DeckLinkC
import Foundation
import SDIEngine

enum DeckLinkMapping {
    /// The most frames ever prerolled, whatever a device claims: the bridge's pool holds 16 and every one is a full HD buffer.
    static let maxPrerollFrames = 10

    /// The scheduler's preroll for a device whose SDK minimum is `deviceMinimum` (-1 or 0: it did not say): at least 3,
    /// at least what the device asks for, at most `maxPrerollFrames`.
    static func prerollFrames(deviceMinimum: Int64) -> Int {
        let wanted = deviceMinimum > Int64(maxPrerollFrames) ? maxPrerollFrames : Int(max(0, deviceMinimum))
        return max(3, wanted)
    }

    /// The SDK's four completion results map one to one. A value the bridge did not recognise counts as dropped: it
    /// must never be mistaken for a frame that reached the screen.
    static func completionResult(_ result: DLBCompletionResult) -> SDICompletionResult {
        switch result {
        case .completed: return .completed
        case .displayedLate: return .displayedLate
        case .dropped: return .dropped
        case .flushed: return .flushed
        case .unknown: return .dropped
        @unknown default: return .dropped
        }
    }

    /// What the keying request means for the card.
    struct KeyingPlan: Equatable {
        /// Turn the external keyer on (the card then outputs fill and key from one BGRA frame with alpha).
        var useKeyer: Bool
        /// Whether the card should receive straight colour (divided by alpha) or the compositor's premultiplied colour.
        var straightAlpha: Bool
    }

    static func keyingPlan(_ keying: SDIKeying) -> KeyingPlan {
        switch keying {
        case .none:
            // Without the keyer the card drops alpha on YCbCr outputs, so the premultiplied colour is simply "over black".
            return KeyingPlan(useKeyer: false, straightAlpha: false)
        case .external(let mode):
            return KeyingPlan(useKeyer: true, straightAlpha: mode == .straight)
        }
    }

    static func bridgeAlphaMode(straight: Bool) -> DLBAlphaMode {
        straight ? .straight : .premultiplied
    }

    /// Where an error happened, because the same bridge error means different things to the engine in each place.
    enum Context {
        case open(connector: Int)
        case enable(connector: Int, modeName: String, keyed: Bool)
        case schedule
        case runtime
    }

    /// Translates a bridge error into the engine's error. A card that is gone is `.deviceDisconnected`; an SDK failure on a
    /// card that is still there is `.hardwareFault(detail:)` with the bridge's own words and the SDK result code (KI-056),
    /// so an operator is never told to reconnect a card that was never unplugged.
    static func sdiError(_ error: Error, context: Context) -> SDIError {
        if let sdi = error as? SDIError { return sdi }
        let fault = SDIError.hardwareFault(detail: detail(error))
        let nsError = error as NSError
        guard nsError.domain == DLBErrorDomain, let code = DLBError.Code(rawValue: nsError.code) else { return fault }
        switch code {
        case .deviceRemoved, .driverNotInstalled:
            return .deviceDisconnected
        case .notSupported:
            switch context {
            case .enable(_, let name, let keyed): return keyed ? .keyingUnavailable(connector: connectorOf(context)) : .unsupportedMode(name)
            case .open(let c): return .connectorUnavailable(c)
            case .schedule, .runtime: return .notEnabled
            }
        case .busy:
            switch context {
            case .open(let c), .enable(let c, _, _): return .connectorUnavailable(c)
            case .schedule, .runtime: return fault
            }
        case .badState:
            return context.isSchedule ? .notEnabled : .portClosed
        case .badArgument:
            if case .enable(_, let name, _) = context { return .unsupportedMode(name) }
            return .notEnabled
        case .outOfMemory, .sdkFailure, .profileTimeout:
            return fault
        @unknown default:
            return fault
        }
    }

    private static func connectorOf(_ context: Context) -> Int {
        switch context {
        case .open(let c), .enable(let c, _, _): return c
        case .schedule, .runtime: return 0
        }
    }

    /// The bridge's own message for an error, for logs.
    static func detail(_ error: Error) -> String {
        let nsError = error as NSError
        if let hr = nsError.userInfo[DLBErrorHRESULTKey] as? Int { return "\(nsError.localizedDescription) [hresult \(hr)]" }
        return nsError.localizedDescription
    }
}

extension DeckLinkMapping.Context {
    var isSchedule: Bool { if case .schedule = self { return true } else { return false } }
}
