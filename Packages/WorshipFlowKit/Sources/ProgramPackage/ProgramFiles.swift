// LIB-005: file helpers for the package: hashing, cloning and chunked copying with cancellation, and `lstat` checks.
// Foundation, CryptoKit and Darwin only.
import Foundation
import CryptoKit
import Darwin

enum ProgramFiles {
    static let chunkSize = 1 << 20

    struct Info {
        var size: Int64
        var isRegular: Bool
        var isSymlink: Bool
        var modified: Double
        /// Names the file has (`st_nlink`). A file this app writes into a package has one.
        var linkCount: Int = 1
    }

    /// `lstat`: describes the entry itself, never what a link points to. Nil when nothing is there.
    static func lstatInfo(_ url: URL) -> Info? {
        var st = stat()
        guard lstat(url.path, &st) == 0 else { return nil }
        let mode = st.st_mode & S_IFMT
        return Info(size: Int64(st.st_size), isRegular: mode == S_IFREG, isSymlink: mode == S_IFLNK,
                    modified: Double(st.st_mtimespec.tv_sec) + Double(st.st_mtimespec.tv_nsec) / 1e9, linkCount: Int(st.st_nlink))
    }

    /// `stat`: describes what a path leads to, following links (a library's own media files may be aliases).
    static func statInfo(_ path: String) -> Info? {
        var st = stat()
        guard stat(path, &st) == 0 else { return nil }
        let mode = st.st_mode & S_IFMT
        return Info(size: Int64(st.st_size), isRegular: mode == S_IFREG, isSymlink: false,
                    modified: Double(st.st_mtimespec.tv_sec) + Double(st.st_mtimespec.tv_nsec) / 1e9)
    }

    static func hex(_ digest: SHA256.Digest) -> String { digest.map { String(format: "%02x", $0) }.joined() }

    /// SHA-256 of a file, read in chunks.
    static func sha256(of url: URL, isCancelled: () -> Bool = { false }) throws -> String {
        let handle = try FileHandle(forReadingFrom: url)
        defer { try? handle.close() }
        var hasher = SHA256()
        while true {
            if isCancelled() { throw ProgramPackageError.cancelled }
            guard let data = try handle.read(upToCount: chunkSize), !data.isEmpty else { break }
            hasher.update(data: data)
        }
        return hex(hasher.finalize())
    }

    /// Copies `source` to `destination` (which must not exist), reading in chunks so a cancel is noticed within about one chunk.
    /// Returns the SHA-256 of what was written. `onBytes` gets the size of each piece. FIX-G: with a `limit` (the size the manifest
    /// states) the copy stops, before writing, as soon as the next piece would take it past that size.
    @discardableResult
    static func chunkedCopy(from source: URL, to destination: URL, chunkSize: Int = ProgramFiles.chunkSize, limit: Int64? = nil,
                            limitName: String = "a file", isCancelled: () -> Bool, onBytes: (Int64) -> Void) throws -> String {
        let reader = try FileHandle(forReadingFrom: source)
        defer { try? reader.close() }
        guard FileManager.default.createFile(atPath: destination.path, contents: nil) else {
            throw ProgramPackageError.copyFailed("\(destination.lastPathComponent) could not be created.")
        }
        let writer = try FileHandle(forWritingTo: destination)
        defer { try? writer.close() }
        var hasher = SHA256()
        var written: Int64 = 0
        while true {
            if isCancelled() { throw ProgramPackageError.cancelled }
            guard let data = try reader.read(upToCount: max(1, chunkSize)), !data.isEmpty else { break }
            if let limit, written + Int64(data.count) > limit { throw ProgramPackageError.mediaDamaged(limitName) }
            hasher.update(data: data)
            try writer.write(contentsOf: data)
            written += Int64(data.count)
            onBytes(Int64(data.count))
        }
        try writer.synchronize()
        return hex(hasher.finalize())
    }

    /// Clones `source` to `destination` where the file system can (APFS, same volume): instant and no extra space. Returns false
    /// when it cannot, and the caller copies instead.
    static func clone(from source: URL, to destination: URL) -> Bool {
        clonefile(source.path, destination.path, 0) == 0
    }
}
