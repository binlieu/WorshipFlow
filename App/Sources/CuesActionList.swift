// CUE-002b (item 6): the ordered, numbered list of actions of a macro or a slide, with a picker per action kind. Used by the macro
// editor and the slide-actions editor; the decisions (kinds offered, reasons something is unavailable, row text) come from OperatorCore.
// UI-005g: rows are the design's `.act` (38 pt, number 20, kind column 150, detail, tags), "Add action" its 26 pt `.btn`.
import SwiftUI
import CueEngine
import OperatorCore
import MIDIIO

struct ActionListEditor: View {
    let app: AppModel
    let context: CueActionContext
    /// The macro being edited, so a macro cannot be offered itself.
    var editingMacro: UUID?
    let actions: [CueAction]
    /// UI-008: a list nested under another one (the marker's) tags its rectangles with its own prefix, so the macro's `act.N` and `main.add` are not overwritten.
    var rectPrefix = ""
    let onChange: ([CueAction]) -> Void

    @State private var editing: Int?

    var body: some View {
        let choices = app.cueChoices()
        VStack(alignment: .leading, spacing: 0) {
            ForEach(Array(actions.enumerated()), id: \.offset) { index, action in
                CuesActionRow(index: index, actions: actions, choices: choices, editingMacro: editingMacro, editing: $editing, rectPrefix: rectPrefix, onChange: onChange)
                    .padding(.bottom, 6)
            }
            addMenu(choices).padding(.top, 4)
        }
    }

    private func addMenu(_ choices: CueChoices) -> some View {
        let groups = Dictionary(grouping: CueActionKind.allCases.filter { CueActionEditing.isAllowed($0, in: context) }, by: \.group)
        let order = ["Show", "Look and props", "Stage", "Media", "Audio", "Other"]
        return Menu {
            ForEach(order.filter { groups[$0] != nil }, id: \.self) { group in
                Section(group) {
                    ForEach(groups[group] ?? []) { kind in
                        let reason = CueActionEditing.unavailableReason(for: kind, choices: offered(kind, choices))
                        Button {
                            if let new = CueActionEditing.defaultAction(for: kind, choices: offered(kind, choices)) {
                                var list = actions
                                CueStepEditing.insert(new, into: &list, at: list.count)
                                onChange(list)
                                editing = list.count - 1
                            }
                        } label: { Text(reason.map { "\(kind.title) (\($0))" } ?? kind.title) }
                            .disabled(reason != nil)
                    }
                }
            }
        } label: {
            // ui.css `.btn`: 26 pt, padding 0 10 plus the border, gap 6; a 15 pt plus, the words, a 12 pt chevron.
            HStack(spacing: 6) {
                Image(systemName: "plus").font(.wf(13)).frame(width: 15, height: 15)
                Text("Add action").font(.wf(12, .medium)).wfLine()
                Image(systemName: "chevron.down").font(.wf(9, .semibold)).frame(width: 12, height: 12)
            }
            .foregroundStyle(Tok.text)
            .padding(.horizontal, 11).frame(height: Space.controlHeight)
            .wfOutline(RoundedRectangle(cornerRadius: Radius.md), stroke: Tok.borderStrong, fill: Tok.surface2)
            .wfRect("\(rectPrefix)main.add", size: 12, weight: 500, radius: Radius.md)
            .contentShape(Rectangle())
        }
        .menuStyle(.button).buttonStyle(.plain).menuIndicator(.hidden).fixedSize()
        .wfFocusReport(.popUp)
        .accessibilityLabel("Add action")
    }

    /// A macro cannot be offered itself.
    private func offered(_ kind: CueActionKind, _ all: CueChoices) -> CueChoices {
        var c = all
        c.macros = all.macros(excluding: editingMacro)
        return c
    }
}

/// One action row (`.act`): a 20 pt number, the kind with its icon in a 150 pt column, the detail, the screen tags. Move, edit and remove
/// are the owner's extras: they appear at the right on hover, while the row has keyboard focus or while the edit form is open; they stay
/// in the accessibility tree, so the row is as drawn and still fully operable.
struct CuesActionRow: View {
    let index: Int
    let actions: [CueAction]
    let choices: CueChoices
    var editingMacro: UUID?
    @Binding var editing: Int?
    var rectPrefix = ""
    let onChange: ([CueAction]) -> Void
    @State private var hovering = false

