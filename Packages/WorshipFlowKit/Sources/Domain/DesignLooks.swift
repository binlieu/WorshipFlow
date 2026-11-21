// UI-005b item 6: the four Looks the design draws in the Look row: Full, Notes, Lower 3rd, BG only. Made for a NEW library only.
// A Look is a set of per-screen choices (which of background, slide and props a screen draws). It has no notes layer, so no Look can
// carry speaker notes to an audience or broadcast screen: notes are drawn by the stage layouts, on stage screens alone.
import Foundation

public enum DesignLooks {
    /// Per role, the layers each Look shows. A role that is not listed shows everything (the stage layout alone decides what a stage
    /// screen draws, notes included; a Look only gates its props layer).
    ///
    /// - Full: every layer on every screen.
    /// - Notes: audience shows the words and the background without props; broadcast shows the words only; stage unchanged.
    /// - Lower 3rd: broadcast shows the slide and props without the background layer (the lower-third plate is the theme's); audience unchanged.
    /// - BG only: audience and broadcast show the background layer alone; stage unchanged.
    static let table: [(name: String, audience: Set<LayerKind>?, broadcast: Set<LayerKind>?)] = [
        ("Full", nil, nil),
        ("Notes", [.background, .slide], [.slide]),
        ("Lower 3rd", nil, [.slide, .props]),
        ("BG only", [.background], [.background]),
    ]

    /// The four Looks for the screens in `profiles`. Each call makes new ids.
    public static func make(profiles: [ScreenProfile]) -> [Look] {
        table.map { entry in
            var screens: [UUID: ScreenLook] = [:]
            for profile in profiles {
                let layers: Set<LayerKind>?
                switch profile.role {
                case .audience: layers = entry.audience
                case .broadcast: layers = entry.broadcast
                case .stage: layers = nil
                }
                if let layers { screens[profile.id] = ScreenLook(themeID: nil, visibleLayers: layers) }
            }
            return Look(id: UUID(), name: entry.name, screens: screens)
        }
    }
}
