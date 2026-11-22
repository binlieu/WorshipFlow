// OUT-004: the operator window. Libraries and playlists on the left, the open presentation in the middle with
// search above it, live previews and controls on the right, transport along the bottom. Errors appear in a bar at
// the top of this window and never on an output (NFR-08).
import SwiftUI
import AppKit
import Domain
import OperatorCore
import OutputEngine

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
        .font(.wfBody)          // UI-005i: controls and text without a style of their own are Inter too
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
                .font(.wf(17, .bold)).foregroundStyle(.orange)
            Text("WorshipFlow looked for the library here:")
            Text(problem.path).font(.wfMono(13)).textSelection(.enabled)
            Text(problem.message).foregroundStyle(.secondary).textSelection(.enabled)
            if problem.fromNewerBuild {
                // FIX-H item 14: nothing was written. The two ways out are to quit (and use the newer WorshipFlow) or to use another library.
                Text("Nothing was written to the library, so it is still exactly as the newer WorshipFlow left it.")
                    .fixedSize(horizontal: false, vertical: true)
                HStack(spacing: 8) {
                    Button("Quit WorshipFlow") { NSApplication.shared.terminate(nil) }.buttonStyle(HeaderButtonStyle(kind: .primary))
                    Button("Open a different library…") { Self.openDifferentLibrary() }.buttonStyle(HeaderButtonStyle())
                }
            } else {
                Text("The file has not been changed or deleted. Check that the disk is connected and the folder is writable, or move the file aside and restart to begin a new library. Restore a backup copy over it to get your songs back.")
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(32)
        .frame(maxWidth: 720, maxHeight: .infinity, alignment: .topLeading)
    }
}

extension LibraryProblemView {
    /// Asks for another library file, then starts WorshipFlow again on it (a library is opened once per launch) and quits this copy.
    @MainActor static func openDifferentLibrary() {
        let panel = NSOpenPanel()
        panel.message = "Choose the library file to open instead"
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = false
        guard panel.runModal() == .OK, let url = panel.url else { return }
        let configuration = NSWorkspace.OpenConfiguration()
        configuration.arguments = ["--library", url.path]
        configuration.createsNewApplicationInstance = true
        NSWorkspace.shared.openApplication(at: Bundle.main.bundleURL, configuration: configuration) { _, _ in
            DispatchQueue.main.async { NSApplication.shared.terminate(nil) }
        }
    }
}

