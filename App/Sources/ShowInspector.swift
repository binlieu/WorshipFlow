// UI-003 Part 1: the right-hand column of Show. Preview and Live side by side, every other enabled screen beneath, one
// compact row of Looks, tabs (Props, Cues, Audio and, while open, Quick edit) and the stage message pinned at the bottom.
// Screen configuration is not here: "Configure…" switches to the Screens mode.
import SwiftUI
import Domain
import OutputEngine
import OperatorCore

struct ShowInspector: View {
    let app: AppModel
    @Bindable var workspace: WorkspaceModel

    var body: some View {
        VStack(spacing: 0) {
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    monitors.padding(.horizontal, Space.s5).padding(.top, Space.s5).padding(.bottom, Space.s4)
                    otherScreens.padding(.horizontal, Space.s5).padding(.bottom, Space.s4)
                    lookRow.padding(.horizontal, Space.s5).padding(.bottom, Space.s3)
                    tabBar
                    tabContent.padding(Space.s5)
                }
            }
            Rectangle().fill(Tok.border).frame(height: 1)
            if let stage = app.stage { StageMessageView(stage: stage).padding(Space.s5) }
        }
        .background(Tok.surface)
        .onChange(of: workspace.slides.isEmpty) { _, empty in app.ui.tabs.selectedSlideChanged(hasSelectedSlide: !empty) }
    }

    private var live: ScreenProfile? { ShowMonitors.live(app.profiles) }

    // MARK: Preview and Live

    private var monitors: some View {
        HStack(alignment: .top, spacing: Space.s3) {
            VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: 6) {
                    Badge(text: "PREVIEW", style: .preview)
                    if !workspace.slides.isEmpty { Text("slide \(workspace.show.selectedIndex + 1)").font(.system(size: 12)).foregroundStyle(Tok.muted) }
                }
                preview
                // The tab edits the SELECTED slide in preview. It never changes the screens.
                Button { app.openQuickEdit() } label: {
                    HStack(spacing: 6) {
                        Image(systemName: "pencil")
                        Text(QuickEditLabels.previewTitle)
                        KeyHint(key: QuickEditLabels.previewShortcut)
                    }.frame(maxWidth: .infinity)
                }
                .buttonStyle(HeaderButtonStyle()).disabled(workspace.slides.isEmpty)
                .help("Edit the selected slide in the side panel. \(QuickEditLabels.previewChip): the screens change when you go live with it.")
                .accessibilityLabel("Quick edit the selected slide. Preview only.")
            }
            VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: 6) {
                    liveBadge
                    Text(live?.name ?? "Audience").font(.system(size: 12)).foregroundStyle(Tok.muted).lineLimit(1)
                }
                liveMonitor
                // The other quick edit: it DELIBERATELY changes what the audience sees now, so it says so and is outlined in
                // the warning colour, apart from the preview edit beside it.
                Button { app.requestLiveQuickEdit() } label: {
                    HStack(spacing: 6) {
                        Image(systemName: "pencil.and.outline")
                        Text(QuickEditLabels.liveTitle)
                    }.frame(maxWidth: .infinity)
                }
                .buttonStyle(HeaderButtonStyle())
                .overlay(RoundedRectangle(cornerRadius: Radius.md).stroke(Tok.warning, lineWidth: 1.5))
                .disabled(workspace.show.liveSlide == nil)
                .help("\(HeaderChrome.Control.editLiveSlide.tooltip)")
                .accessibilityLabel("Edit live slide. Changes what the audience sees now.")
                .popover(isPresented: Binding(get: { app.ui.showLiveQuickEdit }, set: { app.ui.showLiveQuickEdit = $0 }), arrowEdge: .bottom) {
                    QuickEditView(workspace: workspace) { app.ui.showLiveQuickEdit = false }
                }
            }
        }
    }

    @ViewBuilder private var preview: some View {
        let index = workspace.show.selectedIndex
        Group {
            if workspace.slides.indices.contains(index) {
                SlideThumbnail(app: app, slide: workspace.slides[index].content)
            } else if let open = workspace.openScripture, open.contents.indices.contains(index) {
                SlideThumbnail(app: app, slide: open.contents[index])       // LIB-004c: a passage in preview
            } else {
                RoundedRectangle(cornerRadius: Radius.sm).fill(Tok.surface2).aspectRatio(16.0 / 9.0, contentMode: .fit)
            }
        }
        .padding(3)
        .overlay(RoundedRectangle(cornerRadius: Radius.md).stroke(Tok.blue, lineWidth: 2))
        .accessibilityLabel("Preview: the selected slide")
    }

    @ViewBuilder private var liveMonitor: some View {
        Group {
            if let live { LiveScreenPreview(app: app, screenID: live.id) } else {
                RoundedRectangle(cornerRadius: Radius.sm).fill(Tok.surface2).aspectRatio(16.0 / 9.0, contentMode: .fit)
            }
        }
        .padding(app.mode == .live ? 7 : 3)
        .overlay(RoundedRectangle(cornerRadius: Radius.lg).stroke(app.mode == .live ? Tok.liveFill : Tok.border, lineWidth: app.mode == .live ? 3 : 1))
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

    // MARK: Other screens

    private var otherScreens: some View {
        let others = ShowMonitors.others(app.profiles)
        return VStack(alignment: .leading, spacing: Space.s3) {
            if !others.isEmpty {
                LazyVGrid(columns: [GridItem(.flexible(), spacing: Space.s3, alignment: .top), GridItem(.flexible(), spacing: Space.s3, alignment: .top)],
                          alignment: .leading, spacing: Space.s3) {
                    ForEach(others) { profile in screenCard(profile) }
                }
            }
            HStack {
                if app.profiles.filter(\.isEnabled).isEmpty {
                    Text("No screens are enabled.").font(.caption).foregroundStyle(Tok.muted)
                }
                Spacer()
                Button("Configure…") { workspace.setMode(.screens) }.buttonStyle(.plain).foregroundStyle(Tok.muted)
                    .font(.system(size: 12)).help("Screen settings are in the Screens mode (Command-6)")
            }
        }
    }

    private func screenCard(_ profile: ScreenProfile) -> some View {
        let readout = app.readouts.first { $0.id == profile.id }
        let simulated = readout?.sdi?.isSimulated == true || readout?.mirrors.contains { $0.sdi?.isSimulated == true } == true
        return VStack(alignment: .leading, spacing: 4) {
            LiveScreenPreview(app: app, screenID: profile.id)
            HStack(spacing: 5) {
                Circle().fill(profile.role.tokenColor).frame(width: 7, height: 7).accessibilityHidden(true)
                Text(profile.role.rawValue.capitalized).font(.system(size: 12, weight: .semibold)).lineLimit(1)
                Spacer(minLength: 0)
                if simulated { Badge(text: "SIM", style: .outline(Tok.broadcast)) }
            }
            Text(destinationText(profile)).font(.system(size: 12)).foregroundStyle(Tok.muted).lineLimit(2)
                .fixedSize(horizontal: false, vertical: true)
            if profile.name.caseInsensitiveCompare(profile.role.rawValue) != .orderedSame {
                Text(profile.name).font(.wfCaption).foregroundStyle(Tok.muted).lineLimit(1)
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(profile.name), \(profile.role.rawValue) screen, \(destinationText(profile))\(simulated ? ", simulated" : "")")
    }

    private func destinationText(_ profile: ScreenProfile) -> String {
        let place = app.destinationName(profile.destination)
        return profile.destination.isSDI ? "\(place) · \(profile.videoMode.name)" : place
    }

    // MARK: Look

    private var lookRow: some View {
        GeometryReader { geo in lookButtons(width: geo.size.width) }.frame(height: Space.controlHeight)
    }

    private func lookButtons(width: CGFloat) -> some View {
        // The row minus its label and the chevron: as many Looks as their names allow, the rest in the menu.
        let room = Double(width) - 38 - 30
        let split = LookRow.split(app.looks, selected: app.selectedLookID, capacity: LookRow.capacity(for: app.looks, availableWidth: room))
        return HStack(spacing: 6) {
            SectionLabel("Look").frame(width: 38, alignment: .leading)
            ForEach(split.visible) { look in
                let selected = look.id == app.selectedLookID
                Button { app.selectLook(look.id) } label: {
                    Text(look.name).lineLimit(1).fixedSize().frame(maxWidth: .infinity)
                }
                .buttonStyle(HeaderButtonStyle(selected: selected))
                .overlay(RoundedRectangle(cornerRadius: Radius.md).stroke(selected ? Tok.cyan : .clear, lineWidth: 2))
                .accessibilityAddTraits(selected ? .isSelected : [])
            }
            if !split.overflow.isEmpty {
                Menu {
                    ForEach(split.overflow) { look in Button(look.name) { app.selectLook(look.id) } }
                } label: { Image(systemName: "chevron.down") }
                    .menuStyle(.borderlessButton).menuIndicator(.hidden).fixedSize().help("More Looks")
                    .accessibilityLabel("More Looks")
            }
            if app.looks.isEmpty { Text("No Looks yet.").font(.caption).foregroundStyle(Tok.muted) }
        }
    }

    // MARK: Tabs

    private var tabBar: some View {
        HStack(spacing: Space.s4) {
            ForEach(app.ui.tabs.visible) { tab in
                let selected = app.ui.tabs.selected == tab
                Button { app.ui.tabs.select(tab) } label: {
                    HStack(spacing: 4) {
                        Text(tab.title).font(.system(size: 13, weight: selected ? .semibold : .regular))
                        if tab == .quickEdit { Circle().fill(Tok.blue).frame(width: 6, height: 6).accessibilityHidden(true) }
                    }
                    .padding(.horizontal, 4).frame(height: 30)
                    .foregroundStyle(selected ? Tok.text : Tok.muted)
                    .overlay(alignment: .bottom) { Rectangle().fill(selected ? Tok.cyan : .clear).frame(height: 2) }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityAddTraits(selected ? [.isButton, .isSelected] : .isButton)
            }
            Spacer()
        }
        .padding(.horizontal, Space.s5)
        .overlay(alignment: .bottom) { Rectangle().fill(Tok.border).frame(height: 1) }
    }

    @ViewBuilder private var tabContent: some View {
        switch app.ui.tabs.selected {
        case .props: props
        case .cues:
            CuesTabView(app: app, workspace: workspace)
        case .audio:
            if let audio = app.audio { AudioPanel(audio: audio) } else { Text("Audio is not available.").foregroundStyle(Tok.muted) }
        case .quickEdit:
            QuickEditTab(app: app, workspace: workspace)
        }
    }

    private var props: some View {
        let roles = LayerPresence.roles(showing: .props, screens: app.layerInputs)
        return VStack(alignment: .leading, spacing: Space.s4) {
            if app.props.isEmpty {
                Text("No props. Add a logo image in Screens to keep it above the slides.").font(.caption).foregroundStyle(Tok.muted)
            }
            ForEach(app.props) { prop in
                HStack(spacing: Space.s3) {
                    Image(systemName: "photo").foregroundStyle(Tok.muted).frame(width: 18)
                    Text(prop.name).lineLimit(1)
                    Spacer()
                    if app.unavailableImages.contains(prop.imagePath) {
                        Text("File not readable").font(.caption).foregroundStyle(Tok.warning)
                    }
                    // The roles whose screens show the props layer under the active Look: what is true, not decoration.
                    ForEach(roles, id: \.self) { role in
                        Text(role == .audience ? "AUD" : "BRD").font(.system(size: 11, weight: .bold)).tracking(0.4)
                            .foregroundStyle(role.tokenColor).padding(.horizontal, 8).frame(height: 20)
                            .overlay(Capsule().stroke(role.tokenColor, lineWidth: 1)).fixedSize()
                            .accessibilityLabel("\(role.rawValue) screens show props")
                    }
                    Toggle(prop.name, isOn: Binding(get: { prop.isOn }, set: { app.setProp(prop.id, isOn: $0) }))
                        .toggleStyle(.switch).labelsHidden().tint(Tok.cyan)
                }
            }
            ForEach(Array(app.messages.enumerated()), id: \.offset) { _, m in
                Text(m).font(.caption).foregroundStyle(Tok.warning)
            }
        }
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
                    Text("Slide \(index + 1) of \(workspace.slides.count)").font(.system(size: 14, weight: .semibold))
                    if let section = sectionName(slide) { Text(section).font(.system(size: 12)).foregroundStyle(Tok.muted) }
                    Spacer(minLength: 4)
                    Text(QuickEditLabels.previewChip).font(.system(size: 12, weight: .medium)).foregroundStyle(Tok.blue)
                        .padding(.horizontal, 9).frame(height: 22).overlay(Capsule().stroke(Tok.blue, lineWidth: 1))
                        .accessibilityLabel("Preview only. The screens do not change until this slide goes live.")
                    Button { app.closeQuickEdit() } label: { HStack(spacing: 5) { Text("Done"); KeyHint(key: "esc") } }
                        .buttonStyle(HeaderButtonStyle()).keyboardShortcut(.cancelAction)
                        .help("Close the Quick edit tab (Escape)")
                }
                field("First language", slide: slide, kind: .first, focus: true)
                field("Second language", slide: slide, kind: .second, focus: false)
                field("Speaker notes — stage screens only", slide: slide, kind: .notes, focus: false)
                Text(workspace.hasUnsavedDrafts ? "Saving…" : "Saved · \(QuickEditLabels.previewNote)")
                    .font(.wfCaption).foregroundStyle(Tok.muted).lineLimit(2).fixedSize(horizontal: false, vertical: true)
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
            let editor = WordsEditorField(label: label, text: binding, minHeight: kind == .notes ? 34 : 50)
            if focus { editor.focused($firstFocused) } else { editor }
        }
    }
}
