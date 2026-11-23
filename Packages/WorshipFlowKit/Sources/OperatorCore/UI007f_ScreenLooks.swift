// UI-007f (SC-51): the Look a screen uses. A screen the operator gave a Look of its own (`ScreenProfile.screenLookID`) composes with it; every
// other screen follows the show's Look, as before. Pure rules, Foundation and Domain only; `SettingsModel` holds the choice and the composers
// (`PublishedScenes`, `ImageUsage`, the app's thumbnails and layer chips) read it through `overrides`.
import Foundation
import Domain

public enum ScreenLooks {
    /// The Look `profile` uses: its own when it chose one that still exists, else `global` (the show's Look).
    public static func look(for profile: ScreenProfile, global: Look?, looks: [Look]) -> Look? {
        if let id = profile.screenLookID, let own = looks.first(where: { $0.id == id }) { return own }
        return global
    }

    /// The screens that use a Look other than the show's: one entry per such screen. Empty for a library where no screen chose a Look (and the
    /// composers then behave exactly as they did before screens could choose), and for a screen whose choice is the show's Look anyway.
    public static func overrides(profiles: [ScreenProfile], global: Look?, looks: [Look]) -> [UUID: Look] {
        var result: [UUID: Look] = [:]
        for profile in profiles {
            guard let id = profile.screenLookID, id != global?.id, let own = looks.first(where: { $0.id == id }) else { continue }
            result[profile.id] = own
        }
        return result
    }

    /// What the Screens mode says about one screen: the name of the Look it uses and whether the operator chose it for this screen.
    public struct Summary: Sendable, Equatable {
        public var lookName: String?
        public var isOwn: Bool
        public init(lookName: String?, isOwn: Bool) {
            self.lookName = lookName
            self.isOwn = isOwn
        }
        /// "Worship (chosen for this screen)" or "Sermon (follows the show's Look)"; "No Look" when there is none at all.
        public var text: String {
            guard let lookName else { return "No Look" }
            return isOwn ? "\(lookName) (chosen for this screen)" : "\(lookName) (follows the show's Look)"
        }
    }

    public static func summary(for profile: ScreenProfile, global: Look?, looks: [Look]) -> Summary {
        if let id = profile.screenLookID, let own = looks.first(where: { $0.id == id }) { return Summary(lookName: own.name, isOwn: true) }
        return Summary(lookName: global?.name, isOwn: false)
    }
}