    var body: some View {
        let action = actions[index]
        let description = CueActionEditing.describe(action, choices: choices)
        let kind = CueActionKind.of(action)
        let id = "\(rectPrefix)act.\(index)"
        let shown = hovering || editing == index
        HStack(spacing: 10) {
            Text("\(index + 1)").font(.wf(11, .bold).monospacedDigit()).frame(width: 20, height: 20)
                .background(Tok.surface3, in: Circle()).wfRect("\(id).n", size: 11, weight: 700, radius: 10)
                .frame(width: 22, alignment: .leading).accessibilityHidden(true)
            HStack(spacing: 8) {
                Image(systemName: kind?.symbol ?? "questionmark").font(.wf(13)).frame(width: 15, height: 15).accessibilityHidden(true)
                Text(description.title).font(.wf(13, .bold)).lineLimit(1).wfLine()
            }
            .frame(width: 150, alignment: .leading).wfRect("\(id).col")
            Text(description.detail).font(.wf(13)).foregroundStyle(description.isBroken ? Tok.warning : Tok.muted)
                .lineLimit(1).truncationMode(.tail).wfLine().frame(maxWidth: .infinity, alignment: .leading).wfRect("\(id).detail", size: 13, weight: 400)
            HStack(spacing: 4) {
                ForEach(Array(description.screens.enumerated()), id: \.offset) { n, screen in
                    PillTag(text: screen.tag, color: screen.color, rectID: "\(id).tag.\(n)")
                }
            }
            .wfRect("\(id).tags")
        }
        .padding(.horizontal, 11).padding(.vertical, 9)
        .background(Tok.surface, in: RoundedRectangle(cornerRadius: Radius.lg))
        .overlay(RoundedRectangle(cornerRadius: Radius.lg).strokeBorder(description.isBroken ? Tok.warning : Tok.border, lineWidth: 1))
        .overlay(alignment: .trailing) { controlRow(action: action, kind: kind).opacity(shown ? 1 : 0).padding(.trailing, 6) }
        .wfRect(id, radius: Radius.lg)
        .onHover { hovering = $0 }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Step \(index + 1): \(description.title) \(description.detail)")
    }

    private func controlRow(action: CueAction, kind: CueActionKind?) -> some View {
        HStack(spacing: 2) {
            iconButton("chevron.up", "Move up", disabled: index == 0) { var l = actions; CueStepEditing.move(&l, from: index, to: index - 1); onChange(l) }
            iconButton("chevron.down", "Move down", disabled: index == actions.count - 1) { var l = actions; CueStepEditing.move(&l, from: index, to: index + 1); onChange(l) }
            iconButton("slider.horizontal.3", "Edit", disabled: kind == nil) { editing = index }
                .popover(isPresented: Binding(get: { editing == index }, set: { if !$0, editing == index { editing = nil } }), arrowEdge: .trailing) {
                    ActionEditForm(action: action, choices: choices, editingMacro: editingMacro) { new in
                        var l = actions; CueStepEditing.replace(&l, at: index, with: new); onChange(l)
                    }
                    .frame(width: 340).padding(Space.s5)
                }
            iconButton("trash", "Remove", disabled: false) { var l = actions; CueStepEditing.remove(&l, at: index); onChange(l) }
        }
        .padding(.horizontal, 4).background(Tok.surface2, in: RoundedRectangle(cornerRadius: Radius.md))
    }

    private func iconButton(_ symbol: String, _ label: String, disabled: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) { Image(systemName: symbol).frame(width: 24, height: 24).contentShape(Rectangle()) }
            .buttonStyle(.plain).foregroundStyle(Tok.muted).disabled(disabled).opacity(disabled ? 0.35 : 1)
            .help(label).accessibilityLabel(label)
    }
}

