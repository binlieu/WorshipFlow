// UI-002 Part 5: what a playlist item can be besides a presentation: a section header ("Pre-service", "Worship") or a
// countdown. Pure rules for stepping across them and for the countdown arithmetic. Foundation only.
import Foundation

public struct CountdownSpec: Equatable, Codable, Sendable {
    public enum Mode: Equatable, Codable, Sendable {
        /// Counts down this many seconds from the moment it goes live.
        case duration(seconds: Int)
        /// Counts down to this time today (24-hour clock). A time already past reads zero.
        case targetTime(hour: Int, minute: Int)
    }
    public var label: String
    public var mode: Mode

    public init(label: String, mode: Mode) {
        self.label = label
        switch mode {
        case .duration(let s): self.mode = .duration(seconds: max(0, s))
        case .targetTime(let h, let m): self.mode = .targetTime(hour: min(23, max(0, h)), minute: min(59, max(0, m)))
        }
    }
}

/// UI-005b: a file from the media bin as a playlist item. A video or picture plays over the slides (the foreground), a sound plays as
/// audio. The name is the bin's name when the item was made, kept so the row and a program package can say what it was.
public struct MediaItemSpec: Equatable, Codable, Sendable, Hashable {
    public var assetID: UUID
    public var name: String
    public var kind: MediaKind

    public init(assetID: UUID, name: String, kind: MediaKind) {
        self.assetID = assetID
        self.name = name
        self.kind = kind
    }
}

/// UI-005b: an announcements loop: a set of pictures shown one after another, or one video repeated, until the operator presses
/// Next. It never ends or advances by itself.
public struct AnnouncementsSpec: Equatable, Codable, Sendable, Hashable {
    public static let pictureSeconds = 3...120

    public var label: String
    public var items: [MediaItemSpec]
    /// How long each picture stays when there is more than one (a single picture stays; a video repeats).
    public var secondsPerPicture: Int

    public init(label: String, items: [MediaItemSpec], secondsPerPicture: Int = 8) {
        self.label = label
        self.items = items.filter { $0.kind != .audio }
        self.secondsPerPicture = min(Self.pictureSeconds.upperBound, max(Self.pictureSeconds.lowerBound, secondsPerPicture))
    }

    /// A single video repeats; anything else is pictures, cycled.
    public var isVideoLoop: Bool { items.count == 1 && items[0].kind == .video }
    public var assetIDs: [UUID] { items.map(\.assetID) }

    /// Which picture is up `elapsed` seconds after the loop started (always 0 for one item or none).
    public func pictureIndex(afterSeconds elapsed: Double) -> Int {
        guard items.count > 1, elapsed.isFinite, elapsed > 0 else { return 0 }
        return Int(elapsed / Double(secondsPerPicture)) % items.count
    }
}

public enum PlaylistItemKind: Equatable, Sendable, Codable {
    case presentation
    case header(label: String)
    case countdown(CountdownSpec)
    /// LIB-004c: a Bible passage, kept as a reference and translation codes (see `ScriptureItemSpec`).
    case scripture(ScriptureItemSpec)
    /// UI-005b: a presentation from a sermons library, listed with the sermon icon. It plays exactly as a presentation does.
    case sermon
    /// UI-005b: a file from the media bin (see `MediaItemSpec`).
    case media(MediaItemSpec)
    /// UI-005b: an announcements loop (see `AnnouncementsSpec`).
    case announcements(AnnouncementsSpec)

    /// True for the kinds whose slides come from a stored presentation (the item's `presentationID`).
    public var hasSlides: Bool {
        switch self { case .presentation, .sermon: true; default: false }
    }
    /// True for the kinds that play a file over the screens or through the speakers instead of showing slides.
    public var isMediaPlayback: Bool {
        switch self { case .media, .announcements: true; default: false }
    }

    /// A header is a label in the list: it cannot go live, and Next and Previous skip over it.
    public var isSelectableLive: Bool { if case .header = self { return false } else { return true } }
    public var isHeader: Bool { if case .header = self { return true } else { return false } }
    public var isScripture: Bool { if case .scripture = self { return true } else { return false } }

    /// The stored form: a kind word and a small JSON payload (nil for a presentation).
    public var stored: (kind: String, payload: String?) {
        switch self {
        case .presentation: return ("presentation", nil)
        case .header(let label): return ("header", Self.encode(["label": label]))
        case .countdown(let spec): return ("countdown", (try? String(data: JSONEncoder.sorted.encode(spec), encoding: .utf8)) ?? nil)
        case .scripture(let spec): return ("scripture", (try? String(data: JSONEncoder.sorted.encode(spec), encoding: .utf8)) ?? nil)
        case .sermon: return ("sermon", nil)
        case .media(let spec): return ("media", (try? String(data: JSONEncoder.sorted.encode(spec), encoding: .utf8)) ?? nil)
        case .announcements(let spec): return ("announcements", (try? String(data: JSONEncoder.sorted.encode(spec), encoding: .utf8)) ?? nil)
        }
    }

