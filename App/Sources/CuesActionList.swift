// CUE-002b (item 6): the ordered, numbered list of actions of a macro or a slide, with a picker per action kind. Used by the macro
// editor and the slide-actions editor; the decisions (kinds offered, reasons something is unavailable, row text) come from OperatorCore.
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
    let onChange: ([CueAction]) -> Void

    @State private var editing: Int?

    var body: some View {
        let choices = app.cueChoices()
        VStack(alignment: .leading, spacing: Space.s3) {
            ForEach(Array(actions.enumerated()), id: \.offset) { index, action in
                row(index, action, choices)
            }
            addMenu(choices)
        }
    }

    private func row(_ index: Int, _ action: CueAction, _ choices: CueChoices) -> some View {
        let description = CueActionEditing.describe(action, choices: choices)
        let kind = CueActionKind.of(action)
        return HStack(spacing: Space.s4) {
            Text("\(index + 1)").font(.wf(12, .bold).monospacedDigit())
                .frame(width: 24, height: 24).background(Tok.surface3, in: Circle()).accessibilityHidden(true)
            Image(systemName: kind?.symbol ?? "questionmark").frame(width: 18).foregroundStyle(Tok.muted).accessibilityHidden(true)
            Text(description.title).font(.wf(14, .semibold)).frame(width: 190, alignment: .leading).lineLimit(1)
            Text(description.detail).font(.wf(13)).foregroundStyle(description.isBroken ? Tok.warning : Tok.muted)
                .lineLimit(1).truncationMode(.tail).frame(maxWidth: .infinity, alignment: .leading)
            ScreenTags(screens: description.screens)
            HStack(spacing: 2) {
                iconButton("chevron.up", "Move up", disabled: index == 0) { move(index, to: index - 1) }
                iconButton("chevron.down", "Move down", disabled: index == actions.count - 1) { move(index, to: index + 1) }
                iconButton("slider.horizontal.3", "Edit", disabled: kind == nil) { editing = index }
                    .popover(isPresented: Binding(get: { editing == index }, set: { if !$0, editing == index { editing = nil } }), arrowEdge: .trailing) {
                        ActionEditForm(action: action, choices: choices, editingMacro: editingMacro) { new in replace(index, new) }
                            .frame(width: 340).padding(Space.s5)
                    }
                iconButton("trash", "Remove", disabled: false) { remove(index) }
            }
        }
        .padding(.horizontal, Space.s4).frame(minHeight: 48)
        .background(Tok.surface, in: RoundedRectangle(cornerRadius: Radius.lg))
        .overlay(RoundedRectangle(cornerRadius: Radius.lg).stroke(description.isBroken ? Tok.warning : Tok.border, lineWidth: 1))
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Step \(index + 1): \(description.title) \(description.detail)")
    }

    private func iconButton(_ symbol: String, _ label: String, disabled: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) { Image(systemName: symbol).frame(width: 24, height: 24).contentShape(Rectangle()) }
            .buttonStyle(.plain).foregroundStyle(Tok.muted).disabled(disabled).opacity(disabled ? 0.35 : 1)
            .help(label).accessibilityLabel(label)
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
            HStack(spacing: 6) { Image(systemName: "plus"); Text("Add action"); Image(systemName: "chevron.down").font(.wf(9)) }
                .font(.wf(13, .medium)).padding(.horizontal, 12).frame(height: 30)
                .overlay(RoundedRectangle(cornerRadius: Radius.md).stroke(Tok.borderStrong, lineWidth: 1))
        }
        .menuStyle(.borderlessButton).menuIndicator(.hidden).fixedSize()
        .accessibilityLabel("Add action")
    }

    /// A macro cannot be offered itself.
    private func offered(_ kind: CueActionKind, _ all: CueChoices) -> CueChoices {
        var c = all
        c.macros = all.macros(excluding: editingMacro)
        return c
    }

    private func move(_ i: Int, to j: Int) { var l = actions; CueStepEditing.move(&l, from: i, to: j); onChange(l) }
    private func remove(_ i: Int) { var l = actions; CueStepEditing.remove(&l, at: i); onChange(l) }
    private func replace(_ i: Int, _ new: CueAction) { var l = actions; CueStepEditing.replace(&l, at: i, with: new); onChange(l) }
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
