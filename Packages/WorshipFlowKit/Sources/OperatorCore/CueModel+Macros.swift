// CUE-002b (item 6): creating, renaming, reordering, editing and deleting macros. Every change goes through the store, which
// refuses what the engine refuses (a blank name, a cycle, a macro that would make a slide move the show); the model then reads the
// library again, so what the screen shows is what is stored.
import Foundation
import CueEngine
import CueStore

public enum MacroDeleteOutcome: Equatable, Sendable {
    /// Something still runs the macro. Nothing was deleted. One line per user of it.
    case blocked([String])
    /// Deleted. One line per thing that was rewritten because it used the macro (empty when nothing did).
    case deleted([String])
    case failed
}

extension CueModel {
    public func macro(_ id: UUID) -> Macro? { library.macro(id: id) }

    @discardableResult
    public func createMacro(name: String) async -> Macro? {
        let macro = Macro(name: name.trimmingCharacters(in: .whitespacesAndNewlines), steps: [])
        do {
            try await store.saveMacro(macro)
            lastError = nil
            await reload()
            return macro
        } catch {
            lastError = Self.message(for: error)
            return nil
        }
    }

    public func renameMacro(_ id: UUID, to name: String) async {
        do {
            try await store.renameMacro(id: id, to: name.trimmingCharacters(in: .whitespacesAndNewlines))
            lastError = nil
            await reload()
        } catch { lastError = Self.message(for: error) }
    }

    public func moveMacro(_ id: UUID, to index: Int) async {
        var ids = macros.map(\.id)
        guard let from = ids.firstIndex(of: id) else { return }
        ids.remove(at: from)
        ids.insert(id, at: min(max(index, 0), ids.count))
        do {
            try await store.reorderMacros(ids)
            await reload()
        } catch { lastError = Self.message(for: error) }
    }

    /// Replaces the steps of a macro. A cycle, or a transport step in a macro that a slide runs, is refused with the engine's words.
    public func setSteps(_ steps: [CueAction], of id: UUID) async {
        guard var macro = library.macro(id: id) else { return }
        macro.steps = steps
        do {
            try await store.saveMacro(macro)
            lastError = nil
            await reload()
        } catch { lastError = Self.message(for: error) }
    }

    /// Deletes a macro. While anything runs it, nothing is deleted and the users come back as `.blocked`; the operator then chooses
    /// to delete anyway (`force`), which removes the references and says what it changed.
    public func deleteMacro(_ id: UUID, force: Bool = false) async -> MacroDeleteOutcome {
        do {
            let result = try await store.deleteMacro(id: id, force: force)
            if !result.deleted { return .blocked(result.blockedBy.map(Self.describe)) }
            var lines = result.changes.map(Self.describe(change:))
            lines += result.leftUnreadable.map { "Left as it is: \(Self.describe($0))" }
            lastError = nil
            await reload()
            if force, !lines.isEmpty { note("Deleted the macro. " + lines.joined(separator: " ")) }
            return .deleted(lines)
        } catch {
            lastError = Self.message(for: error)
            return .failed
        }
    }

    static func describe(_ referrer: CueReferrer) -> String {
        switch referrer {
        case .macro(_, let name): "the macro \u{201C}\(name)\u{201D}"
        case .slide: "a slide\u{2019}s actions"
        case .scheduledEvent(_, let name): "the scheduled event \u{201C}\(name)\u{201D}"
        case .midiBinding(_, let name): "the MIDI binding \u{201C}\(name)\u{201D}"
        case .unreadable(let record, _): "a \(record == .macro ? "macro" : "stored item") that cannot be read"
        }
    }

    static func describe(change: CueReferenceChange) -> String {
        switch change {
        case .macroStepsRemoved(_, let name, let n): "\(n) step\(n == 1 ? "" : "s") removed from \u{201C}\(name)\u{201D}."
        case .slideActionsRemoved(_, let n): "\(n) slide action\(n == 1 ? "" : "s") removed."
        case .eventActionsRemoved(_, let name, _, let disabled):
            "\u{201C}\(name)\u{201D} lost the macro" + (disabled ? " and was switched off." : ".")
        case .midiBindingDeleted(_, let name): "The MIDI binding \u{201C}\(name)\u{201D} was deleted."
        }
    }
}
