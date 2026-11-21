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
        public var title: String { self == .clearWords ? "Clear" : "Clear all" }
        public var detail: String {
            self == .clearWords ? "Hide the words on every screen"
                                : "Hide the words and stop a clip playing over them (Shift-Escape)"
        }
    }
    public static let primary: Action = .clearWords
    public static let menu: [Action] = [.clearAll]
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
