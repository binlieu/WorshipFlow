// CUE-002b (item 6) / UI-001: the Cues mode, after docs/UI/screens/06-cues.png as far as the features exist. Left: macros, slide
// actions, the schedule and the control inputs. Centre: what is chosen. Right: the MIDI map, the keyboard and the activity.
// Playback markers (AUTO-08) and Stream Deck are not drawn: neither exists yet, and a control that does nothing is not shown.
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
                CuesSidebar(app: app, cue: cue, workspace: workspace).frame(width: 260)
                Divider()
                CuesCentre(app: app, cue: cue, workspace: workspace).frame(maxWidth: .infinity, maxHeight: .infinity)
                Divider()
                CuesInfoColumn(app: app, cue: cue).frame(width: Space.inspectorWidth)
            }
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
            VStack(alignment: .leading, spacing: Space.s5) {
                HStack {
                    SectionLabel("Macros")
                    Spacer()
                    Button { create() } label: { Image(systemName: "plus").frame(width: 24, height: 24).contentShape(Rectangle()) }
                        .buttonStyle(.plain).help("New macro").accessibilityLabel("New macro")
                }
                VStack(spacing: 2) {
                    ForEach(cue.macros) { macro in
                        row(symbol: "bolt", title: macro.name, trailing: "\(macro.steps.count)", selected: selection == .macro(macro.id)) {
                            app.ui.cuesSelection = .macro(macro.id)
                        }
                    }
                    if cue.macros.isEmpty {
                        Text("No macros yet. Press + to make one.").font(.system(size: 12)).foregroundStyle(Tok.muted)
                            .frame(maxWidth: .infinity, alignment: .leading).padding(.horizontal, Space.s3)
                    }
                }
                Divider()
                SectionLabel("Slide actions")
                row(symbol: "music.note", title: "Actions on slides", trailing: "\(slidesWithActions)", selected: selection == .slideActions) {
                    app.ui.cuesSelection = .slideActions
                }
                Divider()
                SectionLabel("Schedule")
                row(symbol: "calendar", title: "Scheduled events", trailing: "\(cue.schedule.events.filter(\.isEnabled).count)", selected: selection == .schedule) {
                    app.ui.cuesSelection = .schedule
                }
                Divider()
                SectionLabel("Control inputs")
                VStack(spacing: 2) {
                    row(symbol: "pianokeys", title: "MIDI", trailingView: AnyView(midiDot), selected: selection == .midi) { app.ui.cuesSelection = .midi }
                    row(symbol: "dot.radiowaves.left.and.right", title: "Remote control",
                        trailingView: AnyView(Text(cue.remoteStatus.isRunning ? "on" : "off").font(.system(size: 12)).foregroundStyle(Tok.muted)),
                        selected: selection == .remote) { app.ui.cuesSelection = .remote }
                }
            }
            .padding(Space.s5)
        }
        .background(Tok.surface)
    }

    private var slidesWithActions: Int { workspace.slides.filter { !cue.slideActions.actions(for: $0.id).isEmpty }.count }

    @ViewBuilder private var midiDot: some View {
        switch cue.midiStatus.source {
        case .connected: Circle().fill(Tok.statusOK).frame(width: 8, height: 8).accessibilityLabel("MIDI device connected")
        case .waiting, .failed: Image(systemName: "exclamationmark.triangle.fill").font(.system(size: 10)).foregroundStyle(Tok.warning).accessibilityLabel("MIDI device offline")
        case .none: Text(cue.midiStatus.isEnabled ? "on" : "off").font(.system(size: 12)).foregroundStyle(Tok.muted)
        }
    }

    private func create() {
        Task { @MainActor in
            if let macro = await cue.createMacro(name: "New macro") { app.ui.cuesSelection = .macro(macro.id) }
        }
    }

    private func row(symbol: String, title: String, trailing: String? = nil, trailingView: AnyView? = nil, selected: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: Space.s3) {
                Image(systemName: symbol).frame(width: 18).foregroundStyle(Tok.muted)
                Text(title).font(.system(size: 14)).lineLimit(1)
                Spacer(minLength: 4)
                if let trailing { Text(trailing).font(.system(size: 12)).foregroundStyle(Tok.muted) }
                if let trailingView { trailingView }
            }
            .padding(.horizontal, Space.s3).frame(height: 32)
            .background(selected ? Tok.surface3 : .clear, in: RoundedRectangle(cornerRadius: Radius.md))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(selected ? .isSelected : [])
    }
}

