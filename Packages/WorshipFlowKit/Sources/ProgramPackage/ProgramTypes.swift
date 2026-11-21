// LIB-005: the public types of exporting and importing a program (errors, plans, summaries, hooks).
import Foundation
import Persistence

public enum ProgramPackageError: Error, Equatable, Sendable, LocalizedError {
    case notImplemented
    case playlistNotFound
    case notAProgramPackage(String)
    case newerFormat(found: Int, supported: Int)
    case manifestTooLarge(Int)
    case manifestUnreadable(String)
    case unsafePath(String)
    case linkNotAllowed(String)
    case packageFileMissing(String)
    case tooManyFiles(Int)
    case mediaDamaged(String)
    case mediaNameTaken(String)
    case destinationExists(String)
    case cancelled
    case copyFailed(String)
    case noLibraryFolder
    case builtInThemeClash(String)
    case notEnoughSpace(needed: Int64, available: Int64)
    case backupFailed(String)
    case destinationInsideLibrary
    case injected(String)

    public var errorDescription: String? {
        switch self {
        case .notImplemented: return "Not implemented yet."
        case .playlistNotFound: return "That playlist no longer exists."
        case .notAProgramPackage(let why): return "This is not a WorshipFlow program: \(why)"
        case .newerFormat(let found, let supported):
            return "This program was saved by a newer WorshipFlow (format \(found)); this version reads up to format \(supported). Update WorshipFlow on this Mac, then open it again. Nothing was imported."
        case .manifestTooLarge(let size): return "The program description is unusually large (\(size) bytes), so it was not opened. Nothing was imported."
        case .manifestUnreadable(let why): return "The program description could not be read: \(why) Nothing was imported."
        case .unsafePath(let path): return "The program names a file in a way that is not allowed (\(path)), so it was not opened. Nothing was imported."
        case .linkNotAllowed(let path): return "The program contains a link (\(path)) instead of a file, so it was not opened. Nothing was imported."
        case .packageFileMissing(let path): return "The program lists a file that is not in the package (\(path)). Nothing was imported."
        case .tooManyFiles(let n): return "The program lists \(n) media files, more than this version opens. Nothing was imported."
        case .mediaDamaged(let name): return "The file \(name) in the package is damaged or was changed. Nothing was imported."
        case .mediaNameTaken(let name): return "A different file already uses the name \(name) in the program's media folder. Nothing was imported."
        case .destinationExists(let name): return "\(name) already exists. Choose another name, or replace it deliberately."
        case .cancelled: return "Cancelled. Nothing was written."
        case .copyFailed(let why): return "A file could not be copied: \(why)"
        case .noLibraryFolder: return "This library has no folder to keep the program's media in."
        case .builtInThemeClash(let name):
            return "The program has a theme called \"\(name)\" that claims to be one of WorshipFlow's built-in themes, so it was not opened. Nothing was imported."
        case .notEnoughSpace(let needed, let available):
            let f = { (n: Int64) in ByteCountFormatter.string(fromByteCount: n, countStyle: .file) }
            return "There is not enough free space on this Mac's library drive to import this program: it needs about \(f(needed)) (with some room to spare) and \(f(available)) is free. Free some space, then import it again. Nothing was imported."
        case .backupFailed(let why):
            return "A backup of the library could not be written first (\(why)), so nothing was replaced and nothing was imported."
        case .destinationInsideLibrary:
            return "That place is inside WorshipFlow's own library folder, which the app manages. Choose another folder for the program, such as the Desktop or a USB stick."
        case .injected(let what): return what
        }
    }
}

/// Bytes done and total while files are copied.
public struct ProgramProgress: Sendable, Equatable {
    public var bytesDone: Int64
    public var bytesTotal: Int64
    public var filesDone: Int
    public var filesTotal: Int
    public init(bytesDone: Int64, bytesTotal: Int64, filesDone: Int, filesTotal: Int) {
        self.bytesDone = bytesDone
        self.bytesTotal = bytesTotal
        self.filesDone = filesDone
        self.filesTotal = filesTotal
    }
}

