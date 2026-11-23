// CUE-002b (item 6) / UI-001: the Cues mode, after docs/UI/screens/06-cues.png as far as the features exist. Left: macros, slide
// actions, the control inputs and the schedule. Centre: what is chosen. Right: the MIDI map, the keyboard and the activity.
// UI-005g: drawn at the rectangles of docs/UI/mockups/06-cues.html (columns 230 / 1fr / 380, rows, bar, tables), measured by
// scripts/design-map-cues.json. UI-006g added the keyboard trigger (CU-21), a dry run in place of "Test in Preview" (CU-22) and one slide-
// actions row per presentation; Playback markers are not drawn (no feature behind them);
// Stream Deck is a row marked "later", as the design draws it.
import SwiftUI
import Domain
import CueEngine
import OperatorCore

struct CuesModeView: View {
    let app: AppModel
    @Bindable var workspace: WorkspaceModel

    var body: some View {
        if let cue = app.cue {
            HStack(spacing: 0) {
                // ui.css: a column's 1 pt border is inside its 230 and 380 pt.
                CuesSidebar(app: app, cue: cue, workspace: workspace)
                    .padding(.trailing, 1).frame(width: 230)
                    .background(Tok.surface)
                    .overlay(alignment: .trailing) { Rectangle().fill(Tok.border).frame(width: 1) }
                CuesCentre(app: app, cue: cue, workspace: workspace).frame(maxWidth: .infinity, maxHeight: .infinity)
                    .background(Tok.bg)
                CuesInfoColumn(app: app, cue: cue)
                    .padding(.leading, 1).frame(width: 380)
                    .background(Tok.surface)
                    .overlay(alignment: .leading) { Rectangle().fill(Tok.border).frame(width: 1) }
            }
            .task { await cue.refreshSlideActionPresentations() }      // FIX-V (L5): one read when Cues appears; a rename or deletion elsewhere shows
        } else {
            Text("Macros and control inputs are not available.").foregroundStyle(Tok.muted).frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }
}

// MARK: Selection

extension CuesSelection {
    /// The chosen item if it still exists, else the first macro, else the slide actions.
    @MainActor static func effective(_ chosen: CuesSelection?, cue: CueModel) -> CuesSelection {
        if let chosen {
            if case .macro(let id) = chosen, cue.macro(id) == nil {} else { return chosen }
        }
        if let first = cue.macros.first { return .macro(first.id) }
        return .slideActions
    }
}

// MARK: Sidebar

private struct CuesSidebar: View {
    let app: AppModel
    let cue: CueModel
    @Bindable var workspace: WorkspaceModel

