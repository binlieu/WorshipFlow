// TESTDATA-001: reads the synthetic songs written by scripts/make-test-data.py. A song is "<title>.txt" (the pasted lyrics of the
// import sheet: section labels such as "Verse 1" and "Chorus", blocks separated by blank lines) and, for a two-language song,
// "<title>.vi.txt" (the second language, the same blocks in the same order). The title is the file name without its extension.
import Foundation
import Domain
import Persistence

public struct SongFile: Sendable, Equatable {
    public var title: String
    public var primary: String
    public var secondary: String?
    public init(title: String, primary: String, secondary: String?) { self.title = title; self.primary = primary; self.secondary = secondary }
}

public enum SongFiles {
    /// The import sheet's "lines per slide" default. The slides of a song come from `Reflow.contents`, the sheet's own splitter.
    public static let linesPerSlide = 2
    public static let secondarySuffix = ".vi.txt"

    public static func read(folder: URL) throws -> [SongFile] {
        let names = try FileManager.default.contentsOfDirectory(atPath: folder.path)
            .filter { $0.hasSuffix(".txt") && !$0.hasSuffix(secondarySuffix) && !$0.hasPrefix(".") }
            .sorted()
        return try names.map { name in
            let title = String(name.dropLast(".txt".count))
            let primary = try String(contentsOf: folder.appendingPathComponent(name), encoding: .utf8)
            let other = folder.appendingPathComponent(title + secondarySuffix)
            let secondary = FileManager.default.fileExists(atPath: other.path) ? try String(contentsOf: other, encoding: .utf8) : nil
            return SongFile(title: title, primary: primary, secondary: secondary)
        }
    }

    public static func specs(_ songs: [SongFile], linesPerSlide: Int = linesPerSlide) -> [LibraryStore.SongSpec] {
        songs.map { LibraryStore.SongSpec(title: $0.title, results: Reflow.contents(primary: $0.primary, secondary: $0.secondary, maxLines: linesPerSlide)) }
    }
}
