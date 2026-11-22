// UI-003 Part 1 / UI-005a: the right-hand column of Show, drawn to docs/UI (01-operator-show). Preview and Live side by side, the
// other enabled screens beneath, one slim row for what the design does not draw (Edit live slide, the live background override,
// Configure), one compact row of Looks, tabs (Props, Cues, Audio and, while open, Quick edit) and the stage message under them.
// Screen configuration is not here: "Configure…" switches to the Screens mode.
import SwiftUI
import AppKit
import Domain
import OutputEngine
import OperatorCore

struct ShowInspector: View {
    let app: AppModel
    @Bindable var workspace: WorkspaceModel
    @State private var textPropEditing: TextPropEdit?

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                monitors.padding(.horizontal, 12).padding(.vertical, 10)
                slimRow.padding(.horizontal, 12).padding(.bottom, 8)
                Rectangle().fill(Tok.border).frame(height: 1)
                lookRow.padding(.horizontal, 12).padding(.vertical, 8)
                tabBar
                tabContent
                Rectangle().fill(Tok.border).frame(height: 1)
                if let stage = app.stage { StageMessageView(stage: stage).padding(.horizontal, 12).padding(.vertical, 10) }
            }
        }
        .background(Tok.surface)
        .onChange(of: workspace.slides.isEmpty) { _, empty in app.ui.tabs.selectedSlideChanged(hasSelectedSlide: !empty) }
    }

    private var live: ScreenProfile? { ShowMonitors.live(app.profiles) }

    // MARK: Monitors

    /// The connector a screen is on, short: "SDI 3", "SDI 1+2" (fill and key), or the place's own name ("Window").
    private func connectorText(_ profile: ScreenProfile) -> String {
        if case .sdi(_, let connector, let keying, _) = profile.destination { return keying ? "SDI \(connector)+\(connector + 1)" : "SDI \(connector)" }
        return app.destinationName(profile.destination)
    }

    private var monitors: some View {
        let others = ShowMonitors.others(app.profiles)
        return Grid(horizontalSpacing: 10, verticalSpacing: 10) {
            GridRow(alignment: .top) {
                VStack(alignment: .leading, spacing: 6) {
                    HStack(spacing: 6) {
                        Badge(text: "PREVIEW", style: .preview)
                        if !workspace.slides.isEmpty { Text("slide \(workspace.show.selectedIndex + 1)").font(.wf(11)).foregroundStyle(Tok.muted) }
                    }
                    preview
                }
                VStack(alignment: .leading, spacing: 6) {
                    HStack(spacing: 6) {
                        liveBadge
                        Text(live.map { "\($0.role.rawValue.capitalized) · \(connectorText($0))" } ?? "Audience").font(.wf(11)).foregroundStyle(Tok.muted).lineLimit(1)
                    }
                    liveMonitor
                }
            }
            if !others.isEmpty {
                GridRow(alignment: .top) {
                    screenCard(others[0])
                    if others.count > 1 { screenCard(others[1]) } else { Color.clear }
                }
                if others.count > 2 {
                    GridRow(alignment: .top) {
                        screenCard(others[2])
                        if others.count > 3 { screenCard(others[3]) } else { Color.clear }
                    }
                }
            }
        }
    }

    /// The row for what the design does not draw but the operator needs: Edit live slide (the one edit that changes Live),
    /// the live background override with Drop, and Configure.
    private var slimRow: some View {
        HStack(spacing: 6) {
            Button { app.requestLiveQuickEdit() } label: {
                HStack(spacing: 5) { Image(systemName: "pencil.and.outline"); Text(QuickEditLabels.liveTitle) }
            }
            .buttonStyle(HeaderButtonStyle(ring: Tok.warning)).fixedSize()
            .disabled(workspace.show.liveSlide == nil)
            .help("\(HeaderChrome.Control.editLiveSlide.tooltip)")
            .accessibilityLabel("Edit live slide. Changes what the audience sees now.")
            .popover(isPresented: Binding(get: { app.ui.showLiveQuickEdit }, set: { app.ui.showLiveQuickEdit = $0 }), arrowEdge: .bottom) {
                QuickEditView(workspace: workspace) { app.ui.showLiveQuickEdit = false }
            }
            overrideChip
            Spacer(minLength: 4)
            if app.profiles.filter(\.isEnabled).isEmpty { Text("No screens enabled").font(.wf(11)).foregroundStyle(Tok.muted) }
            Button("Configure…") { workspace.setMode(.screens) }.buttonStyle(HeaderButtonStyle(kind: .ghost))
                .help("Screen settings are in the Screens mode (Command-6)")
        }
    }

    /// Shown while a background chosen in the media bin is on: it replaces every slide's own background on the live screens
    /// (and is never written to the presentation). The button drops it.
    @ViewBuilder private var overrideChip: some View {
        if let media = app.media, media.hasLiveBackgroundOverride {
            let name = media.layers.background.flatMap { media.asset($0.selection.assetID)?.name } ?? "a background"
            HStack(spacing: 5) {
                Image(systemName: "film").font(.wf(11)).foregroundStyle(Tok.muted).accessibilityHidden(true)
                Text("Override: \(name)").font(.wf(11)).foregroundStyle(Tok.muted).lineLimit(1).truncationMode(.middle)
                Button("Drop") { media.dropBackgroundOverride() }.buttonStyle(HeaderButtonStyle(compact: true))
                    .help("Drop the live background override and go back to each slide's own background")
                    .accessibilityLabel("Drop the live background override")
            }
            .accessibilityElement(children: .contain)
        }
    }

    @ViewBuilder private var preview: some View {
        let index = workspace.show.selectedIndex
        Group {
            if workspace.slides.indices.contains(index) {
                SlideThumbnail(app: app, slide: workspace.slides[index].content, cornerRadius: 6)
            } else if let open = workspace.openScripture, open.contents.indices.contains(index) {
                SlideThumbnail(app: app, slide: open.contents[index], cornerRadius: 6)       // LIB-004c: a passage in preview
            } else {
                RoundedRectangle(cornerRadius: 6).fill(Tok.surface2).aspectRatio(16.0 / 9.0, contentMode: .fit)
            }
        }
        .wfThumbState(radius: 6, preview: true)
        .padding(4)
        .accessibilityLabel("Preview: the selected slide")
    }

    @ViewBuilder private var liveMonitor: some View {
        Group {
            if let live { LiveScreenPreview(app: app, screenID: live.id, cornerRadius: 6) } else {
                RoundedRectangle(cornerRadius: 6).fill(Tok.surface2).aspectRatio(16.0 / 9.0, contentMode: .fit)
            }
        }
        .wfThumbState(radius: 6, live: app.mode == .live, liveColor: Tok.liveFill)
        .padding(app.mode == .live ? 5 : 0)
        .accessibilityLabel("Live: what the audience screen shows now")
    }

    @ViewBuilder private var liveBadge: some View {
        switch app.mode {
        case .live: Badge(text: "LIVE", style: .live)
        case .cleared: Badge(text: "CLEARED", style: .warning)
        case .blackout: Badge(text: "BLACKOUT", style: .warning)
        case .stopped: Badge(text: "NOT LIVE", style: .outline(Tok.muted))
        }
    }

    /// A stage or broadcast monitor with its ONE caption line: a dot, the role in bold, the connector, and SIM where it is simulated.
    private func screenCard(_ profile: ScreenProfile) -> some View {
        let readout = app.readouts.first { $0.id == profile.id }
        let simulated = readout?.sdi?.isSimulated == true || readout?.mirrors.contains { $0.sdi?.isSimulated == true } == true
        return VStack(alignment: .leading, spacing: 5) {
            LiveScreenPreview(app: app, screenID: profile.id, cornerRadius: 6)
                .wfThumbState(radius: 6)
            HStack(spacing: 6) {
                Circle().fill(profile.role.tokenColor).frame(width: 8, height: 8).accessibilityHidden(true)
                Text(profile.role.rawValue.capitalized).font(.wf(11, .semibold)).foregroundStyle(Tok.text).lineLimit(1)
                Text(connectorText(profile)).font(.wf(11)).foregroundStyle(Tok.muted).lineLimit(1)
                Spacer(minLength: 0)
                if simulated { Text("SIM").font(.wf(9, .bold)).tracking(0.54).foregroundStyle(Tok.broadcast).padding(.horizontal, 6).padding(.vertical, 1)
                    .wfOutline(RoundedRectangle(cornerRadius: Radius.sm), stroke: Tok.broadcast).fixedSize() }
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(profile.name), \(profile.role.rawValue) screen, \(app.destinationName(profile.destination))\(simulated ? ", simulated" : "")")
        .help("\(profile.name): \(app.destinationName(profile.destination)) · \(profile.videoMode.name)")
    }

    // MARK: Look

    private var lookRow: some View {
        GeometryReader { geo in lookButtons(width: geo.size.width) }.frame(height: 24)
    }

    private func lookButtons(width: CGFloat) -> some View {
        // The row minus its label and the chevron: as many Looks as their names allow, the rest in the menu.
        let room = Double(width) - 36 - 8 - 28
        let split = LookRow.split(app.looks, selected: app.selectedLookID, capacity: LookRow.capacity(for: app.looks, availableWidth: room))
        return HStack(spacing: 4) {
            SectionLabel("Look").frame(width: 36, alignment: .leading)
            ForEach(split.visible) { look in
                let selected = look.id == app.selectedLookID
                Button { app.selectLook(look.id) } label: {
                    Text(look.name).font(.wf(11, .medium)).lineLimit(1).fixedSize().frame(maxWidth: .infinity, minHeight: 24)
                }
                .buttonStyle(LookButtonStyle(selected: selected))
                .accessibilityAddTraits(selected ? .isSelected : [])
            }
            if !split.overflow.isEmpty {
                Menu {
                    ForEach(split.overflow) { look in Button(look.name) { app.selectLook(look.id) } }
                } label: { Image(systemName: "chevron.down").font(.wf(10, .semibold)).foregroundStyle(Tok.muted).frame(width: 24, height: 24) }
                    .menuStyle(.borderlessButton).menuIndicator(.hidden).fixedSize().help("More Looks")
                    .accessibilityLabel("More Looks")
            }
            if app.looks.isEmpty { Text("No Looks yet.").font(.wf(11)).foregroundStyle(Tok.muted) }
        }
    }

    // MARK: Tabs

    private var tabBar: some View {
        WFTabs(tabs: app.ui.tabs.visible.map { .init(value: $0, title: $0.title, symbol: $0 == .quickEdit ? "pencil" : nil, dot: $0 == .quickEdit) },
               selection: Binding(get: { app.ui.tabs.selected }, set: { app.ui.tabs.select($0) }))
    }

    @ViewBuilder private var tabContent: some View {
        switch app.ui.tabs.selected {
        case .props: props.padding(.horizontal, 12).padding(.vertical, 10)
        case .cues:
            CuesTabView(app: app, workspace: workspace).padding(12)
        case .audio:
            Group { if let audio = app.audio { AudioPanel(audio: audio) } else { Text("Audio is not available.").foregroundStyle(Tok.muted) } }.padding(12)
        case .quickEdit:
            QuickEditTab(app: app, workspace: workspace).padding(.horizontal, 12).padding(.vertical, 10)
        }
    }

    private var props: some View {
        return VStack(alignment: .leading, spacing: 0) {
            if app.props.isEmpty {
                Text("No props. Add a logo image in Screens, or a text prop below, to keep it above the slides.").font(.wf(11)).foregroundStyle(Tok.muted)
            }
            ForEach(app.props) { prop in propRow(prop) }
            ForEach(Array(app.messages.enumerated()), id: \.offset) { _, m in
                Text(m).font(.wf(11)).foregroundStyle(Tok.warning)
            }
            Button { textPropEditing = TextPropEdit(propID: nil) } label: { Label("Add text prop…", systemImage: "plus") }
                .buttonStyle(HeaderButtonStyle(kind: .ghost)).padding(.top, 6)
                .help("A service title strap, a speaker name: words kept above the slides on the screens you choose")
        }
        .sheet(item: $textPropEditing) { edit in TextPropSheet(app: app, edit: edit) }
    }

    /// One prop: icon by kind, name, the roles it is targeted to as pills that switch off when clicked, then its switch. The pills
    /// say where the prop is drawn when it is on and the screen's Look shows props: what is true, not decoration.
    private func propRow(_ prop: Prop) -> some View {
        HStack(spacing: 8) {
            Image(systemName: prop.kind == .text ? "textformat" : "photo").font(.wf(13)).foregroundStyle(Tok.text).frame(width: 15)
            Text(prop.name).font(.wf(13)).lineLimit(1)
            Spacer()
            if prop.kind == .image, app.unavailableImages.contains(prop.imagePath) {
                Text("File not readable").font(.wf(11)).foregroundStyle(Tok.warning)
            }
            ForEach(PropPills.pills(for: prop), id: \.role) { pill in
                // FIX-H item 10: a pill is a toggle. Off is drawn dimmed and stays in the row, so a click turns it on again.
                Button { app.togglePropTarget(prop.id, role: pill.role) } label: {
                    PillTag(text: pill.label, color: pill.role.tokenColor, height: 16).opacity(pill.isDimmed ? 0.35 : 1)
                }
                .buttonStyle(.plain)
                .help(pill.isOn ? "Drawn on \(pill.role.rawValue) screens. Click to stop showing it there." : "Not drawn on \(pill.role.rawValue) screens. Click to show it there.")
                .accessibilityLabel("\(prop.name) on \(pill.role.rawValue) screens")
                .accessibilityValue(pill.isOn ? "On" : "Off")
                .accessibilityAddTraits(.isToggle)
                .accessibilityHint(pill.isOn ? "Stops showing this prop on \(pill.role.rawValue) screens" : "Shows this prop on \(pill.role.rawValue) screens")
            }
            Toggle(prop.name, isOn: Binding(get: { prop.isOn }, set: { app.setProp(prop.id, isOn: $0) }))
                .toggleStyle(.wfBare)
        }
        .frame(height: 28)
        .contentShape(Rectangle())
        .contextMenu {
            Menu("Show on") {
                ForEach(ScreenRole.allCases, id: \.self) { role in
                    Toggle(role.rawValue.capitalized, isOn: Binding(get: { prop.targets.contains(role) }, set: { app.setProp(prop.id, target: role, isOn: $0) }))
                }
            }
            if prop.kind == .text { Button("Edit…") { textPropEditing = TextPropEdit(propID: prop.id) } }
            Divider()
            Button("Remove prop", role: .destructive) { app.removeProp(prop.id) }
        }
    }

    static func abbreviation(_ role: ScreenRole) -> String {
        switch role { case .audience: "AUD"; case .stage: "STG"; case .broadcast: "BRD" }
    }
}

struct TextPropEdit: Identifiable {
    let id = UUID()
    var propID: UUID?
}

/// UI-005b: makes or edits a text prop: its name, words, size, colour, position, and the screens it is drawn on. The words are drawn
/// by the same text path as the slides' words. Nothing changes on a screen until the prop is on and targeted to it.
struct TextPropSheet: View {
    let app: AppModel
    let edit: TextPropEdit
    @Environment(\.dismiss) private var dismiss
    @State private var name = "Service title strap"
    @State private var words = ""
    @State private var size = 48.0
    @State private var color = Color.white
    @State private var anchor = PropAnchor.bottomLeft
    @State private var targets: Set<ScreenRole> = [.broadcast]

    var body: some View {
        VStack(alignment: .leading, spacing: Space.s4) {
            Text(edit.propID == nil ? "Add text prop" : "Edit text prop").font(.wfHeadline)
            TextField("Name (for example Service title strap)", text: $name).textFieldStyle(.roundedBorder)
            TextField("Words", text: $words).textFieldStyle(.roundedBorder)
            HStack {
                Stepper("Size \(Int(size))", value: $size, in: TextPropSpec.fontSizes, step: 2)
                ColorPicker("Colour", selection: $color, supportsOpacity: false)
            }
            Picker("Position", selection: $anchor) { ForEach(PropAnchor.allCases, id: \.self) { Text($0.title).tag($0) } }
            HStack(spacing: Space.s4) {
                Text("Show on").font(.wf(12)).foregroundStyle(Tok.muted)
                ForEach(ScreenRole.allCases, id: \.self) { role in
                    Toggle(role.rawValue.capitalized, isOn: Binding(get: { targets.contains(role) },
                        set: { on in if on { targets.insert(role) } else { targets.remove(role) } })).toggleStyle(.wfCheckbox)
                }
            }
            Text("Speaker notes never go to the audience or broadcast screens, and this prop does not change that.")
                .font(.wfSmall).foregroundStyle(Tok.muted).fixedSize(horizontal: false, vertical: true)
            if let problem = TextPropRules.problem(name: name, targets: targets) {
                Text(problem).font(.wfSmall).foregroundStyle(Tok.warning).fixedSize(horizontal: false, vertical: true)
            } else if edit.propID == nil {
                Text(TextPropRules.savedOffNote).font(.wfSmall).foregroundStyle(Tok.muted)      // FIX-H item 10
            }
            HStack {
                Spacer()
                Button("Cancel") { dismiss() }.keyboardShortcut(.cancelAction)
                Button("Save") { if save() { dismiss() } }.keyboardShortcut(.defaultAction)
                    .disabled(TextPropRules.problem(name: name, targets: targets) != nil)
            }
        }
        .padding(Space.s6).frame(width: 460)
        .onAppear {
            guard let id = edit.propID, let prop = app.props.first(where: { $0.id == id }), let spec = prop.text else { return }
            name = prop.name; words = spec.text; size = spec.fontSize; anchor = spec.anchor; targets = prop.targets
            color = Self.color(hex: spec.colorHex)
        }
    }

    /// True when it was saved. A refusal (no name, no screen) leaves the sheet open; the line above the buttons says why.
    private func save() -> Bool {
        let spec = TextPropSpec(text: words, fontSize: size, colorHex: Self.hex(color), anchor: anchor)
        if let id = edit.propID { return app.saveTextProp(id, name: name, spec: spec, targets: targets) }
        return app.addTextProp(name: name, spec: spec, targets: targets) != nil
    }

    static func hex(_ color: Color) -> String {
        let c = NSColor(color).usingColorSpace(.sRGB) ?? .white
        return String(format: "#%02X%02X%02X", Int((c.redComponent * 255).rounded()), Int((c.greenComponent * 255).rounded()), Int((c.blueComponent * 255).rounded()))
    }
    static func color(hex: String) -> Color {
        let c = TextPropSpec(text: "", colorHex: hex).color
        return Color(.sRGB, red: c.red, green: c.green, blue: c.blue)
    }
}

/// The Look row's button: `.btn` at 24 pt and 11 pt text; selected = `surface-3` with a 1.5 pt selection-blue ring.
struct LookButtonStyle: ButtonStyle {
    let selected: Bool
    func makeBody(configuration: Configuration) -> some View {
        let shape = RoundedRectangle(cornerRadius: Radius.md)
        configuration.label
            .padding(.horizontal, 4)
            .foregroundStyle(Tok.text)
            .background { shape.fill(selected ? Tok.surface3 : Tok.surface2) }
            .overlay { shape.strokeBorder(Tok.borderStrong, lineWidth: 1) }
            .overlay { if selected { shape.strokeBorder(Tok.blue, lineWidth: 1.5) } }
            .opacity(configuration.isPressed ? 0.8 : 1)
            .contentShape(shape)
    }
}

// MARK: Quick edit tab

/// The selected slide's two language fields and speaker notes, with a "Preview only" chip and Done (Escape). It edits the
/// SELECTED slide, never the live output: the audience sees the change when the slide is taken live again.
struct QuickEditTab: View {
    let app: AppModel
    @Bindable var workspace: WorkspaceModel
    @FocusState private var firstFocused: Bool

    var body: some View {
        let index = workspace.show.selectedIndex
        VStack(alignment: .leading, spacing: Space.s3) {
            if workspace.slides.indices.contains(index) {
                let slide = workspace.slides[index]
                HStack(spacing: 8) {
                    Text("Slide \(index + 1) of \(workspace.slides.count)").font(.wf(13, .bold))
                    if let section = sectionName(slide) { Text(section).font(.wf(11)).foregroundStyle(Tok.muted) }
                    Spacer(minLength: 4)
                    PillTag(text: QuickEditLabels.previewChip, color: Tok.blue, height: 18)
                        .accessibilityLabel("Preview only. The screens do not change until this slide goes live.")
                }
                let names = workspace.quickEditLanguageLabels          // FIX-H item 13: a reading of the words is a suggestion ("Vietnamese?")
                field(names.first.text, slide: slide, kind: .first, focus: true)
                field(names.second.text, slide: slide, kind: .second, focus: false)
                field("Speaker notes — stage screens only", slide: slide, kind: .notes, focus: false)
                // The design's footer row: the saved note at the left, Done (esc) at the right.
                HStack(spacing: 8) {
                    // The note counts from the last real write; it redraws each second only while this tab is open.
                    TimelineView(.periodic(from: .now, by: 1)) { _ in
                        Text(workspace.hasUnsavedDrafts ? "Saving…" : workspace.quickEditSavedNote())
                            .font(.wf(11)).foregroundStyle(Tok.muted).lineLimit(2).fixedSize(horizontal: false, vertical: true)
                    }
                    Spacer(minLength: 4)
                    Button { app.closeQuickEdit() } label: { HStack(spacing: 5) { Text("Done"); KeyHint(key: "esc") } }
                        .buttonStyle(HeaderButtonStyle()).keyboardShortcut(.cancelAction)
                        .help("Close the Quick edit tab (Escape)")
                }
                .padding(.top, 2)
            } else {
                Text("Select a slide to edit its words.").foregroundStyle(Tok.muted)
            }
        }
        .onAppear { firstFocused = true }
        .onChange(of: app.ui.focusQuickEdit) { _, _ in firstFocused = true }
    }

    private func sectionName(_ slide: Slide) -> String? {
        slide.groupID.flatMap { id in workspace.groups.first { $0.id == id }?.name }
    }

    private enum Kind { case first, second, notes }

    private func field(_ label: String, slide: Slide, kind: Kind, focus: Bool) -> some View {
        let binding = Binding<String>(
            get: {
                switch kind { case .first: slide.content.primary; case .second: slide.content.secondary ?? ""; case .notes: slide.notes }
            },
            set: { new in
                var content = slide.content
                switch kind {
                case .first: content.primary = new; workspace.editSlide(id: slide.id, content: content)
                case .second: content.secondary = new.isEmpty ? nil : new; workspace.editSlide(id: slide.id, content: content)
                case .notes: workspace.editSlide(id: slide.id, content: content, notes: new)
                }
            })
        return VStack(alignment: .leading, spacing: 3) {
            SectionLabel(label)
            let editor = WordsEditorField(label: label, text: binding, minHeight: kind == .notes ? 30 : 46, placeholder: kind == .notes ? "None" : nil)
            if focus { editor.focused($firstFocused) } else { editor }
        }
    }
}
