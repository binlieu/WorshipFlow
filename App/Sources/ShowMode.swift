// UI-001 / ADR-0007: the Show mode. Library and playlist on the left, the slide grid in the middle, Preview and Live
// side by side with the screens summary, Looks, props and timers on the right. Everything here is an existing panel
// re-homed; the decisions live in OperatorCore.
import SwiftUI
import Domain
import OutputEngine
import OperatorCore

struct ShowModeView: View {
    let app: AppModel
    @Bindable var workspace: WorkspaceModel
    let query: String
    let clearQuery: () -> Void
    /// Keyboard focus belongs on the slide grid, so the transport keys never land in a text field by accident (KI-021).
    var gridFocused: FocusState<Bool>.Binding

    var body: some View {
        HSplitView {
            LibrarySidebar(app: app, workspace: workspace)
                .frame(minWidth: 240, idealWidth: Space.sidebarWidth, maxWidth: 320)
            CentrePane(app: app, workspace: workspace, query: query, clearQuery: clearQuery)
                .frame(minWidth: 460)
                .focusable().focused(gridFocused).focusEffectDisabled()
            ShowInspector(app: app, workspace: workspace)
                .frame(minWidth: 320, idealWidth: Space.inspectorWidth, maxWidth: 400)
        }
    }
}

struct ShowInspector: View {
    let app: AppModel
    @Bindable var workspace: WorkspaceModel

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                monitors.padding(Space.s5)
                divider
                screensSummary.padding(Space.s5)
                divider
                looks.padding(Space.s5)
                divider
                propsAndMessages.padding(Space.s5)
                if let stage = app.stage {
                    divider
                    TimersPanel(app: app, stage: stage).padding(Space.s5)
                }
            }
        }
        .background(Tok.surface)
    }

    private var divider: some View { Rectangle().fill(Tok.border).frame(height: 1) }

    private var audience: ScreenProfile? {
        app.profiles.first { $0.role == .audience && $0.isEnabled } ?? app.profiles.first { $0.role == .audience }
    }

    // MARK: Preview and Live

    private var monitors: some View {
        HStack(alignment: .top, spacing: Space.s3) {
            VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: 6) {
                    Badge(text: "PREVIEW", style: .preview)
                    if !workspace.slides.isEmpty { Text("slide \(workspace.show.selectedIndex + 1)").font(.system(size: 12)).foregroundStyle(Tok.muted) }
                }
                preview
            }
            VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: 6) {
                    liveBadge
                    Text(audience?.name ?? "Audience").font(.system(size: 12)).foregroundStyle(Tok.muted).lineLimit(1)
                }
                live
            }
        }
    }

    @ViewBuilder private var preview: some View {
        let index = workspace.show.selectedIndex
        Group {
            if workspace.slides.indices.contains(index) {
                SlideThumbnail(app: app, slide: workspace.slides[index].content)
            } else {
                RoundedRectangle(cornerRadius: Radius.sm).fill(Tok.surface2).aspectRatio(16.0 / 9.0, contentMode: .fit)
            }
        }
        .padding(3)
        .overlay(RoundedRectangle(cornerRadius: Radius.md).stroke(Tok.blue, lineWidth: 2))
        .accessibilityLabel("Preview: the selected slide")
    }

    @ViewBuilder private var live: some View {
        Group {
            if let audience { LiveScreenPreview(app: app, screenID: audience.id) } else {
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

    // MARK: Screens summary

    private var screensSummary: some View {
        VStack(alignment: .leading, spacing: Space.s3) {
            HStack {
                SectionLabel("Screens")
                Spacer()
                Button("Configure…") { workspace.setMode(.screens) }.buttonStyle(.plain).foregroundStyle(Tok.muted)
                    .font(.system(size: 12))
            }
            let enabled = app.profiles.filter(\.isEnabled)
            if enabled.isEmpty {
                Text("No screens are enabled. Open Screens to set them up.").font(.caption).foregroundStyle(Tok.muted)
            }
            LazyVGrid(columns: [GridItem(.flexible(), spacing: Space.s3), GridItem(.flexible(), spacing: Space.s3)], alignment: .leading, spacing: Space.s3) {
                ForEach(enabled) { profile in screenCard(profile) }
            }
        }
    }

    private func screenCard(_ profile: ScreenProfile) -> some View {
        let readout = app.readouts.first { $0.id == profile.id }
        let simulated = readout?.sdi?.isSimulated == true || readout?.mirrors.contains { $0.sdi?.isSimulated == true } == true
        return VStack(alignment: .leading, spacing: 4) {
            LiveScreenPreview(app: app, screenID: profile.id)
            HStack(spacing: 5) {
                RoleChip(role: profile.role)
                if simulated { Badge(text: "SIMULATED", style: .outline(Tok.broadcast)) }
            }
            Text(profile.name).font(.system(size: 12, weight: .semibold)).lineLimit(1)
            Text(destinationText(profile)).font(.wfMonoData).foregroundStyle(Tok.muted).lineLimit(2)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(profile.name), \(profile.role.rawValue) screen, \(destinationText(profile))\(simulated ? ", simulated" : "")")
    }

    private func destinationText(_ profile: ScreenProfile) -> String {
        let place = app.destinationName(profile.destination)
        return profile.destination.isSDI ? "\(place) · \(profile.videoMode.name)" : place
    }

    // MARK: Looks

    private var looks: some View {
        VStack(alignment: .leading, spacing: Space.s3) {
            SectionLabel("Look")
            LazyVGrid(columns: [GridItem(.flexible(), spacing: Space.s3), GridItem(.flexible(), spacing: Space.s3)], spacing: Space.s3) {
                ForEach(app.looks) { look in
                    let selected = look.id == app.selectedLookID
                    Button { app.selectLook(look.id) } label: {
                        HStack(spacing: 6) {
                            if selected { Image(systemName: "checkmark") }
                            Text(look.name).lineLimit(1)
                        }
                        .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(HeaderButtonStyle(selected: selected))
                    .overlay(RoundedRectangle(cornerRadius: Radius.md).stroke(selected ? Tok.cyan : .clear, lineWidth: 2))
                    .accessibilityAddTraits(selected ? .isSelected : [])
                }
            }
            if app.looks.isEmpty { Text("No Looks yet.").font(.caption).foregroundStyle(Tok.muted) }
        }
    }

    // MARK: Props and messages

    private var propsAndMessages: some View {
        VStack(alignment: .leading, spacing: Space.s3) {
            SectionLabel("Props and messages")
            if app.props.isEmpty {
                Text("No props. Add a logo image in Screens to keep it above the slides.").font(.caption).foregroundStyle(Tok.muted)
            }
            ForEach(app.props) { prop in
                HStack {
                    Image(systemName: "photo").foregroundStyle(Tok.muted)
                    Text(prop.name).lineLimit(1)
                    Spacer()
                    if app.unavailableImages.contains(prop.imagePath) {
                        Text("File not readable").font(.caption).foregroundStyle(Tok.warning)
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
