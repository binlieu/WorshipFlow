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
        .preferredColorScheme(Self.scheme(app.appearance))
        .background(OperatorWindowGuardInstaller())     // R4: the window does not close while the screens are open
    }
}

extension ContentView {
    static func scheme(_ choice: AppearanceChoice) -> ColorScheme? {
        switch choice.forcedScheme { case nil: nil; case .dark?: .dark; case .light?: .light }
    }
}

/// Shown instead of the workspace when the library file cannot be opened. The file is never touched.
struct LibraryProblemView: View {
    let problem: LibraryProblem

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label("The song library could not be opened", systemImage: "exclamationmark.triangle.fill")
                .font(.title2.bold()).foregroundStyle(.orange)
            Text("WorshipFlow looked for the library here:")
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
            if let cue = app.cue {
                // CUE-002b: a failed action, a skipped scheduled event, a refused edit. Inside the operator window, never on an output.
                if let error = cue.lastError { ErrorBar(message: error) { cue.dismissError() } }
                ForEach(cue.notices) { notice in ErrorBar(message: notice.text) { cue.dismissNotice(notice.id) } }
            }
            modeContent
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            // The transport bar is in every mode: an operator in Screens can still advance the service. The clip strip
            // is in every mode but Show, where the media controller row under the dock replaces it (UI-003).
            if workspace.mode != .show, let media = app.media, media.layers.foreground != nil {
                Divider()
                MediaTransportStrip(media: media)
            }
            TransportBar(app: app, workspace: workspace)
        }
        .background(Tok.bg)
        .navigationTitle(serviceName)
        .navigationSubtitle(serviceSubtitle)
        .toolbar {
            ToolbarItem(placement: .principal) { modeSwitcher }
            ToolbarItem(placement: .primaryAction) { toolbarStatus }
        }
        // UI-002: while a countdown is live its time is rewritten as it changes. It never moves the show on.
        .task(id: workspace.liveCountdown?.itemID) {
            guard workspace.liveCountdown != nil else { return }
            while !Task.isCancelled {
                workspace.countdownTick()
                try? await Task.sleep(for: .milliseconds(250))
            }
        }
        .onChange(of: query) { _, new in Task { await workspace.search(new) } }
        .onChange(of: app.ui.focusSearch) { _, ticket in
            searchFocused = true
            // Coming from another mode, the sidebar appears a moment later and the grid focus request of the mode change
            // runs first, so ask again once both are done (unless another request or a Escape came in meanwhile).
            Task { @MainActor in
                try? await Task.sleep(for: .milliseconds(300))
                if app.ui.focusSearch == ticket, workspace.mode == .show { searchFocused = true }
            }
        }
        .onChange(of: searchFocused) { _, now in app.ui.searchHasFocus = now }
        // Keyboard focus belongs on the slide grid: at launch, after a sheet closes, and when Escape leaves the search.
        .onAppear { focusGridSoon() }
        .onChange(of: app.workspaceLoaded) { _, _ in focusGridSoon() }
        .onChange(of: app.ui.focusGrid) { _, _ in focusGridSoon() }
        .onChange(of: app.ui.anySheetOpen) { was, now in if was && !now { focusGridSoon() } }
        .onChange(of: workspace.mode) { _, _ in focusGridSoon() }
        .onChange(of: app.ui.leaveSearch) { _, _ in
            query = ""
            focusGridSoon()
        }
        .sheet(isPresented: Binding(get: { app.ui.showImport }, set: { app.ui.showImport = $0 })) {
            ImportSheet(app: app, workspace: workspace, existingID: app.ui.importExistingID)
        }
        .modifier(ProgramTransferModifier(app: app, workspace: workspace))
        .sheet(isPresented: Binding(get: { app.ui.showSectionOrders }, set: { app.ui.showSectionOrders = $0 })) {
            SectionOrderSheet(app: app, workspace: workspace)
        }
        .sheet(isPresented: Binding(get: { app.ui.showThemeEditor }, set: { app.ui.showThemeEditor = $0 })) {
            ThemeEditorSheet(app: app, workspace: workspace)
        }
    }

    @ViewBuilder private var modeContent: some View {
        switch workspace.mode {
        case .show:
            ShowModeView(app: app, workspace: workspace, query: $query, gridFocused: $gridFocused, searchFocused: $searchFocused)
        case .edit: EditModeView(app: app, workspace: workspace)
        case .media: MediaModeView(app: app)
        case .stage: StageModeView(app: app)
        case .cues: CuesModeView(app: app, workspace: workspace)
        case .screens: ScreensModeView(app: app)
        }
    }

    // MARK: Toolbar

    /// The window's own title and subtitle carry the service and the library, so the name is shown once (KI-068).
    private var serviceName: String {
        workspace.playlists.first { $0.id == workspace.selectedPlaylistID }?.name ?? "No playlist"
    }
    private var serviceSubtitle: String {
        "WorshipFlow · \(workspace.libraries.first { $0.id == workspace.selectedLibraryID }?.name ?? "")"
    }

    /// The segmented mode switcher: icon and word per mode, Command-1 to Command-6.
    private var modeSwitcher: some View {
        HStack(spacing: Space.s1) {
            ForEach(WorkspaceMode.allCases) { mode in
                let selected = workspace.mode == mode
                Button { workspace.setMode(mode) } label: {
                    HStack(spacing: 5) {
                        Image(systemName: Self.symbol(mode)).font(.system(size: 11))
                        Text(mode.title).font(.system(size: 12, weight: selected ? .semibold : .regular))
                    }
                    .padding(.horizontal, 10).frame(height: 24)
                    .foregroundStyle(selected ? Tok.text : Tok.muted)
                    .background(selected ? Tok.surface3 : .clear, in: RoundedRectangle(cornerRadius: Radius.md))
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .help("\(mode.title) (Command-\(mode.commandDigit))")
                .accessibilityLabel(mode.title)
                .accessibilityHint("Command-\(mode.commandDigit)")
                .accessibilityAddTraits(selected ? [.isButton, .isSelected] : .isButton)
            }
        }
        .padding(Space.s1)
        .wfOutline(RoundedRectangle(cornerRadius: Radius.lg), stroke: Tok.border, fill: Tok.surface2)
        .padding(1)   // room inside the toolbar item, which clips to its bounds
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Mode")
    }

    static func symbol(_ mode: WorkspaceMode) -> String {
        switch mode {
        case .show: "play.fill"
        case .edit: "pencil"
        case .media: "film"
        case .stage: "music.mic"
        case .cues: "bolt"
        case .screens: "display"
        }
    }

    /// Timers, then the AUD, STG and BRD pills: visible in every mode.
    private var toolbarStatus: some View {
        HStack(spacing: Space.s4) {
            if let stage = app.stage { ToolbarTimersView(stage: stage) }
            HStack(spacing: 6) { ForEach(app.rolePills) { RolePillView(pill: $0) } }
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
            Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(Tok.warning).accessibilityHidden(true)
            Text(message).fixedSize(horizontal: false, vertical: true).textSelection(.enabled)
            Spacer()
            Button("Dismiss", action: dismiss)
        }
        .padding(.horizontal, 12).padding(.vertical, 8)
        .background(Tok.warning.opacity(0.16))
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Error: \(message)")
    }
}

/// R3 / R12: typed text or settings that are not on disk yet. Stays until the write succeeds; there is nothing to dismiss.
struct UnsavedBar: View {
    let message: String

    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: "exclamationmark.octagon.fill").foregroundStyle(Tok.warning).accessibilityHidden(true)
            Text(message).fixedSize(horizontal: false, vertical: true).textSelection(.enabled)
            Spacer()
        }
        .padding(.horizontal, 12).padding(.vertical, 8)
        .background(Tok.warning.opacity(0.22))
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Not saved: \(message)")
    }
}
