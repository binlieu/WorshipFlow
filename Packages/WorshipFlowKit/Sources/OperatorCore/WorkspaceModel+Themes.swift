// APP-001 / KI-023 / PRES-06: which theme a presentation uses. The choice is stored with the presentation; the
// live and preview themes follow the presentation that is live and the one that is open.
import Foundation
import Domain
import Persistence

extension WorkspaceModel {
    /// The theme chosen for the open presentation; nil means the role default.
    public var openThemeID: UUID? { openPresentationID.flatMap { presentationThemes[$0] } }

    /// The theme currently chosen for the presentation that is live (it follows `setTheme` at once). What the screens
    /// show is `shownThemeID`. It reaches audience screens only (`ThemeResolver`).
    public var liveThemeID: UUID? { showParts.liveDeck.flatMap { presentationThemes[$0.presentationID] } }

    /// R13: the theme the audience screens use for the live presentation. Captured when the show is triggered, so
    /// choosing another theme for the live presentation changes preview at once and the screens from the next trigger.
    /// `liveThemeID` is the theme currently chosen for the live presentation, which may be newer than this.
    public var shownThemeID: UUID? { capturedLiveThemeID }

    func learnThemes(of list: [Presentation]) {
        for p in list { presentationThemes[p.id] = p.themeID }     // a nil theme removes the entry
    }

    /// Reads the stored theme of one presentation that may belong to a library other than the selected one.
    func learnTheme(ofPresentation id: UUID) async {
        if let p = presentations.first(where: { $0.id == id }) { learnThemes(of: [p]); return }
        for library in libraries {
            if let list = try? await store.presentations(in: library.id), let p = list.first(where: { $0.id == id }) {
                learnThemes(of: [p])
                return
            }
        }
    }

    /// Chooses the theme for a presentation (nil: role default). A built-in or stored theme id; anything else is refused.
    public func setTheme(_ themeID: UUID?, forPresentation id: UUID) async {
        do {
            try await store.setTheme(themeID, forPresentation: id)
        } catch StoreError.invalidReference {
            lastError = "Could not choose the theme: that theme no longer exists. Choose another theme from the list."
            return
        } catch {
            lastError = Self.message(for: error, doing: "choose the theme")
            return
        }
        presentationThemes[id] = themeID
        await reloadPresentations()
        onAppearanceChange?()
    }

    /// After a custom theme was deleted (the store cleared it from presentations): re-reads every presentation's
    /// theme, then tells the app. Presentations in every library are read, not just the selected one.
    public func themesChanged() async {
        var fresh: [UUID: UUID] = [:]
        for library in libraries {
            if let list = await attempt("read the presentations", { try await self.store.presentations(in: library.id) }) {
                for p in list { if let theme = p.themeID { fresh[p.id] = theme } }
            }
        }
        presentationThemes = fresh
        await reloadPresentations()
        onAppearanceChange?()
    }
}
