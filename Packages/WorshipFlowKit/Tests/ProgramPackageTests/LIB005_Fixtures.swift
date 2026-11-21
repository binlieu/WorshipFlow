// LIB-005: shared fixtures. Everything is invented and generated in the test's own temporary folder.
import Testing
import Foundation
import CryptoKit
import GRDB
import Domain
@_spi(ProgramPackage) import Persistence
import ProgramPackage

final class Rig: @unchecked Sendable {
    let root: URL

    init() throws {
        root = FileManager.default.temporaryDirectory.appendingPathComponent("wf-lib005-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    }

    deinit { try? FileManager.default.removeItem(at: root) }

    func url(_ parts: String...) -> URL { parts.reduce(root) { $0.appendingPathComponent($1) } }

    func bytes(seed: Int, count: Int = 2_000) -> Data {
        Data((0..<count).map { UInt8(truncatingIfNeeded: $0 &* 31 &+ seed &* 7) })
    }

    @discardableResult
    func write(_ data: Data, to url: URL) throws -> URL {
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try data.write(to: url)
        return url
    }

    func openStore(_ folder: String) throws -> LibraryStore {
        try LibraryStore.open(at: url(folder, "Library.sqlite"))
    }

    /// Every file and folder below `base`, as paths relative to it, sorted. Empty when `base` does not exist.
    func listing(_ base: URL) -> [String] {
        guard let walker = FileManager.default.enumerator(atPath: base.path) else { return [] }
        return (walker.allObjects as? [String] ?? []).sorted()
    }
}

func sha256(_ data: Data) -> String { SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined() }

/// The program a church member prepares at home.
struct HomeProgram {
    let rig: Rig
    let store: LibraryStore
    let libraryID: UUID
    let playlistID: UUID
    let songOne: UUID
    let songTwo: UUID
    let themeID: UUID
    let lookID: UUID
    let assetID: UUID
    /// Where the pictures and the clip were kept: a folder standing for an external drive.
    let drive: URL
    let imageA: URL
    let imageB: URL        // the same bytes as imageA under another name
    let imageC: URL
    let background: URL
    let clip: URL
    let scriptureSpec: ScriptureItemSpec
    var items: [PlaylistItem]

    static let verseMarker = "ZZQ-INVENTED-VERSE-TEXT-93711"

    static func make(_ rig: Rig, folder: String = "home", withScripture: Bool = true) async throws -> HomeProgram {
        let store = try rig.openStore(folder)
        let drive = rig.url("ExternalDrive", "pictures")
        let imageA = try rig.write(rig.bytes(seed: 1), to: drive.appendingPathComponent("a.png"))
        let imageB = try rig.write(rig.bytes(seed: 1), to: drive.appendingPathComponent("copy of a.png"))
        let imageC = try rig.write(rig.bytes(seed: 2), to: drive.appendingPathComponent("c.jpg"))
        let background = try rig.write(rig.bytes(seed: 3), to: drive.appendingPathComponent("sky.png"))
        let clip = try rig.write(rig.bytes(seed: 4, count: 5_000), to: drive.appendingPathComponent("loop.mov"))

        let library = try await store.createLibrary(name: "Songs")
        let one = try await store.createPresentation(in: library.id, title: "Invented Song One", kind: .song)
        try await store.replaceContent(of: one.id, with: [
            ReflowResult(sectionName: "Verse 1", content: SlideContent(primary: "First line of verse", secondary: "Dòng đầu")),
            ReflowResult(sectionName: "Verse 1", content: SlideContent(primary: "Second line of verse")),
            ReflowResult(sectionName: "Chorus", content: SlideContent(primary: "Chorus words here")),
        ])
        var slides = try await store.slides(of: one.id)
        let textBox = SlideObject(frame: NormalizedRect(x: 0.1, y: 0.1, width: 0.5, height: 0.2),
                                  content: .text(TextObject(text: "A caption", style: Theme.fullScreen.primary.style)))
        slides[1].content.objects = [SlideObject(frame: NormalizedRect(x: 0, y: 0, width: 0.5, height: 0.5),
                                                 content: .image(ImageObject(path: imageA.path, contentMode: .fill)))]
        slides[1].notes = "Pause here"
        slides[2].content.objects = [
            SlideObject(frame: .full, content: .image(ImageObject(path: imageB.path))), textBox,
            SlideObject(frame: NormalizedRect(x: 0.5, y: 0.5, width: 0.3, height: 0.3), opacity: 0.5,
                        content: .image(ImageObject(path: imageC.path)))]
        for slide in slides { try await store.updateSlide(slide) }
        let groups = try await store.groups(of: one.id)
        let arrangement = try await store.createArrangement(for: one.id, name: "Short", groupIDs: [groups[1].id, groups[0].id])

        let two = try await store.createPresentation(in: library.id, title: "Invented Sermon", kind: .sermon)
        _ = try await store.appendSlide(to: two.id, content: SlideContent(primary: "Point one"))
        _ = try await store.appendSlide(to: two.id, content: SlideContent(primary: "Point two", secondary: "Ý hai"))

        let theme = Theme(id: UUID(), name: "Sky", background: .image(path: background.path),
                          primary: Theme.fullScreen.primary, secondary: nil)
        try await store.saveTheme(theme)
        try await store.setTheme(theme.id, forPresentation: two.id)
        let screen = UUID()
        let look = Look(id: UUID(), name: "Morning", screens: [screen: ScreenLook(themeID: theme.id, visibleLayers: [.slide, .background])])
        try await store.saveLook(look)
        let asset = try await store.addMediaAsset(name: "Loop", kind: .video, path: clip.path, bookmark: nil,
                                                  duration: 3, pixelWidth: 640, pixelHeight: 360)

        let actions = """
            {"version":1,"actions":[{"kind":"media.playForeground","assetID":"\(asset.id.uuidString.lowercased())"},\
            {"kind":"look.select","id":"\(look.id.uuidString.lowercased())"},{"kind":"future.thing","level":3}]}
            """
        let firstSlide = slides[0].id
        try await store.programWrite { db, _ in
            try db.execute(sql: "INSERT INTO cueSlideActions (slideID, definition, createdAt, updatedAt) VALUES (?, ?, ?, ?)",
                           arguments: [firstSlide.uuidString, actions, Date(), Date()])
        }

        let playlist = try await store.createPlaylist(name: "Sunday plan")
        var items: [PlaylistItem] = []
        items.append(try await store.addPlaylistHeader("Worship", to: playlist.id))
        items.append(try await store.addPresentation(one.id, to: playlist.id))
        try await store.setArrangement(arrangement.id, forPlaylistItem: items[1].id)
        items.append(try await store.addPlaylistCountdown(CountdownSpec(label: "Start", mode: .duration(seconds: 300)), to: playlist.id))
        items.append(try await store.addPresentation(two.id, to: playlist.id))
        let spec = ScriptureItemSpec(label: "John 3:16 (inv)", ranges: [.init(book: "JHN", startChapter: 3, startVerse: 16, endChapter: 3, endVerse: 16)],
                                     primaryCode: "inv-en", secondaryCode: "inv-vi")
        if withScripture {
            items.append(try await store.addPlaylistScripture(spec, to: playlist.id))
            try await store.programWrite { db, _ in
                try db.execute(sql: """
                    INSERT INTO scriptureTranslation (id, code, name, language, abbreviation, isPublicDomain, versificationID, verseCount, importedAt)
                    VALUES (?, 'inv-en', 'Invented', 'en', 'INV', 1, 'KJV', 1, ?)
                    """, arguments: [UUID().uuidString, Date()])
                let id = try String.fetchOne(db, sql: "SELECT id FROM scriptureTranslation WHERE code = 'inv-en'")!
                try db.execute(sql: """
                    INSERT INTO scriptureVerse (translationID, bookOrder, chapter, verse, text, textFolded) VALUES (?, 43, 3, 16, ?, ?)
                    """, arguments: [id, HomeProgram.verseMarker, HomeProgram.verseMarker.lowercased()])
            }
        }
        return HomeProgram(rig: rig, store: store, libraryID: library.id, playlistID: playlist.id, songOne: one.id, songTwo: two.id,
                           themeID: theme.id, lookID: look.id, assetID: asset.id, drive: drive, imageA: imageA, imageB: imageB,
                           imageC: imageC, background: background, clip: clip, scriptureSpec: spec, items: items)
    }

    /// Exports the playlist to `<rig>/<name>.worshipflowprogram` and returns the package URL.
    @discardableResult
    func export(as name: String = "Sunday") async throws -> URL {
        let plan = try await ProgramExporter.plan(store: store, playlistID: playlistID, appVersion: "9.9.9")
        let destination = rig.url("\(name).\(ProgramFormat.fileExtension)")
        try ProgramExporter.write(plan, to: destination)
        return destination
    }
}

/// How many rows each table of a library holds, for "nothing changed" checks.
func rowCounts(_ store: LibraryStore) async throws -> [String: Int] {
    try await store.programRead { db in
        var counts: [String: Int] = [:]
        for table in ["library", "presentation", "slide", "slideGroup", "arrangement", "arrangementItem", "playlist", "playlistItem",
                      "theme", "look", "mediaAsset", "cueSlideActions", "scriptureTranslation", "scriptureVerse"] {
            counts[table] = try Int.fetchOne(db, sql: "SELECT COUNT(*) FROM \(table)") ?? -1
        }
        return counts
    }
}

/// A playlist described in words that do not depend on ids or on where files are kept, so two libraries can be compared.
func describe(_ store: LibraryStore, playlist id: UUID) async throws -> [String] {
    var lines: [String] = []
    let name = try await store.playlists().first { $0.id == id }?.name ?? "?"
    lines.append("playlist \(name)")
    let items = try await store.playlistItems(of: id)
    let themes = try await store.themes()
    for item in items {
        switch item.kind {
        case .header(let label): lines.append("header \(label)")
        case .countdown(let spec): lines.append("countdown \(spec.label) \(spec.mode)")
        case .scripture(let spec): lines.append("scripture \(spec)")
        // UI-005b: three new kinds; the switch must name them (existing lines unchanged).
        case .sermon: lines.append("sermon \(item.title)")
        case .media(let spec): lines.append("media \(spec.name) \(spec.kind)")
        case .announcements(let spec): lines.append("announcements \(spec.label) \(spec.items.map(\.name)) \(spec.secondsPerPicture)")
        case .presentation:
            lines.append("presentation \(item.title)")
            let groups = try await store.groups(of: item.presentationID)
            let names = Dictionary(uniqueKeysWithValues: groups.map { ($0.id, $0.name) })
            let arrangements = try await store.arrangements(of: item.presentationID)
            let chosen = arrangements.first { $0.id == item.arrangementID }
            lines.append("  arrangement \(chosen?.name ?? "-") \((chosen?.groupIDs ?? []).map { names[$0] ?? "?" })")
            for a in arrangements { lines.append("  has arrangement \(a.name) \(a.groupIDs.map { names[$0] ?? "?" })") }
            for slide in try await store.slides(of: item.presentationID) {
                var line = "  slide \(slide.content.primary) | \(slide.content.secondary ?? "-") | \(slide.notes) | \(slide.groupID.flatMap { names[$0] } ?? "-")"
                for object in slide.content.objects {
                    switch object.content {
                    case .image(let image):
                        let data = FileManager.default.contents(atPath: image.path)
                        line += " [image \(image.contentMode) \(object.frame) \(object.opacity) \(data.map(sha256) ?? "MISSING")]"
                    default: line += " [\(object.content) \(object.frame)]"
                    }
                }
                lines.append(line)
            }
            let theme = try await store.presentationThemeID(item.presentationID)
            if let theme, let t = themes.first(where: { $0.id == theme }) {
                if case .image(let path) = t.background {
                    lines.append("  theme \(t.name) image \(FileManager.default.contents(atPath: path).map(sha256) ?? "MISSING")")
                } else { lines.append("  theme \(t.name)") }
            }
        }
    }
    return lines
}

extension LibraryStore {
    func presentationThemeID(_ id: UUID) async throws -> UUID? {
        try await programRead { db in
            try String.fetchOne(db, sql: "SELECT themeID FROM presentation WHERE id = ?", arguments: [id.uuidString]).flatMap(UUID.init(uuidString:))
        }
    }
}

/// A counter the Sendable closures can share.
final class Counter: @unchecked Sendable {
    private let lock = NSLock()
    private var value = 0
    @discardableResult func next() -> Int { lock.lock(); defer { lock.unlock() }; value += 1; return value }
    var count: Int { lock.lock(); defer { lock.unlock() }; return value }
}

struct Boom: Error, Equatable {}
