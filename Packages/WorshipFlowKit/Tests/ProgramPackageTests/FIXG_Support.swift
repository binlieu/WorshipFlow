// FIX-G: helpers shared by the FIXG_ program-package tests. Everything is invented and lives in the test's own temporary folder.
import Testing
import Foundation
import Domain
@_spi(ProgramPackage) import Persistence
@testable import ProgramPackage

/// Edits a package's `program.json` as loose JSON (for damage a typed document could not express).
func editManifest(_ package: URL, _ change: (inout [String: Any]) throws -> Void) throws {
    let url = package.appendingPathComponent(ProgramFormat.manifestName)
    var object = try #require(try JSONSerialization.jsonObject(with: Data(contentsOf: url)) as? [String: Any])
    try change(&object)
    try JSONSerialization.data(withJSONObject: object, options: [.sortedKeys]).write(to: url)
}

/// Applies `change` to every slide entry of every presentation in `program.json`.
func editSlides(_ package: URL, _ change: (inout [String: Any]) -> Void) throws {
    try editManifest(package) { root in
        var presentations = root["presentations"] as? [[String: Any]] ?? []
        for p in presentations.indices {
            var slides = presentations[p]["slides"] as? [[String: Any]] ?? []
            for s in slides.indices { change(&slides[s]) }
            presentations[p]["slides"] = slides
        }
        root["presentations"] = presentations
    }
}

extension HomeProgram {
    /// Gives the second song's first slide the Loop clip as its own background and returns the selection.
    @discardableResult
    func giveSermonABackground() async throws -> MediaSelection {
        let selection = MediaSelection(assetID: assetID, kind: .video, duration: 3)
        var slides = try await store.slides(of: songTwo)
        slides[0].content.background = selection
        try await store.updateSlide(slides[0])
        return selection
    }

    func sermonBackgrounds(in other: LibraryStore) async throws -> [MediaSelection?] {
        try await other.slides(of: songTwo).map(\.content.background)
    }
}

/// A fixed clock for backup names.
final class FixedDates: @unchecked Sendable {
    private let lock = NSLock()
    private var next: Date
    init(start: Date = Date(timeIntervalSince1970: 1_800_000_000)) { next = start }
    func tick() -> Date { lock.lock(); defer { lock.unlock() }; let d = next; next = d.addingTimeInterval(60); return d }
}

/// Makes the church library hold a different version of the home program, so an import conflicts on every item.
func makeConflicting(_ store: LibraryStore, home: HomeProgram) async throws {
    // Same ids as the home program, different words.
    try await store.programWrite { db, _ in
        try db.execute(sql: "UPDATE slide SET primaryText = primaryText || ' (church edit)' WHERE presentationID = ?", arguments: [home.songOne.uuidString])
    }
}

/// Sums byte counts reported from worker threads.
final class ByteCounter: @unchecked Sendable {
    private let lock = NSLock()
    private var sum: Int64 = 0
    func add(_ n: Int64) { lock.lock(); sum += n; lock.unlock() }
    var total: Int64 { lock.lock(); defer { lock.unlock() }; return sum }
}
