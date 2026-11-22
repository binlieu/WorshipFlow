// FIX-K item 1: the five clear icon buttons (Clear lyric, background, foreground, music, all) as a pure function of what is live. Foundation and Domain only.
// An icon lights only for something that is live on its own layer, its glyph says what it would clear (a film for a video, a photo for a picture, the plain
// layer glyph while its layer is empty) and its tooltip names the thing and the key. Choosing an item in the bin without sending it live lights nothing.
import Foundation
import Domain

public enum ClearIcon: CaseIterable, Sendable { case lyric, background, foreground, music, all }

/// What is live, as the icons need it. Built by the app from the show, the media layers and the sound player.
public struct ClearLiveState: Equatable, Sendable {
    /// The words are showing (a live slide, not cleared, not blacked out).
    public var hasLiveWords: Bool
    /// What is live on the background layer (a bin choice, else the live slide's own background); nil: nothing of those.
    public var backgroundKind: MediaKind?
    public var backgroundName: String?
    /// FIX-N item 4: what the theme's own background is (a video or a picture), nil when it is neither. It lights the background icon when
    /// nothing else is named, because Clear background hides it too.
    public var themeBackgroundKind: MediaKind?
    public var foregroundKind: MediaKind?
    public var foregroundName: String?
    /// A sound cue is playing (the newest one's name).
    public var musicName: String?
    public var hasMusic: Bool

    public init(hasLiveWords: Bool = false, backgroundKind: MediaKind? = nil, backgroundName: String? = nil, themeBackgroundKind: MediaKind? = nil, foregroundKind: MediaKind? = nil,
                foregroundName: String? = nil, musicName: String? = nil, hasMusic: Bool? = nil) {
        self.hasLiveWords = hasLiveWords
        self.backgroundKind = backgroundKind
        self.backgroundName = backgroundName
        self.themeBackgroundKind = themeBackgroundKind
        self.foregroundKind = foregroundKind
        self.foregroundName = foregroundName
        self.musicName = musicName
        self.hasMusic = hasMusic ?? (musicName != nil)
    }
}

public enum ClearGlyph: Equatable, Sendable {
    case words, film, photo, backgroundLayer, foregroundLayer, music, all
}

public struct ClearIconState: Equatable, Sendable {
    public var enabled: Bool
    public var glyph: ClearGlyph
    public var tooltip: String

    public static func state(for icon: ClearIcon, live: ClearLiveState) -> ClearIconState {
        func word(_ kind: MediaKind) -> String { kind == .video ? "video" : "picture" }
        func glyph(_ kind: MediaKind) -> ClearGlyph { kind == .video ? .film : .photo }
        func layer(_ title: String, _ key: String, _ kind: MediaKind?, _ name: String?, plain: ClearGlyph) -> ClearIconState {
            guard let kind else { return ClearIconState(enabled: false, glyph: plain, tooltip: "Clear \(title): nothing live, \(key)") }
            let named = (name?.isEmpty ?? true) ? "" : ": \(name!)"
            return ClearIconState(enabled: true, glyph: glyph(kind), tooltip: "Clear \(title) \(word(kind))\(named), \(key)")
        }
        switch icon {
        case .lyric:
            return ClearIconState(enabled: live.hasLiveWords, glyph: .words, tooltip: "Clear lyric, esc")
        case .background:
            if live.backgroundKind == nil, let theme = live.themeBackgroundKind {
                return ClearIconState(enabled: true, glyph: glyph(theme), tooltip: "Clear background: theme \(word(theme)), ⌃⌥B")
            }
            return layer("background", "⌃⌥B", live.backgroundKind, live.backgroundName, plain: .backgroundLayer)
        case .foreground:
            return layer("foreground", "⌃⌥F", live.foregroundKind, live.foregroundName, plain: .foregroundLayer)
        case .music:
            let named = (live.musicName?.isEmpty ?? true) ? "" : ": \(live.musicName!)"
            return ClearIconState(enabled: live.hasMusic, glyph: .music, tooltip: "Clear music\(named), ⌃⌥M")
        case .all:
            let any = live.hasLiveWords || live.backgroundKind != nil || live.themeBackgroundKind != nil || live.foregroundKind != nil || live.hasMusic
            return ClearIconState(enabled: any, glyph: .all, tooltip: "Clear all, ⇧ esc")
        }
    }
}

public enum ClearIconRule {
    /// FIX-N item 4: a theme's own background as the icon sees it: the shared loop is a video, a theme picture a picture; a colour, a gradient or
    /// a transparent background is neither.
    public static func themeBackgroundKind(_ background: ThemeBackground) -> MediaKind? {
        switch background {
        case .media: .video
        case .image: .image
        case .color, .transparent, .gradient: nil
        }
    }

    /// One line for logs: each icon's enabled flag and glyph.
    public static func describe(live: ClearLiveState) -> String {
        ClearIcon.allCases.map { icon in
            let s = ClearIconState.state(for: icon, live: live)
            return "\(icon) \(s.enabled ? "ON" : "off") \(s.glyph)"
        }.joined(separator: ", ")
    }
}
