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
    private var cache: [String: String] = [:]
    private(set) var files: [ProgramExportFile] = []
    private(set) var entries: [ProgramDocument.MediaEntry] = []
    private var known: Set<String> = []

    /// The package path for a library path: `media/<sha256>.<ext>` for a readable file, `media/missing/<name>` otherwise.
    mutating func reference(_ path: String) -> String {
        if let hit = cache[path] { return hit }
        let name = ProgramPathRules.safeName((path as NSString).lastPathComponent)
        var result = "\(ProgramFormat.mediaFolder)/missing/\(name)"
        if path.hasPrefix("/"), let info = ProgramFiles.statInfo(path), info.isRegular,
           let digest = try? ProgramFiles.sha256(of: URL(fileURLWithPath: path)) {
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

    var missingNames: [String] { entries.filter { $0.status == .missing }.map(\.name) }
}

/// The ids a presentation's slide actions refer to.
struct ActionReferences {
    var assets: [UUID] = []
    var looks: [UUID] = []
    /// Kinds of action that point at things a program does not carry (macros, props, timers, messages).
    var notCarried: Set<String> = []

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
        let slides = try await store.slides(of: id).map { slide -> ProgramDocument.SlideEntry in
            let objects = slide.content.objects.map { object -> SlideObject in
                guard case .image(var image) = object.content else { return object }
                image.path = collector.reference(image.path)
                var copy = object
                copy.content = .image(image)
                return copy
            }
            let json = actions[slide.id]
            if let json { references.add(json) }
            return .init(id: slide.id, primary: slide.content.primary, secondary: slide.content.secondary, notes: slide.notes,
                         groupID: slide.groupID, objects: objects, actions: json)
        }
        let groups = try await store.groups(of: id).map { ProgramDocument.GroupEntry(id: $0.id, name: $0.name) }
        let arrangements = try await store.arrangements(of: id).map {
            ProgramDocument.ArrangementEntry(id: $0.id, name: $0.name, groupIDs: $0.groupIDs)
        }
        return .init(id: id, title: head.title, kind: PresentationKind(rawValue: head.kind) ?? .other,
                     themeID: head.theme.flatMap(UUID.init(uuidString:)), slides: slides, groups: groups, arrangements: arrangements)
    }

    static func theme(_ theme: Theme, collector: inout MediaCollector) -> Theme {
        guard case .image(let path) = theme.background else { return theme }
        var copy = theme
        copy.background = .image(path: collector.reference(path))
        return copy
    }

    static func lookEntry(_ look: Look) -> ProgramDocument.LookEntry {
        var screens: [String: ProgramDocument.LookEntry.Screen] = [:]
        for (id, screen) in look.screens {
            screens[id.uuidString] = .init(themeID: screen.themeID, visibleLayers: screen.visibleLayers.map(\.rawValue).sorted())
        }
        return .init(id: look.id, name: look.name, screens: screens)
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
                                                  group: $0.groupID.flatMap { names[$0] }, objects: $0.objects, actions: $0.actions) },
                     arrangements: p.arrangements.map { .init(name: $0.name, groups: $0.groupIDs.map { names[$0] ?? "" }) })
    }
}
