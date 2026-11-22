// CUE-002b (item 6): the centre of the Cues mode for a macro, the slide actions and the schedule.
import SwiftUI
import Domain
import CueEngine
import OperatorCore

// MARK: Macro

struct MacroEditor: View {
    let app: AppModel
    let cue: CueModel
    let macroID: UUID
    @State private var name = ""
    @State private var blockedBy: [String]?
    @FocusState private var nameFocused: Bool

    var body: some View {
        if let macro = cue.macro(macroID) {
            CuesPage(leading: { titleBar(macro) }, trailing: { trailingBar(macro) }) {
                ActionListEditor(app: app, context: .macro, editingMacro: macro.id, actions: macro.steps) { steps in
                    Task { @MainActor in await cue.setSteps(steps, of: macro.id) }
                }
                // The design's "Playback markers" section sits here (a 54 pt timeline and its axis). Markers are not stored or run yet,
                // so nothing is drawn; its room is kept so the note below stays where the design has it.
                Color.clear.frame(height: 142)
                orderNote
            }
            .task(id: macro.id) { name = macro.name }
            .alert("Other things still run \u{201C}\(macro.name)\u{201D}", isPresented: Binding(get: { blockedBy != nil }, set: { if !$0 { blockedBy = nil } })) {
                Button("Delete anyway", role: .destructive) { Task { @MainActor in _ = await cue.deleteMacro(macro.id, force: true) } }
                Button("Keep it", role: .cancel) {}
            } message: {
                Text("It is used by \((blockedBy ?? []).joined(separator: ", ")). Deleting it removes it from each of them.")
            }
        }
    }

    /// `.card` with a 15 pt warning icon: padding 10 x 12, radius 10, 12 pt on a 17 pt line. The second sentence says what the executor
    /// really does (CueExecutor: a step that moves the show first, then the Look, props and messages, media, sound, timers and MIDI; a
    /// wait splits the list), not the design's "top to bottom on one frame boundary".
    private var orderNote: some View {
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: "exclamationmark.triangle").font(.wf(13)).frame(width: 15, height: 15).accessibilityHidden(true)
            (Text("Order is fixed and visible.").font(.wf(12, .bold)) + Text(" Actions run top to bottom, in the order shown, except that a step that moves the show comes first, then the Look, props and messages, media, sound, timers and MIDI. A wait splits the list in two. A macro never changes which destination a screen is mapped to, and it cannot put speaker notes on an Audience or Broadcast screen.").font(.wf(12)).foregroundColor(Tok.muted))
                .lineSpacing(2.5).fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 13).padding(.vertical, 11)
        .background(Tok.surface, in: RoundedRectangle(cornerRadius: Radius.xl))
        .overlay(RoundedRectangle(cornerRadius: Radius.xl).strokeBorder(Tok.border, lineWidth: 1))
        .wfRect("main.note", radius: Radius.xl)
        .accessibilityElement(children: .combine)
    }

    @ViewBuilder private func titleBar(_ macro: Macro) -> some View {
        // The title is a field so the macro can be renamed; it is as wide as its text, as the design's span is.
        Text(name.isEmpty ? " " : name).font(.wf(17, .bold)).lineLimit(1).wfLine(22).opacity(0).wfRect("main.title", size: 17, weight: 700)
            .frame(minWidth: 40, alignment: .leading)
            .overlay(alignment: .leading) {
                TextField("Macro name", text: $name)
                    .textFieldStyle(.plain).font(.wf(17, .bold)).focused($nameFocused)
                    .onSubmit { commitName(macro) }
                    .onChange(of: nameFocused) { _, focused in if !focused { commitName(macro) } }
                    .accessibilityLabel("Macro name")
            }
            .fixedSize()
        let count = macro.steps.count
        CuesChip(text: "Macro \u{00B7} \(count) action\(count == 1 ? "" : "s")", rectID: "main.pill")
        // The owner's extra: delete. It sits in the free room between the chip and the trigger.
        Menu {
            Button("Delete macro\u{2026}", role: .destructive) { delete(macro) }
        } label: { Image(systemName: "ellipsis").font(.wf(13)).foregroundStyle(Tok.muted).frame(width: 22, height: 22).contentShape(Rectangle()) }
            .menuStyle(.button).buttonStyle(.plain).menuIndicator(.hidden).fixedSize().help("More").accessibilityLabel("More")
    }

    @ViewBuilder private func trailingBar(_ macro: Macro) -> some View {
        // UI-006g: the Trigger field is a menu that chooses the macro's function key (CU-21); "Dry run" lists what Run would do (CU-22).
        CuesTriggerField(cue: cue, macro: macro)
        CuesDryRunButton(app: app, cue: cue, macroID: macro.id)
        Button { cue.submit(.runMacro(macro.id), from: .button) } label: {
            HStack(spacing: 6) { Image(systemName: "bolt").font(.wf(13)).frame(width: 15, height: 15); Text("Run").wfLine() }
        }
        .buttonStyle(HeaderButtonStyle(kind: .primary)).wfRect("main.run", size: 12, weight: 500, radius: Radius.md)
        .help("Run this macro now").accessibilityLabel("Run macro")
    }

    private func commitName(_ macro: Macro) {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed != macro.name else { return }
        Task { @MainActor in
            await cue.renameMacro(macro.id, to: trimmed)
            if cue.lastError != nil { name = macro.name }
        }
    }

    private func delete(_ macro: Macro) {
        Task { @MainActor in
            if case .blocked(let users) = await cue.deleteMacro(macro.id) { blockedBy = users }
        }
    }
}