/// A soak run has no library: it only drives the screens from the command line.
struct SoakView: View {
    let app: AppModel

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Soak run").font(.wf(17, .bold))
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
            operatorToolbar
            if let error = workspace.lastError ?? app.settingsError {
                ErrorBar(message: error) { workspace.dismissError(); app.dismissSettingsError() }
            }
            if let notice = app.fontNotice { ErrorBar(message: notice) { app.dismissFontNotice() } }
            ForEach(app.shownFaultCards) { card in OutputFaultBar(app: app, card: card).transition(.opacity) }
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
            // UI-005a: the design drops the bar in Edit, Stage and Screens; the keys still work and the toolbar shows the live chip.
            if workspace.mode.showsTransportBar { TransportBar(app: app, workspace: workspace) }
        }
        .background(Tok.bg)
        .ignoresSafeArea(.container, edges: .top)          // the bar is the window's top 52 pt: there is no title bar above it
        .navigationTitle(serviceName)           // the window's own title (Window menu, VoiceOver); the bar below draws its own block (UI-005j)
        .navigationSubtitle(serviceSubtitle)
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
        .onChange(of: gridFocused) { _, now in app.ui.gridHasFocus = now }        // FIX-I item 1: controls under the grid inherit its focus
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

    /// UI-005j: the design's 52 pt toolbar, drawn by the app instead of the system toolbar so every item sits where the mockup puts it:
    /// 14 pt in, the three window buttons' 52 pt and 6 pt (the window has no title bar of its own, see `WindowChrome`), then 12 pt between
    /// the sidebar button, the title block, the mode switcher (centred in the room between them and the timers), the timers and the pills.
    private var operatorToolbar: some View {
        HStack(spacing: 12) {
            Color.clear.frame(width: 58, height: 1)      // under the window's own three buttons
            sidebarToggle
            titleBlock
            Spacer(minLength: 0)
            modeSwitcher
            Spacer(minLength: 0)
                // Open or close the screens: not in the design's toolbar, so it floats in the free room right of the mode switcher and takes none.
                .overlay(alignment: .leading) { screensButton.padding(.leading, 12) }
            if !workspace.mode.showsTransportBar, app.mode != .stopped { liveChip }
            if let stage = app.stage { ToolbarTimersView(stage: stage) }
            HStack(spacing: 12) {
                ForEach(app.rolePills) { pill in
                    RolePillView(pill: pill, rectID: "tb.pill.\(pill.abbreviation.lowercased())")
                        .onTapGesture { if pill.status == .fault { app.showFaultCards(for: pill.role) } }      // FIX-I item 7: shows the card again
                        .accessibilityAddTraits(pill.status == .fault ? .isButton : [])
                        .help(pill.status == .fault ? "\(pill.accessibilityText). Click to show the message with Retry and Details" : pill.accessibilityText)
                }
            }
        }
        .padding(.horizontal, 14)
        .frame(height: Space.toolbarHeight)
        .background(Tok.surface)
        .overlay(alignment: .bottom) { Rectangle().fill(Tok.border).frame(height: 1) }
        .background(WindowDragArea())
        .background(WindowChrome())
        .wfRect("tb")
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Toolbar")
    }

    private var screensButton: some View {
        Button { app.screensOn ? app.stopScreens() : app.startScreens() } label: {
            Image(systemName: app.screensOn ? "display.trianglebadge.exclamationmark" : "display").font(.wf(13)).frame(width: 28, height: 24)
        }
        .buttonStyle(HeaderButtonStyle(kind: .ghost, compact: true))
        .help(app.screensOn ? "Close screens" : "Open screens")
        .accessibilityLabel(app.screensOn ? "Close screens" : "Open screens")
    }

    /// The window's own title and subtitle carry the service and the library, so the name is shown once (KI-068).
    private var serviceName: String {
        workspace.serviceTitle()      // UI-005b: the service date and time when the playlist has them, else its name
    }
    private var serviceSubtitle: String {
        "WorshipFlow · \(workspace.libraries.first { $0.id == workspace.selectedLibraryID }?.name ?? "")"
    }

    /// UI-005j: the design's title block (13/600 over 11 muted, 16 pt lines), set by the toolbar so its place is the design's.
    private var titleBlock: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(serviceName).font(.wf(13, .semibold)).foregroundStyle(Tok.text).lineLimit(1).frame(maxWidth: .infinity, alignment: .leading).frame(height: 16).wfRect("tb.title", size: 13, weight: 600)
            Text(serviceSubtitle).font(.wf(11)).foregroundStyle(Tok.muted).lineLimit(1).frame(maxWidth: .infinity, alignment: .leading).frame(height: 16).wfRect("tb.subtitle", size: 11, weight: 400)
        }
        .fixedSize()
        .accessibilityElement(children: .ignore)
        .accessibilityHidden(true)       // the window title carries the same words
    }

    /// The design's sidebar toggle (a ghost icon button left of the title). Only the Show mode has the sidebar.
    private var sidebarToggle: some View {
        Button { app.ui.sidebarVisible.toggle() } label: {
            Image(systemName: "sidebar.left").font(.wf(14)).foregroundStyle(Tok.muted).frame(width: 15, height: 15).padding(.horizontal, 11).frame(height: 26)
        }
        .buttonStyle(.plain)
        .wfRect("tb.sidebarToggle")
        .keyboardShortcut("s", modifiers: [.command, .option])
        .disabled(workspace.mode != .show)
        .help(app.ui.sidebarVisible ? "Hide the sidebar (Option-Command-S)" : "Show the sidebar (Option-Command-S)")
        .accessibilityLabel(app.ui.sidebarVisible ? "Hide the sidebar" : "Show the sidebar")
    }

    /// The segmented mode switcher: icon and word per mode, Command-1 to Command-6.
    private var modeSwitcher: some View {
        WFSegmented(items: WorkspaceMode.allCases.map { .init(value: $0, title: $0.title, symbol: Self.symbol($0), label: "\($0.title) (Command-\($0.commandDigit))") },
                    selection: Binding(get: { workspace.mode }, set: { workspace.setMode($0) }), accessibilityName: "Mode", rectID: "tb.modes")
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

    private var liveChip: some View {
        HStack(spacing: 6) {
            switch app.mode {
            case .live: ThumbTag(text: "LIVE", kind: .live)
            case .cleared: ThumbTag(text: "CLEARED", kind: .warning)
            case .blackout: ThumbTag(text: "BLACKOUT", kind: .warning)
            case .stopped: EmptyView()
            }
            Text(workspace.liveChipLine ?? "").font(.wf(11)).foregroundStyle(Tok.muted).lineLimit(1).frame(maxWidth: 220, alignment: .leading)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("On the screens: \(workspace.livePositionLine ?? "")")
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
        // UI-005a: the design's message card; the one existing action (Dismiss) stays. Retry and Details need a per-error action (UI-005b).
        MessageCard(message: message) {
            Button("Dismiss", action: dismiss).buttonStyle(HeaderButtonStyle())
        }
        .padding(.horizontal, 12).padding(.vertical, 6)
        .background(Tok.bg)
    }
}

/// UI-005b: an output that stopped sending, with the design's two actions. Retry output reopens that output once; Details shows the
/// recorded fault text with a Copy button. After a Retry that failed, the card says so in plain words.
struct OutputFaultBar: View {
    let app: AppModel
    let card: OutputFaultCard
    @State private var showDetails = false
    @FocusState private var focusedButton: Int?

    var body: some View {
        MessageCard(message: app.retryNotes[card.screenID] ?? card.message) {
            HStack(spacing: 8) {
                Button("Retry output") { app.retryOutput(card) }.buttonStyle(HeaderButtonStyle())
                    .help("Open \(card.name) again. The show on the other screens is not touched.")
                    .focused($focusedButton, equals: 0)
                Button("Details") { showDetails = true }.buttonStyle(HeaderButtonStyle())
                    .focused($focusedButton, equals: 1)
            }
        }
        .padding(.horizontal, 12).padding(.vertical, 6)
        .background(Tok.bg)
        // FIX-I item 7: the card fades after five seconds, but not while the pointer is over it or a button in it has keyboard focus (or its Details is open).
        .onHover { app.faultCardPointer($0, screenID: card.screenID) }
        .onChange(of: focusedButton) { _, now in app.faultCardFocus(now != nil || showDetails, screenID: card.screenID) }
        .onChange(of: showDetails) { _, now in app.faultCardFocus(now || focusedButton != nil, screenID: card.screenID) }
        .sheet(isPresented: $showDetails) { OutputFaultDetails(card: card) }
    }
}

struct OutputFaultDetails: View {
    let card: OutputFaultCard
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(alignment: .leading, spacing: Space.s4) {
            Text("\(card.name): what was recorded").font(.wfHeadline)
            Text(card.detail).font(.wfMono(12)).textSelection(.enabled)
                .frame(maxWidth: .infinity, alignment: .leading).padding(8)
                .wfOutline(RoundedRectangle(cornerRadius: Radius.md), stroke: Tok.border, fill: Tok.bg)
            HStack {
                Button("Copy") {
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(card.detail, forType: .string)
                }
                Spacer()
                Button("Close") { dismiss() }.keyboardShortcut(.defaultAction)
            }
        }
        .padding(Space.s6).frame(width: 460)
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
