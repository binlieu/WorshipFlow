// LIB-004c: the Scripture view's model. The installed translations, the two the operator chose, the typed reference and what it
// came to (a passage, or a problem in plain words), search, and keeping a passage. The words come from `ScriptureStore`; the
// passage reaches the screens through the workspace (preview first, then the same Go Live, Next and Previous as a song).
// Foundation and Observation only: the views live in the app target. Every read of the library is awaited off the main actor.
import Foundation
import Observation
import Domain
import Persistence
import ScriptureEngine
import ScriptureStore

/// A passage ready to show: the engine's slides, the slides as the screens get them, and the reference it was made from.
public struct ScripturePassage: Equatable, Sendable, Identifiable {
    public internal(set) var id: UUID
    /// "John 3:16–18 (KJV)".
    public var title: String
    public var slides: [ScriptureSlide]
    /// One per slide, in order: the words with the reference as the last line (`ScriptureSlideContent`).
    public var contents: [SlideContent]
    /// What a playlist item keeps: the reference and the translation codes.
    public var spec: ScriptureItemSpec
    /// Plain notes for the operator: verses a translation lacks, chapters numbered differently.
    public var messages: [String]
}

public enum ScriptureResolution: Sendable {
    case ready(ScripturePassage)
    /// A translation the item needs is not in the library. The text says which.
    case notInstalled(String)
    case failed(String)
}

public enum ScriptureImportState: Equatable, Sendable {
    case idle
    case running(done: Int, total: Int)
    case finished(String)
    case failed(String)
    /// The code is already in the library; nothing was changed. `confirmReplace()` or `cancelReplace()` answers.
    case needsReplace(code: String, name: String)
}

public struct PendingRemoval: Equatable, Sendable {
    public var code: String
    public var name: String
}

public struct ScriptureSearchRow: Equatable, Sendable, Identifiable {
    public var ref: VerseRef
    /// In the language of the translation searched ("Giăng 3:16").
    public var reference: String
    public var snippet: String
    public var id: String { "\(ref.book.rawValue)-\(ref.chapter)-\(ref.verse)" }
}

@MainActor
@Observable
public final class ScriptureModel {
    // MARK: State the interface reads

    public internal(set) var translations: [StoredTranslation] = []
    /// False until the first read of the library has finished, so the view does not flash "nothing installed".
    public internal(set) var hasLoaded = false
    public internal(set) var primaryCode: String?
    public internal(set) var secondaryCode: String?
    public internal(set) var versesPerSlide = 1
    /// What is in the reference field.
    public var referenceText = ""
    /// Why there is no passage, in plain words; nil when there is one or nothing was asked.
    public internal(set) var problem: String?
    public internal(set) var passage: ScripturePassage?
    /// A refused choice of translations ("choose a different one").
    public internal(set) var choiceMessage: String?
    public var searchText = ""
    public internal(set) var searchResults: [ScriptureSearchRow] = []
    public internal(set) var searchTruncated = false
    public internal(set) var searchMessage: String?
    public internal(set) var importState = ScriptureImportState.idle
    public internal(set) var pendingRemoval: PendingRemoval?
    public internal(set) var translationsError: String?

    /// Called on every change of `importState` (tests watch the progress through it).
    @ObservationIgnored public var onImportState: ((ScriptureImportState) -> Void)?
    /// The theme whose text boxes decide how much fits on a slide. The app answers with the audience screen's theme.
    @ObservationIgnored public var themeProvider: @MainActor () -> Theme = { .fullScreen }

    @ObservationIgnored let store: ScriptureStore
    @ObservationIgnored let library: ScriptureLibrary
    @ObservationIgnored let stateStore: LibraryStore?
    @ObservationIgnored weak var workspace: WorkspaceModel?
    @ObservationIgnored var pendingImport: TranslationFile?
    /// Awaited before each read of the library for a passage. Nil in the app; tests hold and release a read through it.
    @ObservationIgnored var readGate: (@MainActor () async -> Void)?
    @ObservationIgnored var searchToken = 0
    @ObservationIgnored var showToken = 0

    static let choicesKey = "scripture.choices"

    /// FIX-F item 4: every request that puts a passage, a playlist item or a song into preview takes a number from one counter (the
    /// workspace's), and checks after each await that it is still the newest. Without a workspace the model counts alone.
    func beginRequest() -> Int {
        if let workspace { return workspace.beginPreviewRequest() }
        showToken += 1
        return showToken
    }

    func isCurrent(_ token: Int) -> Bool { workspace?.isCurrentPreviewRequest(token) ?? (token == showToken) }

    public init(store: ScriptureStore, stateStore: LibraryStore? = nil) {
        self.store = store
        self.library = ScriptureLibrary(store: store)
        self.stateStore = stateStore
    }

