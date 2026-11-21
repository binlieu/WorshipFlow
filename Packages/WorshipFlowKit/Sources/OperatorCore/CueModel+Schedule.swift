// CUE-002b (item 3): the schedule. The app calls `pollSchedule()` once a second with the wall clock, and `wakeFromSleep()` when
// the Mac wakes; what was due is run through the one command path, what was missed is reported, and the engine's memory is
// saved (at once when something fired or was skipped, otherwise every 30 seconds) so a relaunch can look at the time the app was shut.
import Foundation
import CueEngine
import CueStore

public struct NextScheduledEvent: Sendable, Equatable {
    public var name: String
    public var date: Date
}

extension CueModel {
    static let stateSaveInterval: TimeInterval = 30
    static let lookAhead: TimeInterval = 8 * 24 * 3600

    public func pollSchedule() {
        guard isLoaded else { return }
        let now = wallClock()
        let before = schedule.state.lastHandled
        let due = schedule.poll(now: now, calendar: calendar)
        let blocked = hardwareTestIsRunning()
        for item in due.fire {
            if blocked {
                note("\u{201C}\(item.event.name)\u{201D} was due, but the Hardware Test is running, so it was not run.")
            } else {
                submit(.runActions(item.actions, .schedule), from: .schedule)
                log(.schedule, "event \(item.event.name)")
            }
        }
        for skipped in due.skipped { note(skipped.message) }
        let changed = schedule.state.lastHandled != before
        let stale = scheduleSavedAt.map { now.timeIntervalSince($0) >= Self.stateSaveInterval } ?? true
        if changed || !due.skipped.isEmpty || stale { saveScheduleState(at: now) }
    }

    /// The Mac woke up: look now instead of waiting for the next second, so what was missed in sleep is reported at once.
    public func wakeFromSleep() { pollSchedule() }

    private func saveScheduleState(at now: Date) {
        let state = schedule.state
        scheduleSavedAt = now
        let previous = scheduleSaveTail
        scheduleSaveTail = Task { @MainActor [weak self, store] in
            await previous?.value
            do { try await store.saveScheduleState(state) } catch { self?.lastError = Self.message(for: error) }
        }
    }

    /// Waits for the schedule's memory to be written. `force` writes the latest check too (quitting).
    public func flushSchedule(force: Bool = false) async {
        if force, isLoaded { saveScheduleState(at: wallClock()) }
        await scheduleSaveTail?.value
    }

    /// The earliest enabled event in the next eight days, for the Cues tab.
    public func nextScheduledEvent() -> NextScheduledEvent? {
        let now = wallClock()
        var best: NextScheduledEvent?
        for event in schedule.events where event.isEnabled {
            guard let date = event.occurrences(after: now, upTo: now.addingTimeInterval(Self.lookAhead), calendar: calendar).first else { continue }
            if best == nil || date < best!.date { best = NextScheduledEvent(name: event.name, date: date) }
        }
        return best
    }

    // MARK: Editing

    public func saveEvent(_ event: ScheduledEvent) async {
        do {
            _ = try await store.saveScheduledEvent(event)
            lastError = nil
            await reload()
        } catch { lastError = Self.message(for: error) }
    }

    public func setEventEnabled(_ enabled: Bool, id: UUID) async {
        do {
            _ = try await store.setScheduledEvent(id: id, enabled: enabled)
            await reload()
        } catch { lastError = Self.message(for: error) }
    }

    public func deleteEvent(_ id: UUID) async {
        do {
            try await store.deleteScheduledEvent(id: id)
            await reload()
        } catch { lastError = Self.message(for: error) }
    }
}
