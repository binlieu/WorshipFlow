// UI-001 / ADR-0007: typed accessors for the design tokens (docs/UI/design-tokens.json). Colours come from named colour
// sets in Assets.xcassets (dark and light), so views never use literals. A test fails if the catalog and the token
// file drift apart. Output colours (canvas, lyric inks, plate) are render-engine constants and are not used here.
import SwiftUI

enum Tok {
    static let bg = Color("bg")
    static let surface = Color("surface")
    static let surface2 = Color("surface-2")
    static let surface3 = Color("surface-3")
    static let border = Color("border")
    static let borderStrong = Color("border-strong")
    static let text = Color("text")
    static let muted = Color("muted")
    static let cyan = Color("cyan")
    static let blue = Color("blue")
    static let warning = Color("warning")
    /// Means on air and nothing else (text and dots).
    static let live = Color("live")
    /// Fill of Go Live, the LIVE tag and the live ring. Text on it: `onLive`.
    static let liveFill = Color("live-fill")
    static let onLive = Color("on-live")
    static let broadcast = Color("broadcast")
    static let brandA = Color("brand-a")
    static let brandB = Color("brand-b")
    static let onBrand = Color("on-brand")
    static let roleAudience = Color("role-audience")
    static let roleStage = Color("role-stage")
    static let roleBroadcast = Color("role-broadcast")
    static let statusOK = Color("status-ok")
    static let sectionVerse = Color("section-verse")
    static let sectionChorus = Color("section-chorus")
    static let sectionBridge = Color("section-bridge")

    static var brandGradient: LinearGradient {
        LinearGradient(colors: [brandA, brandB], startPoint: .topLeading, endPoint: .bottomTrailing)
    }
}

enum Space {
    static let s1: CGFloat = 2, s2: CGFloat = 4, s3: CGFloat = 8, s4: CGFloat = 12, s5: CGFloat = 14, s6: CGFloat = 24, s7: CGFloat = 32
    static let controlHeight: CGFloat = 26
    static let transportHeight: CGFloat = 36
    static let transportBarHeight: CGFloat = 56
    static let toolbarHeight: CGFloat = 52
    static let headerHeight: CGFloat = 48
    static let sidebarWidth: CGFloat = 256
    static let inspectorWidth: CGFloat = 372
}

enum Radius {
    static let xs: CGFloat = 3, sm: CGFloat = 4, md: CGFloat = 6, lg: CGFloat = 8, xl: CGFloat = 10
    /// ui.css values the token file lacks (UI-005a): the segmented control's and the toolbar timers' track, and a segment inside it.
    static let track: CGFloat = 7, segment: CGFloat = 5
}

/// ui.css values the token file lacks (UI-005a). The parity test pins them to the mockup's CSS.
enum Metric {
    static let thumbRingPreview: CGFloat = 2, thumbRingLive: CGFloat = 3, thumbRingOffset: CGFloat = 2
    static let toggleWidth: CGFloat = 30, toggleHeight: CGFloat = 18, checkboxSize: CGFloat = 14
    static let scrubTrack: CGFloat = 5, scrubThumb: CGFloat = 13
    static let monitorGap: CGFloat = 10, lookHeight: CGFloat = 24, timerCapsuleHeight: CGFloat = 28
}

/// UI-005i: every text style of the operator interface. They are Inter (bundled; tnum and cv11 on) at the size, weight and
/// letter-spacing ui.css gives each role; the system font replaces Inter only if it could not be registered. Monospaced text stays
/// the system monospaced face (SF Mono), as the mockups have it. Line height is the font's own (about 1.21 em, the CSS's 16/13).
/// Letter-spacing and upper-casing are not part of a Font; the views that need them (badges, section labels) apply them.
/// These are for the operator interface only: projected text follows each theme's own font (ThemeStyle.fontName), never these.
extension Font {
    /// Inter at `size` points and `weight`. The one primitive the named styles are built on.
    static func wf(_ size: CGFloat, _ weight: Weight = .regular) -> Font {
        if let f = InterFont.ctFont(size: size, weight: InterFont.cssWeight(weight)) { return Font(f) }
        return .system(size: size, weight: weight).monospacedDigit()
    }
    /// System monospaced (SF Mono) for timecodes, data and paths.
    static func wfMono(_ size: CGFloat, _ weight: Weight = .regular) -> Font { .system(size: size, weight: weight, design: .monospaced) }

    // ui.css roles
    static let wfBody = Font.wf(13)                                  // body, .li
    static let wfBodyStrong = Font.wf(13, .semibold)                 // .tb .title, .btn.lg, .tm b
    static let wfControl = Font.wf(12)                               // .field, label.k
    static let wfControlStrong = Font.wf(12, .medium)                // .btn, .seg b, .tabs b
    static let wfSectionLabel = Font.wf(11, .semibold)               // .h, .pill
    static let wfBadge = Font.wf(10, .bold)                          // .badge
    static let wfCaption = Font.wf(11)                               // .cap, .tb .sub, .li .n
    static let wfCaptionStrong = Font.wf(11, .semibold)              // .cap b
    static let wfSmall = Font.wf(10)                                 // macOS caption size
    static let wfTag = Font.wf(9, .heavy)                            // .thumb .tag
    static let wfMonoData = Font.wfMono(11, .medium)
    static let wfMonoReadout = Font.wfMono(17, .semibold)

    // The system text styles' sizes (macOS), kept so no row changes height: replaces .caption, .callout, .headline and the rest.
    static let wfSubheadline = Font.wf(11)
    static let wfCallout = Font.wf(12)
    static let wfHeadline = Font.wf(13, .bold)
    static let wfTitle3 = Font.wf(15)
    static let wfTitle2 = Font.wf(17)
    static let wfTitle = Font.wf(22)
    static let wfLargeTitle = Font.wf(26)
}