/// The form for one action: a picker per kind of value.
struct ActionEditForm: View {
    let action: CueAction
    let choices: CueChoices
    var editingMacro: UUID?
    let onChange: (CueAction) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: Space.s4) {
            Text(CueActionKind.of(action)?.title ?? "Action").font(.wf(13, .semibold))
            form
        }
    }

    @ViewBuilder private var form: some View {
        switch action {
        case .transport(.goToSlide(let index)):
            Stepper("Slide number \(index + 1)", value: Binding(get: { index + 1 }, set: { onChange(.transport(.goToSlide(index: max(0, $0 - 1)))) }), in: 1...999)
        case .transport(.blackout(let mode)):
            Picker("Blackout", selection: Binding(get: { mode }, set: { onChange(.transport(.blackout($0))) })) {
                Text("On").tag(CueBlackout.on); Text("Off").tag(CueBlackout.off); Text("Toggle").tag(CueBlackout.toggle)
            }.pickerStyle(.segmented)
        case .transport:
            Text("Nothing to choose.").font(.wfSmall).foregroundStyle(Tok.muted)
        case .selectLook(let id):
            picker("Look", choices.looks, id) { onChange(.selectLook($0)) }
        case .prop(let id, let on):
            picker("Prop", choices.props, id) { onChange(.prop(id: $0, isOn: on)) }
            Toggle("Show the prop", isOn: Binding(get: { on }, set: { onChange(.prop(id: id, isOn: $0)) }))
        case .showMessage(let id, let fields):
            TextField("Message for the stage screens", text: Binding(get: { fields["text"] ?? "" }, set: { onChange(.showMessage(id: id, fields: ["text": $0])) }))
                .textFieldStyle(.roundedBorder)
        case .hideMessage:
            Text("Takes the message off the stage screens.").font(.wfSmall).foregroundStyle(Tok.muted)
        case .startTimer(let id): picker("Timer", choices.timers, id) { onChange(.startTimer($0)) }
        case .pauseTimer(let id): picker("Timer", choices.timers, id) { onChange(.pauseTimer($0)) }
        case .resetTimer(let id): picker("Timer", choices.timers, id) { onChange(.resetTimer($0)) }
        case .setBackground(let id):
            if let id { picker("Background", choices.pictures, id) { onChange(.setBackground(assetID: $0)) } }
            else { Text("Takes the background away.").font(.wfSmall).foregroundStyle(Tok.muted) }
        case .playForeground(let id): picker("Picture or video", choices.pictures, id) { onChange(.playForeground(assetID: $0)) }
        case .stopForeground: Text("Stops the clip over the slide.").font(.wfSmall).foregroundStyle(Tok.muted)
        case .playAudio(let id): picker("Sound", choices.sounds, id) { onChange(.playAudio(assetID: $0)) }
        case .stopAudio(let id): picker("Sound", choices.sounds, id) { onChange(.stopAudio(assetID: $0)) }
        case .midiOut(let message): MIDIOutForm(message: message, onChange: { onChange(.midiOut($0)) })
        case .runMacro(let id): picker("Macro", choices.macros(excluding: editingMacro), id) { onChange(.runMacro($0)) }
        case .wait(let seconds):
            Stepper("Wait \(String(format: "%g", seconds)) s", value: Binding(get: { seconds }, set: { onChange(.wait(seconds: max(0, $0))) }), in: 0...3600, step: 0.5)
        case .unknown:
            Text("This action was written by a newer version. It is skipped when run and kept as it is.").font(.wfSmall).foregroundStyle(Tok.muted)
        }
    }

    private func picker(_ title: String, _ list: [CueChoice], _ current: UUID, _ set: @escaping (UUID) -> Void) -> some View {
        Picker(title, selection: Binding(get: { current }, set: set)) {
            if !list.contains(where: { $0.id == current }) { Text("(missing)").tag(current) }
            ForEach(list) { Text($0.name).tag($0.id) }
        }
    }
}

private struct MIDIOutForm: View {
    let message: MIDIMessage
    let onChange: (MIDIMessage) -> Void

    private var kind: String {
        switch message { case .noteOn: "noteOn"; case .noteOff: "noteOff"; case .controlChange: "cc"; case .programChange: "pc" }
    }
    private var parts: (channel: Int, d1: Int, d2: Int) {
        switch message {
        case .noteOn(let c, let n, let v): (c, n, v)
        case .noteOff(let c, let n, let v): (c, n, v)
        case .controlChange(let c, let n, let v): (c, n, v)
        case .programChange(let c, let p): (c, p, 0)
        }
    }
    private func make(_ kind: String, _ c: Int, _ a: Int, _ b: Int) -> MIDIMessage {
        switch kind {
        case "noteOff": .noteOff(channel: c, note: a, velocity: b)
        case "cc": .controlChange(channel: c, controller: a, value: b)
        case "pc": .programChange(channel: c, program: a)
        default: .noteOn(channel: c, note: a, velocity: b)
        }
    }

    var body: some View {
        let p = parts
        VStack(alignment: .leading, spacing: Space.s3) {
            Picker("Message", selection: Binding(get: { kind }, set: { onChange(make($0, p.channel, p.d1, kind == "pc" ? 100 : p.d2)) })) {
                Text("Note on").tag("noteOn"); Text("Note off").tag("noteOff"); Text("Control change").tag("cc"); Text("Program change").tag("pc")
            }
            Stepper("Channel \(p.channel)", value: Binding(get: { p.channel }, set: { onChange(make(kind, $0, p.d1, p.d2)) }), in: 1...16)
            Stepper(kind == "cc" ? "Controller \(p.d1)" : kind == "pc" ? "Program \(p.d1)" : "Note \(MIDIText.noteName(p.d1)) (\(p.d1))",
                    value: Binding(get: { p.d1 }, set: { onChange(make(kind, p.channel, $0, p.d2)) }), in: 0...127)
            if kind != "pc" {
                Stepper(kind == "cc" ? "Value \(p.d2)" : "Velocity \(p.d2)", value: Binding(get: { p.d2 }, set: { onChange(make(kind, p.channel, p.d1, $0)) }), in: 0...127)
            }
        }
    }
}
