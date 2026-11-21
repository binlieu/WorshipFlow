// HW-002 / OUT-005: SDI destinations, mirrors and video mode survive storage; rows written by v5 still read (schema v6).
import Testing
import Foundation
import GRDB
import Domain
@testable import Persistence

@Suite struct HW002_ScreenProfileStoreTests {
    func storeURL() -> URL {
        FileManager.default.temporaryDirectory
            .appendingPathComponent("wf-tests-\(UUID().uuidString)", isDirectory: true)
            .appendingPathComponent("Library.sqlite")
    }

    @Test func sdiProfileWithMirrorsAndModeRoundTrips() async throws {
        let store = try LibraryStore.inMemory()
        var keyed = ScreenProfile(name: "Broadcast", role: .broadcast,
                                  destination: .sdi(deviceID: "sim-duo2", connector: 1, keying: true, fillAlphaMode: .straight))
        keyed.mirrors = [.window, .display(3), .sdi(deviceID: "sim-duo2", connector: 3, keying: false, fillAlphaMode: .premultiplied)]
        keyed.videoMode = .hd1080p50
        let plain = ScreenProfile(name: "Audience", role: .audience, destination: .display(2))
        try await store.saveScreenProfiles([plain, keyed])
        let back = try await store.screenProfiles()
        #expect(back == [plain, keyed])
        #expect(back[1].mirrors.count == 3 && back[1].videoMode == .hd1080p50)
    }

    @Test func aRowWrittenBeforeV6ReadsWithDefaultMirrorsAndMode() async throws {
        let url = storeURL()
        let id = UUID()
        do {
            let old = try LibraryStore.open(at: url, migratingUpTo: "v5")
            try await old.writer.write { db in
                try db.execute(sql: """
                    INSERT INTO screenProfile (id, sortOrder, name, role, destination, displayID, isEnabled)
                    VALUES (?, 0, 'Audience', 'audience', 'display', 2, 1)
                    """, arguments: [id.dbText])
            }
        }
        let store = try LibraryStore.open(at: url)
        let back = try await store.screenProfiles()
        #expect(back.count == 1)
        #expect(back[0].id == id && back[0].destination == .display(2))
        #expect(back[0].mirrors.isEmpty && back[0].videoMode == .hd1080p5994)
    }

    @Test func aProfileWithoutExtrasStoresNothingExtra() async throws {
        let store = try LibraryStore.inMemory()
        let p = ScreenProfile(name: "Stage", role: .stage, destination: .window)
        try await store.saveScreenProfiles([p])
        let extra: String? = try await store.writer.read { db in
            try String.fetchOne(db, sql: "SELECT extra FROM screenProfile WHERE id = ?", arguments: [p.id.dbText])
        }
        #expect(extra == nil)
    }

    @Test func aMirrorsOnlyChangeIsStored() async throws {
        let store = try LibraryStore.inMemory()
        var p = ScreenProfile(name: "Audience", role: .audience, destination: .window)
        try await store.saveScreenProfiles([p])
        p.mirrors = [.display(7)]
        try await store.saveScreenProfiles([p])
        #expect(try await store.screenProfiles() == [p])
    }
}