    /// Joins the workspace: a shown passage goes into its preview, and its playlist can open and keep passages.
    public func connect(_ workspace: WorkspaceModel) {
        self.workspace = workspace
        workspace.scripture = self
    }

    // MARK: Loading and choices

    public var isEmpty: Bool { hasLoaded && translations.isEmpty }

    /// The second sentence of the empty state, under its title.
    public static let emptyHint = "WorshipFlow comes with no Bible text. Import a translation file you are allowed to use; it stays in your library."

    public var emptyMessage: String {
        "No Bible translation is installed on this Mac. WorshipFlow comes with no Bible text: import a translation file you are allowed to use, and it stays in your library."
    }

    public func load() async {
        do { translations = try await store.translations() } catch {
            translationsError = Self.message(for: error)
            translations = []
        }
        var saved = Choices()
        if let text = try? await stateStore?.state(for: Self.choicesKey), let data = text.data(using: .utf8),
           let decoded = try? JSONDecoder().decode(Choices.self, from: data) { saved = decoded }
        primaryCode = installed(saved.primary) ? saved.primary : translations.first?.code
        secondaryCode = installed(saved.secondary) && saved.secondary != primaryCode ? saved.secondary : nil
        versesPerSlide = min(max(saved.versesPerSlide ?? 1, 1), Self.mostVersesPerSlide)
        hasLoaded = true
    }

    public static let mostVersesPerSlide = 4

    func installed(_ code: String?) -> Bool {
        guard let code else { return false }
        return translations.contains { $0.code.caseInsensitiveCompare(code) == .orderedSame }
    }

    func translation(_ code: String?) -> StoredTranslation? {
        guard let code else { return nil }
        return translations.first { $0.code.caseInsensitiveCompare(code) == .orderedSame }
    }

    public func setPrimary(_ code: String) async {
        guard installed(code) else { return }
        choiceMessage = nil
        if secondaryCode.map({ $0.caseInsensitiveCompare(code) == .orderedSame }) == true { secondaryCode = nil }
        primaryCode = translation(code)?.code
        await saveChoices()
        await refresh()
    }

    public func setSecondary(_ code: String?) async {
        if let code {
            guard installed(code) else { return }
            if primaryCode?.caseInsensitiveCompare(code) == .orderedSame {
                choiceMessage = "Choose a different translation for the second language: it is the same as the first."
                return
            }
        }
        choiceMessage = nil
        secondaryCode = translation(code)?.code
        await saveChoices()
        await refresh()
    }

    public func setVersesPerSlide(_ count: Int) async {
        versesPerSlide = min(max(count, 1), Self.mostVersesPerSlide)
        await saveChoices()
        await refresh()
    }

    private struct Choices: Codable {
        var primary: String?
        var secondary: String?
        var versesPerSlide: Int?
    }

    func saveChoices() async {
        guard let stateStore else { return }
        let choices = Choices(primary: primaryCode, secondary: secondaryCode, versesPerSlide: versesPerSlide)
        guard let data = try? JSONEncoder().encode(choices), let text = String(data: data, encoding: .utf8) else { return }
        // A convenience like the saved place: not worth interrupting the operator when it cannot be written.
        try? await stateStore.setState(text, for: Self.choicesKey)
    }

    /// Shows the passage again after a choice changed, when one is shown. It is made again from the shown passage's own ranges (never
    /// from the text in the field, which may be an edit that was not submitted), keeps its identity and its playlist item, and
    /// leaves the field alone.
    private func refresh() async {
        guard let shown = passage, let primary = primaryCode else { return }
        let token = beginRequest()
        let itemID = workspace?.openScripture?.itemID
        let options = ScriptureSlideLimits.options(theme: themeProvider(), bilingual: secondaryCode != nil, versesPerSlide: versesPerSlide)
        let found: ScriptureLookup
        await readGate?()
        do { found = try await library.lookup(ranges: Self.ranges(of: shown.spec), primary: primary, secondary: secondaryCode, options: options) } catch {
            guard isCurrent(token) else { return }
            fail(Self.message(for: error))
            return
        }
        guard isCurrent(token) else { return }
        guard let presentation = found.presentation, !presentation.slides.isEmpty else {
            let said = found.presentation?.report.messages.joined(separator: " ") ?? ""
            fail(said.isEmpty ? "No verses were found for that reference." : said)
            return
        }
        if let text = ScripturePassageLimit.refusal(slides: presentation.slides.count, title: presentation.title) { fail(text); return }
        var made = Self.passage(from: found, presentation: presentation)
        made.id = shown.id
        problem = nil
        passage = made
        workspace?.openScripturePassage(made, itemID: itemID, adopt: false)
    }

