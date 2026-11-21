// OUT-004: the operator window. Libraries and playlists on the left, the open presentation in the middle with
// search above it, live previews and controls on the right, transport along the bottom. Errors appear in a bar at
// the top of this window and never on an output (NFR-08).
import SwiftUI
import Domain
import OperatorCore

struct ContentView: View {
    @Bindable var app: AppModel

    var body: some View {
        Group {
            if let problem = app.libraryProblem {
                LibraryProblemView(problem: problem)
            } else if let workspace = app.workspace {
                WorkspaceView(app: app, workspace: workspace)
            } else {
                SoakView(app: app)
            }
        }
        .frame(minWidth: 1100, minHeight: 640)
        .background(OperatorWindowGuardInstaller())     // R4: the window does not close while the screens are open
    }
}

/// Shown instead of the workspace when the library file cannot be opened. The file is never touched.
struct LibraryProblemView: View {
    let problem: LibraryProblem

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label("The song library could not be opened", systemImage: "exclamationmark.triangle.fill")
                .font(.title2.bold()).foregroundStyle(.orange)
            Text("WORSHIPFLOW looked for the library here:")
            Text(problem.path).font(.system(.body, design: .monospaced)).textSelection(.enabled)
            Text(problem.message).foregroundStyle(.secondary).textSelection(.enabled)
            Text("The file has not been changed or deleted. Check that the disk is connected and the folder is writable, or move the file aside and restart to begin a new library. Restore a backup copy over it to get your songs back.")
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(32)
        .frame(maxWidth: 720, maxHeight: .infinity, alignment: .topLeading)
    }
}

/// A soak run has no library: it only drives the screens from the command line.
struct SoakView: View {
    let app: AppModel

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Soak run").font(.title2.bold())
            Text("The screens are driven from the command line. No library is opened in this mode.")
                .foregroundStyle(.secondary)
            ScreensPanel(model: app)
        }
        .padding(24)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }
}

struct WorkspaceView: View {
    let app: AppModel
    @Bindable var workspace: WorkspaceModel
    @State private var query = ""
    @FocusState private var searchFocused: Bool
    @FocusState private var gridFocused: Bool

    var body: some View {
        VStack(spacing: 0) {
            if let error = workspace.lastError ?? app.settingsError {
                ErrorBar(message: error) { workspace.dismissError(); app.dismissSettingsError() }
            }
            ForEach(app.unsavedProblems, id: \.self) { UnsavedBar(message: $0) }
            NavigationSplitView {
                LibrarySidebar(app: app, workspace: workspace)
                    .navigationSplitViewColumnWidth(min: 240, ideal: 280, max: 380)
            } detail: {
                HSplitView {
                    CentrePane(app: app, workspace: workspace, query: query, clearQuery: { query = "" })
                        .frame(minWidth: 460)
                        .focusable()
                        .focused($gridFocused)
                        .focusEffectDisabled()
                    RightColumn(app: app)
                        .frame(minWidth: 340, idealWidth: 380, maxWidth: 520)
                }
            }
            .searchable(text: $query, placement: .toolbar, prompt: "Search titles and lyrics")
            .searchFocused($searchFocused)
            if let media = app.media, media.layers.foreground != nil {
                Divider()
                MediaTransportStrip(media: media)
            }
            Divider()
            TransportBar(app: app, workspace: workspace)
        }
        .onChange(of: query) { _, new in Task { await workspace.search(new) } }
        .onChange(of: app.ui.focusSearch) { _, _ in searchFocused = true }
        // Keyboard focus belongs on the slide grid: at launch, after a sheet closes, and when Escape leaves the search.
        .onAppear { focusGridSoon() }
        .onChange(of: app.workspaceLoaded) { _, _ in focusGridSoon() }
        .onChange(of: app.ui.focusGrid) { _, _ in focusGridSoon() }
        .onChange(of: app.ui.anySheetOpen) { was, now in if was && !now { focusGridSoon() } }
        .onChange(of: app.ui.leaveSearch) { _, _ in
            query = ""
            focusGridSoon()
        }
        .sheet(isPresented: Binding(get: { app.ui.showImport }, set: { app.ui.showImport = $0 })) {
            ImportSheet(app: app, workspace: workspace, existingID: app.ui.importExistingID)
        }
        .sheet(isPresented: Binding(get: { app.ui.showSectionOrders }, set: { app.ui.showSectionOrders = $0 })) {
            SectionOrderSheet(app: app, workspace: workspace)
        }
        .sheet(isPresented: Binding(get: { app.ui.showThemeEditor }, set: { app.ui.showThemeEditor = $0 })) {
            ThemeEditorSheet(app: app, workspace: workspace)
        }
        .sheet(isPresented: Binding(get: { app.ui.showStageEditor }, set: { app.ui.showStageEditor = $0 })) {
            if let stage = app.stage { StageEditorSheet(app: app, stage: stage) }
        }
        .toolbar {
            ToolbarItemGroup {
                Button { app.newPresentation() } label: { Label("New presentation", systemImage: "doc.badge.plus") }
                    .help("New presentation (Command-N)")
                Button { app.openImport(existing: nil) } label: { Label("Import lyrics", systemImage: "text.badge.plus") }
                    .help("Import lyrics (Command-I)")
                Button { app.ui.showSectionOrders = true } label: { Label("Section orders", systemImage: "list.number") }
                    .help("Section orders of the open song")
                    .disabled(workspace.openPresentationID == nil)
                Button { app.ui.showThemeEditor = true } label: { Label("Themes", systemImage: "paintpalette") }
                    .help("Create and edit themes")
                Button { app.ui.showStageEditor = true } label: { Label("Stage layouts", systemImage: "rectangle.3.group") }
                    .help("Create and edit stage screen layouts")
                    .disabled(app.stage == nil)
            }
        }
    }
}

