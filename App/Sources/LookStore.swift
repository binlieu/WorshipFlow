// OUT-003: Looks and props as JSON beside the screen profiles. Interim: the SQLite tables come after schema v2.
import Foundation
import Domain

/// A prop plus the security-scoped bookmark of its image file, so access survives relaunches.
struct StoredProp: Codable, Equatable {
    var prop: Prop
    var bookmark: Data?
}

struct LookLibrary: Codable, Equatable {
    var looks: [Look]
    var selectedLookID: UUID?
    var props: [StoredProp]
}

struct LookStore {
    let url: URL

    static var standard: LookStore {
        LookStore(url: ScreenProfileStore.standard.url.deletingLastPathComponent().appendingPathComponent("looks.json"))
    }

    enum LoadResult {
        case missing
        case loaded(LookLibrary)
        case unreadable(String)
    }

    func load() -> LoadResult {
        guard FileManager.default.fileExists(atPath: url.path) else { return .missing }
        do {
            return .loaded(try JSONDecoder().decode(LookLibrary.self, from: Data(contentsOf: url)))
        } catch {
            return .unreadable("\(error)")
        }
    }

    func save(_ library: LookLibrary) throws {
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        try encoder.encode(library).write(to: url, options: .atomic)
    }
}
