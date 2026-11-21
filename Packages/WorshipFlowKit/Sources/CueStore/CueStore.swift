// CUE-002a: macros, slide actions, scheduled events with the engine's state, and MIDI bindings, in the church's library file.
//
// `CueStore` reads and writes the `cue*` tables (schema v9) through the `LibraryStore` it is given, on that store's one
// connection pool: it never opens the file itself (ADR-0004 decision 2). Every operation that touches more than one row
// (a validated save, a forced macro delete, a reflow elsewhere) is one transaction, so a failure leaves exactly what was there.
//
// Definitions are JSON text with a `version` (see `CueEngine`). A row this version cannot read, or one written by a newer
// format, is never replaced: saving over it throws instead of dropping what this version cannot see.
import Foundation
import GRDB
import CueEngine
@_spi(CueStore) import Persistence

public final class CueStore: Sendable {
    let library: LibraryStore
    /// The clock used to restart a scheduled event "from now". Injected so tests do not depend on the wall clock.
    let now: @Sendable () -> Date

    public init(library: LibraryStore, now: @escaping @Sendable () -> Date = { Date() }) {
        self.library = library
        self.now = now
    }
}
