// CUE-002a: the public vocabulary of `CueStore`: errors, what refers to a macro, and the load report.
import Foundation
import CueEngine

/// The kinds of record `CueStore` keeps, for messages and reports.
public enum CueRecordKind: String, Sendable, Equatable, Hashable {
    case macro, slideActions, scheduledEvent, midiBinding, scheduleState

    var label: String {
        switch self {
        case .macro: return "macro"
        case .slideActions: return "slide actions"
        case .scheduledEvent: return "scheduled event"
        case .midiBinding: return "MIDI binding"
        case .scheduleState: return "schedule state"
        }
    }
}

public enum CueStoreError: Error, Sendable, Equatable {
    case notFound
    /// The engine refused the macro (blank name, cycle, too deep). Nothing was written.
    case invalidMacro(MacroLibraryError)
    /// The edit would put a transport command into a macro that slides run. Slide ids with the reasons. Nothing was written.
    case macroBreaksSlideActions([UUID: [SlideActionError]])
    case invalidSlideActions([SlideActionError])
    /// A macro id that is not in the library, in a slide action, an event or a MIDI binding.
    case unknownMacro(UUID)
    /// The engine's reasons the event cannot work.
    case invalidEvent([String])
    /// A pattern that can never match a message. The binding's name.
    case invalidBinding(String)
    /// A reorder list that names an id twice.
    case invalidOrder
    /// The stored row was written by a newer version; saving over it would drop what this version cannot read.
    case storedByNewerVersion(record: CueRecordKind, id: String, version: Int)
    /// The stored row cannot be read, so it is not replaced.
    case unreadable(record: CueRecordKind, id: String)
    /// The library file is older than schema v9; open it with `LibraryStore.open(at:)` to update it.
    case libraryNeedsUpdate

    /// Operator-readable text.
    public var message: String {
        switch self {
        case .notFound: return "That item is no longer in the library."
        case .invalidMacro(let e): return e.message
        case .macroBreaksSlideActions(let problems):
            let first = problems.values.first?.first?.message ?? ""
            return "This change would make \(problems.count) slide\(problems.count == 1 ? "" : "s") run a macro that moves the show. \(first)"
        case .invalidSlideActions(let errors): return errors.first?.message ?? "These slide actions are not allowed."
        case .unknownMacro: return "That macro no longer exists."
        case .invalidEvent(let reasons): return reasons.joined(separator: " ")
        case .invalidBinding(let name): return "The MIDI binding \u{201C}\(name)\u{201D} has a channel, number or value range that no message can match."
        case .invalidOrder: return "The new order lists the same item twice."
        case .storedByNewerVersion(let kind, _, let v):
            return "This \(kind.label) was saved by a newer version of WorshipFlow (format \(v)); it was left as it is."
        case .unreadable(let kind, _): return "This \(kind.label) cannot be read; it was left as it is."
        case .libraryNeedsUpdate: return "This library file has not been updated for show control yet."
        }
    }
}

/// Something that uses a macro, so deleting the macro would break it.
public enum CueReferrer: Sendable, Equatable, Hashable {
    case macro(id: UUID, name: String)
    case slide(id: UUID)
    case scheduledEvent(id: UUID, name: String)
    case midiBinding(id: UUID, name: String)
    /// A row that cannot be read (or was written by a newer version) and whose text mentions the macro's id.
    case unreadable(record: CueRecordKind, id: String)
}

/// What a forced delete rewrote.
public enum CueReferenceChange: Sendable, Equatable, Hashable {
    case macroStepsRemoved(id: UUID, name: String, count: Int)
    case slideActionsRemoved(id: UUID, count: Int)
    /// `disabled` is true when the event no longer has anything to run and was switched off.
    case eventActionsRemoved(id: UUID, name: String, count: Int, disabled: Bool)
    case midiBindingDeleted(id: UUID, name: String)
}

public struct MacroDeletion: Sendable, Equatable {
    public var deleted: Bool
    /// Why it was not deleted. Empty when `deleted`.
    public var blockedBy: [CueReferrer]
    /// What a forced delete changed elsewhere.
    public var changes: [CueReferenceChange]
    /// Rows that mention the macro but could not be rewritten (unreadable or newer-version); they were left as they were.
    public var leftUnreadable: [CueReferrer]
}

/// One thing `CueStore.loadLibrary()` could not load cleanly. The rest of the library still loads.
public struct CueLoadIssue: Sendable, Equatable, Identifiable {
    public enum Problem: Sendable, Equatable {
        /// The row could not be decoded and was left out. The decoder's text.
        case unreadable(String)
        /// Written by a newer format. It was loaded as far as it is understood, and will not be overwritten.
        case newerVersion(found: Int, supported: Int)
        /// An action this version does not know. It is kept, skipped when run, and written back unchanged.
        case unknownAction(index: Int, kind: String)
        case macroLibrary(MacroLibraryError)
        case slideActionNotAllowed(SlideActionError)
    }

    public var record: CueRecordKind
    /// The row's id as stored (a macro, event or binding id; a slide id for slide actions; "1" for the schedule state).
    public var recordID: String
    public var problem: Problem
    public var id: String { "\(record.rawValue):\(recordID):\(problem)" }

    public var message: String {
        switch problem {
        case .unreadable(let why): return "A \(record.label) could not be read and was skipped (\(why))."
        case .newerVersion(let found, let supported):
            return "A \(record.label) was saved in format \(found), newer than this version understands (\(supported)). It is kept as it is."
        case .unknownAction(_, let kind): return "A \(record.label) holds an action this version does not know (\u{201C}\(kind)\u{201D}); it is skipped when run."
        case .macroLibrary(let e): return e.message
        case .slideActionNotAllowed(let e): return e.message
        }
    }
}

/// Everything the cue engine needs, read in one pass.
public struct CueLibrary: Sendable {
    public var macros: MacroLibrary
    public var slideActions: SlideActionSet
    /// Events plus the remembered state. `lastHandled` only names events that exist.
    public var schedule: ScheduleEngine
    public var midi: MIDIBindingSet
    /// Anything that could not be loaded cleanly. Empty for a healthy library.
    public var issues: [CueLoadIssue]

    public init(macros: MacroLibrary = MacroLibrary(), slideActions: SlideActionSet = SlideActionSet(),
                schedule: ScheduleEngine = ScheduleEngine(), midi: MIDIBindingSet = MIDIBindingSet(), issues: [CueLoadIssue] = []) {
        self.macros = macros
        self.slideActions = slideActions
        self.schedule = schedule
        self.midi = midi
        self.issues = issues
    }
}
