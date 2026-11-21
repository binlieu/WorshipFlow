// LIB-005: reading a playlist and what it needs out of a library into `ProgramDocument` entries. Used to write a package and
// to compare what a package holds with what the library already has.
import Foundation
import GRDB
import Domain
import CueEngine
@_spi(ProgramPackage) import Persistence

/// Turns the paths a library holds into package paths, hashing each file once. The same bytes get the same package path, so
/// identical files are stored once.
struct MediaCollector {
    /// FIX-G: polled between files and inside a file's hashing; a true answer ends the plan with `cancelled`.
    var isCancelled: @Sendable () -> Bool = { false }
    /// FIX-G: called, on the thread that hashed, after each file is hashed.
    var onHash: (@Sendable (String) -> Void)?
    private var cache: [String: String] = [:]
    private(set) var files: [ProgramExportFile] = []
    private(set) var entries: [ProgramDocument.MediaEntry] = []
    private var known: Set<String> = []

    /// The package path for a library path: `media/<sha256>.<ext>` for a readable file, `media/missing/<name>` otherwise.
    mutating func reference(_ path: String) async throws -> String {
        if let hit = cache[path] { return hit }
        if isCancelled() { throw ProgramPackageError.cancelled }
        let name = ProgramPathRules.safeName((path as NSString).lastPathComponent)
        var result = "\(ProgramFormat.mediaFolder)/missing/\(name)"
        var digest: String?
        let info = path.hasPrefix("/") ? ProgramFiles.statInfo(path) : nil
        if let info, info.isRegular { digest = try await Self.hashAtUtilityPriority(URL(fileURLWithPath: path), isCancelled: isCancelled, onHash: onHash) }
        if let info, let digest {
            let ext = ProgramPathRules.safeExtension(of: name)
            result = "\(ProgramFormat.mediaFolder)/\(digest)" + (ext.isEmpty ? "" : ".\(ext)")
            if known.insert(result).inserted {
                files.append(ProgramExportFile(source: URL(fileURLWithPath: path), packagePath: result, name: name, sha256: digest,
                                               size: info.size, modified: info.modified))
                entries.append(.init(file: result, name: name, status: .included, sha256: digest, size: info.size))
            }
        } else if known.insert(result).inserted {
            entries.append(.init(file: result, name: name, status: .missing, sha256: nil, size: nil))
        }
        cache[path] = result
        return result
    }

    /// FIX-G: hashing reads whole files, so it runs on a utility-priority queue and never keeps an operator's thread busy. A file
    /// that cannot be read answers nil (it is recorded as missing); a cancel throws.
    private static func hashAtUtilityPriority(_ url: URL, isCancelled: @escaping @Sendable () -> Bool,
                                              onHash: (@Sendable (String) -> Void)?) async throws -> String? {
        try await withCheckedThrowingContinuation { continuation in
            DispatchQueue.global(qos: .utility).async {
                do {
                    let digest = try ProgramFiles.sha256(of: url, isCancelled: isCancelled)
                    onHash?(url.lastPathComponent)
                    continuation.resume(returning: digest)
                } catch ProgramPackageError.cancelled {
                    continuation.resume(throwing: ProgramPackageError.cancelled)
                } catch {
                    continuation.resume(returning: nil)
                }
            }
        }
    }

    var missingNames: [String] { entries.filter { $0.status == .missing }.map(\.name) }
}

/// The ids a presentation's slide actions refer to.
struct ActionReferences {
    var assets: [UUID] = []
    var looks: [UUID] = []
    /// Kinds of action that point at things a program does not carry (macros, props, timers, messages).
    var notCarried: Set<String> = []
    /// FIX-G: slides whose own background names a bin item that is no longer in the library.
    var lostBackgrounds = 0

    mutating func add(_ json: JSONValue) {
        guard let data = try? JSONEncoder().encode(json), let list = try? JSONDecoder().decode(CueActionList.self, from: data) else { return }
        for action in list.actions {
            switch action {
            case .playForeground(let id), .playAudio(let id), .stopAudio(let id): assets.append(id)
            case .setBackground(let id): if let id { assets.append(id) }
            case .selectLook(let id): looks.append(id)
            case .runMacro: notCarried.insert("macros")
            case .prop: notCarried.insert("props")
            case .startTimer, .pauseTimer, .resetTimer: notCarried.insert("timers")
            case .showMessage, .hideMessage: notCarried.insert("stage messages")
            default: break
            }
        }
    }
}

