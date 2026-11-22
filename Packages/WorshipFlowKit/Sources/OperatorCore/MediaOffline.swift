// UI-006d: bin files that cannot be read now (the design's "1 file is offline" callout with Locate...). Pure decisions: the words and
// which other offline files move with the one the operator found. Foundation and Domain only.
import Foundation
import Domain

public enum MediaOffline {
    public struct Summary: Equatable, Sendable {
        public var headline: String
        public var detail: String?
    }

    public struct Move: Equatable, Sendable {
        public var assetID: UUID
        public var newPath: String
        public init(assetID: UUID, newPath: String) { self.assetID = assetID; self.newPath = newPath }
    }

    /// Why the file is not there, as far as the path tells: a disk that is not connected, or a file that is not at its place.
    public static func reason(forPath path: String, directoryExists: (String) -> Bool) -> String {
        let parts = path.split(separator: "/", omittingEmptySubsequences: true)
        if parts.count >= 3, parts[0] == "Volumes" {
            let volume = String(parts[1])
            if !directoryExists("/Volumes/\(volume)") { return "the disk \"\(volume)\" is not connected." }
        }
        return "the file is not there any more (moved, renamed or deleted)."
    }

    private static func fileName(_ asset: MediaAsset) -> String { URL(fileURLWithPath: asset.path).lastPathComponent }

    /// Nil when nothing is offline. One file: its name and the reason. Several: two names and the count of the rest.
    public static func summary(offline: [MediaAsset], directoryExists: (String) -> Bool) -> Summary? {
        guard let first = offline.first else { return nil }
        if offline.count == 1 {
            return Summary(headline: "1 file is offline", detail: "\(fileName(first)) \u{2014} \(reason(forPath: first.path, directoryExists: directoryExists))")
        }
        let rest = offline.count - 2
        let names = rest > 0 ? "\(fileName(offline[0])), \(fileName(offline[1])) and \(rest) more." : "\(fileName(offline[0])) and \(fileName(offline[1]))."
        return Summary(headline: "\(offline.count) files are offline", detail: names)
    }

    /// The operator found `target`'s file at `chosen`. Other offline items that were in the same folder as the target move with it when a
    /// file of the same name is in the chosen file's folder (a disk that came back under another name or place). Nothing else moves.
    public static func relocationPlan(target: MediaAsset, chosen: String, offline: [MediaAsset], fileExists: (String) -> Bool) -> [Move] {
        var moves = [Move(assetID: target.id, newPath: chosen)]
        let oldFolder = (target.path as NSString).deletingLastPathComponent
        let newFolder = (chosen as NSString).deletingLastPathComponent
        for other in offline where other.id != target.id && (other.path as NSString).deletingLastPathComponent == oldFolder {
            let path = newFolder + "/" + (other.path as NSString).lastPathComponent
            if path != chosen, fileExists(path) { moves.append(Move(assetID: other.id, newPath: path)) }
        }
        return moves
    }
}