/// One file the export will copy. Identical files are listed once.
public struct ProgramExportFile: Sendable, Equatable {
    public var source: URL
    /// The package path, `media/<sha256>.<ext>`.
    public var packagePath: String
    public var name: String
    public var sha256: String
    public var size: Int64
    /// The source file's modification time when the plan was made, to notice a change before the copy.
    var modified: Double = 0
}

/// A file the program refers to that could not be read when the plan was made.
public struct ProgramMissingMedia: Sendable, Equatable {
    public var name: String
    public init(name: String) { self.name = name }
}

public struct ProgramExportPlan: Sendable {
    public var document: ProgramDocument
    public var files: [ProgramExportFile]
    public var missing: [ProgramMissingMedia]
    public var warnings: [String]
    /// FIX-G: the library's folder, so `write` can refuse a destination inside it.
    public var libraryFolder: URL?
    public var totalBytes: Int64 { files.reduce(0) { $0 + $1.size } }
    public var presentationCount: Int { document.presentations.count }
    public var itemCount: Int { document.items.count }
}

/// Seams for tests: a failure at a chosen point of writing a package.
public struct ProgramExportHooks: Sendable {
    /// Called after each media file is copied, with how many are done. A throw fails the export.
    public var afterFile: (@Sendable (Int) throws -> Void)?
    /// Called after everything is written into the temporary folder and before it is moved into place.
    public var beforeMove: (@Sendable () throws -> Void)?
    /// FIX-G: the size of the pieces a file is copied in where cloning is not used (one megabyte by default).
    public var chunkSize: Int?
    /// FIX-G: copy in pieces even where the file system could clone, as on another volume or a non-APFS one.
    public var cloneDisabled: Bool
    /// FIX-G: called with the size of every piece copied.
    public var onChunk: (@Sendable (Int64) -> Void)?
    public init(afterFile: (@Sendable (Int) throws -> Void)? = nil, beforeMove: (@Sendable () throws -> Void)? = nil,
                chunkSize: Int? = nil, cloneDisabled: Bool = false, onChunk: (@Sendable (Int64) -> Void)? = nil) {
        self.afterFile = afterFile
        self.beforeMove = beforeMove
        self.chunkSize = chunkSize
        self.cloneDisabled = cloneDisabled
        self.onChunk = onChunk
    }
    public static let none = ProgramExportHooks()
}

/// FIX-G: a seam for tests of planning.
public struct ProgramPlanHooks: Sendable {
    /// Called on the thread that hashed a file, after it was hashed, with the file's name.
    public var onHash: (@Sendable (String) -> Void)?
    public init(onHash: (@Sendable (String) -> Void)? = nil) { self.onHash = onHash }
    public static let none = ProgramPlanHooks()
}

/// A package that was read and checked, without anything being written.
public struct ProgramPackageContents: Sendable {
    public let url: URL
    public let document: ProgramDocument
    /// The files of `media/` that the document lists as included, by package path, with their size on disk.
    let files: [String: Int64]
}

/// FIX-G: what is on air or in use right now. A presentation that is live is never replaced by an import (both are kept), and
/// while anything is live a theme or Look that is in use is not replaced either.
public struct ProgramLiveContext: Sendable, Equatable {
    public var livePresentationIDs: Set<UUID>
    public var isShowLive: Bool
    public var themeIDsInUse: Set<UUID>
    public var lookIDsInUse: Set<UUID>
    public init(livePresentationIDs: Set<UUID> = [], isShowLive: Bool = false, themeIDsInUse: Set<UUID> = [], lookIDsInUse: Set<UUID> = []) {
        self.livePresentationIDs = livePresentationIDs
        self.isShowLive = isShowLive || !livePresentationIDs.isEmpty
        self.themeIDsInUse = themeIDsInUse
        self.lookIDsInUse = lookIDsInUse
    }
    public static let none = ProgramLiveContext()
}

/// What to do with an item whose id is already in the library with different content. One answer for the whole import.
public enum ProgramConflictChoice: Sendable, Equatable {
    case keepMine
    case useImported
    /// The imported copy gets a new id and " (imported)" in its title. The default and the safest.
    case keepBoth
    public static let `default`: ProgramConflictChoice = .keepBoth
}

