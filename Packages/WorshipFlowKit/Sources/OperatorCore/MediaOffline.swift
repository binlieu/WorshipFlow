// UI-006d: bin files that cannot be read now (the design's "1 file is offline" callout with Locate...). Pure decisions: the words and
// which other offline files move with the one the operator found. Foundation and Domain only.
import Foundation
import Domain

public enum MediaOffline {
    // FIX-V item 6 (L8): when coming forward is a reason to look at the files again.

    /// What the last check looked at: the bin's file paths and the disks that were connected.
    public struct Signature: Equatable, Sendable {
        public var paths: [String]
        public var volumes: [String]
        public init(paths: [String], volumes: [String]) { self.paths = paths; self.volumes = volumes }
    }

    public struct LastCheck: Equatable, Sendable {
        public var signature: Signature
        public var at: Date
        public init(signature: Signature, at: Date) { self.signature = signature; self.at = at }
    }

    /// Seconds after which an unchanged bin on unchanged disks is looked at again when the app comes forward (a file can be renamed on the same
    /// disk). A burst of activations inside that time is no check at all.
    public static let activationInterval: TimeInterval = 60

    /// FIX-Y (REVIEW-5 L16): seconds one volume may take to answer a check before the check gives up on it (for that round) and goes on with the others.
    public static let volumeReadLimit: TimeInterval = 8

    /// The volume a path is on, as far as the path tells: "/Volumes/<name>" for a mounted disk, "/" for everything else (the startup disk).
    public static func volume(of path: String) -> String {
        let parts = path.split(separator: "/", omittingEmptySubsequences: true)
        if parts.count >= 3, parts[0] == "Volumes" { return "/Volumes/\(parts[1])" }
        return "/"
    }

    /// Whether coming forward starts a check: the first one, a bin or set of disks that changed, or a last check that is old.
    public static func shouldCheckOnActivation(last: LastCheck?, now: Date, signature: Signature) -> Bool {
        guard let last else { return true }
        return last.signature != signature || now.timeIntervalSince(last.at) >= activationInterval
    }

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