    /// An item that cannot be read becomes a header, so one damaged row never stops the playlist from loading.
    public init(storedKind: String, payload: String?) {
        switch storedKind {
        case "presentation": self = .presentation
        case "header":
            let label = payload.flatMap { Self.decode($0)?["label"] }
            self = .header(label: label ?? "Header")
        case "countdown":
            if let payload, let data = payload.data(using: .utf8), let spec = try? JSONDecoder().decode(CountdownSpec.self, from: data) {
                self = .countdown(spec)
            } else { self = .header(label: "Countdown") }
        case "scripture":
            if let payload, let data = payload.data(using: .utf8), let spec = try? JSONDecoder().decode(ScriptureItemSpec.self, from: data) {
                self = .scripture(spec)
            } else { self = .header(label: "Scripture") }
        case "sermon": self = .sermon
        case "media":
            if let payload, let data = payload.data(using: .utf8), let spec = try? JSONDecoder().decode(MediaItemSpec.self, from: data) {
                self = .media(spec)
            } else { self = .header(label: "Media file") }
        case "announcements":
            if let payload, let data = payload.data(using: .utf8), let spec = try? JSONDecoder().decode(AnnouncementsSpec.self, from: data) {
                self = .announcements(spec)
            } else { self = .header(label: "Announcements") }
        default: self = .header(label: "Unknown item")
        }
    }

    private enum CodingKeys: String, CodingKey { case kind, payload }
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        self.init(storedKind: try c.decode(String.self, forKey: .kind), payload: try c.decodeIfPresent(String.self, forKey: .payload))
    }
    public func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(stored.kind, forKey: .kind)
        try c.encodeIfPresent(stored.payload, forKey: .payload)
    }

    private static func encode(_ dict: [String: String]) -> String? {
        (try? JSONEncoder.sorted.encode(dict)).flatMap { String(data: $0, encoding: .utf8) }
    }
    private static func decode(_ text: String) -> [String: String]? {
        text.data(using: .utf8).flatMap { try? JSONDecoder().decode([String: String].self, from: $0) }
    }
}

private extension JSONEncoder {
    static var sorted: JSONEncoder { let e = JSONEncoder(); e.outputFormatting = [.sortedKeys]; return e }
}

public enum PlaylistStepping {
    /// The index Next (`direction` 1) or Previous (-1) goes to from `index`, skipping headers; nil at either end. From nil
    /// (nothing selected) a forward step finds the first playable item.
    public static func target(kinds: [PlaylistItemKind], from index: Int?, direction: Int) -> Int? {
        guard !kinds.isEmpty, direction == 1 || direction == -1 else { return nil }
        var j = (index ?? (direction == 1 ? -1 : kinds.count)) + direction
        while kinds.indices.contains(j) {
            if kinds[j].isSelectableLive { return j }
            j += direction
        }
        return nil
    }

    /// Where a stored place on `index` lands: that item if it can be live, else the next playable one, else the one before.
    public static func landing(kinds: [PlaylistItemKind], at index: Int) -> Int? {
        guard kinds.indices.contains(index) else { return nil }
        if kinds[index].isSelectableLive { return index }
        return target(kinds: kinds, from: index, direction: 1) ?? target(kinds: kinds, from: index, direction: -1)
    }
}

/// One running countdown. It never moves the show on: at zero it stays at zero until the operator steps.
public struct CountdownRun: Equatable, Sendable {
    public let endsAt: Date

    public init(spec: CountdownSpec, startedAt: Date, calendar: Calendar = .current) {
        switch spec.mode {
        case .duration(let seconds):
            endsAt = startedAt.addingTimeInterval(TimeInterval(seconds))
        case .targetTime(let hour, let minute):
            let target = calendar.date(bySettingHour: hour, minute: minute, second: 0, of: startedAt) ?? startedAt
            endsAt = max(target, startedAt) == target ? target : startedAt
        }
        total = max(0, Int(endsAt.timeIntervalSince(startedAt).rounded(.up)))
    }

    private let total: Int

    /// Whole seconds left, never below zero and never above the starting value.
    public func remaining(at now: Date) -> Int {
        min(total, max(0, Int(endsAt.timeIntervalSince(now).rounded(.up))))
    }
    public func isFinished(at now: Date) -> Bool { remaining(at: now) == 0 }
}

public enum CountdownText {
    public static func format(_ seconds: Int) -> String {
        let s = max(0, seconds)
        return s >= 3600 ? String(format: "%d:%02d:%02d", s / 3600, (s / 60) % 60, s % 60) : String(format: "%d:%02d", s / 60, s % 60)
    }
}
