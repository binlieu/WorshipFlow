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
    static let sidebarWidth: CGFloat = 256
    static let inspectorWidth: CGFloat = 372
}

enum Radius {
    static let xs: CGFloat = 3, sm: CGFloat = 4, md: CGFloat = 6, lg: CGFloat = 8, xl: CGFloat = 10
}

extension Font {
    static let wfSectionLabel = Font.system(size: 11, weight: .semibold)
    static let wfBadge = Font.system(size: 10, weight: .bold)
    static let wfMonoData = Font.system(size: 11, weight: .medium, design: .monospaced)
    static let wfMonoReadout = Font.system(size: 17, weight: .semibold, design: .monospaced)
    static let wfCaption = Font.system(size: 11)
}

