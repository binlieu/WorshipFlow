// UI-004: which build this is. The version, the build number, the short git commit and the build date come from the app's
// Info.plist; the commit and date are written into the BUILT plist by the build (never into a tracked file). A build made
// without git carries neither and reads as a development build. The About window, the Hardware Test report and summary.txt
// all print `line` or `detail`, so a person who reads one out is naming the build that made it.
import Foundation

public struct BuildInfo: Equatable, Sendable {
    public static let commitKey = "WFBuildCommit"
    public static let dateKey = "WFBuildDate"

    public let version: String
    public let build: String
    /// Short commit, `-dirty` after it when the tree had uncommitted changes. Nil when the build had no git.
    public let commit: String?
    /// `yyyy-MM-dd`, or nil.
    public let date: String?

    public init(infoDictionary: [String: Any]?) {
        func text(_ key: String) -> String? {
            guard let raw = infoDictionary?[key] as? String else { return nil }
            let t = raw.trimmingCharacters(in: .whitespacesAndNewlines)
            // An unexpanded build setting ("$(MARKETING_VERSION)") or an empty value is not a version.
            return t.isEmpty || t.hasPrefix("$(") ? nil : t
        }
        version = text("CFBundleShortVersionString") ?? "unknown"
        build = text("CFBundleVersion") ?? "unknown"
        commit = text(Self.commitKey).flatMap { Self.matches($0, #"^[0-9a-f]{7,40}(-dirty)?$"#) ? $0 : nil }
        date = text(Self.dateKey).flatMap { Self.matches($0, #"^\d{4}-\d{2}-\d{2}$"#) ? $0 : nil }
    }

    /// The running app's own build.
    public static var current: BuildInfo { BuildInfo(infoDictionary: Bundle.main.infoDictionary) }

    public var isDevelopmentBuild: Bool { commit == nil }

    /// `commit 71d344d, built 2026-11-21`, or `development build`.
    public var detail: String {
        guard let commit else { return "development build" }
        return "commit \(commit)" + (date.map { ", built \($0)" } ?? "")
    }

    /// `WorshipFlow 0.0.1 (build 41), commit 71d344d, built 2026-11-21`.
    public var line: String { "WorshipFlow \(version) (build \(build)), \(detail)" }

    private static func matches(_ text: String, _ pattern: String) -> Bool {
        text.range(of: pattern, options: .regularExpression) != nil
    }
}
