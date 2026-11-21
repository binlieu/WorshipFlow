// UI-002 Part 2 / ADR-0007: the Screens mode. A screens list on the left, a signal map above the selected screen's
// settings on the right. The map is drawn entirely from `SignalMapPresenter` (OutputEngine): what each connector carries,
// in the order and with the fill and key route the card reports. This file decides nothing; it draws.
import SwiftUI
import AppKit
import Domain
import OutputEngine
import OperatorCore
import SDIEngine
import UniformTypeIdentifiers

struct ScreensModeView: View {
    let app: AppModel
    @Environment(\.openWindow) private var openWindow
    @State private var exportMessage: String?

    private var selectedID: UUID? {
        if let id = app.ui.selectedScreenID, app.profiles.contains(where: { $0.id == id }) { return id }
        return app.profiles.first?.id
    }
    private var selected: ScreenProfile? { app.profiles.first { $0.id == selectedID } }

    var body: some View {
        HStack(spacing: 0) {
            ScreensList(app: app, selectedID: selectedID, exportMessage: exportMessage, openTest: { openWindow(id: "hardware-test") },
                        export: exportBundle)
                .frame(width: 330)
            Divider()
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    SignalMapSection(app: app, selected: selected)
                    Rectangle().fill(Tok.border).frame(height: 1)
                    if let profile = selected, let readout = app.readouts.first(where: { $0.id == profile.id }) {
                        ScreenDetail(app: app, profile: profile, readout: readout)
                    } else {
                        Text("No screens.").foregroundStyle(Tok.muted).padding(Space.s6)
                    }
                    Rectangle().fill(Tok.border).frame(height: 1)
                    AdvancedSection(app: app)
                }
            }
            .background(Tok.bg)
        }
    }

    private func exportBundle() {
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.zip]
        panel.nameFieldStringValue = HardwareTestBundle.fileName(simulated: app.showSimulatedSDIDevice)
        panel.message = "Saves the environment and the SDI devices WorshipFlow can see. No video is sent."
        guard panel.runModal() == .OK, let url = panel.url else { return }
        Task { @MainActor in
            let problem = await app.exportDiagnosticBundle(to: url)
            exportMessage = problem ?? "Saved \(url.lastPathComponent)."
        }
    }
}

// MARK: List