enum ProgramSnapshot {
    /// One presentation as a package entry. Image paths become package paths through `collector`.
    static func presentation(_ id: UUID, in store: LibraryStore, collector: inout MediaCollector,
                             references: inout ActionReferences) async throws -> ProgramDocument.PresentationEntry? {
        let key = id.uuidString
        let head = try await store.programRead { db in
            try Row.fetchOne(db, sql: "SELECT title, kind, themeID FROM presentation WHERE id = ?", arguments: [key])
                .map { row in (title: row["title"] as String, kind: row["kind"] as String, theme: row["themeID"] as String?) }
        }
        guard let head else { return nil }
        let actionRows = try await store.programRead { db in
            try Row.fetchAll(db, sql: """
                SELECT a.slideID AS slideID, a.definition AS definition FROM cueSlideActions a
                JOIN slide s ON s.id = a.slideID WHERE s.presentationID = ?
                """, arguments: [key]).map { ($0["slideID"] as String, $0["definition"] as String) }
        }
        var actions: [UUID: JSONValue] = [:]
        for (slide, text) in actionRows {
            if let uuid = UUID(uuidString: slide), let json = JSONValue.parse(text) { actions[uuid] = json }
        }
        let binAssets = Dictionary(try await store.mediaAssets(kind: nil).map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        var slides: [ProgramDocument.SlideEntry] = []
        for slide in try await store.slides(of: id) {
            var objects: [SlideObject] = []
            for object in slide.content.objects {
                guard case .image(var image) = object.content else { objects.append(object); continue }
                image.path = try await collector.reference(image.path)
                var copy = object
                copy.content = .image(image)
                objects.append(copy)
            }
            let json = actions[slide.id]
            if let json { references.add(json) }
            // FIX-G: the slide's own background: its bin item travels in `mediaAssets`, its file in `media/`.
            var background: ProgramDocument.BackgroundEntry?
            if let own = slide.content.background {
                if let asset = binAssets[own.assetID] {
                    references.assets.append(asset.id)
                    background = .init(assetID: asset.id, kind: own.kind, duration: own.duration, file: try await collector.reference(asset.path))
                } else {
                    references.lostBackgrounds += 1
                }
            }
            slides.append(.init(id: slide.id, primary: slide.content.primary, secondary: slide.content.secondary, notes: slide.notes,
                                groupID: slide.groupID, objects: objects, actions: json, background: background))
        }
        let groups = try await store.groups(of: id).map { ProgramDocument.GroupEntry(id: $0.id, name: $0.name) }
        let arrangements = try await store.arrangements(of: id).map {
            ProgramDocument.ArrangementEntry(id: $0.id, name: $0.name, groupIDs: $0.groupIDs)
        }
        return .init(id: id, title: head.title, kind: PresentationKind(rawValue: head.kind) ?? .other,
                     themeID: head.theme.flatMap(UUID.init(uuidString:)), slides: slides, groups: groups, arrangements: arrangements)
    }

    static func theme(_ theme: Theme, collector: inout MediaCollector) async throws -> Theme {
        guard case .image(let path) = theme.background else { return theme }
        var copy = theme
        copy.background = .image(path: try await collector.reference(path))
        return copy
    }

    /// A Look as a package entry. `profiles` are this Mac's screen profiles: each screen the Look names is recorded with its role
    /// (audience, stage, broadcast), because the profile ids belong to this Mac only (FIX-G item 10).
    static func lookEntry(_ look: Look, profiles: [ScreenProfile] = []) -> ProgramDocument.LookEntry {
        var screens: [String: ProgramDocument.LookEntry.Screen] = [:]
        var roles: [String: String] = [:]
        for (id, screen) in look.screens {
            screens[id.uuidString] = .init(themeID: screen.themeID, visibleLayers: screen.visibleLayers.map(\.rawValue).sorted())
            if let profile = profiles.first(where: { $0.id == id }) { roles[id.uuidString] = profile.role.rawValue }
        }
        return .init(id: look.id, name: look.name, screens: screens, roles: roles)
    }

    static func item(_ item: PlaylistItem) -> ProgramDocument.ItemEntry {
        switch item.kind {
        case .presentation:
            return .init(id: item.id, kind: "presentation", presentationID: item.presentationID, arrangementID: item.arrangementID)
        case .header(let label): return .init(id: item.id, kind: "header", label: label)
        case .countdown(let spec): return .init(id: item.id, kind: "countdown", countdown: spec)
        case .scripture(let spec): return .init(id: item.id, kind: "scripture", scripture: spec)
        }
    }

    /// What a playlist item entry means in the library's own terms.
    static func kind(of entry: ProgramDocument.ItemEntry) -> PlaylistItemKind? {
        switch entry.kind {
        case "presentation": return .presentation
        case "header": return .header(label: entry.label ?? "")
        case "countdown": return entry.countdown.map { .countdown($0) }
        case "scripture": return entry.scripture.map { .scripture($0) }
        default: return nil
        }
    }

    /// The part of a presentation that makes it "the same" or "different": text, sections, arrangements, objects, actions, theme.
    /// Ids of slides, sections and arrangements are left out; sections are named.
    struct ContentKey: Equatable {
        struct SlideKey: Equatable {
            var primary: String
            var secondary: String?
            var notes: String
            var group: String?
            var objects: [SlideObject]
            var actions: JSONValue?
            /// The package path of the background's file (ids of bin items differ between libraries, bytes do not).
            var background: String?
        }
        struct ArrangementKey: Equatable {
            var name: String
            var groups: [String]
        }
        var title: String
        var kind: PresentationKind
        var themeID: UUID?
        var slides: [SlideKey]
        var arrangements: [ArrangementKey]
    }

    static func contentKey(_ p: ProgramDocument.PresentationEntry) -> ContentKey {
        let names = Dictionary(p.groups.map { ($0.id, $0.name) }, uniquingKeysWith: { first, _ in first })
        return .init(title: p.title, kind: p.kind, themeID: p.themeID,
                     slides: p.slides.map { .init(primary: $0.primary, secondary: $0.secondary, notes: $0.notes,
                                                  group: $0.groupID.flatMap { names[$0] }, objects: $0.objects, actions: $0.actions,
                                                  background: $0.background?.file) },
                     arrangements: p.arrangements.map { .init(name: $0.name, groups: $0.groupIDs.map { names[$0] ?? "" }) })
    }
}