// MARK: Centre

private struct CuesCentre: View {
    let app: AppModel
    let cue: CueModel
    @Bindable var workspace: WorkspaceModel

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Space.s5) {
                switch CuesSelection.effective(app.ui.cuesSelection, cue: cue) {
                case .macro(let id): MacroEditor(app: app, cue: cue, macroID: id).id(id)
                case .slideActions: SlideActionsEditor(app: app, cue: cue, workspace: workspace)
                case .schedule: ScheduleEditor(app: app, cue: cue)
                case .midi: MIDISection(app: app, cue: cue)
                case .remote: RemoteSection(app: app, cue: cue)
                }
            }
            .padding(Space.s6)
            .frame(maxWidth: .infinity, alignment: .topLeading)
        }
    }
}

// MARK: Right column

private struct CuesInfoColumn: View {
    let app: AppModel
    let cue: CueModel

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Space.s5) {
                midiMap
                Divider()
                keyboard
                Divider()
                activity
            }
            .padding(Space.s5)
        }
        .background(Tok.surface)
    }

    private var midiMap: some View {
        VStack(alignment: .leading, spacing: Space.s3) {
            HStack {
                SectionLabel("MIDI map")
                Spacer()
                Button("Manage…") { app.ui.cuesSelection = .midi }.buttonStyle(HeaderButtonStyle())
            }
            if cue.bindings.bindings.isEmpty {
                Text("No MIDI bindings. Turn MIDI on and press Learn to bind a pad.").font(.system(size: 12)).foregroundStyle(Tok.muted)
            } else {
                ForEach(cue.bindings.bindings) { binding in
                    HStack {
                        Text(MIDIText.pattern(binding.pattern)).font(.wfMonoData).frame(width: 120, alignment: .leading).lineLimit(1)
                        Text(MIDIText.command(binding.command, macros: cue.macros)).font(.system(size: 13)).lineLimit(1)
                        Spacer(minLength: 0)
                        if cue.conflictingBindingIDs.contains(binding.id) {
                            Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(Tok.warning).help("Another binding uses the same pad").accessibilityLabel("Conflict")
                        }
                    }
                    Divider()
                }
            }
        }
    }

    private var keyboard: some View {
        VStack(alignment: .leading, spacing: Space.s3) {
            SectionLabel("Keyboard")
            ForEach(Self.keys, id: \.1) { key, command in
                HStack { KeyHint(key: key).frame(width: 96, alignment: .leading); Text(command).font(.system(size: 13)); Spacer() }
                Divider()
            }
        }
    }

    /// The same list a test checks for clashes (`ShowShortcuts`), with the MEDIA-010 layer clears.
    static let keys: [(String, String)] = ShowShortcuts.all.map { ($0.key, $0.command) }

    private var activity: some View {
        VStack(alignment: .leading, spacing: Space.s3) {
            SectionLabel("Activity")
            if cue.activity.isEmpty {
                Text("Nothing has run yet.").font(.system(size: 12)).foregroundStyle(Tok.muted)
            }
            ForEach(cue.activity.suffix(14)) { line in
                HStack(alignment: .firstTextBaseline, spacing: 6) {
                    Text(line.time, format: .dateTime.hour().minute().second()).foregroundStyle(Tok.muted)
                    Text("\(line.source.label) \(line.text)").foregroundStyle(line.isProblem ? Tok.warning : Tok.text)
                        .lineLimit(2).fixedSize(horizontal: false, vertical: true)
                }
                .font(.wfMonoData)
            }
        }
    }
}
