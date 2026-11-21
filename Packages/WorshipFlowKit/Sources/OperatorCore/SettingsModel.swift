// APP-001 / KI-025 / KI-023: screen profiles, Looks, props and custom themes, read from and written to SQLite.
// Changes take effect in memory at once (the screens must not wait for the disk) and are written in order on a
// chain. A failed write sets `lastError` with a message a volunteer can act on; it never throws at the interface.
// Foundation and Observation only; the views live in the app target.
import Foundation
import Observation
import Domain
import Persistence

@MainActor
@Observable
public final class SettingsModel {
    // MARK: State the interface reads

    public internal(set) var profiles: [ScreenProfile] = []
    public internal(set) var looks: [Look] = []
    public internal(set) var selectedLookID: UUID?
    public internal(set) var props: [Prop] = []
    /// Custom themes only, by folded name. Built-in themes live in code.
    public internal(set) var customThemes: [Theme] = []
    public internal(set) var lastError: String?
    /// Things that happened at load that the operator may want to know (an old file that could not be read).
    public internal(set) var notices: [String] = []
    public internal(set) var isLoaded = false

    /// Built-in themes first, then the custom ones.
    public var themes: [Theme] { Theme.builtIn + customThemes }
    public var currentLook: Look? { looks.first { $0.id == selectedLookID } }

    /// Called on the main actor after a change to the screen profiles, so the app can re-plan its outputs.
    @ObservationIgnored public var onProfilesChange: (@MainActor () -> Void)?
    /// Called after a change to Looks, props or themes, so the app can publish scenes again.
    @ObservationIgnored public var onAppearanceChange: (@MainActor () -> Void)?

    // MARK: Internals

    @ObservationIgnored let store: LibraryStore
    @ObservationIgnored private let legacy: LegacySettingsFiles?
    @ObservationIgnored private let defaultProfiles: @MainActor () -> [ScreenProfile]
    @ObservationIgnored private var tail: Task<Void, Never>?
    /// False when the stored profiles could not be read: writing the (replace-all) profile set would destroy them.
    @ObservationIgnored private var profilesWritable = true

    static let selectedLookKey = "settings.selectedLook"
    static let legacyImportKey = "settings.legacyImport"

    /// - Parameters:
    ///   - legacy: the old JSON files to import once into empty tables; nil skips the import.
    ///   - defaultProfiles: the screens a first launch starts with.
    public init(store: LibraryStore, legacy: LegacySettingsFiles? = nil,
                defaultProfiles: @escaping @MainActor () -> [ScreenProfile]) {
        self.store = store
        self.legacy = legacy
        self.defaultProfiles = defaultProfiles
    }

    // MARK: Loading

    /// Imports the old JSON files once if the tables are empty, then reads everything. A first launch gets the
    /// default screens and one "Standard" Look.
    public func load() async {
        await importLegacyIfNeeded()

        do {
            profiles = try await store.screenProfiles()
        } catch {
            profilesWritable = false
            profiles = defaultProfiles()
            lastError = Self.message(for: error, doing: "read the screen settings")
                + " Default screens are used for now, and the stored settings are left as they are."
        }
        if profiles.isEmpty, profilesWritable {
            profiles = defaultProfiles()
            persistProfiles()
        }

        customThemes = Self.sorted((await attempt("read the themes") { try await self.store.themes() }) ?? [])
        props = await attempt("read the props") { try await self.store.props() } ?? []
        var stored = await attempt("read the Looks") { try await self.store.looks() } ?? []
        if stored.isEmpty {
            let standard = Look(id: UUID(), name: "Standard")
            stored = [standard]
            persist("save the Look") { [store] in try await store.saveLook(standard) }
        }
        looks = stored
        let saved = try? await store.state(for: Self.selectedLookKey)
        selectedLookID = saved.flatMap(UUID.init(uuidString:)).flatMap { id in stored.contains { $0.id == id } ? id : nil }
            ?? stored[0].id
        isLoaded = true
    }

