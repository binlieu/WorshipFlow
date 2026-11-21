// LIB-005: after a program import, the themes and Looks it brought are read in. Screens, props and the chosen Look are not touched.
import Foundation
import Domain

extension SettingsModel {
    public func reloadThemesAndLooksAfterProgramImport() async {
        // The store lists themes by folded name, which is the order the rest of the app shows them in.
        if let themes = try? await store.themes() { customThemes = themes }
        if let stored = try? await store.looks(), !stored.isEmpty {
            looks = stored
            if !stored.contains(where: { $0.id == selectedLookID }) { selectedLookID = stored[0].id }
        }
    }
}