private struct ScreensList: View {
    let app: AppModel
    let selectedID: UUID?
    let exportMessage: String?
    let openTest: () -> Void
    let export: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                SectionLabel("Screens")
                Spacer()
                if app.screensOn {
                    Button { app.stopScreens() } label: { Text("Close screens") }.buttonStyle(HeaderButtonStyle())
                } else {
                    Button { app.startScreens() } label: { Text("Open screens") }.buttonStyle(HeaderButtonStyle())
                }
            }
            .padding(.horizontal, Space.s5).frame(height: Space.headerHeight)
            Rectangle().fill(Tok.border).frame(height: 1)
            ScrollView {
                VStack(spacing: Space.s3) {
                    ForEach(app.profiles) { profile in row(profile) }
                }
                .padding(Space.s4)
                .frame(width: 330)
            }
            .scrollBounceBehavior(.basedOnSize)
            verification
        }
        .background(Tok.surface)
    }

    private func row(_ profile: ScreenProfile) -> some View {
        let isSelected = profile.id == selectedID
        let simulated = app.readouts.first { $0.id == profile.id }.map { $0.sdi?.isSimulated == true || $0.mirrors.contains { $0.sdi?.isSimulated == true } } ?? false
        return HStack(alignment: .top, spacing: Space.s4) {
            LiveScreenPreview(app: app, screenID: profile.id).frame(width: 88)
            VStack(alignment: .leading, spacing: 3) {
                Text(profile.name).font(.system(size: 14, weight: .semibold)).lineLimit(1)
                RoleChip(role: profile.role)
                if simulated { Badge(text: "SIMULATED", style: .outline(Tok.broadcast)) }
                Text(destinationText(profile)).font(.wfCaption).foregroundStyle(Tok.muted).lineLimit(2)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            Toggle("Enabled", isOn: Binding(get: { profile.isEnabled }, set: { var p = profile; p.isEnabled = $0; app.updateProfile(p) }))
                .toggleStyle(.switch).labelsHidden().tint(Tok.cyan).fixedSize()
                .accessibilityLabel("\(profile.name) enabled")
        }
        .padding(Space.s3)
        .background(isSelected ? Tok.surface3 : .clear, in: RoundedRectangle(cornerRadius: Radius.lg))
        .overlay(RoundedRectangle(cornerRadius: Radius.lg).stroke(isSelected ? Tok.borderStrong : .clear, lineWidth: 1))
        .contentShape(Rectangle())
        .onTapGesture { app.ui.selectedScreenID = profile.id }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("\(profile.name), \(profile.role.rawValue) screen, \(destinationText(profile))")
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }

    private func destinationText(_ profile: ScreenProfile) -> String {
        let place = app.destinationName(profile.destination)
        return profile.destination.isSDI ? "\(place) · \(profile.videoMode.name)" : place
    }

    private var device: SDIDeviceInfo? {
        let profile = app.profiles.first { $0.id == selectedID }
        for d in [profile?.destination].compactMap({ $0 }) + (profile?.mirrors ?? []) {
            if case .sdi(let id, _, _, _) = d, let status = app.sdiStatuses.first(where: { $0.id == id }) { return status.info }
        }
        return app.sdiStatuses.first?.info
    }

    private var verification: some View {
        let v = ScreensPresentation.verification(for: device)
        return VStack(alignment: .leading, spacing: Space.s3) {
            HStack(spacing: 6) {
                Image(systemName: "checkmark.shield").foregroundStyle(Tok.muted)
                Text("Verification").font(.system(size: 13, weight: .semibold))
                Spacer()
                Badge(text: v.level.uppercased(), style: .outline(device?.isSimulated == true ? Tok.broadcast : Tok.muted))
            }
            Text(v.text).font(.system(size: 12)).foregroundStyle(Tok.muted).fixedSize(horizontal: false, vertical: true)
            HStack(spacing: Space.s3) {
                Button(action: openTest) { Text("Run signal test…") }.buttonStyle(HeaderButtonStyle())
                    .help("Opens the Hardware Test window")
                Button(action: export) { Text("Export log bundle…") }.buttonStyle(HeaderButtonStyle())
                    .help("Saves the environment and the SDI devices as a zip file. No video is sent.")
            }
            if let exportMessage { Text(exportMessage).font(.wfCaption).foregroundStyle(Tok.muted).fixedSize(horizontal: false, vertical: true) }
        }
        .padding(Space.s4)
        .background(Tok.surface2, in: RoundedRectangle(cornerRadius: Radius.lg))
        .overlay(RoundedRectangle(cornerRadius: Radius.lg).stroke(Tok.border, lineWidth: 1))
        .padding(Space.s4)
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Verification: \(v.level)")
    }
}

// MARK: Signal map

private struct SignalMapSection: View {
    let app: AppModel
    let selected: ScreenProfile?
    @State private var pending: SDIPreset?