    /// Waits until every change made so far has been written (or has failed and been reported).
    public func flush() async { await tail?.value }

    public func dismissError() { lastError = nil }

    // MARK: Legacy import

    private func importLegacyIfNeeded() async {
        guard let legacy else { return }
        if let done = try? await store.state(for: Self.legacyImportKey), done == "done" { return }
        var complete = true

        if await tableIsEmpty({ try await self.store.screenProfiles() }) {
            switch LegacySettings.readProfiles(legacy.screenProfilesURL) {
            case .missing: break
            case .unreadable(let why):
                complete = false
                notices.append("The old screen settings file could not be read and was left as it is. (\(why))")
            case .loaded(let old):
                if await attempt("import the old screen settings", { try await self.store.saveScreenProfiles(old) }) == nil { complete = false }
            }
        }

        let emptyLooks = await tableIsEmpty { try await self.store.looks() }
        let emptyProps = await tableIsEmpty { try await self.store.props() }
        if emptyLooks, emptyProps {
            switch LegacySettings.readLooks(legacy.looksURL) {
            case .missing: break
            case .unreadable(let why):
                complete = false
                notices.append("The old Looks file could not be read and was left as it is. (\(why))")
            case .loaded(let old):
                if await importLooks(old) == false { complete = false }
            }
        }
        if complete {
            _ = await attempt("remember the import") { try await self.store.setState("done", for: Self.legacyImportKey) }
        }
    }

    private func importLooks(_ old: LegacyLookLibrary) async -> Bool {
        let result: Bool? = await attempt("import the old Looks") {
            for look in old.looks { try await self.store.saveLook(look) }
            for stored in old.props { try await self.store.saveProp(stored.prop, bookmark: stored.bookmark) }
            if let selected = old.selectedLookID, old.looks.contains(where: { $0.id == selected }) {
                try await self.store.setState(selected.uuidString, for: Self.selectedLookKey)
            }
            return true
        }
        return result == true
    }

    /// True only when the table was read and has no rows. An unreadable table is never imported over.
    private func tableIsEmpty<T>(_ read: () async throws -> [T]) async -> Bool {
        guard let rows = try? await read() else { return false }
        return rows.isEmpty
    }

    // MARK: Screen profiles (OUT-002)

    public func updateProfile(_ profile: ScreenProfile) {
        guard let i = profiles.firstIndex(where: { $0.id == profile.id }), profiles[i] != profile else { return }
        profiles[i] = profile
        persistProfiles()
        onProfilesChange?()
    }

    private func persistProfiles() {
        guard profilesWritable else { return }
        let snapshot = profiles
        persist("save the screen settings") { [store] in try await store.saveScreenProfiles(snapshot) }
    }

    // MARK: Looks (SCRN-08)

    public func screenLook(for screenID: UUID) -> ScreenLook { currentLook?.screenLook(for: screenID) ?? .standard }

    public func selectLook(_ id: UUID) {
        guard id != selectedLookID, looks.contains(where: { $0.id == id }) else { return }
        selectedLookID = id
        persistSelectedLook()
        onAppearanceChange?()
    }

    /// A Look that starts as a copy of the current one, selected.
    @discardableResult
    public func addLook() -> Look {
        var look = currentLook ?? Look(id: UUID(), name: "Look")
        look.id = UUID()
        look.name = "Look \(looks.count + 1)"
        looks.append(look)
        selectedLookID = look.id
        persistLook(look)
        persistSelectedLook()
        onAppearanceChange?()
        return look
    }