    /// FIX-F item 3: the library changed under the shown passage (`code` was removed or replaced). The passage is read again from the
    /// library by its own ranges and codes. A primary translation that is gone gives the plain "not installed" state (the missing code is
    /// never kept for Add to playlist); a second one that is gone is dropped with a notice. Only the preview changes, never live.
    func reshow(after code: String) async {
        guard let shown = passage else { return }
        let uses = shown.spec.translationCodes.contains { $0.caseInsensitiveCompare(code) == .orderedSame }
        guard uses else { return }
        let token = beginRequest()
        let itemID = workspace?.openScripture?.itemID
        var spec = shown.spec
        var notice: String?
        if let second = spec.secondaryCode, !installed(second) {
            spec.secondaryCode = nil
            notice = "The second translation “\(second)” is no longer installed, so the passage is shown without it."
        }
        guard installed(spec.primaryCode) else {
            let text = Self.notInstalledText(spec.primaryCode, spec, keptItem: itemID != nil)
            if let itemID, let item = workspace?.playlistItems.first(where: { $0.id == itemID }) {
                workspace?.openScriptureProblem(text, item: item, title: spec.label)
            } else {
                fail(text)
            }
            return
        }
        let options = ScriptureSlideLimits.options(theme: themeProvider(), bilingual: spec.secondaryCode != nil, versesPerSlide: versesPerSlide)
        let found: ScriptureLookup
        await readGate?()
        do { found = try await library.lookup(ranges: Self.ranges(of: spec), primary: spec.primaryCode, secondary: spec.secondaryCode, options: options) } catch {
            guard isCurrent(token) else { return }
            fail(Self.message(for: error))
            return
        }
        guard isCurrent(token) else { return }
        guard let presentation = found.presentation, !presentation.slides.isEmpty else {
            let said = found.presentation?.report.messages.joined(separator: " ") ?? ""
            fail(said.isEmpty ? "No verses were found for that reference." : said)
            return
        }
        if let text = ScripturePassageLimit.refusal(slides: presentation.slides.count, title: presentation.title) { fail(text); return }
        var made = Self.passage(from: found, presentation: presentation)
        made.id = shown.id
        if let notice { made.messages.append(notice) }
        problem = nil
        passage = made
        workspace?.openScripturePassage(made, itemID: itemID, adopt: false)
    }

    func reloadTranslations() async {
        do { translations = try await store.translations(); translationsError = nil } catch {
            translationsError = Self.message(for: error)
        }
    }

    static func message(for error: Error) -> String {
        if let known = error as? ScriptureStoreError { return known.message }
        return "The Bible library could not be read: \(error.localizedDescription)"
    }

    // MARK: The typed reference

    /// Book names to offer for what is typed so far.
    public var suggestions: [ScriptureSuggestion] { ScriptureSuggestions.suggest(referenceText) }

