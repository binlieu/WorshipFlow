// FIX-B R4: the rules for leaving the app while the screens may be showing the audience something. Pure, so the
// decision is tested; the app's window delegate and application delegate only ask it and act on the answer.
import Foundation

public enum QuitRequest: Sendable, Equatable {
    /// Command-Q or the application menu's Quit.
    case quitCommand
    /// AppKit asks whether the app ends because its last window closed.
    case lastWindowClosed
    /// The operator window's close button or Command-W.
    case operatorWindowClose
}

public enum QuitDecision: Sendable, Equatable {
    /// Go ahead. Everything is written to the library first.
    case allow
    /// Ask the operator; quit only on "confirmTitle".
    case confirm(title: String, message: String, confirmTitle: String)
    /// Do not do it. Show the message.
    case refuse(message: String)
}

public enum QuitPolicy {
    public static func decision(for request: QuitRequest, screensOpen: Bool) -> QuitDecision {
        guard screensOpen else { return .allow }
        switch request {
        case .quitCommand:
            return .confirm(
                title: "Quit WORSHIPFLOW while the screens are open?",
                message: "The screens are open, so the audience may be looking at them. Quitting closes every screen and ends the show. Your typing and settings are saved first.",
                confirmTitle: "Quit and Close Screens")
        case .operatorWindowClose:
            return .refuse(message: "The screens are still open, so this window stays. Close the screens first (Show, then Close Screens) if the service is over, or choose Quit.")
        case .lastWindowClosed:
            return .refuse(message: "The screens are still open, so WORSHIPFLOW keeps running.")
        }
    }

    /// Hiding the app hides every window it owns, the screens' included.
    public static func mayHide(screensOpen: Bool) -> Bool { !screensOpen }
}