    var body: some View {
        let selection = CuesSelection.effective(app.ui.cuesSelection, cue: cue)
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                CuesSection(first: true, rectID: "sb.sec.0") {
                    HStack(spacing: 8) {
                        SectionLabel("Macros", rectID: "sb.macros.title")
                        Spacer()
                        Button { create() } label: {
                            Image(systemName: "plus").font(.wf(12)).frame(width: 12, height: 12).wfRect("sb.macros.plus").padding(6).contentShape(Rectangle())
                        }
                        .buttonStyle(.plain).padding(-6).help("New macro").accessibilityLabel("New macro")
                    }
                    .padding(.bottom, 6)
                    ForEach(Array(cue.macros.enumerated()), id: \.element.id) { index, macro in
                        CuesListRow(symbol: "bolt", title: macro.name, count: "\(macro.steps.count)", selected: selection == .macro(macro.id),
                                    rectID: "sb.macros.row.\(index)", accessibility: "\(macro.name), \(macro.steps.count) actions") {
                            app.ui.cuesSelection = .macro(macro.id)
                        }
                    }
                    if cue.macros.isEmpty {
                        Text("No macros yet. Press + to make one.").font(.wf(12)).foregroundStyle(Tok.muted).padding(.horizontal, 8)
                    }
                }
                CuesSection(rectID: "sb.sec.1") {
                    SectionLabel("Slide actions", rectID: "sb.slides.title").padding(.bottom, 6)
                    // UI-006g: one row per presentation that has slide actions, as the design lists them. A row of the open presentation chooses the
                    // editor; another presentation's row opens it in Preview first (never Live), because the actions are edited on its slides.
                    ForEach(Array(slideRows.enumerated()), id: \.element.id) { index, row in
                        let chosen = selection == .slideActions && row.id == workspace.openPresentationID
                        CuesListRow(symbol: "music.note", title: row.title, count: "\(row.count)", selected: chosen,
                                    rectID: "sb.slides.row.\(index)", accessibility: "Slide actions, \(row.title), \(row.count) slide\(row.count == 1 ? "" : "s") with actions") {
                            choose(row.id)
                        }
                    }
                    if slideRows.isEmpty {
                        CuesListRow(symbol: "music.note", title: "Actions on slides", count: "0", selected: selection == .slideActions,
                                    rectID: "sb.slides.row.0", accessibility: "Slide actions, no slides have actions") { app.ui.cuesSelection = .slideActions }
                    }
                }
                CuesSection(rectID: "sb.sec.2") {
                    SectionLabel("Control inputs", rectID: "sb.inputs.title").padding(.bottom, 6)
                    CuesListRow(symbol: "slider.vertical.3", title: midiTitle, trailing: AnyView(midiState), selected: selection == .midi,
                                rectID: "sb.inputs.row.0", accessibility: "MIDI") { app.ui.cuesSelection = .midi }
                    // The design draws Stream Deck as a row marked "later": there is no Stream Deck support, so it is not a button.
                    CuesListRow(symbol: "square.grid.2x2", title: "Stream Deck", count: "later", enabled: false,
                                rectID: "sb.inputs.row.1", accessibility: "Stream Deck, later, not available") {}
                    CuesListRow(symbol: "dot.radiowaves.left.and.right", title: "Remote control", count: cue.remoteStatus.isRunning ? "on" : "off", selected: selection == .remote,
                                rectID: "sb.inputs.row.2", accessibility: "Remote control, \(cue.remoteStatus.isRunning ? "on" : "off")") { app.ui.cuesSelection = .remote }
                }
                // The owner's extra (CUE-003): the schedule, below the designed sections so nothing of them moves.
                CuesSection(rectID: "sb.sec.3") {
                    SectionLabel("Schedule", rectID: "sb.schedule.title").padding(.bottom, 6)
                    CuesListRow(symbol: "calendar", title: "Scheduled events", count: "\(cue.schedule.events.filter(\.isEnabled).count)", selected: selection == .schedule,
                                rectID: "sb.schedule.row.0") { app.ui.cuesSelection = .schedule }
                }
            }
        }
        .background(Tok.surface)
    }

    private struct SlideRow: Identifiable { var id: UUID; var title: String; var count: Int }

    /// The presentations with actions, by title. The open one is counted from what is open now (an edit shows at once) and is listed even
    /// with none, so its editor can always be reached.
    private var slideRows: [SlideRow] {
        let open = workspace.openPresentationID
        var rows = cue.slideActionPresentations.filter { $0.id != open }.map { SlideRow(id: $0.id, title: $0.title, count: $0.slideCount) }
        if let open, let title = workspace.presentations.first(where: { $0.id == open })?.title {
            rows.append(SlideRow(id: open, title: title, count: workspace.slides.filter { !cue.slideActions.actions(for: $0.id).isEmpty }.count))
            rows.sort { $0.title.localizedCaseInsensitiveCompare($1.title) == .orderedAscending }
        }
        return rows
    }

    private func choose(_ presentationID: UUID) {
        app.ui.cuesSelection = .slideActions
        guard presentationID != workspace.openPresentationID else { return }
        Task { @MainActor in await workspace.openPresentation(presentationID) }
    }
    private var midiTitle: String { cue.midi.inputName.map { "MIDI \u{2014} \($0)" } ?? "MIDI" }

    @ViewBuilder private var midiState: some View {
        switch cue.midiStatus.source {
        case .connected: Text("\u{25CF}").font(.wf(11)).foregroundStyle(Tok.statusOK).wfLine().wfRect("sb.inputs.row.0.n", size: 11, weight: 400).accessibilityLabel("MIDI device connected")
        case .waiting, .failed: Image(systemName: "exclamationmark.triangle.fill").font(.wf(10)).foregroundStyle(Tok.warning).wfRect("sb.inputs.row.0.n").accessibilityLabel("MIDI device offline")
        case .none: Text(cue.midiStatus.isEnabled ? "on" : "off").font(.wf(11)).foregroundStyle(Tok.muted).wfLine().wfRect("sb.inputs.row.0.n", size: 11, weight: 400)
        }
    }

    private func create() {
        Task { @MainActor in
            if let macro = await cue.createMacro(name: "New macro") { app.ui.cuesSelection = .macro(macro.id) }
        }
    }
}

