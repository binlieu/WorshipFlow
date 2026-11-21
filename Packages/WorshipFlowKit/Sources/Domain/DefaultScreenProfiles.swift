// OUT-002: the screens a first launch starts with. Foundation only.
import Foundation

extension ScreenProfile {
    /// Audience on the first display that is not the operator's (else a window), Stage in a window,
    /// Broadcast in a window and disabled.
    public static func defaults(displays: [UInt32], operatorDisplay: UInt32?) -> [ScreenProfile] {
        let audienceDestination: OutputDestination
        if let other = displays.first(where: { $0 != operatorDisplay }) {
            audienceDestination = .display(other)
        } else {
            audienceDestination = .window
        }
        return [
            ScreenProfile(name: "Audience", role: .audience, destination: audienceDestination),
            ScreenProfile(name: "Stage", role: .stage, destination: .window),
            ScreenProfile(name: "Broadcast", role: .broadcast, destination: .window, isEnabled: false),
        ]
    }
}
