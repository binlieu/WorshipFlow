// LIB-004c: the Scripture view, in the centre of Show. A reference field (English or Vietnamese book names, suggestions as you
// type, Return shows the passage), the two translations, the passage as the same slide thumbnails songs use, verse search, and the
// Translations screen. The decisions live in `ScriptureModel`; this file only draws them. There is no design picture for scripture,
// so it uses the existing tokens and header style and keeps to plain words.
import SwiftUI
import Domain
import OperatorCore
import ScriptureStore

enum ScriptureScreen: String, CaseIterable, Identifiable {
    case reference, search, translations
    var id: String { rawValue }
    var title: String {
        switch self {
        case .reference: "Reference"
        case .search: "Search"
        case .translations: "Translations"
        }
    }
}

struct ScriptureView: View {
    let app: AppModel
    @Bindable var workspace: WorkspaceModel
    @Bindable var scripture: ScriptureModel
    private var screen: ScriptureScreen {
        get { app.ui.scriptureScreen }
        nonmutating set { app.ui.scriptureScreen = newValue }
    }
    @FocusState private var focus: Field?

    private enum Field { case reference, search }

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
            content
        }
        .background(Tok.bg)
        .onAppear { askForFocus() }
        .onChange(of: app.ui.focusScripture) { _, _ in
            if screen == .translations { screen = .reference }
            askForFocus()
        }
        .onChange(of: screen) { _, now in
            if now == .reference { focus = .reference } else if now == .search { focus = .search }
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Scripture")
    }

    /// The window moves keyboard focus to the slide grid a moment after a mode or sheet change; ask again after that.
    private func askForFocus() {
        guard screen != .translations else { return }
        let wanted: Field = screen == .search ? .search : .reference
        focus = wanted
        Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(350))
            if app.ui.scriptureOpen, screen != .translations { focus = wanted }
        }
    }

    // MARK: Header

    private var header: some View {
        VStack(alignment: .leading, spacing: Space.s3) {
            HStack(spacing: Space.s3) {
                Image(systemName: "book.closed").foregroundStyle(Tok.muted)
                Text("Scripture").font(.system(size: 20, weight: .bold))
                Spacer(minLength: 4)
                Picker("Scripture screen", selection: Binding(get: { screen }, set: { screen = $0 })) {
                    ForEach(ScriptureScreen.allCases) { Text($0.title).tag($0) }
                }
                .pickerStyle(.segmented).labelsHidden().fixedSize().accessibilityLabel("Scripture screen")
                Button { app.ui.scriptureOpen = false; app.ui.focusGrid += 1 } label: { Image(systemName: "xmark") }
                    .buttonStyle(HeaderButtonStyle()).help("Close Scripture and go back to the songs")
                    .accessibilityLabel("Close Scripture")
            }
            switch screen {
            case .reference: referenceControls
            case .search: searchControls
            case .translations: EmptyView()
            }
        }
        .padding(.horizontal, Space.s5).padding(.vertical, Space.s4)
    }

    private var referenceControls: some View {
        VStack(alignment: .leading, spacing: Space.s3) {
            HStack(spacing: 6) {
                Image(systemName: "text.cursor").foregroundStyle(Tok.muted).accessibilityHidden(true)
                TextField("Type a reference: John 3:16-18, Giăng 3:16, Psalm 23", text: $scripture.referenceText)
                    .textFieldStyle(.plain).font(.system(size: 15))
                    .focused($focus, equals: .reference)
                    .onSubmit { show() }
                    .accessibilityLabel("Reference")
                KeyHint(key: "⌘J")
                Button("Show") { show() }.buttonStyle(HeaderButtonStyle()).disabled(scripture.primaryCode == nil)
                    .help("Show the passage in Preview (Return)")
            }
            .padding(.horizontal, 10).frame(height: 34)
            .background(Tok.surface2, in: RoundedRectangle(cornerRadius: Radius.md))
            .overlay(RoundedRectangle(cornerRadius: Radius.md).stroke(focus == .reference ? Tok.cyan : Tok.borderStrong, lineWidth: 1))
            if !scripture.suggestions.isEmpty {
                HStack(spacing: 6) {
                    Text("Books").font(.wfCaption).foregroundStyle(Tok.muted)
                    ForEach(scripture.suggestions) { suggestion in
                        Button(suggestion.name) { scripture.referenceText = suggestion.completion; focus = .reference }
                            .buttonStyle(HeaderButtonStyle())
                            .accessibilityLabel("Book \(suggestion.name)")
                    }
                    Spacer(minLength: 0)
                }
            }
            HStack(spacing: Space.s4) {
                translationPickers
                Stepper(value: Binding(get: { scripture.versesPerSlide }, set: { n in Task { await scripture.setVersesPerSlide(n) } }),
                        in: 1...ScriptureModel.mostVersesPerSlide) {
                    Text("\(scripture.versesPerSlide) verse\(scripture.versesPerSlide == 1 ? "" : "s") per slide").font(.system(size: 12))
                }
                .fixedSize()
                Spacer(minLength: 0)
                Button { Task { await scripture.addToPlaylist() } } label: { Label("Add to playlist", systemImage: "text.badge.plus") }
                    .buttonStyle(HeaderButtonStyle()).disabled(scripture.passage == nil)
                    .help("Keep the passage in the playlist. Only the reference and the translations are kept.")
                Button { Task { await scripture.saveAsPresentation() } } label: { Label("Save as presentation", systemImage: "square.and.arrow.down") }
                    .buttonStyle(HeaderButtonStyle()).disabled(scripture.passage == nil)
                    .help("Make an ordinary presentation you can edit, in the selected library")
            }
            if let message = scripture.choiceMessage { Text(message).font(.caption).foregroundStyle(Tok.warning) }
        }
    }

    private var translationPickers: some View {
        HStack(spacing: Space.s3) {
            Picker("First", selection: Binding(get: { scripture.primaryCode ?? "" }, set: { code in Task { await scripture.setPrimary(code) } })) {
                if scripture.primaryCode == nil { Text("None installed").tag("") }
                ForEach(scripture.translations) { Text($0.abbreviation).tag($0.code) }
            }
            .fixedSize().disabled(scripture.translations.isEmpty)
            .accessibilityLabel("First translation")
            Picker("Second", selection: Binding(get: { scripture.secondaryCode ?? "" }, set: { code in Task { await scripture.setSecondary(code.isEmpty ? nil : code) } })) {
                Text("No second translation").tag("")
                ForEach(scripture.translations.filter { $0.code != scripture.primaryCode }) { Text($0.abbreviation).tag($0.code) }
            }
            .fixedSize().disabled(scripture.translations.count < 2)
            .accessibilityLabel("Second translation")
        }
    }

    private func show() {
        let text = scripture.referenceText
        Task {
            await scripture.show(text)
            if scripture.passage != nil { app.ui.focusGrid += 1 }      // Return again, or the arrows, now drive the show
        }
    }

    // MARK: Search

    private var searchControls: some View {
        VStack(alignment: .leading, spacing: Space.s3) {
            HStack(spacing: 6) {
                Image(systemName: "magnifyingglass").foregroundStyle(Tok.muted).accessibilityHidden(true)
                TextField("Search the words of the verses", text: $scripture.searchText)
                    .textFieldStyle(.plain).font(.system(size: 15))
                    .focused($focus, equals: .search)
                    .onSubmit { Task { await scripture.search(scripture.searchText) } }
                    .onChange(of: scripture.searchText) { _, new in Task { await scripture.search(new) } }
                    .accessibilityLabel("Search verses")
            }
            .padding(.horizontal, 10).frame(height: 34)
            .background(Tok.surface2, in: RoundedRectangle(cornerRadius: Radius.md))
            .overlay(RoundedRectangle(cornerRadius: Radius.md).stroke(focus == .search ? Tok.cyan : Tok.borderStrong, lineWidth: 1))
            Text("Searches \(scripture.translations.first { $0.code == scripture.primaryCode }?.name ?? "the first translation"). Accents and capital letters do not matter: \"binh an\" finds \"bình an\".")
                .font(.caption).foregroundStyle(Tok.muted)
        }
    }

    // MARK: Content

    @ViewBuilder private var content: some View {
        switch screen {
        case .reference: referenceContent
        case .search: ScriptureSearchResults(scripture: scripture) { row in
            Task { await scripture.openSearchResult(row); screen = .reference; app.ui.focusGrid += 1 }
        }
        case .translations: ScriptureTranslationsView(scripture: scripture)
        }
    }

    @ViewBuilder private var referenceContent: some View {
        if scripture.isEmpty {
            ScriptureEmptyState(scripture: scripture) { screen = .translations }
        } else if let problem = workspace.openScripture?.problem ?? scripture.problem {
            VStack(spacing: 8) {
                Image(systemName: "exclamationmark.triangle.fill").font(.largeTitle).foregroundStyle(Tok.warning)
                Text(problem).font(.system(size: 14)).multilineTextAlignment(.center).textSelection(.enabled).frame(maxWidth: 520)
                    .accessibilityLabel("Problem: \(problem)")
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else if let passage = scripture.passage {
            PassageGrid(app: app, workspace: workspace, passage: passage) { scripture.selectSlide($0) }
        } else {
            VStack(spacing: 8) {
                Image(systemName: "book").font(.largeTitle).foregroundStyle(Tok.muted)
                Text("Type a reference and press Return").font(.title3)
                Text("English or Vietnamese book names both work: John 3:16-18, Giăng 3:16, 1 Cor 13, Ps 23. Use the Search tab to find a verse by its words.")
                    .font(.caption).foregroundStyle(Tok.muted).multilineTextAlignment(.center).frame(maxWidth: 480)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }
}

/// With nothing installed: says so, and offers Import.
struct ScriptureEmptyState: View {
    @Bindable var scripture: ScriptureModel
    let showTranslations: () -> Void

    var body: some View {
        VStack(spacing: 10) {
            Image(systemName: "books.vertical").font(.largeTitle).foregroundStyle(Tok.muted)
            Text("No Bible translation is installed").font(.title3)
            Text(ScriptureModel.emptyHint).font(.caption).foregroundStyle(Tok.muted).multilineTextAlignment(.center).frame(maxWidth: 480)
            HStack {
                Button("Import…") { chooseTranslationFile(scripture) }.buttonStyle(HeaderButtonStyle())
                Button("Translations") { showTranslations() }.buttonStyle(HeaderButtonStyle())
            }
            ScriptureImportStatus(scripture: scripture)
        }
        .padding(Space.s6)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .accessibilityElement(children: .contain)
    }
}

/// The passage as slide thumbnails, drawn like the song grid: a blue ring for Preview, a red ring and tag for Live.
struct PassageGrid: View {
    let app: AppModel
    @Bindable var workspace: WorkspaceModel
    let passage: ScripturePassage
    let select: (Int) -> Void

    private var deckID: UUID? { workspace.openScripture?.deckID }
    private var ringColor: Color { app.mode == .live ? Tok.liveFill : Tok.warning }

    var body: some View {
        VStack(spacing: 0) {
            if !passage.messages.isEmpty {
                VStack(alignment: .leading, spacing: 2) {
                    ForEach(passage.messages, id: \.self) { Text($0).font(.caption).foregroundStyle(Tok.warning).fixedSize(horizontal: false, vertical: true) }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, Space.s5).padding(.vertical, Space.s3)
                .accessibilityElement(children: .combine)
                .accessibilityLabel("Notes: \(passage.messages.joined(separator: " "))")
            }
            HStack {
                Text(passage.title).font(.system(size: 13, weight: .semibold))
                Text("\(passage.contents.count) slide\(passage.contents.count == 1 ? "" : "s")").font(.caption).foregroundStyle(Tok.muted)
                Spacer()
            }
            .padding(.horizontal, Space.s5).padding(.vertical, Space.s2)
            GeometryReader { geo in
                ScrollViewReader { proxy in
                    ScrollView {
                        LazyVGrid(columns: Array(repeating: GridItem(.flexible(minimum: 100, maximum: 300), spacing: SlideGridLayout.spacing, alignment: .top),
                                                 count: SlideGridLayout.columnCount(width: Double(geo.size.width))),
                                  alignment: .leading, spacing: SlideGridLayout.spacing) {
                            ForEach(passage.contents.indices, id: \.self) { i in cell(i).id(i) }
                        }
                        .padding(Space.s5)
                    }
                    .onChange(of: workspace.show.selectedIndex) { _, new in withAnimation { proxy.scrollTo(new) } }
                }
            }
        }
    }

    private func liveIndex() -> Int? {
        guard let deckID, app.show.liveDeck?.presentationID == deckID else { return nil }
        return app.show.liveIndex
    }

    private func cell(_ i: Int) -> some View {
        let selected = workspace.show.selectedIndex == i
        let live = liveIndex() == i
        let slide = passage.slides[i]
        return VStack(alignment: .leading, spacing: 4) {
            SlideThumbnail(app: app, slide: passage.contents[i])
                .overlay(alignment: .topLeading) { tag(live: live, selected: selected).padding(5) }
                .padding(3)
                .overlay(RoundedRectangle(cornerRadius: Radius.md).stroke(selected ? Tok.blue : .clear, lineWidth: 2))
                .padding(live ? 4 : 0)
                .overlay(RoundedRectangle(cornerRadius: Radius.lg).stroke(live ? ringColor : .clear, lineWidth: 3))
            HStack(spacing: 6) {
                Text("\(i + 1)").font(.system(size: 12, weight: .bold).monospacedDigit()).foregroundStyle(Tok.text)
                Text(slide.reference).font(.system(size: 12)).foregroundStyle(Tok.muted).lineLimit(1)
            }
            .padding(.horizontal, 4)
        }
        .contentShape(Rectangle())
        .onTapGesture(count: 2) { app.triggerSlide(i) }
        .onTapGesture { select(i) }
        .contextMenu { Button("Go Live") { app.triggerSlide(i) } }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Slide \(i + 1): \(passage.contents[i].primary)")
        .accessibilityValue([live ? "live" : nil, selected ? "in preview" : nil].compactMap { $0 }.joined(separator: ", "))
        .accessibilityAddTraits(selected ? .isSelected : [])
    }

    @ViewBuilder private func tag(live: Bool, selected: Bool) -> some View {
        if live {
            switch app.mode {
            case .cleared: Badge(text: "CLEARED", style: .warning)
            case .blackout: Badge(text: "BLACKOUT", style: .warning)
            default: Badge(text: "LIVE", style: .live)
            }
        } else if selected {
            Badge(text: "PREVIEW", style: .preview)
        }
    }
}

struct ScriptureSearchResults: View {
    @Bindable var scripture: ScriptureModel
    let open: (ScriptureSearchRow) -> Void

    var body: some View {
        if scripture.isEmpty {
            Text(scripture.emptyMessage).font(.caption).foregroundStyle(Tok.muted).padding(Space.s6).frame(maxWidth: .infinity, maxHeight: .infinity)
        } else if scripture.searchResults.isEmpty {
            Text(scripture.searchMessage ?? "Type a word or two. Every word must appear, and \"a quoted phrase\" must appear as written.")
                .font(.caption).foregroundStyle(Tok.muted).multilineTextAlignment(.center).padding(Space.s6)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            List {
                ForEach(scripture.searchResults) { row in
                    Button { open(row) } label: {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(row.reference).font(.system(size: 13, weight: .semibold))
                            Text(row.snippet).font(.system(size: 12)).foregroundStyle(Tok.muted).lineLimit(2)
                        }
                        .frame(maxWidth: .infinity, alignment: .leading).contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("\(row.reference): \(row.snippet)")
                    .accessibilityHint("Opens this verse in Preview")
                }
                if scripture.searchTruncated {
                    Text("More verses match. Add a word to narrow the list.").font(.caption).foregroundStyle(Tok.muted)
                }
            }
            .listStyle(.plain).scrollContentBackground(.hidden)
            .accessibilityLabel("Search results")
        }
    }
}