extension WorkspaceView {
    /// Puts keyboard focus on the slide grid (KI-021). Done a moment later so it wins over the search field's
    /// default focus at launch and over a closing sheet.
    private func focusGridSoon() {
        searchFocused = false
        gridFocused = true
        Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(150))
            searchFocused = false
            gridFocused = true
        }
    }
}

struct ErrorBar: View {
    let message: String
    let dismiss: () -> Void

    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(.orange).accessibilityHidden(true)
            Text(message).fixedSize(horizontal: false, vertical: true).textSelection(.enabled)
            Spacer()
            Button("Dismiss", action: dismiss)
        }
        .padding(.horizontal, 12).padding(.vertical, 8)
        .background(Color.orange.opacity(0.18))
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Error: \(message)")
    }
}

/// R3 / R12: typed text or settings that are not on disk yet. Stays until the write succeeds; there is nothing to dismiss.
struct UnsavedBar: View {
    let message: String

    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: "exclamationmark.octagon.fill").foregroundStyle(.red).accessibilityHidden(true)
            Text(message).fixedSize(horizontal: false, vertical: true).textSelection(.enabled)
            Spacer()
        }
        .padding(.horizontal, 12).padding(.vertical, 8)
        .background(Color.red.opacity(0.15))
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Not saved: \(message)")
    }
}

/// Everything on the right: a live picture of each screen, then the media bin, the screens panel, Looks and props.
struct RightColumn: View {
    @Bindable var app: AppModel

    var body: some View {
        ScrollViewReader { proxy in
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                Text("Live screens").font(.headline)
                ForEach(app.profiles.filter(\.isEnabled)) { profile in
                    VStack(alignment: .leading, spacing: 4) {
                        HStack {
                            Text(profile.name).font(.subheadline.bold())
                            Text(profile.role.rawValue.capitalized).font(.caption).foregroundStyle(.secondary)
                        }
                        LiveScreenPreview(app: app, screenID: profile.id)
                    }
                }
                Divider()
                if let media = app.media {
                    MediaBinPanel(app: app, media: media)
                    Divider()
                }
                if let audio = app.audio {
                    AudioPanel(audio: audio)
                    Divider()
                }
                ScreensPanel(model: app).id("screens-panel")
                Divider()
                if let stage = app.stage {
                    TimersPanel(app: app, stage: stage)
                    Divider()
                }
                LookPanel(model: app)
                Divider()
                PropsPanel(model: app)
                if !app.messages.isEmpty {
                    Divider()
                    ForEach(Array(app.messages.enumerated()), id: \.offset) { _, m in
                        Text(m).font(.caption).foregroundStyle(.orange)
                    }
                }
            }
            .padding(14)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .task {
            // Test hook for runs that cannot scroll: start with the Screens panel in view.
            guard CommandLine.arguments.contains("--show-screens-panel") else { return }
            try? await Task.sleep(for: .seconds(1))
            proxy.scrollTo("screens-panel", anchor: .top)
        }
        }
    }
}
