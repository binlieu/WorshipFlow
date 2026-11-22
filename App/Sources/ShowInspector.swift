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
        VStack(spacing: 0) {
            scrolling
            // UI-005j: what the design does not draw (Edit live slide, the live background override with Drop, Configure…) sits at the
            // bottom, pinned, in the area the design leaves empty; it takes no space when there is nothing to show.
            if showsSlimRow {
                Rectangle().fill(Tok.border).frame(height: 1)
                slimRow.padding(.horizontal, 12).padding(.vertical, 8)
                    .background(Tok.surface)
            }
        }
        .background(Tok.surface)
    }

    private var showsSlimRow: Bool {
        workspace.show.liveSlide != nil || app.media?.hasLiveBackgroundOverride == true || app.profiles.filter(\.isEnabled).isEmpty
    }

    private var scrolling: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                monitors.padding(.horizontal, 12).padding(.vertical, 10)
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
                        Badge(text: "PREVIEW", style: .preview, rectID: "insp.mon.0.badge")
                        if !workspace.slides.isEmpty { Text("slide \(workspace.show.selectedIndex + 1)").font(.wf(11)).foregroundStyle(Tok.muted).wfLine().wfRect("insp.mon.0.caption", size: 11, weight: 400) }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .wfRect("insp.mon.0.head")
                    preview
                }
                .wfRect("insp.mon.0")
                VStack(alignment: .leading, spacing: 6) {
                    HStack(spacing: 6) {
                        liveBadge
                        Text(live.map { "\($0.role.rawValue.capitalized) · \(connectorText($0))" } ?? "Audience").font(.wf(11)).foregroundStyle(Tok.muted).lineLimit(1).wfLine()
                            .wfRect("insp.mon.1.caption", size: 11, weight: 400)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .wfRect("insp.mon.1.head")
                    liveMonitor
                }
                .wfRect("insp.mon.1")
            }
            if !others.isEmpty {
                GridRow(alignment: .top) {
                    screenCard(others[0], at: 2)
                    if others.count > 1 { screenCard(others[1], at: 3) } else { Color.clear }
                }
                if others.count > 2 {
                    GridRow(alignment: .top) {
                        screenCard(others[2], at: 4)
                        if others.count > 3 { screenCard(others[3], at: 5) } else { Color.clear }
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
        .wfRect("insp.mon.0.thumb", radius: 6)
        .wfThumbState(radius: 6, preview: true)
        .accessibilityLabel("Preview: the selected slide")
    }

    @ViewBuilder private var liveMonitor: some View {
        Group {
            if let live { LiveScreenPreview(app: app, screenID: live.id, cornerRadius: 6) } else {
                RoundedRectangle(cornerRadius: 6).fill(Tok.surface2).aspectRatio(16.0 / 9.0, contentMode: .fit)
            }
        }
        .wfRect("insp.mon.1.thumb", radius: 6)
        .wfThumbState(radius: 6, live: app.mode == .live, liveColor: Tok.liveFill)
        .accessibilityLabel("Live: what the audience screen shows now")
    }

    @ViewBuilder private var liveBadge: some View {
        switch app.mode {
        case .live: Badge(text: "LIVE", style: .live, rectID: "insp.mon.1.badge")
        case .cleared: Badge(text: "CLEARED", style: .warning, rectID: "insp.mon.1.badge")
        case .blackout: Badge(text: "BLACKOUT", style: .warning, rectID: "insp.mon.1.badge")
        case .stopped: Badge(text: "NOT LIVE", style: .outline(Tok.muted), rectID: "insp.mon.1.badge")
        }
    }

    /// A stage or broadcast monitor with its ONE caption line: a dot, the role in bold, the connector, and SIM where it is simulated.
    private func screenCard(_ profile: ScreenProfile, at index: Int) -> some View {
        let readout = app.readouts.first { $0.id == profile.id }
        let simulated = readout?.sdi?.isSimulated == true || readout?.mirrors.contains { $0.sdi?.isSimulated == true } == true
        return VStack(alignment: .leading, spacing: 5) {
            LiveScreenPreview(app: app, screenID: profile.id, cornerRadius: 6)
                .wfRect("insp.mon.\(index).thumb", radius: 6)
                .wfThumbState(radius: 6)
            HStack(spacing: 6) {
                Circle().fill(profile.role.tokenColor).frame(width: 8, height: 8).wfRect("insp.mon.\(index).dot").accessibilityHidden(true)
                Text(profile.role.rawValue.capitalized).font(.wf(11, .semibold)).foregroundStyle(Tok.text).lineLimit(1).wfLine().wfRect("insp.mon.\(index).role", size: 11, weight: 600)
                Text(connectorText(profile)).font(.wf(11)).foregroundStyle(Tok.muted).lineLimit(1).wfLine().wfRect("insp.mon.\(index).dest", size: 11, weight: 400)
                Spacer(minLength: 0)
                if simulated { Text("SIM").font(.wf(9, .bold)).tracking(0.54).wfLine().foregroundStyle(Tok.broadcast).padding(.horizontal, 7).padding(.vertical, 2)
                    .wfOutline(RoundedRectangle(cornerRadius: Radius.sm), stroke: Tok.broadcast).wfRect("insp.mon.\(index).sim", size: 9, weight: 700, radius: Radius.sm).fixedSize() }
            }
            .wfRect("insp.mon.\(index).cap")
        }
        .frame(maxHeight: .infinity, alignment: .top)       // the grid row's height is its tallest card (the Broadcast caption is 20 pt), as in CSS grid
        .wfRect("insp.mon.\(index)")
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(profile.name), \(profile.role.rawValue) screen, \(app.destinationName(profile.destination))\(simulated ? ", simulated" : "")")
        .help("\(profile.name): \(app.destinationName(profile.destination)) · \(profile.videoMode.name)")
    }

    // MARK: Look

    private var lookRow: some View {
        GeometryReader { geo in lookButtons(width: geo.size.width) }.frame(height: 24).wfRect("insp.look.row")
    }

    private func lookButtons(width: CGFloat) -> some View {
        // The row minus its label, its chevron and the two 8 pt gaps: as many Looks as their names allow, the rest in the menu.
        let room = Double(width) - 36 - 8 - 8 - 18
        let split = LookRow.split(app.looks, selected: app.selectedLookID, capacity: LookRow.capacity(for: app.looks, availableWidth: room))
        return HStack(spacing: 8) {
            SectionLabel("Look").frame(width: 36, alignment: .leading).wfRect("insp.look.label", size: 11, weight: 600)
            HStack(spacing: 4) {
                ForEach(Array(split.visible.enumerated()), id: \.element.id) { index, look in
                    let selected = look.id == app.selectedLookID
                    Button { app.selectLook(look.id) } label: {
                        Text(look.name).font(.wf(11, .medium)).lineLimit(1).frame(maxWidth: .infinity, minHeight: 24)
                    }
                    .buttonStyle(LookButtonStyle(selected: selected))
                    .wfRect("insp.look.\(index)", size: 11, weight: 500, radius: Radius.md)
                    .accessibilityAddTraits(selected ? .isSelected : [])
                }
                if app.looks.isEmpty { Text("No Looks yet.").font(.wf(11)).foregroundStyle(Tok.muted) }
            }
            .frame(maxWidth: .infinity)
            // The design's chevron: always there; it lists every Look (the ones that did not fit in the row are only here).
            Menu {
                ForEach(app.looks) { look in
                    Button { app.selectLook(look.id) } label: {
                        if look.id == app.selectedLookID { Label(look.name, systemImage: "checkmark") } else { Text(look.name) }
                    }
                }
            } label: { Image(systemName: "chevron.down").font(.wf(10, .semibold)).foregroundStyle(Tok.muted).frame(width: 12, height: 12).frame(width: 18, height: 24).wfRect("insp.look.more") }
                .menuStyle(.button).buttonStyle(.plain).menuIndicator(.hidden).fixedSize().help("All Looks")
                .accessibilityLabel("All Looks")
        }
    }

    // MARK: Tabs

    private var tabBar: some View {
        WFTabs(tabs: app.ui.tabs.visible.map { .init(value: $0, title: $0.title, symbol: $0 == .quickEdit ? "pencil" : nil, dot: $0 == .quickEdit) },
               selection: Binding(get: { app.ui.tabs.selected }, set: { app.ui.tabs.select($0) }), rectID: "insp.tabs")
        .overlay(alignment: .trailing) {
            // UI-005j: "Add text prop…" is a + in the Props tab's line, not a row of its own (nothing is lost).
            if app.ui.tabs.selected == .props {
                Button { textPropEditing = TextPropEdit(propID: nil) } label: { Image(systemName: "plus").font(.wf(12)).foregroundStyle(Tok.muted).frame(width: 22, height: 22) }
                    .buttonStyle(.plain).padding(.trailing, 10).wfRect("insp.tabs.add")
                    .help("Add a text prop: a service title strap, a speaker name, words kept above the slides on the screens you choose")
                    .accessibilityLabel("Add text prop")
            }
        }
        .sheet(item: $textPropEditing) { edit in TextPropSheet(app: app, edit: edit) }
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
                Text("No props. Add a logo image in Screens, or a text prop with the + above, to keep it above the slides.").font(.wf(11)).foregroundStyle(Tok.muted)
            }
            ForEach(Array(app.props.enumerated()), id: \.element.id) { index, prop in propRow(prop, at: index) }
            ForEach(Array(app.messages.enumerated()), id: \.offset) { _, m in
                Text(m).font(.wf(11)).foregroundStyle(Tok.warning)
            }
        }
    }

    /// One prop: icon by kind, name, the roles it is targeted to as pills that switch off when clicked, then its switch. The pills
    /// say where the prop is drawn when it is on and the screen's Look shows props: what is true, not decoration.
    private func propRow(_ prop: Prop, at index: Int) -> some View {
        HStack(spacing: 8) {
            Image(systemName: prop.kind == .text ? "textformat" : "photo").font(.wf(13)).foregroundStyle(Tok.text).frame(width: 15, height: 15)
                .wfRect("insp.prop.\(index).icon")
            Text(prop.name).font(.wf(13)).lineLimit(1).wfRect("insp.prop.\(index).name", size: 13, weight: 400)
            Spacer()
            if prop.kind == .image, app.unavailableImages.contains(prop.imagePath) {
                Text("File not readable").font(.wf(11)).foregroundStyle(Tok.warning)
            }
            // UI-005j: the row shows the screens the prop is on, as the design draws it; the context menu's "Show on" adds or removes one.
            ForEach(PropPills.pills(for: prop).filter(\.isOn), id: \.role) { pill in
                // FIX-H item 10: a pill is a toggle. Off is drawn dimmed and stays in the row, so a click turns it on again.
                Button { app.togglePropTarget(prop.id, role: pill.role) } label: {
                    PillTag(text: pill.label, color: pill.role.tokenColor, height: 16, rectID: "insp.prop.\(index).pill.\(pill.label)").opacity(pill.isDimmed ? 0.35 : 1)
                }
                .buttonStyle(.plain)
                .help(pill.isOn ? "Drawn on \(pill.role.rawValue) screens. Click to stop showing it there." : "Not drawn on \(pill.role.rawValue) screens. Click to show it there.")
                .accessibilityLabel("\(prop.name) on \(pill.role.rawValue) screens")
                .accessibilityValue(pill.isOn ? "On" : "Off")
                .accessibilityAddTraits(.isToggle)
                .accessibilityHint(pill.isOn ? "Stops showing this prop on \(pill.role.rawValue) screens" : "Shows this prop on \(pill.role.rawValue) screens")
            }
            Toggle(prop.name, isOn: Binding(get: { prop.isOn }, set: { app.setProp(prop.id, isOn: $0) }))
                .toggleStyle(.wfBare).wfRect("insp.prop.\(index).toggle", radius: 9)
        }
        .frame(height: 28)
        .wfRect("insp.prop.\(index)")
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
