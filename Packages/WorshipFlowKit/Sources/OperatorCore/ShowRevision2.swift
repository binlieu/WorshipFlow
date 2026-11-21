// UI-003 Part 1 (design revision 2): the pure decisions behind the revised Show mode. Slide grid columns, the media
// dock, the inspector tabs, the two Quick edit wordings, the Look row, the monitors, which screens a layer is on, the
// library list while searching, and which clip the media controller drives. Views draw what these return.
// Foundation and Domain only.
import Foundation
import Domain

// MARK: Slide grid

public enum SlideGridLayout {
    public static let thumbnailMinimumWidth = 140.0
    public static let spacing = 12.0
    public static let inset = 14.0

    /// How many thumbnails fit across `width` points of the centre column: five at the design's window size (the
    /// centre is 812 pt at 1440 pt), more when wider, never fewer than one.
    public static func columnCount(width: Double) -> Int {
        guard width.isFinite, width > 0 else { return 1 }
        let usable = max(0, width - 2 * inset)
        return max(1, Int((usable + spacing) / (thumbnailMinimumWidth + spacing)))
    }
}

// MARK: Media dock

public enum MediaDockTab: String, CaseIterable, Identifiable, Sendable {
    case backgrounds, videos, images, audio
    public var id: String { rawValue }
    public var title: String {
        switch self { case .backgrounds: "Backgrounds"; case .videos: "Videos"; case .images: "Images"; case .audio: "Audio" }
    }
    /// Backgrounds is everything that can sit behind the words (a picture or a video); the bin has no other notion of
    /// "background", so the tab does not invent one.
    public func includes(_ kind: MediaKind) -> Bool {
        switch self {
        case .backgrounds: kind != .audio
        case .videos: kind == .video
        case .images: kind == .image
        case .audio: kind == .audio
        }
    }
}

public enum MediaLayerChoice: String, CaseIterable, Identifiable, Sendable {
    case background, foreground
    public var id: String { rawValue }
    public var title: String { self == .background ? "Background" : "Foreground" }
}

public enum MediaDockAction: Equatable, Sendable {
    case setBackground(UUID), playForeground(UUID), playAudio(UUID)
}

/// Height and collapsed state of the dock, remembered with the library's settings.
public struct MediaDockState: Equatable, Codable, Sendable {
    public var height: Double = MediaDock.defaultHeight
    public var isCollapsed = false
    public init(height: Double = MediaDock.defaultHeight, isCollapsed: Bool = false) {
        self.height = height
        self.isCollapsed = isCollapsed
    }
}

public enum MediaDock {
    public static let defaultHeight = 176.0
    public static let minimumHeight = 132.0

    public static func assets(_ all: [MediaAsset], tab: MediaDockTab) -> [MediaAsset] { all.filter { tab.includes($0.kind) } }

    /// What a click on a tile does: sound plays as a cue whatever the layer choice; a picture or video follows it.
    public static func action(for asset: MediaAsset, layer: MediaLayerChoice) -> MediaDockAction {
        if asset.kind == .audio { return .playAudio(asset.id) }
        return layer == .background ? .setBackground(asset.id) : .playForeground(asset.id)
    }

    public static func showsLayerChoice(on tab: MediaDockTab) -> Bool { tab != .audio }

    /// The dock is at least `minimumHeight` and at most half of the column it sits in.
    public static func clampedHeight(_ height: Double, available: Double) -> Double {
        guard height.isFinite else { return defaultHeight }
        let ceiling = available.isFinite ? max(minimumHeight, available / 2) : defaultHeight
        return min(ceiling, max(minimumHeight, height))
    }
}

// MARK: Inspector tabs

public enum InspectorTab: String, CaseIterable, Identifiable, Sendable {
    case props, cues, audio, quickEdit
    public var id: String { rawValue }
    public var title: String {
        switch self { case .props: "Props"; case .cues: "Cues"; case .audio: "Audio"; case .quickEdit: "Quick edit" }
    }
}

/// The tabs under the Look row. Quick edit is a fourth tab that exists only while it is open.
public struct InspectorTabs: Equatable, Sendable {
    public private(set) var selected: InspectorTab = .props
    public private(set) var quickEditIsOpen = false
    private var returnTab: InspectorTab = .props

    public init() {}

    public var visible: [InspectorTab] { quickEditIsOpen ? InspectorTab.allCases : [.props, .cues, .audio] }

    public mutating func select(_ tab: InspectorTab) {
        guard tab != .quickEdit || quickEditIsOpen else { return }
        selected = tab
    }

