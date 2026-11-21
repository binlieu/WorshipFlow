// UI-003 (LIVE-03): the stage message and the timers shown in the toolbar. Both are small; the decisions are here, the
// views only draw them. Foundation and Domain only.
import Foundation
import Domain

/// One timer in the toolbar.
public struct ToolbarTimerRow: Sendable, Equatable, Identifiable {
    public var id: UUID
    public var name: String
    public var text: String
    public var isRunning: Bool
    /// A countdown that has passed zero: drawn in the warning colour (never red: red means on screen now).
    public var isOverrun: Bool
    /// Only a countdown has a start or pause button in the toolbar.
    public var canToggle: Bool
    public var kindLabel: String
}

extension StageModel {
    // MARK: Stage message

    /// Shows `text` on every stage screen (nothing else). Blank text is ignored: use `clearStageMessage()` to remove one.
    public func sendMessage(_ text: String) {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        stageMessage = trimmed
        var recent = recentMessages.filter { $0 != trimmed }
        recent.insert(trimmed, at: 0)
        recentMessages = Array(recent.prefix(Self.recentMessageLimit))
        enqueueWrite(.messages)
        onChange?()
    }

    public func clearStageMessage() {
        guard stageMessage != nil else { return }
        stageMessage = nil
        onChange?()
    }

    /// The app tells the model whether the show is stopped. Stop takes the message off the stage screens; a message sent
    /// while nothing is live waits for the show.
    public func showStateChanged(isStopped: Bool) {
        let becameStopped = isStopped && !showWasStopped
        showWasStopped = isStopped
        if becameStopped { clearStageMessage() }
    }

    // MARK: Timers in the toolbar

    /// The timers the toolbar shows: the operator's marks, or by default the first elapsed timer and the first countdown.
    public var toolbarTimers: [ShowTimer] {
        let chosen: Set<UUID>
        if let marks = toolbarMarks {
            chosen = Set(marks)
        } else {
            var ids: Set<UUID> = []
            if let e = timers.first(where: { if case .elapsed = $0.kind { true } else { false } }) { ids.insert(e.id) }
            if let c = timers.first(where: { if case .countdown = $0.kind { true } else { false } }) { ids.insert(c.id) }
            chosen = ids
        }
        return timers.filter { chosen.contains($0.id) }
    }

    public func isShownInToolbar(_ id: UUID) -> Bool { toolbarTimers.contains { $0.id == id } }

    public func setShownInToolbar(_ id: UUID, _ on: Bool) {
        guard timers.contains(where: { $0.id == id }) else { return }
        var marks = toolbarTimers.map(\.id)
        marks.removeAll { $0 == id }
        if on { marks.append(id) }
        toolbarMarks = marks
        toolbarRevision &+= 1
        enqueueWrite(.toolbar)
    }

    public func toolbarTimerRows(at seconds: TimeInterval) -> [ToolbarTimerRow] {
        let labels = Dictionary(uniqueKeysWithValues: timerRows(at: seconds).map { ($0.id, $0.kindLabel) })
        return toolbarTimers.map { timer in
            var canToggle = false
            if case .countdown = timer.kind { canToggle = true }
            return ToolbarTimerRow(id: timer.id, name: timer.name, text: TimeFormat.clock(seconds: timer.value(at: seconds)),
                                   isRunning: timer.isRunning, isOverrun: timer.isOverrun(at: seconds), canToggle: canToggle,
                                   kindLabel: labels[timer.id] ?? "")
        }
    }

    /// Start or pause, for a countdown only; any other timer is left as it is.
    public func toggleToolbarTimer(_ id: UUID) {
        guard let timer = timers.first(where: { $0.id == id }), case .countdown = timer.kind else { return }
        if timer.isRunning { pauseTimer(id) } else { startTimer(id) }
    }
}
