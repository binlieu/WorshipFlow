// UI-002 Part 1 (KI-068): small presentation decisions for the Show and Edit headers, the Clear control and thumbnails.
import Foundation
import Domain

public enum HeaderChrome {
    /// Words on the header buttons, or icons only when the header is too narrow for them.
    public static func showsLabels(availableWidth: Double, labelledWidth: Double) -> Bool { availableWidth >= labelledWidth }

    public enum Control: CaseIterable, Sendable {
        case addSlide, reflow, addToPlaylist, quickEdit, editLiveSlide, themes, sectionOrders

        public var title: String {
            switch self {
            case .addSlide: "Add slide"
            case .reflow: "Reflow…"
            case .addToPlaylist: "Add to playlist"
            case .quickEdit: QuickEditLabels.previewTitle
            case .editLiveSlide: QuickEditLabels.liveTitle
            case .themes: "Themes…"
            case .sectionOrders: "Section orders…"
            }
        }
        public var keyHint: String? {
            switch self { case .quickEdit: QuickEditLabels.previewShortcut; case .editLiveSlide: QuickEditLabels.liveShortcut; default: nil }
        }
        public var tooltip: String {
            switch self {
            case .addSlide: "Add a slide after the selected one"
            case .reflow: "Re-flow the lyrics of this song"
            case .addToPlaylist: "Add this song to the playlist"
            case .quickEdit: "Quick edit (Command-E): edit the selected slide in the side panel. Preview only; the screens change when you go live with it. To change what is on screen now, use Edit live slide (Option-Command-E)."
            case .editLiveSlide: "Edit live slide (Option-Command-E): \(QuickEditLabels.liveWarning)"
            case .themes: "Create and edit themes"
            case .sectionOrders: "Section orders of the open song"
            }
        }
        public var accessibilityLabel: String { title.replacingOccurrences(of: "…", with: "") }
    }
}

/// The Clear control: one split control. Clicking clears the words; the attached menu offers Clear all.
public enum ClearControl {
    public enum Action: Sendable, Equatable {
        case clearWords, clearAll
        /// MEDIA-010: the three layer clears.
        case clearBackground, clearForeground, clearMusic
        public var title: String {
            switch self {
            case .clearWords: "Clear"
            case .clearAll: "Clear all"
            case .clearBackground: "Clear background"
            case .clearForeground: "Clear foreground"
            case .clearMusic: "Clear music"
            }
        }
        public var detail: String {
            switch self {
            case .clearWords: "Hide the words on every screen"
            case .clearAll: "Hide the words and stop a clip playing over them (Shift-Escape)"
            case .clearBackground: "Drop the background chosen from the media bin and hide the background on every screen. The next slide shows its own background again"
            case .clearForeground: "Stop the clip playing over the words"
            case .clearMusic: "Stop the sound player (not a video's own sound)"
            }
        }
        /// The key that does it, as the Cues key table shows it. Option and Control keys are never transport keys, so the
        /// app's key monitor lets them through to the Show menu.
        public var shortcut: String {
            switch self {
            case .clearWords: "esc"
            case .clearAll: "⇧ esc"
            case .clearBackground: "⌃⌥B"
            case .clearForeground: "⌃⌥F"
            case .clearMusic: "⌃⌥M"
            }
        }
    }
    public static let primary: Action = .clearWords
    public static let menu: [Action] = [.clearAll]
    /// MEDIA-010: the three layer clears, listed after Clear all in the Clear menu.
    public static let layerMenu: [Action] = [.clearBackground, .clearForeground, .clearMusic]
}

/// How a slide thumbnail is drawn: the theme's colour or image always; a background video or still as one frame
/// (never animated), so a thumbnail is not flat black when the theme shows media.
public struct ThumbnailPolicy: Sendable, Equatable {
    public var wantsFrames: Bool
    public var cacheable: Bool { !wantsFrames }
    public var animates: Bool { false }
    public init(scene: SceneDescription) { wantsFrames = scene.backgroundMedia != nil || scene.foregroundMedia != nil }
}

/// UI-002 Part 3: the Media mode's left list (the design's "Media bin" and "Audio" groups) and its header title.
public enum MediaBinCategories {
    public struct Entry: Equatable, Sendable {
        public var title: String
        public var kind: MediaKind?
        public var count: Int
        public var isAudio: Bool { kind == .audio }
    }

    public static func title(for kind: MediaKind?) -> String {
        switch kind {
        case nil: "All media"
        case .video?: "Videos"
        case .image?: "Pictures"
        case .audio?: "Sound"
        }
    }

    public static func entries(kinds: [MediaKind]) -> [Entry] {
        let all: [MediaKind?] = [nil, .video, .image, .audio]
        return all.map { k in Entry(title: title(for: k), kind: k, count: k == nil ? kinds.count : kinds.filter { $0 == k }.count) }
    }
}

/// UI-002 Part 4: System, Dark or Light. Dark is the default. The choice is stored with the library's settings.
public enum AppearanceChoice: String, CaseIterable, Sendable, Identifiable {
    case system, dark, light
    public var id: String { rawValue }
    public static let `default`: AppearanceChoice = .dark
    public var title: String { rawValue.capitalized }
    public enum Scheme: Sendable, Equatable { case dark, light }
    /// Nil follows the system.
    public var forcedScheme: Scheme? { self == .system ? nil : (self == .dark ? .dark : .light) }
    public static func restored(from stored: String?) -> AppearanceChoice { stored.flatMap(AppearanceChoice.init(rawValue:)) ?? .default }
}

/// MEDIA-010: every key the Cues mode's keyboard table lists, in one place so a test can see that no two share a key.
/// FIX-I item 2: the hints on the transport bar's buttons: the keys that really do it.
public enum TransportKeyHints {
    public static let previous = "⇧␣"
    public static let next = "␣"
    public static let goLive = "↩"
}

public enum ShowShortcuts {
    public struct Entry: Equatable, Sendable { public var key: String; public var command: String }

    public static let all: [Entry] = [
        Entry(key: "Space", command: "Next slide"), Entry(key: "⇧ Space", command: "Previous slide"),
        Entry(key: "← → ↑ ↓", command: "Move the selection (Preview only)"),
        Entry(key: "↩", command: "Go live with the selected slide, or send the selected media item live"), Entry(key: "B", command: "Blackout (toggle)"),
        Entry(key: ClearControl.Action.clearWords.shortcut, command: "Clear"),
        Entry(key: ClearControl.Action.clearAll.shortcut, command: "Clear all"),
        Entry(key: ClearControl.Action.clearBackground.shortcut, command: "Clear background"),
        Entry(key: ClearControl.Action.clearForeground.shortcut, command: "Clear foreground"),
        Entry(key: ClearControl.Action.clearMusic.shortcut, command: "Clear music"),
        Entry(key: "⌘E", command: "Quick edit"), Entry(key: "⌘F", command: "Search"), Entry(key: "⌘J", command: "Scripture"),
    ]
}