    /// Command-E. Needs a selected slide. Returns whether the tab is open and selected.
    @discardableResult
    public mutating func openQuickEdit(hasSelectedSlide: Bool) -> Bool {
        guard hasSelectedSlide else { return false }
        if !quickEditIsOpen { returnTab = selected == .quickEdit ? .props : selected }
        quickEditIsOpen = true
        selected = .quickEdit
        return true
    }

    /// Done (Escape): the tab goes and the operator is back where they were.
    public mutating func closeQuickEdit() {
        guard quickEditIsOpen else { return }
        quickEditIsOpen = false
        if selected == .quickEdit { selected = returnTab }
    }

    /// The tab edits the selected slide, so it cannot outlive it.
    public mutating func selectedSlideChanged(hasSelectedSlide: Bool) {
        if !hasSelectedSlide { closeQuickEdit() }
    }
}

// MARK: The two Quick edits

/// The words and keys that keep the two meanings of "quick edit" apart. The tab edits the selected slide in preview;
/// the live action deliberately changes what the audience sees now.
public enum QuickEditLabels {
    public static let previewTitle = "Quick edit"
    public static let previewShortcut = "⌘E"
    public static let previewChip = "Preview only"
    public static let previewNote = "Edits the selected slide in preview. The screens change when you go live with it."
    public static let liveTitle = "Edit live slide…"
    public static let liveShortcut = "⌥⌘E"
    public static let liveMenuTitle = "Quick Edit Live Slide…"
    /// UI-005b: "Saved 2 s ago · live at next trigger", from the time of the last real write. Nil: nothing was written yet.
    public static func savedNote(secondsAgo: Int?) -> String {
        let tail = " · live at next trigger"
        guard let secondsAgo else { return "No edits yet" + tail }
        let s = max(0, secondsAgo)
        if s < 60 { return "Saved \(s) s ago" + tail }
        if s < 3600 { return "Saved \(s / 60) min ago" + tail }
        return "Saved \(s / 3600) h ago" + tail
    }
    public static let liveWarning = "This changes what the audience sees now, and saves the new words."
}

// MARK: Look row

public enum LookRow {
    /// How many Look buttons fit in `availableWidth` points (the row without its label and chevron), judged from the
    /// length of each name. Always at least one, never more than the Looks there are.
    public static func capacity(for looks: [Look], availableWidth: Double) -> Int {
        guard availableWidth.isFinite, !looks.isEmpty else { return max(1, looks.count) }
        var used = 0.0, count = 0
        for look in looks {
            let width = max(44.0, Double(look.name.count) * 7.0 + 20.0) + (count > 0 ? 6 : 0)
            if used + width > availableWidth { break }
            used += width
            count += 1
        }
        return max(1, count)
    }

    /// The Looks that fit on the row and the rest for the chevron menu. The selected Look is always on the row: when it
    /// would be in the menu it takes the last place and the Look it displaces goes to the menu.
    public static func split(_ looks: [Look], selected: UUID?, capacity: Int) -> (visible: [Look], overflow: [Look]) {
        let room = max(1, capacity)
        guard looks.count > room else { return (looks, []) }
        var visible = Array(looks.prefix(room))
        if let selected, !visible.contains(where: { $0.id == selected }), let chosen = looks.first(where: { $0.id == selected }) {
            visible[room - 1] = chosen
        }
        let shown = Set(visible.map(\.id))
        return (visible, looks.filter { !shown.contains($0.id) })
    }
}

// MARK: Monitors

public enum ShowMonitors {
    /// The screen the Live monitor shows: the first enabled audience screen, or the first audience screen.
    public static func live(_ profiles: [ScreenProfile]) -> ScreenProfile? {
        profiles.first { $0.role == .audience && $0.isEnabled } ?? profiles.first { $0.role == .audience }
    }

    /// Every other enabled screen, Stage first, then Broadcast, then further audience screens.
    public static func others(_ profiles: [ScreenProfile]) -> [ScreenProfile] {
        let liveID = live(profiles)?.id
        let rest = profiles.filter { $0.isEnabled && $0.id != liveID }
        return [ScreenRole.stage, .broadcast, .audience].flatMap { role in rest.filter { $0.role == role } }
    }
}

// MARK: Which screens a layer is on

public struct ScreenLayerInput: Equatable, Sendable {
    public var role: ScreenRole
    public var isEnabled: Bool
    public var visibleLayers: Set<LayerKind>
    /// The screen's theme draws a motion background (so a chosen background video appears there).
    public var backgroundIsMedia: Bool
    public init(role: ScreenRole, isEnabled: Bool, visibleLayers: Set<LayerKind>, backgroundIsMedia: Bool) {
        self.role = role
        self.isEnabled = isEnabled
        self.visibleLayers = visibleLayers
        self.backgroundIsMedia = backgroundIsMedia
    }
}

