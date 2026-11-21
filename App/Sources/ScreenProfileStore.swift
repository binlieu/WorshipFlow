// OUT-002: screen profiles as JSON in Application Support. Interim: the SQLite table arrives with a later slice.
import Foundation
import Domain

struct ScreenProfileStore {
    let url: URL

    static var standard: ScreenProfileStore {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? URL(fileURLWithPath: NSTemporaryDirectory())
        return ScreenProfileStore(url: base.appendingPathComponent("WORSHIPFLOW", isDirectory: true)
            .appendingPathComponent("screen-profiles.json"))
    }

    enum LoadResult {
        case missing
        case loaded([ScreenProfile])
        case unreadable(String)
    }

    func load() -> LoadResult {
        guard FileManager.default.fileExists(atPath: url.path) else { return .missing }
        do {
            let profiles = try JSONDecoder().decode([ScreenProfile].self, from: Data(contentsOf: url))
            return profiles.isEmpty ? .missing : .loaded(profiles)
        } catch {
            return .unreadable("\(error)")
        }
    }

    func save(_ profiles: [ScreenProfile]) throws {
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        try encoder.encode(profiles).write(to: url, options: .atomic)
    }
}