    var body: some View {
        let map = app.signalMap
        VStack(alignment: .leading, spacing: Space.s4) {
            HStack(spacing: Space.s3) {
                Text("Signal map").font(.system(size: 18, weight: .bold))
                if map.isSimulated { Badge(text: "SIMULATED", style: .outline(Tok.broadcast)) }
                Spacer()
                Text("A DeckLink card sends what Desktop Video lists, not the display list.")
                    .font(.wfCaption).foregroundStyle(Tok.muted).lineLimit(1).truncationMode(.tail)
                Button { app.rescanSDI() } label: { Label("Rescan devices", systemImage: "arrow.triangle.2.circlepath") }
                    .buttonStyle(HeaderButtonStyle()).help("Look for SDI cards again")
            }
            HStack(alignment: .top, spacing: 0) {
                macTile(map)
                Rectangle().fill(Tok.borderStrong).frame(width: 28, height: 1).padding(.top, 40)
                VStack(alignment: .leading, spacing: Space.s3) {
                    ForEach(map.devices) { block in deviceBlock(block) }
                    if !map.directPaths.isEmpty { directBlock(map.directPaths) }
                    if map.devices.isEmpty && map.directPaths.isEmpty {
                        Text("Nothing is routed. Enable a screen to see its path.").font(.system(size: 12)).foregroundStyle(Tok.muted)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            presets(map)
        }
        .padding(Space.s5)
        .accessibilityElement(children: .contain)
        .accessibilityLabel(map.isSimulated ? "Signal map, simulated" : "Signal map")
    }

    private func macTile(_ map: SignalMap) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Image(systemName: "cpu").font(.system(size: 20)).foregroundStyle(Tok.muted)
            Text(map.hostTitle).font(.system(size: 14, weight: .bold)).lineLimit(2)
            Text("WorshipFlow render engine").font(.system(size: 12)).foregroundStyle(Tok.muted)
            Text(map.summary).font(.wfMonoData).foregroundStyle(Tok.muted)
        }
        .padding(Space.s4).frame(width: 190, alignment: .leading)
        .background(Tok.surface2, in: RoundedRectangle(cornerRadius: Radius.lg))
        .overlay(RoundedRectangle(cornerRadius: Radius.lg).stroke(Tok.border, lineWidth: 1))
        .accessibilityElement(children: .combine)
    }

    private func deviceBlock(_ block: SignalDeviceBlock) -> some View {
        VStack(alignment: .leading, spacing: Space.s3) {
            HStack(spacing: 6) {
                Text(block.caption).font(.system(size: 12, weight: .semibold))
                if block.isSimulated { Badge(text: "SIMULATED", style: .outline(Tok.broadcast)) }
            }
            VStack(alignment: .leading, spacing: 6) { ForEach(block.tiles) { tile in tileRow(tile) } }
            ForEach(block.routeLines, id: \.self) { Text($0).font(.wfCaption).foregroundStyle(Tok.muted) }
        }
    }

    private func directBlock(_ tiles: [SignalTile]) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Displays and windows").font(.system(size: 12, weight: .semibold))
            ForEach(tiles) { tile in tileRow(tile) }
        }
    }

    private func tileRow(_ tile: SignalTile) -> some View {
        let role = tile.screenID.flatMap { id in app.profiles.first { $0.id == id }?.role }
        let color: Color = tile.kind == .unused ? Tok.muted : (tile.kind == .fill || tile.kind == .key ? Tok.roleBroadcast : (role?.tokenColor ?? Tok.cyan))
        let isSelected = tile.screenID != nil && tile.screenID == selected?.id
        return HStack(spacing: 0) {
            HStack(spacing: Space.s3) {
                Image(systemName: Self.symbol(tile.kind)).font(.system(size: 14)).foregroundStyle(color).frame(width: 20)
                VStack(alignment: .leading, spacing: 1) {
                    HStack(spacing: 5) {
                        Text(tile.title).font(.system(size: 13, weight: .semibold)).lineLimit(1)
                        if tile.isSimulated { Badge(text: "SIMULATED", style: .outline(Tok.broadcast)) }
                    }
                    Text(tile.subtitle).font(.system(size: 12)).foregroundStyle(Tok.muted).lineLimit(1)
                    if let fault = tile.faultText {
                        Text(fault).font(.system(size: 11, weight: .medium)).foregroundStyle(Tok.warning).lineLimit(2)
                    } else if let word = tile.stateWord, word != "Running" {
                        Text(word).font(.wfCaption).foregroundStyle(Tok.muted)
                    }
                }
                Spacer(minLength: 0)
            }
            .padding(.horizontal, Space.s4).padding(.vertical, 7)
            .frame(width: 300, alignment: .leading)
            .background(Tok.surface2, in: RoundedRectangle(cornerRadius: Radius.lg))
            .overlay(RoundedRectangle(cornerRadius: Radius.lg).stroke(isSelected ? color : Tok.border, lineWidth: isSelected ? 2 : 1))
            .contentShape(Rectangle())
            .onTapGesture { if let id = tile.screenID { app.ui.selectedScreenID = id } }
            if let note = tile.connectedTo {
                Rectangle().fill(Tok.borderStrong).frame(width: 22, height: 1)
                VStack(alignment: .leading, spacing: 1) {
                    Text("Connected to").font(.system(size: 10, weight: .semibold)).foregroundStyle(Tok.muted)
                    Text(note).font(.system(size: 13, weight: .semibold)).lineLimit(1)
                }
                .padding(.horizontal, Space.s4).padding(.vertical, Space.s3)
                .background(Tok.surface2, in: RoundedRectangle(cornerRadius: Radius.lg))
                .overlay(RoundedRectangle(cornerRadius: Radius.lg).stroke(Tok.border, lineWidth: 1))
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(tile.title), \(tile.subtitle)\(tile.isSimulated ? ", simulated" : "")\(tile.faultText.map { ", \($0)" } ?? "")\(tile.connectedTo.map { ", connected to \($0)" } ?? "")")
    }

    private static func symbol(_ kind: SignalTileKind) -> String {
        switch kind {
        case .unused: "circle.dashed"
        case .output: "circle.circle"
        case .fill: "square.fill.on.square"
        case .key: "key"
        case .display: "display"
        case .window: "macwindow"
        }
    }

    // MARK: Presets

    private var device: SDIDeviceStatus? {
        let profile = selected
        for d in [profile?.destination].compactMap({ $0 }) + (profile?.mirrors ?? []) {
            if case .sdi(let id, _, _, _) = d, let status = app.sdiStatuses.first(where: { $0.id == id }) { return status }
        }
        return app.sdiStatuses.first
    }

    @ViewBuilder private func presets(_ map: SignalMap) -> some View {
        if let device {
            VStack(alignment: .leading, spacing: Space.s3) {
                HStack(spacing: Space.s3) {
                    Text("Plan for \(device.info.displayName)").font(.system(size: 12)).foregroundStyle(Tok.muted)
                    Spacer()
                    ForEach(SDIPreset.allCases, id: \.title) { preset in
                        Button { pending = (pending == preset ? nil : preset) } label: { Text(preset.title) }
                            .buttonStyle(HeaderButtonStyle(selected: pending == preset))
                            .help("Shows what \(preset.title) would change before anything changes")
                    }
                }
                if let preset = pending {
                    proposal(SDIPresets.proposal(preset, device: device, profiles: app.profiles))
                }
            }
        }
    }

    private func proposal(_ p: PresetProposal) -> some View {
        VStack(alignment: .leading, spacing: Space.s3) {
            Text(p.preset.title).font(.system(size: 13, weight: .semibold))
            Text(p.summary).font(.system(size: 12)).foregroundStyle(Tok.muted)
            ForEach(p.changes) { c in
                Text("\(c.screenName): \(c.before) → \(c.after)").font(.system(size: 12))
            }
            ForEach(p.notes, id: \.self) { Text($0).font(.system(size: 12)).foregroundStyle(Tok.warning) }
            if p.isAvailable, !p.changes.isEmpty {
                Text("Changing a card's profile can interrupt its outputs for a few seconds. WorshipFlow asks before it does that.")
                    .font(.wfCaption).foregroundStyle(Tok.muted)
            }
            HStack {
                Button { app.applyPreset(p); pending = nil } label: { Text("Apply") }
                    .buttonStyle(HeaderButtonStyle()).disabled(!p.isAvailable || p.changes.isEmpty)
                Button { pending = nil } label: { Text("Cancel") }.buttonStyle(HeaderButtonStyle())
            }
        }
        .padding(Space.s4)
        .background(Tok.surface2, in: RoundedRectangle(cornerRadius: Radius.lg))
        .overlay(RoundedRectangle(cornerRadius: Radius.lg).stroke(Tok.border, lineWidth: 1))
    }
}

// MARK: Selected screen

private struct ScreenDetail: View {
    let app: AppModel
    let profile: ScreenProfile
    let readout: ScreenReadout

    private var running: Bool { readout.state == .running || readout.state == .hidden }
    private var device: SDIDeviceSummary? {
        for d in [profile.destination] + profile.mirrors {
            if case .sdi(let id, _, _, _) = d, let device = app.sdiDevice(id: id) { return device }
        }
        return nil
    }
    private var deviceInfo: SDIDeviceInfo? {
        if case .sdi(let id, _, _, _) = profile.destination { return app.sdiStatuses.first { $0.id == id }?.info }
        return nil
    }

    var body: some View {
        VStack(alignment: .leading, spacing: Space.s5) {
            header
            HStack(alignment: .top, spacing: Space.s6) {
                leftColumn.frame(maxWidth: .infinity, alignment: .topLeading)
                rightColumn.frame(maxWidth: .infinity, alignment: .topLeading)
            }
            if let message { Text(message).font(.system(size: 12)).foregroundStyle(Tok.warning).fixedSize(horizontal: false, vertical: true) }
            ForEach(readout.renderProblems, id: \.self) { Text("Left out of this screen: \($0)").font(.system(size: 12)).foregroundStyle(Tok.warning) }
            counters
            if let captions = ScreensPresentation.keyedCaptions(destination: profile.destination, device: deviceInfo) { keyedPreviews(captions) }
        }
        .padding(Space.s5)
    }

    // MARK: Header

    private var header: some View {
        HStack(spacing: Space.s3) {
            Text(profile.name).font(.system(size: 18, weight: .bold)).lineLimit(1)
            RoleChip(role: profile.role)
            statusPill
            Spacer()
            if running {
                Button { app.stopScreen(profile.id) } label: { Text("Stop output") }.buttonStyle(HeaderButtonStyle())
            } else if profile.isEnabled {
                Button { app.restartScreen(profile.id) } label: { Text("Start output") }.buttonStyle(HeaderButtonStyle())
            }
        }
    }

    private var statusPill: some View {
        let simulated = readout.sdi?.isSimulated == true
        let (text, color): (String, Color) = switch readout.state {
        case .stopped: (profile.isEnabled ? "Stopped" : "Disabled", Tok.muted)
        case .running: (simulated ? "Running (simulated)" : "Running", Tok.statusOK)
        case .hidden: ("Hidden", Tok.warning)
        case .faulted: ("Fault", Tok.warning)
        }
        return HStack(spacing: 5) {
            Circle().fill(color).frame(width: 7, height: 7)
            Text(text).font(.system(size: 12, weight: .medium)).foregroundStyle(color)
        }
        .padding(.horizontal, 9).frame(height: 22)
        .wfOutline(Capsule(style: .circular), stroke: color)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Status: \(text)")
    }

    private var message: String? {
        switch readout.state {
        case .faulted(let m): return m
        case .hidden: return OutputCoordinator.hiddenMessage
        default: return readout.renderError.map { "Render error: \($0)" }
        }
    }

    // MARK: Settings

    private func binding<T>(_ keyPath: WritableKeyPath<ScreenProfile, T>) -> Binding<T> {
        Binding(get: { profile[keyPath: keyPath] }, set: { value in var p = profile; p[keyPath: keyPath] = value; app.updateProfile(p) })
    }

    private func field<Content: View>(_ label: String, @ViewBuilder _ content: () -> Content) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: Space.s4) {
            Text(label).font(.system(size: 12)).foregroundStyle(Tok.muted).frame(width: 96, alignment: .trailing)
            content().frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private var leftColumn: some View {
        VStack(alignment: .leading, spacing: Space.s4) {
            field("Name") { TextField("Name", text: binding(\.name)).textFieldStyle(.roundedBorder).accessibilityLabel("Name") }
            field("Role") {
                Picker("Role", selection: binding(\.role)) {
                    ForEach(ScreenRole.allCases, id: \.self) { Text($0.rawValue.capitalized).tag($0) }
                }.pickerStyle(.segmented).labelsHidden().accessibilityLabel("Role for \(profile.name)")
            }
            field("Destination") { DestinationEditor(model: app, profile: profile, mirror: nil) }
            if profile.destination.isSDI || profile.mirrors.contains(where: \.isSDI) {
                field("Video mode") { modePicker }
            }
            field("Connected to") {
                noteField(mirror: nil)
            }
        }
    }

    private func noteField(mirror: Int?) -> some View {
        TextField("Optional: what this plugs into", text: Binding(
            get: { profile.connectedNote(mirror: mirror) ?? "" },
            set: { var p = profile; p.setConnectedNote($0, mirror: mirror); app.updateProfile(p) }))
            .textFieldStyle(.roundedBorder)
            .accessibilityLabel(mirror == nil ? "Connected to, a note for \(profile.name)" : "Connected to, a note for mirror \((mirror ?? 0) + 1) of \(profile.name)")
    }

    private var modePicker: some View {
        let modes = device.map { ScreenEditing.modes(for: $0) } ?? VideoModeDescription.allKnown
        return Picker("Video mode", selection: binding(\.videoMode)) {
            ForEach(modes, id: \.self) { Text($0.name).tag($0) }
            if !modes.contains(profile.videoMode) { Text("\(profile.videoMode.name) (not supported)").tag(profile.videoMode) }
        }.labelsHidden().accessibilityLabel("Video mode for \(profile.name)")
    }

    private var rightColumn: some View {
        VStack(alignment: .leading, spacing: Space.s4) {
            if profile.role == .stage {
                field("Stage layout") {
                    if let stage = app.stage {
                        HStack {
                            Picker("Stage layout", selection: Binding(get: { stage.layoutID(forScreen: profile.id) },
                                                                      set: { stage.setLayout($0, forScreen: profile.id) })) {
                                ForEach(stage.layouts) { Text($0.name).tag($0.id) }
                            }.labelsHidden().accessibilityLabel("Stage layout for \(profile.name)")
                            Button { app.workspace?.setMode(.stage) } label: { Text("Edit layouts…") }.buttonStyle(HeaderButtonStyle())
                        }
                    }
                }
                Text("A stage screen uses a stage layout: themes, Looks and props do not apply.")
                    .font(.wfCaption).foregroundStyle(Tok.muted).padding(.leading, 112)
            } else {
                field("Look") {
                    Picker("Theme", selection: Binding(get: { app.screenLook(for: profile.id).themeID }, set: { app.setTheme($0, forScreen: profile.id) })) {
                        Text("Default for this screen").tag(UUID?.none)
                        ForEach(app.themes) { Text($0.name).tag(UUID?.some($0.id)) }
                    }.labelsHidden().accessibilityLabel("Theme in this Look for \(profile.name)")
                }
                field("Layers") {
                    HStack(spacing: Space.s4) {
                        layer("Background", .background); layer("Slide", .slide); layer("Props", .props)
                    }
                }
            }
            field("If output fails") {
                Text(ScreensPresentation.outputFailureText).font(.system(size: 12)).foregroundStyle(Tok.muted).fixedSize(horizontal: false, vertical: true)
            }
            field("Mirrors") { mirrors }
        }
    }

    private func layer(_ title: String, _ layer: LayerKind) -> some View {
        Toggle(title, isOn: Binding(get: { app.screenLook(for: profile.id).visibleLayers.contains(layer) },
                                    set: { app.setLayer(layer, visible: $0, forScreen: profile.id) })).toggleStyle(.checkbox)
    }

    private var mirrors: some View {
        VStack(alignment: .leading, spacing: Space.s3) {
            ForEach(Array(profile.mirrors.enumerated()), id: \.offset) { index, _ in
                VStack(alignment: .leading, spacing: 4) {
                    HStack {
                        Text("Mirror \(index + 1)").font(.system(size: 12, weight: .semibold))
                        Spacer()
                        Button { app.updateProfile(ScreenEditing.removingMirror(profile, at: index)) } label: { Text("Remove") }
                            .buttonStyle(HeaderButtonStyle()).accessibilityLabel("Remove mirror \(index + 1) of \(profile.name)")
                    }
                    DestinationEditor(model: app, profile: profile, mirror: index)
                    noteField(mirror: index)
                    if index < readout.mirrors.count { MirrorStatusLine(mirror: readout.mirrors[index]) }
                }
                .padding(Space.s3)
                .overlay(RoundedRectangle(cornerRadius: Radius.md).stroke(Tok.border, lineWidth: 1))
            }
            Button { app.updateProfile(ScreenEditing.addingMirror(profile)) } label: { Label("Add mirror", systemImage: "plus") }
                .buttonStyle(HeaderButtonStyle()).help("Show the same scene on one more destination")
                .accessibilityLabel("Add mirror to \(profile.name)")
        }
    }

    // MARK: Counters

    private var counters: some View {
        HStack(spacing: Space.s3) {
            counter(String(format: readout.sdi != nil ? "%.2f" : "%.0f", readout.refreshRate), readout.sdi != nil ? "frames per second" : "Hz")
            counter("\(readout.presented)", "frames presented")
            counter("\(readout.dropped)", "dropped", warn: readout.dropped > 0)
            counter("\(readout.late)", "late", warn: readout.late > 0)
            if let sdi = readout.sdi { counter("\(sdi.repeatedFrames)", "repeated", warn: sdi.repeatedFrames > 0) }
        }
        .opacity(running ? 1 : 0.5)
        .accessibilityElement(children: .contain)
    }

    private func counter(_ value: String, _ label: String, warn: Bool = false) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(value).font(.wfMonoReadout).foregroundStyle(warn ? Tok.warning : Tok.cyan)
            Text(label).font(.system(size: 12)).foregroundStyle(Tok.muted)
        }
        .padding(Space.s4).frame(maxWidth: .infinity, alignment: .leading)
        .background(Tok.surface2, in: RoundedRectangle(cornerRadius: Radius.lg))
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(value) \(label)")
    }

    // MARK: Keyed previews

    private func keyedPreviews(_ c: ScreensPresentation.KeyedCaptions) -> some View {
        let scene = app.scene(forScreen: profile.id)
        let straight: Bool = { if case .sdi(_, _, _, let a) = profile.destination { return a == .straight } else { return false } }()
        let _ = app.liveRevision
        return HStack(alignment: .top, spacing: Space.s4) {
            preview(scene, .composite, c.composite, c.compositeDetail, straight)
            preview(scene, .fill, c.fill, c.fillDetail, straight)
            preview(scene, .key, c.key, c.keyDetail, straight)
            VStack(alignment: .leading, spacing: 4) {
                Text(ScreensPresentation.blackIsNotTransparency.headline).font(.system(size: 12, weight: .semibold))
                Text(ScreensPresentation.blackIsNotTransparency.body).font(.system(size: 12)).foregroundStyle(Tok.muted)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .frame(maxWidth: .infinity, alignment: .topLeading)
        }
    }

    private func preview(_ scene: SceneDescription, _ channel: PreviewChannel, _ title: String, _ detail: String, _ straight: Bool) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            ScenePreview(scene: scene, width: 320, cached: false, frames: app.mediaFrames, keyed: true, channel: channel, straightAlpha: straight)
                .clipShape(RoundedRectangle(cornerRadius: Radius.sm))
                .overlay(RoundedRectangle(cornerRadius: Radius.sm).stroke(Tok.border, lineWidth: 1))
            HStack(spacing: 5) {
                Text(title).font(.system(size: 12, weight: .semibold))
                Text(detail).font(.system(size: 12)).foregroundStyle(Tok.muted).lineLimit(1)
            }
        }
        .frame(maxWidth: 230)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(title), \(detail)")
    }
}