public enum LayerPresence {
    /// Roles whose enabled screens show `layer` under the active Look. Stage screens ignore Looks, props and media.
    public static func roles(showing layer: LayerKind, screens: [ScreenLayerInput]) -> [ScreenRole] {
        ordered(screens.filter { $0.isEnabled && $0.role != .stage && $0.visibleLayers.contains(layer) })
    }

    /// Roles on which a chosen background video or picture appears.
    public static func backgroundMediaRoles(screens: [ScreenLayerInput]) -> [ScreenRole] {
        ordered(screens.filter { $0.isEnabled && $0.role != .stage && $0.visibleLayers.contains(.background) && $0.backgroundIsMedia })
    }

    private static func ordered(_ screens: [ScreenLayerInput]) -> [ScreenRole] {
        [ScreenRole.audience, .broadcast].filter { role in screens.contains { $0.role == role } }
    }
}

// MARK: Library list while searching

extension LibraryKind {
    /// The word VoiceOver and the menus use.
    public var title: String {
        switch self {
        case .songs: "Songs"
        case .scripture: "Scripture"
        case .sermons: "Sermons"
        case .announcements: "Announcements"
        }
    }
    var sidebarRank: Int {
        switch self { case .songs: 0; case .scripture: 1; case .sermons: 2; case .announcements: 3 }
    }
}

public enum LibraryListing {
    /// UI-005b: the design's order, songs, scripture, sermons, announcements; each kind in the order its libraries were made.
    public static func sidebarOrder(_ libraries: [Library]) -> [Library] {
        libraries.enumerated().sorted { a, b in
            a.element.kind.sidebarRank != b.element.kind.sidebarRank ? a.element.kind.sidebarRank < b.element.kind.sidebarRank : a.offset < b.offset
        }.map(\.element)
    }

    /// Where the Scripture entry (the Bible view) goes in an ordered list: after the songs libraries.
    public static func scriptureEntryPosition(in ordered: [Library]) -> Int { ordered.filter { $0.kind == .songs }.count }

    public enum Match: Equatable, Sendable { case title, lyrics }
    public struct Row: Equatable, Identifiable, Sendable {
        public var id: UUID
        public var title: String
        public var match: Match?
    }

    public static func hasQuery(_ query: String) -> Bool { !query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }

    /// Without a query, the library. With one, the search hits in the order the search gave them (titles and lyrics),
    /// each marked with where it matched. Hits may belong to other libraries.
    public static func rows(query: String, presentations: [Presentation], hits: [SearchHit]) -> [Row] {
        guard hasQuery(query) else { return presentations.map { Row(id: $0.id, title: $0.title, match: nil) } }
        return hits.map { Row(id: $0.presentationID, title: $0.title, match: $0.matchedTitle ? .title : .lyrics) }
    }
}

// MARK: Media controller

public enum MediaControllerSource: Equatable, Sendable {
    case foregroundClip, audioCue(UUID), backgroundLoop
}

public enum MediaController {
    /// Which loaded file the controller row drives: the clip over the slide, else the sound cue that started last,
    /// else the background video. Nil when none is loaded (the row is not shown).
    public static func pick(foregroundLoaded: Bool, currentAudioCue: UUID?, backgroundIsVideo: Bool) -> MediaControllerSource? {
        if foregroundLoaded { return .foregroundClip }
        if let currentAudioCue { return .audioCue(currentAudioCue) }
        if backgroundIsVideo { return .backgroundLoop }
        return nil
    }
}

// MARK: Media tile marks

public enum MediaTileMark: Equatable, Sendable {
    /// On screen now: the background of a running show, or a clip playing over it. The only red.
    case live
    /// Chosen or selected but not on screen: the blue ring.
    case preview
    /// A sound cue that is sounding (not on screen, so not red).
    case playingSound
    case none
}

public enum MediaTileMarks {
    public static func mark(for asset: MediaAsset, layers: MediaLayers, showIsLive: Bool, selected: UUID?, soundIsPlaying: Bool) -> MediaTileMark {
        if asset.kind == .audio { return soundIsPlaying ? .playingSound : (selected == asset.id ? .preview : .none) }
        let isBackground = layers.background?.selection.assetID == asset.id
        let isForeground = layers.foreground?.selection.assetID == asset.id
        if showIsLive, isBackground || isForeground { return .live }
        if isBackground || isForeground || selected == asset.id { return .preview }
        return .none
    }
}