// MARK: Slide actions

struct SlideActionsEditor: View {
    let app: AppModel
    let cue: CueModel
    @Bindable var workspace: WorkspaceModel

    var body: some View {
        CuesPage(title: "Slide actions") {
          VStack(alignment: .leading, spacing: Space.s5) {
            Text("Actions that run when a slide goes live: not when it is only selected, and not for a quick edit. They cannot move the show, so a slide can never advance itself.")
                .font(.wf(13)).foregroundStyle(Tok.muted).fixedSize(horizontal: false, vertical: true)
            if workspace.slides.isEmpty {
                CueNote(text: "Open a song in Show to give its slides actions.")
            } else {
                slideList
                if let slide = chosenSlide {
                    Text("Slide \((workspace.slides.firstIndex { $0.id == slide.id } ?? 0) + 1): \(firstLine(slide))").font(.wf(14, .semibold))
                    ActionListEditor(app: app, context: .slide, actions: cue.slideActions.actions(for: slide.id)) { actions in
                        Task { @MainActor in try? await cue.setSlideActions(actions, for: slide.id) }
                    }
                }
            }
          }
        }
    }

    private var chosenSlide: Slide? {
        workspace.slides.first { $0.id == app.ui.cuesSlideID } ?? workspace.slides[safe: workspace.showParts.selectedIndex] ?? workspace.slides.first
    }

