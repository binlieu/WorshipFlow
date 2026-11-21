// CUE-002a: shared helpers for the CueStore tests. Written by the implementer.
import Foundation
import GRDB
import Domain
import CueEngine
@_spi(CueStore) import Persistence
import CueStore

let t0 = Date(timeIntervalSinceReferenceDate: 800_000_000)

/// A settable clock for the store.
final class TestClock: @unchecked Sendable {      // guarded by the lock; only read and written through `now`/`set`
    private let lock = NSLock()
    private var current: Date
    init(_ start: Date = t0) { current = start }
    var now: Date { lock.lock(); defer { lock.unlock() }; return current }
    func set(_ d: Date) { lock.lock(); current = d; lock.unlock() }
}

struct Fixture {
    let library: LibraryStore
    let store: CueStore
    let clock: TestClock

    init(library: LibraryStore? = nil, clock: TestClock = TestClock()) throws {
        let lib = try library ?? LibraryStore.inMemory()
        self.library = lib
        self.clock = clock
        self.store = CueStore(library: lib, now: { clock.now })
    }

    /// A presentation with one slide per line; returns the slides in order.
    func slides(_ lines: [String]) async throws -> [Slide] {
        let lib = try await library.createLibrary(name: "L\(UUID().uuidString.prefix(4))")
        let p = try await library.createPresentation(in: lib.id, title: "Song", kind: .song)
        for line in lines { _ = try await library.appendSlide(to: p.id, content: SlideContent(primary: line)) }
        return try await library.slides(of: p.id)
    }

    func rawCount(_ table: String) async throws -> Int {
        try await library.cueRead { db in try Int.fetchOne(db, sql: "SELECT COUNT(*) FROM \(table)") ?? 0 }
    }

    /// Writes a row exactly as given, for the unreadable and newer-version cases.
    func rawExec(_ sql: String, _ args: [String] = []) async throws {
        try await library.cueWrite { db in try db.execute(sql: sql, arguments: StatementArguments(args)) }
    }

    func rawString(_ sql: String, _ args: [String] = []) async throws -> String? {
        try await library.cueRead { db in try String.fetchOne(db, sql: sql, arguments: StatementArguments(args)) }
    }
}

func macro(_ name: String, _ steps: [CueAction] = [], id: UUID = UUID()) -> Macro { Macro(id: id, name: name, steps: steps) }

func weekly(_ name: String = "Sunday", payload: ScheduledEvent.Payload = .actions([.selectLook(UUID())]),
            enabled: Bool = true, id: UUID = UUID()) -> ScheduledEvent {
    ScheduledEvent(id: id, name: name, isEnabled: enabled,
                   timing: .weekly(weekdays: [.sunday], hour: 10, minute: 30, timeZoneID: "UTC"), payload: payload)
}

func noteBinding(_ name: String, note: Int, _ command: MIDICommand, id: UUID = UUID()) -> MIDIBinding {
    MIDIBinding(id: id, name: name, pattern: MIDIPattern(kind: .noteOn, channel: 1, number: note), command: command)
}

func utc(_ iso: String) -> Date {
    let f = ISO8601DateFormatter()
    f.formatOptions = [.withInternetDateTime]
    return f.date(from: iso) ?? .distantPast
}