// MARK: Centre

private struct CuesCentre: View {
    let app: AppModel
    let cue: CueModel
    @Bindable var workspace: WorkspaceModel

    var body: some View {
        switch CuesSelection.effective(app.ui.cuesSelection, cue: cue) {
        case .macro(let id): MacroEditor(app: app, cue: cue, macroID: id).id(id)
        case .slideActions: SlideActionsEditor(app: app, cue: cue, workspace: workspace)
        case .schedule: ScheduleEditor(app: app, cue: cue)
        case .midi: MIDISection(app: app, cue: cue)
        case .remote: RemoteSection(app: app, cue: cue)
        }
    }
}

// MARK: Right column

private struct CuesInfoColumn: View {
    let app: AppModel
    let cue: CueModel

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                CuesSection(first: true, rectID: "r.sec.0") { midiMap.padding(.bottom, 1) }      // a table's collapsed borders add 1 pt under it
                CuesSection(rectID: "r.sec.1") { keyboard.padding(.bottom, 1) }
                CuesSection(rectID: "r.sec.2") { activity }
            }
        }
        .background(Tok.surface)
    }

    private static let inputWidth: CGFloat = 90.5, commandWidth: CGFloat = 224.6

    private var midiMap: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 8) {
                SectionLabel("MIDI map", rectID: "r.midi.title")
                Spacer()
                // The design's button is "Learn…"; learning lives on the MIDI page, so this opens it.
                Button("Manage\u{2026}") { app.ui.cuesSelection = .midi }.buttonStyle(CuesSmallButtonStyle()).wfRect("r.midi.manage", size: 12, weight: 500, radius: Radius.md)
            }
            .frame(height: 22).padding(.bottom, 6)
            CuesTableRow(height: 28, rectID: "r.midi.th") {
                CuesCell(width: Self.inputWidth, rectID: "r.midi.th.0", size: 11, weight: 600) { CuesTableHead(text: "Input") }
                CuesCell(width: Self.commandWidth, rectID: "r.midi.th.1", size: 11, weight: 600) { CuesTableHead(text: "Command") }
                CuesCell(rectID: "r.midi.th.2", size: 11, weight: 600) { EmptyView() }
            }
            if cue.bindings.bindings.isEmpty {
                Text("No MIDI bindings. Turn MIDI on and press Learn on the MIDI page to bind a pad.").font(.wf(12)).foregroundStyle(Tok.muted)
                    .padding(.horizontal, 8).padding(.vertical, 6)
            }
            ForEach(Array(cue.bindings.bindings.enumerated()), id: \.element.id) { index, binding in
                CuesTableRow(rectID: "r.midi.row.\(index)") {
                    CuesCell(width: Self.inputWidth, rectID: "r.midi.row.\(index).0", size: 11, weight: 400) {
                        Text(Self.shortPattern(binding.pattern)).font(.wfMono(11)).lineLimit(1).wfLine()
                    }
                    CuesCell(width: Self.commandWidth, rectID: "r.midi.row.\(index).1") {
                        Text(MIDIText.command(binding.command, macros: cue.macros)).font(.wf(12)).lineLimit(1).wfLine()
                        if cue.conflictingBindingIDs.contains(binding.id) {
                            Image(systemName: "exclamationmark.triangle.fill").font(.wf(10)).foregroundStyle(Tok.warning).padding(.leading, 4)
                                .help("Another binding uses the same pad").accessibilityLabel("Conflict")
                        }
                    }
                    CuesCell(rectID: "r.midi.row.\(index).2") {
                        Menu {
                            Button("Open the MIDI page") { app.ui.cuesSelection = .midi }
                            Button("Delete binding", role: .destructive) { Task { @MainActor in await cue.deleteBinding(binding.id) } }
                        } label: { Image(systemName: "ellipsis").font(.wf(12)).foregroundStyle(Tok.muted).frame(width: 12, height: 12) }
                            .menuStyle(.borderlessButton).menuIndicator(.hidden).fixedSize()
                            .help("Binding actions").accessibilityLabel("Actions for binding \(MIDIText.pattern(binding.pattern))")
                    }
                }
            }
        }
    }

    /// "Note C2" as the design writes it: the channel is left out for channel 1 and written short ("Note C2 ch 2") for another, so it fits the column.
    private static func shortPattern(_ pattern: MIDIPattern) -> String {
        let full = MIDIText.pattern(pattern)
        guard let range = full.range(of: " \u{00B7} ch ") else { return full }
        let channel = full[range.upperBound...]
        return channel == "1" ? String(full[..<range.lowerBound]) : "\(full[..<range.lowerBound]) ch \(channel)"
    }

    private static let keyWidth: CGFloat = 143.6

    private var keyboard: some View {
        VStack(alignment: .leading, spacing: 0) {
            SectionLabel("Keyboard", rectID: "r.kb.title").padding(.bottom, 6)
            ForEach(Array(Self.keys.enumerated()), id: \.offset) { index, entry in
                CuesTableRow(height: index == 0 ? 28 : 29, rectID: "r.kb.row.\(index)") {
                    CuesCell(width: Self.keyWidth, rectID: "r.kb.row.\(index).0") { CuesKbd(key: entry.0, rectID: "r.kb.row.\(index).kbd") }
                    CuesCell(rectID: "r.kb.row.\(index).1") { Text(entry.1).font(.wf(12)).lineLimit(1).wfLine() }
                }
                .accessibilityElement(children: .combine)
                .accessibilityLabel("\(entry.0): \(entry.1)")
            }
        }
    }

    /// The same list a test checks for clashes (`ShowShortcuts`), with the MEDIA-010 layer clears.
    static let keys: [(String, String)] = ShowShortcuts.all.map { ($0.key, $0.command) }

    private var activity: some View {
        VStack(alignment: .leading, spacing: 0) {
            SectionLabel("Activity", rectID: "r.act.title").padding(.bottom, 6)
            if cue.activity.isEmpty {
                Text("Nothing has run yet.").font(.wf(11)).foregroundStyle(Tok.muted).wfLine()
            }
            VStack(alignment: .leading, spacing: 0) {
                ForEach(cue.activity.suffix(14)) { line in
                    HStack(alignment: .firstTextBaseline, spacing: 6) {
                        Text(DateFormatter.cuesClock.string(from: line.time)).foregroundStyle(Tok.muted)
                        Text("\(line.source.label) \(line.text)").foregroundStyle(line.isProblem ? Tok.warning : Tok.muted)
                            .lineLimit(2).fixedSize(horizontal: false, vertical: true)
                    }
                    .font(.wfMono(11)).lineSpacing(4.6).frame(minHeight: 18, alignment: .topLeading)
                }
            }
            .wfRect("r.act.lines")
        }
    }
}