    private var slideList: some View {
        // FIX-Q: the chosen slide is worked out once for the list, not once per row (a search of all the slides per row, 200 x 200, ran on every Next).
        let chosenID = chosenSlide?.id
        return LazyVStack(spacing: 2) {      // FIX-Q: rows are made as they scroll into view, not all 200 on every change
            ForEach(Array(workspace.slides.enumerated()), id: \.element.id) { index, slide in
                let count = cue.slideActions.actions(for: slide.id).count
                let selected = chosenID == slide.id
                Button { app.ui.cuesSlideID = slide.id } label: {
                    HStack(spacing: Space.s3) {
                        Text("\(index + 1)").font(.wf(12, .bold).monospacedDigit()).frame(width: 24)
                        Text(firstLine(slide)).font(.wf(13)).lineLimit(1)
                        Spacer()
                        if count > 0 { Badge(text: "\(count) ACTION\(count == 1 ? "" : "S")", style: .outline(Tok.cyan)) }
                    }
                    .padding(.horizontal, Space.s3).frame(height: 30)
                    .background(selected ? Tok.surface3 : .clear, in: RoundedRectangle(cornerRadius: Radius.md))
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Slide \(index + 1), \(count) actions")
                .accessibilityAddTraits(selected ? .isSelected : [])
            }
        }
        .padding(Space.s2)
        .overlay(RoundedRectangle(cornerRadius: Radius.lg).stroke(Tok.border, lineWidth: 1))
    }

    private func firstLine(_ slide: Slide) -> String { slide.content.primary.split(whereSeparator: \.isNewline).first.map(String.init) ?? "(empty)" }
}

private extension Array {
    subscript(safe index: Int) -> Element? { indices.contains(index) ? self[index] : nil }
}

// MARK: Schedule

struct ScheduleEditor: View {
    let app: AppModel
    let cue: CueModel
    @State private var editing: ScheduleDraft?
    @State private var deleting: ScheduledEvent?

    var body: some View {
        CuesPage(title: "Schedule", trailing: {
            Button { editing = ScheduleDraft() } label: { Label("New event", systemImage: "plus") }
                .buttonStyle(HeaderButtonStyle()).disabled(cue.macros.isEmpty)
                .help(cue.macros.isEmpty ? "Make a macro first: an event runs a macro" : "A macro that runs at a set time")
                .popover(isPresented: Binding(get: { editing != nil && editing?.id == nil }, set: { if !$0 { editing = nil } }), arrowEdge: .bottom) {
                    if editing != nil { ScheduleForm(cue: cue, draft: Binding(get: { editing ?? ScheduleDraft() }, set: { editing = $0 })) { editing = nil } }
                }
        }) {
          VStack(alignment: .leading, spacing: Space.s5) {
            Text("While WorshipFlow is open, an event runs a macro at its time. An event more than five minutes late (the Mac was asleep, or the app was closed) is not run late: it is skipped and you are told.")
                .font(.wf(13)).foregroundStyle(Tok.muted).fixedSize(horizontal: false, vertical: true)
            if cue.schedule.events.isEmpty { CueNote(text: "No scheduled events.") }
            ForEach(cue.schedule.events) { event in row(event) }
            if !cue.missedEvents.isEmpty {
                HStack {
                    Text("Not run").font(.wf(15, .semibold))
                    Spacer()
                    Button("Dismiss all") { cue.dismissMissedEvents() }.buttonStyle(HeaderButtonStyle())
                }
                ForEach(cue.missedEvents) { missed in
                    Text(missed.text).font(.wf(13)).foregroundStyle(Tok.warning).fixedSize(horizontal: false, vertical: true)
                }
            }
          }
        }
        .alert("Delete \u{201C}\(deleting?.name ?? "")\u{201D}?", isPresented: Binding(get: { deleting != nil }, set: { if !$0 { deleting = nil } })) {
            Button("Delete", role: .destructive) { if let e = deleting { Task { @MainActor in await cue.deleteEvent(e.id) } } }
            Button("Cancel", role: .cancel) {}
        }
    }

