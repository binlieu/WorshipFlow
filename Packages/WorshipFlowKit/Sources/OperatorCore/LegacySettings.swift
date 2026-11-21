// APP-001 / KI-025: the JSON files earlier builds used for screen profiles, Looks and props. They are read once to
// fill empty SQLite tables and are never changed or deleted afterwards (they are the user's files).
import Foundation
import Domain

/// Where the old files live: beside the library file, so a library opened with a temporary path is fully isolated.
public struct LegacySettingsFiles: Sendable, Equatable {
    public var screenProfilesURL: URL
    public var looksURL: URL

    public init(screenProfilesURL: URL, looksURL: URL) {
        self.screenProfilesURL = screenProfilesURL
        self.looksURL = looksURL
    }

    /// `screen-profiles.json` and `looks.json` in `folder`.
    public init(folder: URL) {
        self.init(screenProfilesURL: folder.appendingPathComponent("screen-profiles.json"),
                  looksURL: folder.appendingPathComponent("looks.json"))
    }

    /// The folder of a library file.
    public init(libraryURL: URL) {
        self.init(folder: libraryURL.deletingLastPathComponent())
    }
}

/// A prop plus the security-scoped bookmark of its image file, as the old Looks file stored it.
struct LegacyStoredProp: Codable, Equatable {
    var prop: Prop
    var bookmark: Data?
}

/// The old Looks file: Looks, the selected one, and the props.
struct LegacyLookLibrary: Codable, Equatable {
    var looks: [Look]
    var selectedLookID: UUID?
    var props: [LegacyStoredProp]
}

enum LegacyRead<Value> {
    case missing
    case loaded(Value)
    case unreadable(String)
}

enum LegacySettings {
    static func readProfiles(_ url: URL) -> LegacyRead<[ScreenProfile]> {
        guard FileManager.default.fileExists(atPath: url.path) else { return .missing }
        do {
            let profiles = try JSONDecoder().decode([ScreenProfile].self, from: Data(contentsOf: url))
            return profiles.isEmpty ? .missing : .loaded(profiles)
        } catch {
            return .unreadable("\(url.lastPathComponent): \(error.localizedDescription)")
        }
    }

    static func readLooks(_ url: URL) -> LegacyRead<LegacyLookLibrary> {
        guard FileManager.default.fileExists(atPath: url.path) else { return .missing }
        do {
            return .loaded(try JSONDecoder().decode(LegacyLookLibrary.self, from: Data(contentsOf: url)))
        } catch {
            return .unreadable("\(url.lastPathComponent): \(error.localizedDescription)")
        }
    }
}