    /// Reads `text` as a reference (Return in the field), and shows the passage in preview. A reference that cannot be read in full
    /// gives a problem in plain words and no slides: half a passage is never shown.
    public func show(_ text: String) async {
        referenceText = text
        choiceMessage = nil
        let token = beginRequest()
        guard let primary = primaryCode else {
            fail(isEmpty ? "No translation is installed. Import a translation first (Translations, then Import)." : emptyMessage)
            return
        }
        guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            fail("Type a reference such as John 3:16, then press Return.")
            return
        }
        let options = ScriptureSlideLimits.options(theme: themeProvider(), bilingual: secondaryCode != nil, versesPerSlide: versesPerSlide)
        let found: ScriptureLookup
        await readGate?()
        do { found = try await library.lookup(text, primary: primary, secondary: secondaryCode, options: options) } catch {
            guard isCurrent(token) else { return }
            fail(Self.message(for: error))
            return
        }
        guard isCurrent(token) else { return }       // a newer Return came in while this one was reading
        if !found.outcome.problems.isEmpty {
            fail(found.outcome.problems.map(\.message).joined(separator: " "))
            return
        }
        guard let presentation = found.presentation, !presentation.slides.isEmpty else {
            let said = found.presentation?.report.messages.joined(separator: " ") ?? ""
            fail(said.isEmpty ? "No verses were found for that reference." : said)
            return
        }
        if let text = ScripturePassageLimit.refusal(slides: presentation.slides.count, title: presentation.title) { fail(text); return }
        let made = Self.passage(from: found, presentation: presentation)
        problem = nil
        passage = made
        workspace?.openScripturePassage(made)
    }

    func fail(_ text: String) {
        problem = text
        passage = nil
        workspace?.closeScripture()
    }

    static func passage(from found: ScriptureLookup, presentation: ScripturePresentation) -> ScripturePassage {
        let ranges = found.outcome.ranges.map {
            ScriptureItemSpec.Range(book: $0.start.book.rawValue, startChapter: $0.start.chapter, startVerse: $0.start.verse,
                                    endChapter: $0.end.chapter, endVerse: $0.end.verse)
        }
        let spec = ScriptureItemSpec(label: presentation.title, ranges: ranges, primaryCode: found.primary.code,
                                     secondaryCode: found.secondary?.code)
        return ScripturePassage(id: UUID(), title: presentation.title, slides: presentation.slides,
                                contents: presentation.slides.map(ScriptureSlideContent.content(for:)), spec: spec,
                                messages: found.notes + presentation.report.messages)
    }

    static func ranges(of spec: ScriptureItemSpec) -> [VerseRange] {
        spec.ranges.map {
            VerseRange(book: BookID($0.book), startChapter: $0.startChapter, startVerse: $0.startVerse,
                       endChapter: $0.endChapter, endVerse: $0.endVerse)
        }
    }

    /// "John 3:16–18": the reference of a stored item as it would be typed, for the field.
    static func referenceText(of spec: ScriptureItemSpec) -> String {
        ReferenceFormatter.format(ranges(of: spec), language: .english)
    }

    // MARK: A stored passage (a playlist item)

    /// Reads the passage a playlist item keeps, from the library as it is now. A translation that is gone gives `.notInstalled`.
    public func resolve(_ spec: ScriptureItemSpec) async -> ScriptureResolution {
        await readGate?()
        for code in spec.translationCodes {
            do { _ = try await store.translation(code: code) } catch ScriptureStoreError.notFound {
                return .notInstalled(Self.notInstalledText(code, spec))
            } catch { return .failed(Self.message(for: error)) }
        }
        let options = ScriptureSlideLimits.options(theme: themeProvider(), bilingual: spec.secondaryCode != nil, versesPerSlide: versesPerSlide)
        do {
            let found = try await library.lookup(ranges: Self.ranges(of: spec), primary: spec.primaryCode, secondary: spec.secondaryCode, options: options)
            guard let presentation = found.presentation, !presentation.slides.isEmpty else {
                let said = found.presentation?.report.messages.joined(separator: " ") ?? ""
                return .failed(said.isEmpty ? "“\(spec.label)” has no verses in the library." : said)
            }
            if let text = ScripturePassageLimit.refusal(slides: presentation.slides.count, title: presentation.title) { return .failed(text) }
            var made = Self.passage(from: found, presentation: presentation)
            made.spec = spec                    // the item keeps its own label and codes
            made.title = spec.label
            return .ready(made)
        } catch ScriptureStoreError.notFound(let code) {
            return .notInstalled(Self.notInstalledText(code, spec))
        } catch { return .failed(Self.message(for: error)) }
    }

    static func notInstalledText(_ code: String, _ spec: ScriptureItemSpec, keptItem: Bool = true) -> String {
        let end = keptItem ? "remove the item" : "choose another translation and show the passage again"
        return "The translation “\(code)” is not installed on this Mac, so “\(spec.label)” cannot be shown. Import it again (Scripture, Translations) or \(end)."
    }

    /// For a playlist row: a plain warning when a translation the item needs is not installed; nil when all is well (and before
    /// the first read of the library, so no row flashes a warning at launch).
    public func availability(of spec: ScriptureItemSpec) -> String? {
        guard hasLoaded else { return nil }
        let missing = spec.translationCodes.filter { !installed($0) }
        guard !missing.isEmpty else { return nil }
        return "Translation not installed: \(missing.joined(separator: ", "))"
    }

    /// A passage opened from the playlist becomes the one the view shows, with its reference in the field.
    func adopt(_ made: ScripturePassage) {
        passage = made
        problem = nil
        referenceText = Self.referenceText(of: made.spec)
    }

    func clearPassage() {
        passage = nil
    }

    // MARK: The slides in preview

    /// Puts the slide in preview (never live).
    public func selectSlide(_ index: Int) { workspace?.selectSlide(index) }

    // MARK: Keeping a passage

    public func addToPlaylist() async {
        guard let passage else { problem = "Show a passage first, then add it to the playlist."; return }
        await workspace?.addScriptureToPlaylist(passage.spec)
    }

    /// Makes an ordinary presentation of the shown passage (words and references as they are on the slides) and opens it for editing.
    @discardableResult
    public func saveAsPresentation() async -> Presentation? {
        guard let passage else { problem = "Show a passage first, then save it as a presentation."; return nil }
        return await workspace?.saveScriptureAsPresentation(title: passage.title, contents: passage.contents)
    }
}