    private func row(_ event: ScheduledEvent) -> some View {
        let macro: String = {
            switch event.payload {
            case .macro(let id): cue.macro(id)?.name ?? "(missing macro)"
            case .actions(let a): "\(a.count) action\(a.count == 1 ? "" : "s")"
            }
        }()
        return HStack(spacing: Space.s4) {
            Toggle("", isOn: Binding(get: { event.isEnabled }, set: { on in Task { @MainActor in await cue.setEventEnabled(on, id: event.id) } }))
                .toggleStyle(.wfBare).accessibilityLabel("\(event.name) enabled")
            VStack(alignment: .leading, spacing: 2) {
                Text(event.name).font(.wf(14, .semibold))
                Text("\(ScheduleText.timing(event.timing, calendar: .current)) \u{00B7} runs \(macro)").font(.wf(12)).foregroundStyle(Tok.muted)
            }
            Spacer()
            if let problems = cue.schedule.problems()[event.id] {
                Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(Tok.warning).help(problems.joined(separator: " "))
            }
            Button { editing = ScheduleDraft(event: event) } label: { Image(systemName: "slider.horizontal.3") }
                .buttonStyle(.plain).foregroundStyle(Tok.muted).help("Edit").accessibilityLabel("Edit \(event.name)")
                .popover(isPresented: Binding(get: { editing?.id == event.id }, set: { if !$0, editing?.id == event.id { editing = nil } }), arrowEdge: .trailing) {
                    if editing != nil { ScheduleForm(cue: cue, draft: Binding(get: { editing ?? ScheduleDraft() }, set: { editing = $0 })) { editing = nil } }
                }
            Button { deleting = event } label: { Image(systemName: "trash") }
                .buttonStyle(.plain).foregroundStyle(Tok.muted).help("Delete").accessibilityLabel("Delete \(event.name)")
        }
        .padding(.horizontal, Space.s4).frame(minHeight: 52)
        .background(Tok.surface, in: RoundedRectangle(cornerRadius: Radius.lg))
        .overlay(RoundedRectangle(cornerRadius: Radius.lg).stroke(Tok.border, lineWidth: 1))
    }
}

private struct ScheduleForm: View {
    let cue: CueModel
    @Binding var draft: ScheduleDraft
    let done: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: Space.s4) {
            Text(draft.id == nil ? "New event" : "Edit event").font(.wf(13, .semibold))
            TextField("Name", text: $draft.name).textFieldStyle(.roundedBorder)
            Picker("Repeats", selection: $draft.repeats) { Text("Every week").tag(ScheduleDraft.Repeat.weekly); Text("Once").tag(ScheduleDraft.Repeat.once) }
                .pickerStyle(.segmented).labelsHidden()
            if draft.repeats == .weekly {
                HStack(spacing: 4) {
                    ForEach(Weekday.allCases, id: \.self) { day in
                        let on = draft.weekdays.contains(day)
                        Button(Self.letters[day.rawValue - 1]) { if on { draft.weekdays.remove(day) } else { draft.weekdays.insert(day) } }
                            .buttonStyle(HeaderButtonStyle(selected: on)).accessibilityLabel(Self.names[day.rawValue - 1])
                            .accessibilityAddTraits(on ? .isSelected : [])
                    }
                }
                HStack {
                    Stepper("Hour \(String(format: "%02d", draft.hour))", value: $draft.hour, in: 0...23)
                    Stepper("Minute \(String(format: "%02d", draft.minute))", value: $draft.minute, in: 0...59)
                }
            } else {
                DatePicker("When", selection: $draft.date)
            }
            if draft.keepsActions {
                Text("This event runs a list of actions written elsewhere. They are kept as they are.").font(.wfSmall).foregroundStyle(Tok.muted)
            } else {
                Picker("Runs", selection: $draft.macroID) {
                    Text("Choose a macro").tag(UUID?.none)
                    ForEach(cue.macros) { Text($0.name).tag(UUID?.some($0.id)) }
                }
            }
            ForEach(draft.problems, id: \.self) { Text($0).font(.wfSmall).foregroundStyle(Tok.warning) }
            HStack {
                Spacer()
                Button("Cancel", action: done).buttonStyle(HeaderButtonStyle())
                Button("Save") {
                    guard let event = draft.build() else { return }
                    Task { @MainActor in await cue.saveEvent(event); done() }
                }
                .buttonStyle(HeaderButtonStyle(selected: true)).disabled(draft.build() == nil)
            }
        }
        .frame(width: 340).padding(Space.s5)
    }

    static let letters = ["S", "M", "T", "W", "T", "F", "S"]
    static let names = ["Sunday", "Monday", "Tuesday", "Wednesday", "Thursday", "Friday", "Saturday"]
}
