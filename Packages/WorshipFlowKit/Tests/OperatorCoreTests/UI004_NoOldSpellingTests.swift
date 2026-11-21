// UI-004: no user-visible text in the app or its packages spells the product "WORSHIPFLOW" any more. The few places where the old
// spelling is data (the library folder, the Xcode project and scheme names) are listed here and nowhere else.
import Testing
import Foundation

@Suite struct UI004_NoOldSpellingTests {
    private static var repoRoot: URL {
        URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
    }

    /// Source files that may contain the old spelling, with why.
    private static let allowedFiles: [String: String] = [
        "Packages/WorshipFlowKit/Sources/Persistence/LibraryLocation.swift": "the library folder name is data, not a label",
    ]

    @Test func sourcesCarryNoOldSpellingExceptWhereItIsData() throws {
        let fm = FileManager.default
        var offenders: [String] = []
        for dir in ["App/Sources", "Packages/WorshipFlowKit/Sources"] {
            let base = Self.repoRoot.appendingPathComponent(dir)
            guard let e = fm.enumerator(at: base, includingPropertiesForKeys: nil) else { continue }
            for case let url as URL in e where url.pathExtension == "swift" && !url.path.contains("/DeckLinkC/") {
                let rel = String(url.path.dropFirst(Self.repoRoot.path.count + 1))
                if Self.allowedFiles[rel] != nil { continue }
                let text = try String(contentsOf: url, encoding: .utf8)
                if text.contains("WORSHIPFLOW") { offenders.append(rel) }
            }
        }
        #expect(offenders.isEmpty, "old spelling in: \(offenders.sorted())")
    }
}
