// CUE-002b (item 1): the vocabulary of the one command path. Foundation and CueEngine only.
import Foundation
import CueEngine

/// Where a command came from. Shown in the activity list; it never changes what the command does.
public enum CommandSource: String, Sendable, Equatable, CaseIterable {
    case button, key, slideAction, schedule, midi, remote, timer
    /// UI-007d (CU-33): a marker of a clip that is playing live was reached.
    case marker

    public var label: String {
        switch self {
        case .button: "button"
        case .key: "key"
        case .slideAction: "slide action"
        case .schedule: "schedule"
        case .midi: "midi"
        case .remote: "remote"
        case .timer: "timer"
        case .marker: "marker"
        }
    }
}

/// Everything that can move or change the show, from any source. The command path runs these one at a time.
public enum OperatorCommand: Sendable, Equatable {
    case goLive
    /// A double click on a slide of the preview deck.
    case triggerSlide(Int)
    case transport(CueTransport)
    case runMacro(UUID)
    case runActions([CueAction], CueOrigin)
    /// A slide went live: run its actions (if it has any and it is still the live one).
    case slideLive(SlideLiveEvent)
    /// UI-007d (CU-33): live playback reached a marker of a clip. Its actions run on the one path, in order with everything else.
    case markerReached(MarkerFiring)
    /// Deliver the waited stages of earlier runs that have come due.
    case tick
}

/// One line of the activity list in the Cues mode.
public struct ActivityLine: Identifiable, Sendable, Equatable {
    public var id = UUID()
    public var time: Date
    public var source: CommandSource
    public var text: String
    /// Failures and warnings: drawn in the warning colour.
    public var isProblem: Bool
}

/// Something the operator should read: a skipped scheduled event, a failed action. Stays until dismissed.
public struct CueNotice: Identifiable, Sendable, Equatable {
    public var id = UUID()
    public var text: String
}