// MARK: Looks, props, developer

/// Everything that worked in the old Screens panel and has no place in the design's picture stays here, below the screen.
private struct AdvancedSection: View {
    let app: AppModel

    var body: some View {
        VStack(alignment: .leading, spacing: Space.s5) {
            if !app.unavailableImages.isEmpty {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Images that cannot be read (the rest of the screen still shows):").font(.caption.bold()).foregroundStyle(Tok.warning)
                    ForEach(app.unavailableImages, id: \.self) { Text($0).font(.caption).foregroundStyle(Tok.warning).lineLimit(1).truncationMode(.middle) }
                }
            }
            if let environment = app.sdiEnvironment, environment.state == .driverNotInstalled || environment.state == .noCardFound {
                SDIEnvironmentLine(text: environment.message) { app.rescanSDI() }
            }
            if let notice = app.sdiProfileNotice {
                Text(notice).font(.caption).foregroundStyle(Tok.muted).fixedSize(horizontal: false, vertical: true)
                    .accessibilityIdentifier("sdi.profileNotice")
            }
            HStack(alignment: .top, spacing: Space.s6) {
                LookPanel(model: app).frame(maxWidth: .infinity, alignment: .topLeading)
                PropsPanel(model: app).frame(maxWidth: .infinity, alignment: .topLeading)
            }
            DeveloperSection(model: app)
        }
        .padding(Space.s5)
    }
}