    public func renameLook(_ id: UUID, to name: String) {
        guard let i = looks.firstIndex(where: { $0.id == id }), looks[i].name != name else { return }
        guard !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            lastError = "Could not rename the Look: a name is needed. Type at least one letter and try again."
            return
        }
        looks[i].name = name
        persistLook(looks[i])
    }

    /// The last Look cannot be deleted: a screen always has one.
    public func deleteLook(_ id: UUID) {
        guard looks.count > 1, let i = looks.firstIndex(where: { $0.id == id }) else { return }
        looks.remove(at: i)
        persist("delete the Look") { [store] in try await store.deleteLook(id: id) }
        if selectedLookID == id {
            selectedLookID = looks[min(i, looks.count - 1)].id
            persistSelectedLook()
        }
        onAppearanceChange?()
    }

    public func setTheme(_ themeID: UUID?, forScreen screenID: UUID) {
        editScreenLook(screenID) { $0.themeID = themeID }
    }

    public func setLayer(_ layer: LayerKind, visible: Bool, forScreen screenID: UUID) {
        editScreenLook(screenID) { if visible { $0.visibleLayers.insert(layer) } else { $0.visibleLayers.remove(layer) } }
    }

    private func editScreenLook(_ screenID: UUID, _ change: (inout ScreenLook) -> Void) {
        guard let i = looks.firstIndex(where: { $0.id == selectedLookID }) else { return }
        var screenLook = looks[i].screenLook(for: screenID)
        let before = screenLook
        change(&screenLook)
        guard screenLook != before else { return }
        looks[i].screens[screenID] = screenLook
        persistLook(looks[i])
        onAppearanceChange?()
    }

    private func persistLook(_ look: Look) {
        persist("save the Look") { [store] in try await store.saveLook(look) }
    }

    private func persistSelectedLook() {
        let text = selectedLookID?.uuidString
        persist("remember the selected Look") { [store] in try await store.setState(text, for: Self.selectedLookKey) }
    }

    // MARK: Props (MEDIA-08)

    /// Adds a prop. `bookmark` is the security-scoped bookmark of its image file, stored so access survives relaunches.
    public func addProp(_ prop: Prop, bookmark: Data?) {
        guard !props.contains(where: { $0.id == prop.id }) else { return }
        props.append(prop)
        persist("save the prop") { [store] in try await store.saveProp(prop, bookmark: bookmark) }
        onAppearanceChange?()
    }

    public func setProp(_ id: UUID, isOn: Bool) {
        guard let i = props.firstIndex(where: { $0.id == id }), props[i].isOn != isOn else { return }
        props[i].isOn = isOn
        let prop = props[i]
        persist("save the prop") { [store] in try await store.saveProp(prop, bookmark: nil) }
        onAppearanceChange?()
    }

    public func removeProp(_ id: UUID) {
        guard let i = props.firstIndex(where: { $0.id == id }) else { return }
        props.remove(at: i)
        persist("remove the prop") { [store] in try await store.deleteProp(id: id) }
        onAppearanceChange?()
    }

    /// Follows a moved or renamed file, or stores a fresh bookmark for a stale one. Does not redraw anything.
    public func updatePropLocation(_ id: UUID, path: String, bookmark: Data?) {
        guard let i = props.firstIndex(where: { $0.id == id }) else { return }
        props[i].imagePath = path
        let prop = props[i]
        persist("save the prop") { [store] in try await store.saveProp(prop, bookmark: bookmark) }
    }

    /// The stored bookmark for a prop, read from the library.
    public func bookmark(forProp id: UUID) async -> Data? {
        try? await store.bookmark(forProp: id)
    }

    // MARK: Custom themes (PRES-06)

    /// A new theme that starts as a copy of "Full screen". Returns nil (and sets `lastError`) if the name is blank.
    @discardableResult
    public func createTheme(name: String) -> Theme? {
        guard let name = Self.validName(name) else { return blankNameError("create the theme"); }
        var theme = Theme.fullScreen
        theme.id = UUID()
        theme.name = name
        add(theme)
        return theme
    }

    /// A copy of any theme (built-in or custom) with a new id and the name "<name> copy".
    @discardableResult
    public func duplicateTheme(_ id: UUID) -> Theme? {
        guard var theme = themes.first(where: { $0.id == id }) else { return nil }
        theme.id = UUID()
        theme.name = theme.name + " copy"
        add(theme)
        return theme
    }

    public func renameTheme(_ id: UUID, to name: String) {
        guard let i = customThemes.firstIndex(where: { $0.id == id }) else { return }
        guard let name = Self.validName(name) else { _ = blankNameError("rename the theme"); return }
        guard customThemes[i].name != name else { return }
        customThemes[i].name = name
        customThemes = Self.sorted(customThemes)
        persistTheme(id)
        onAppearanceChange?()
    }

    /// Changes one custom theme. Built-in themes cannot be edited; duplicate one first.
    public func updateTheme(_ id: UUID, _ change: (inout Theme) -> Void) {
        guard let i = customThemes.firstIndex(where: { $0.id == id }) else { return }
        var theme = customThemes[i]
        change(&theme)
        theme.id = id
        theme.name = customThemes[i].name           // renaming goes through `renameTheme`
        theme = ThemeEditing.clamped(theme)
        guard theme != customThemes[i] else { return }
        customThemes[i] = theme
        persistTheme(id)
        onAppearanceChange?()
    }

    /// Deletes a custom theme. Screens that used it fall back to their default; presentations that used it lose
    /// the choice (the store clears that in the same transaction; the caller reloads presentations).
    public func deleteTheme(_ id: UUID) async {
        guard customThemes.contains(where: { $0.id == id }) else { return }
        await flush()
        let ok: Void? = await attempt("delete the theme") { try await self.store.deleteTheme(id: id) }
        guard ok != nil else { return }
        customThemes.removeAll { $0.id == id }
        for i in looks.indices {
            var look = looks[i]
            for (screen, screenLook) in look.screens where screenLook.themeID == id {
                look.screens[screen]?.themeID = nil
            }
            if look != looks[i] {
                looks[i] = look
                persistLook(look)
            }
        }
        onAppearanceChange?()
    }

    private func add(_ theme: Theme) {
        customThemes = Self.sorted(customThemes + [theme])
        persistTheme(theme.id)
        onAppearanceChange?()
    }

    private func persistTheme(_ id: UUID) {
        guard let theme = customThemes.first(where: { $0.id == id }) else { return }
        persist("save the theme") { [store] in try await store.saveTheme(theme) }
    }

    private func blankNameError(_ what: String) -> Theme? {
        lastError = "Could not \(what): a name is needed. Type at least one letter and try again."
        return nil
    }

    private static func validName(_ name: String) -> String? {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    private static func sorted(_ themes: [Theme]) -> [Theme] {
        themes.sorted { SearchFolding.fold($0.name) < SearchFolding.fold($1.name) }
    }

    // MARK: Writing

    /// Queues a write behind the earlier ones, so changes reach the file in the order they were made.
    private func persist(_ what: String, _ operation: @escaping @Sendable () async throws -> Void) {
        let previous = tail
        tail = Task { [weak self] in
            await previous?.value
            do { try await operation() } catch {
                self?.lastError = Self.message(for: error, doing: what)
            }
        }
    }

    private func attempt<T>(_ what: String, _ body: () async throws -> T) async -> T? {
        do { return try await body() } catch {
            lastError = Self.message(for: error, doing: what)
            return nil
        }
    }

    static func message(for error: Error, doing what: String) -> String {
        if let store = error as? StoreError {
            switch store {
            case .invalidName: return "Could not \(what): a name is needed. Type at least one letter and try again."
            case .notFound: return "Could not \(what): that item no longer exists. Choose it again from the list."
            case .invalidReference: return "Could not \(what): the settings refer to something that does not exist."
            case .unknownMigration: return "Could not \(what): the library file is from a different version of the app."
            }
        }
        return "Could not \(what): \(error.localizedDescription) The change is in effect now but may be lost when the app quits. Try again; if it keeps failing, restart the app."
    }
}
