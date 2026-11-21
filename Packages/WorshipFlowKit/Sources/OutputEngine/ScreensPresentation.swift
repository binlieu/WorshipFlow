// UI-002 Part 2: wording for the Screens mode that depends on what is known, kept out of the views.
import Foundation
import Domain
import SDIEngine

public enum ScreensPresentation {
    public struct Verification: Equatable, Sendable { public var level: String; public var text: String }

    /// The level is never above what has been measured: nothing in the app records a signal test on a real card, so a real
    /// card is "Implemented, not hardware verified" and the simulator is "Simulated".
    public static func verification(for device: SDIDeviceInfo?) -> Verification {
        guard let device else {
            return Verification(level: "No SDI card", text: "No SDI card is in use. Displays and windows are drawn by the same engine and need no card.")
        }
        if device.isSimulated {
            return Verification(level: "Simulated",
                                text: "This path has only run against the simulated card. It can become Hardware Verified only after a signal test on the real card and the equipment after it.")
        }
        return Verification(level: "Implemented, not hardware verified",
                            text: "This card is driven by code that has not yet been checked on hardware. Run the signal test and keep the log bundle to record what it does.")
    }

    public struct KeyedCaptions: Equatable, Sendable {
        public var composite = "Composite", compositeDetail = "what the keyer produces"
        public var fill: String, fillDetail: String
        public var key: String, keyDetail = "matte: white opaque"
    }

    /// Captions for the three keyed previews, with the connectors the device reports. Nil unless the destination is a fill and key pair.
    public static func keyedCaptions(destination: OutputDestination, device: SDIDeviceInfo?) -> KeyedCaptions? {
        guard case .sdi(_, let connector, true, let alpha) = destination else { return nil }
        var fill = connector, key = connector + 1
        if let route = device?.keyRoute(firstConnector: connector) { fill = route.fillConnector; key = route.keyConnector }
        return KeyedCaptions(fill: "SDI \(fill) · Fill", fillDetail: alpha == .premultiplied ? "premultiplied colour" : "straight colour", key: "SDI \(key) · Key")
    }

    public static let blackIsNotTransparency = (
        headline: "A black background is not transparency.",
        body: "The fill carries colour, the key carries the matte. Set the keyer to linear key, premultiplied to match “Fill alpha”, and check key polarity with a test pattern before the service.")

    /// What the app does when an output fails; it is not a choice.
    public static let outputFailureText = "The show keeps running. This screen shows a warning in this window, and starts again by itself when its card or display returns."
}
