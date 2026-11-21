// LIB-005: media kept relative to the library's folder, and the narrow door `ProgramPackage` uses to reach the library's tables
// through this store's one connection pool (ADR-0004 decision 2: one pool per file, never a second).
//
// Media that a program import copies lives under `<library folder>/Media/Imported/<program id>/`. The library refers to it
// by a path that starts with `Media/Imported/` and is relative to the library's folder, so it still resolves after the whole
// folder is moved to another place or another Mac. The store turns such a path into an absolute one when it reads, and back
// into the relative one when it writes, so the rest of the app only ever sees absolute paths. Every other path (the user's
// own files, wherever they are) passes through untouched.
import Foundation
import GRDB
import Domain

struct MediaPathMapper: Sendable, Equatable {
    static let managedPrefix = "Media/Imported/"
    /// The library's folder, without a trailing slash.
    let root: String

    init(libraryFolder: URL) {
        var path = libraryFolder.standardizedFileURL.path
        while path.count > 1, path.hasSuffix("/") { path.removeLast() }
        root = path
    }

    /// A stored path as the app should use it: absolute. A relative path with a `..` part is left alone (it cannot resolve).
    func runtime(_ path: String) -> String {
        guard path.hasPrefix(Self.managedPrefix), !path.split(separator: "/").contains("..") else { return path }
        return root + "/" + path
    }

    /// A path as it is stored: relative when it lies inside this library's managed media folder, else unchanged.
    func stored(_ path: String) -> String {
        let prefix = root + "/" + Self.managedPrefix
        guard path.hasPrefix(prefix), !path.split(separator: "/").contains("..") else { return path }
        return String(path.dropFirst(root.count + 1))
    }

    func runtime(_ objects: [SlideObject]) -> [SlideObject] { map(objects, runtime) }
    func stored(_ objects: [SlideObject]) -> [SlideObject] { map(objects, stored) }

    private func map(_ objects: [SlideObject], _ f: (String) -> String) -> [SlideObject] {
        objects.map { object in
            guard case .image(var image) = object.content else { return object }
            image.path = f(image.path)
            var copy = object
            copy.content = .image(image)
            return copy
        }
    }

    func runtime(_ theme: Theme) -> Theme { map(theme, runtime) }
    func stored(_ theme: Theme) -> Theme { map(theme, stored) }

    private func map(_ theme: Theme, _ f: (String) -> String) -> Theme {
        guard case .image(let path) = theme.background else { return theme }
        var copy = theme
        copy.background = .image(path: f(path))
        return copy
    }
}

extension LibraryStore {
    func runtimeObjects(_ objects: [SlideObject]) -> [SlideObject] { mediaPaths?.runtime(objects) ?? objects }
    func storedObjects(_ objects: [SlideObject]) -> [SlideObject] { mediaPaths?.stored(objects) ?? objects }
    func runtimeSlide(_ slide: Slide) -> Slide {
        guard let mediaPaths, !slide.content.objects.isEmpty else { return slide }
        var copy = slide
        copy.content.objects = mediaPaths.runtime(slide.content.objects)
        return copy
    }
    func runtimeTheme(_ theme: Theme) -> Theme { mediaPaths?.runtime(theme) ?? theme }
    func storedTheme(_ theme: Theme) -> Theme { mediaPaths?.stored(theme) ?? theme }
    func runtimeAsset(_ asset: MediaAsset) -> MediaAsset {
        guard let mediaPaths else { return asset }
        var copy = asset
        copy.path = mediaPaths.runtime(asset.path)
        return copy
    }
    func runtimePath(_ path: String) -> String { mediaPaths?.runtime(path) ?? path }
    func storedPath(_ path: String) -> String { mediaPaths?.stored(path) ?? path }
}

/// What a write inside `programWrite` may ask the store to do that needs its internals.
@_spi(ProgramPackage)
public struct ProgramWriteTools: Sendable {
    let backend: LibraryStore.SearchBackend

    /// Recomputes a presentation's folded search text. Call after its slides changed, inside the same transaction.
    public func reindex(_ db: Database, presentationID: UUID) throws {
        try SearchIndex.reindex(db, backend: backend, presentationID: presentationID)
    }

    /// The JSON the `theme.definition` column holds.
    public func themeDefinition(_ theme: Theme) throws -> String { try SettingsJSON.encode(theme) }

    /// The JSON the `look.screens` column holds.
    public func lookScreens(_ screens: [UUID: ScreenLook]) throws -> String { try SettingsJSON.encodeScreens(screens) }

    /// The text the `slide.objects` column holds (nil for none). Paths are given as they should be stored.
    public func slideObjects(_ objects: [SlideObject]) -> String? { SlideObjectsJSON.encode(objects) }

    /// The text the `slide.background` column holds (nil for none), as for a slide written by the store itself.
    public func slideBackground(_ selection: MediaSelection?) -> String? { SlideBackgroundJSON.encode(selection) }

    /// True once migration v5 has added `slide.objects`.
    public func hasObjectsColumn(_ db: Database) throws -> Bool { try SearchIndex.slideHasObjectsColumn(db) }
}

@_spi(ProgramPackage)
extension LibraryStore {
    /// The folder the library file lives in, when the store is a file. Imported media goes below it.
    public var libraryFolder: URL? { mediaPaths.map { URL(fileURLWithPath: $0.root, isDirectory: true) } }

    /// The stored form of a media path (relative when inside `Media/Imported`), for values `ProgramPackage` writes itself.
    public func storedMediaPath(_ absolute: String) -> String { storedPath(absolute) }

    /// Reads through this store's pool. For `ProgramPackage` only.
    public func programRead<T: Sendable>(_ body: @Sendable (Database) throws -> T) async throws -> T {
        try await writer.read(body)
    }

    /// Runs `body` in one transaction on this store's pool: it commits when `body` returns and rolls back everything when
    /// it throws. For `ProgramPackage` only.
    public func programWrite<T: Sendable>(_ body: @Sendable (Database, ProgramWriteTools) throws -> T) async throws -> T {
        let tools = ProgramWriteTools(backend: searchBackend)
        return try await writer.write { db in try body(db, tools) }
    }
}