public struct ProgramImportSummary: Sendable, Equatable {
    public enum PlaylistState: Sendable, Equatable { case new, alreadyPresent, conflicting }
    public var playlistName: String
    public var playlist: PlaylistState
    public var newPresentations: [String] = []
    public var alreadyPresent: [String] = []
    public var conflicting: [String] = []
    public var newThemes: Int = 0
    public var conflictingThemes: Int = 0
    public var newLooks: Int = 0
    public var conflictingLooks: Int = 0
    public var newMediaAssets: Int = 0
    public var mediaFilesToCopy: Int = 0
    public var mediaBytesToCopy: Int64 = 0
    public var mediaFilesAlreadyThere: Int = 0
    public var missingMedia: [String] = []
    /// Scripture items whose translation is not installed in this library (they import and show that state).
    public var scriptureNotInstalled: [String] = []
    /// FIX-G: the slide actions that would be imported, by kind (`media.playForeground`, `look.select`, ...) and how many of each.
    public var slideActionKinds: [String: Int] = [:]

    public var hasConflicts: Bool { !conflicting.isEmpty || conflictingThemes > 0 || conflictingLooks > 0 || playlist == .conflicting }
    /// Importing would change nothing.
    public var isNothingToImport: Bool {
        newPresentations.isEmpty && conflicting.isEmpty && newThemes == 0 && conflictingThemes == 0 && newLooks == 0
            && conflictingLooks == 0 && newMediaAssets == 0 && mediaFilesToCopy == 0 && playlist == .alreadyPresent
    }
}

public struct ProgramImportResult: Sendable, Equatable {
    /// The playlist in the library that now stands for the program (an existing one when it was kept).
    public var playlistID: UUID?
    public var presentationsAdded = 0
    public var presentationsReplaced = 0
    public var presentationsKeptAsCopies = 0
    /// FIX-G: titles of presentations that are live and so were not replaced; the imported version was kept beside them.
    public var keptBecauseLive: [String] = []
    /// FIX-G: where the library was backed up before something was replaced (nil when nothing was).
    public var backupURL: URL?
    /// Presentations whose stored content was replaced (the answer "use the imported one"), so an open copy can be reloaded.
    public var replacedPresentationIDs: [UUID] = []
    public var themesAdded = 0
    public var looksAdded = 0
    public var mediaAssetsAdded = 0
    public var mediaFilesCopied = 0
    public var mediaFilesReused = 0
    public var warnings: [String] = []
}

/// Seams for tests: a failure at a chosen point of an import.
public struct ProgramImportHooks: Sendable {
    /// Called after the media files are copied and before the database is touched.
    public var afterMediaCopied: (@Sendable () throws -> Void)?
    /// Called inside the database transaction after every row is written and before it commits.
    public var insideTransaction: (@Sendable () throws -> Void)?
    /// FIX-G: the clock used for the backup's name (the real date by default).
    public var now: (@Sendable () -> Date)?
    /// FIX-G: free space in bytes on the volume of the given folder; nil from it means unknown. The file system by default.
    public var freeSpace: (@Sendable (URL) -> Int64?)?
    /// FIX-G: the size of the pieces a media file is copied in (one megabyte by default); tests use a tiny one.
    public var chunkSize: Int?
    /// FIX-G: called with the size of every piece copied.
    public var onChunk: (@Sendable (Int64) -> Void)?
    public init(afterMediaCopied: (@Sendable () throws -> Void)? = nil, insideTransaction: (@Sendable () throws -> Void)? = nil,
                now: (@Sendable () -> Date)? = nil, freeSpace: (@Sendable (URL) -> Int64?)? = nil, chunkSize: Int? = nil,
                onChunk: (@Sendable (Int64) -> Void)? = nil) {
        self.afterMediaCopied = afterMediaCopied
        self.insideTransaction = insideTransaction
        self.now = now
        self.freeSpace = freeSpace
        self.chunkSize = chunkSize
        self.onChunk = onChunk
    }
    public static let none = ProgramImportHooks()
}
