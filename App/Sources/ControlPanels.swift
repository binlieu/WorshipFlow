// OUT-002 / OUT-003: screens panel, Looks and props. Moved into the workspace's right-hand column (OUT-004).
import SwiftUI
import Domain
import OutputEngine
import OperatorCore
import SDIEngine

struct ScreensPanel: View {
    @Bindable var model: AppModel

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("Screens").font(.headline)
                Spacer()
                if model.screensOn {
                    Button("Close screens") { model.stopScreens() }
                } else {
                    Button("Open screens") { model.startScreens() }
                }
            }
            if !model.unavailableImages.isEmpty {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Images that cannot be read (the rest of the screen still shows):").font(.caption.bold()).foregroundStyle(.orange)
                    ForEach(model.unavailableImages, id: \.self) { path in
                        Text(path).font(.caption).foregroundStyle(.orange).lineLimit(1).truncationMode(.middle)
                    }
                }
            }
            if let environment = model.sdiEnvironment, environment.state == .driverNotInstalled || environment.state == .noCardFound {
                SDIEnvironmentLine(text: environment.message) { model.rescanSDI() }
            }
            if let notice = model.sdiProfileNotice {
                Text(notice).font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                    .accessibilityIdentifier("sdi.profileNotice")
            }
            ForEach(model.sdiDevices) { device in
                ConnectorMapView(device: device, rows: model.connectorRows[device.id] ?? [])
            }
            ForEach(model.readouts) { readout in
                if let profile = model.profiles.first(where: { $0.id == readout.id }) {
                    ScreenRow(model: model, profile: profile, readout: readout)
                    Divider()
                }
            }
            DeveloperSection(model: model)
        }
    }
}

/// HW-004: one calm line when there is no Blackmagic driver or no card. Never an error dialog: everything else works.
struct SDIEnvironmentLine: View {
    let text: String
    let rescan: () -> Void

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Image(systemName: "info.circle").foregroundStyle(.secondary)
            Text(text).font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 4)
            Button("Rescan", action: rescan).controlSize(.small)
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("sdi.environmentLine")
    }
}

/// HW-002: what each connector of an SDI card carries, so nothing about the wiring is a guess.
struct ConnectorMapView: View {
    let device: SDIDeviceSummary
    let rows: [ConnectorRow]

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            HStack(spacing: 6) {
                Text("SDI connectors").font(.subheadline.bold())
                Text(device.label).font(.caption).foregroundStyle(.secondary)
                if device.isSimulated { Text("Simulated").font(.caption.bold()).padding(.horizontal, 5).padding(.vertical, 1)
                    .background(Capsule().fill(Color.purple.opacity(0.25))) }
            }
            if !device.isConnected {
                Text("This SDI card is not connected.").font(.caption).foregroundStyle(Tok.warning)
            }
            ForEach(rows) { row in
                HStack(spacing: 6) {
                    Image(systemName: symbol(row.kind)).foregroundStyle(color(row.kind)).frame(width: 16)
                    Text(row.text).font(.system(.caption, design: .monospaced))
                }
            }
        }
        .padding(8)
        .background(RoundedRectangle(cornerRadius: 6).fill(Color.primary.opacity(0.05)))
        .accessibilityElement(children: .contain)
        .accessibilityLabel("SDI connector map, \(device.label)")
    }

    private func symbol(_ kind: ConnectorRow.Kind) -> String {
        switch kind {
        case .unused: "circle.dashed"
        case .output: "arrow.up.right.circle.fill"
        case .fill: "square.fill"
        case .key: "key.fill"
        }
    }

    private func color(_ kind: ConnectorRow.Kind) -> Color {
        switch kind {
        case .unused: .secondary
        case .output: .green
        case .fill: .blue
        case .key: .orange
        }
    }
}

/// HW-002: developer settings. The simulated card is off by default, so a real operator never sees a fake device.
struct DeveloperSection: View {
    @Bindable var model: AppModel

    var body: some View {
        DisclosureGroup("Developer") {
            VStack(alignment: .leading, spacing: 6) {
                Toggle("Show simulated SDI device", isOn: Binding(get: { model.showSimulatedSDIDevice },
                                                                    set: { model.setShowSimulatedSDIDevice($0) }))
                    .toggleStyle(.wfCheckbox)
                    .accessibilityIdentifier("developer.showSimulatedSDI")
                Text("Adds a simulated four-connector SDI card (no real hardware) to the destinations below.")
                    .font(.caption).foregroundStyle(.secondary)
                if model.showSimulatedSDIDevice {
                    HStack {
                        Button("Simulate unplug") { model.simulateSDIUnplug() }
                        Button("Simulate replug") { model.simulateSDIReplug() }
                    }
                }
            }.padding(.top, 4)
        }
        .accessibilityIdentifier("developer.section")
    }
}

struct ScreenRow: View {
    let model: AppModel
    let profile: ScreenProfile
    let readout: ScreenReadout

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Toggle("Enabled", isOn: binding(\.isEnabled)).toggleStyle(.wfCheckbox)
                TextField("Name", text: binding(\.name)).textFieldStyle(.roundedBorder).frame(maxWidth: 180)
                Picker("Role", selection: binding(\.role)) {
                    ForEach(ScreenRole.allCases, id: \.self) { Text($0.rawValue.capitalized).tag($0) }
                }.frame(maxWidth: 190)
            }
            DestinationEditor(model: model, profile: profile, mirror: nil)
            if profile.destination.isSDI || profile.mirrors.contains(where: \.isSDI) {
                modePicker
            }
            if profile.role != .stage {
                Picker("Theme", selection: themeBinding) {
                    Text("Default for this screen").tag(UUID?.none)
                    ForEach(model.themes) { Text($0.name).tag(UUID?.some($0.id)) }
                }.frame(maxWidth: 320)
                HStack {
                    Text("Layers").font(.caption).foregroundStyle(.secondary)
                    layerToggle("Background", .background)
                    layerToggle("Slide", .slide)
                    layerToggle("Props", .props)
                }
            } else if let stage = model.stage {
                HStack {
                    Picker("Stage layout", selection: Binding(get: { stage.layoutID(forScreen: profile.id) },
                                                              set: { stage.setLayout($0, forScreen: profile.id) })) {
                        ForEach(stage.layouts) { Text($0.name).tag($0.id) }
                    }.frame(maxWidth: 320).accessibilityLabel("Stage layout for \(profile.name)")
                    Button("Edit layouts…") { model.workspace?.setMode(.stage) }
                }
                Text("The stage screen uses a stage layout: themes, Looks and props do not apply.")
                    .font(.caption).foregroundStyle(.secondary)
            } else {
                Text("The stage screen uses its own layout: themes, Looks and props do not apply.")
                    .font(.caption).foregroundStyle(.secondary)
            }
            HStack {
                Text(statusText).font(.subheadline.bold()).foregroundStyle(statusColor)
                Spacer()
                if isRunning {
                    Button("Stop") { model.stopScreen(profile.id) }
                } else if profile.isEnabled {
                    Button("Start") { model.restartScreen(profile.id) }
                }
            }
            if !readout.renderProblems.isEmpty {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Left out of this screen:").font(.caption.bold()).foregroundStyle(.orange)
                    ForEach(readout.renderProblems, id: \.self) { problem in
                        Text(problem).font(.caption).foregroundStyle(.orange).fixedSize(horizontal: false, vertical: true)
                    }
                }
            }
            if let message {
                Text(message).font(.caption).foregroundStyle(statusColor).fixedSize(horizontal: false, vertical: true)
            }
            if isRunning {
                Text(counters).font(.system(.caption, design: .monospaced)).foregroundStyle(readout.state == .hidden ? .secondary : .primary)
            }
            if let sdi = readout.sdi { SDIStatusLines(report: sdi, running: isRunning) }
            mirrorsSection
        }
    }

    private var modePicker: some View {
        let device = sdiDeviceInUse
        let modes = device.map { ScreenEditing.modes(for: $0) } ?? VideoModeDescription.allKnown
        return Picker("Video mode", selection: binding(\.videoMode)) {
            ForEach(modes, id: \.self) { Text($0.name).tag($0) }
            if !modes.contains(profile.videoMode) { Text("\(profile.videoMode.name) (not supported)").tag(profile.videoMode) }
        }
        .frame(maxWidth: 320)
        .accessibilityLabel("Video mode for \(profile.name)")
    }

    private var sdiDeviceInUse: SDIDeviceSummary? {
        for d in [profile.destination] + profile.mirrors {
            if case .sdi(let id, _, _, _) = d, let device = model.sdiDevice(id: id) { return device }
        }
        return nil
    }

    /// OUT-005: extra destinations that show the same scene, each with its own status line.
    private var mirrorsSection: some View {
        VStack(alignment: .leading, spacing: 6) {
            ForEach(Array(profile.mirrors.enumerated()), id: \.offset) { index, _ in
                VStack(alignment: .leading, spacing: 3) {
                    HStack {
                        Text("Mirror \(index + 1)").font(.caption.bold())
                        DestinationEditor(model: model, profile: profile, mirror: index)
                        Button("Remove") { model.updateProfile(ScreenEditing.removingMirror(profile, at: index)) }
                            .accessibilityLabel("Remove mirror \(index + 1) of \(profile.name)")
                    }
                    if index < readout.mirrors.count { MirrorStatusLine(mirror: readout.mirrors[index]) }
                }
                .padding(.leading, 12)
            }
            Button("Add mirror") { model.updateProfile(ScreenEditing.addingMirror(profile)) }
                .accessibilityLabel("Add mirror to \(profile.name)")
                .help("Show the same scene on one more destination")
        }
    }

    private var themeBinding: Binding<UUID?> {
        Binding(get: { model.screenLook(for: profile.id).themeID },
                set: { model.setTheme($0, forScreen: profile.id) })
    }

    private func layerToggle(_ title: String, _ layer: LayerKind) -> some View {
        Toggle(title, isOn: Binding(get: { model.screenLook(for: profile.id).visibleLayers.contains(layer) },
                                    set: { model.setLayer(layer, visible: $0, forScreen: profile.id) }))
            .toggleStyle(.wfCheckbox)
    }

    private var isRunning: Bool { readout.state == .running || readout.state == .hidden }

    private func binding<T>(_ keyPath: WritableKeyPath<ScreenProfile, T>) -> Binding<T> {
        Binding(get: { profile[keyPath: keyPath] },
                set: { value in
                    var p = profile
                    p[keyPath: keyPath] = value
                    model.updateProfile(p)
                })
    }

    private var statusText: String {
        switch readout.state {
        case .stopped: profile.isEnabled ? "Stopped" : "Disabled"
        case .running: readout.sdi?.isSimulated == true ? "Running (Simulated)" : "Running"
        case .hidden: "Hidden"
        case .faulted: "Fault"
        }
    }

    private var statusColor: Color {
        switch readout.state {
        case .stopped: .secondary
        case .running: .green
        case .hidden: .orange
        case .faulted: Tok.warning
        }
    }

    private var message: String? {
        var parts: [String] = []
        switch readout.state {
        case .faulted(let m): parts.append(m)
        case .hidden: parts.append(OutputCoordinator.hiddenMessage)
        default: break
        }
        if let e = readout.renderError { parts.append("Render error: \(e)") }
        return parts.isEmpty ? nil : parts.joined(separator: " ")
    }

    private var counters: String {
        if readout.state == .hidden {
            return "hidden   (paused at: presented \(readout.presented)  dropped \(readout.dropped)  late \(readout.late))"
        }
        if readout.sdi != nil {
            return String(format: "%.2f fps   presented %d   dropped %d   late %d", readout.refreshRate, readout.presented,
                          readout.dropped, readout.late)
        }
        return String(format: "%.0f Hz   presented %d   dropped %d   late %d   max interval %.1f ms",
                      readout.refreshRate, readout.presented, readout.dropped, readout.late, readout.maxIntervalMs)
    }
}

/// HW-002: health, repeated frames and warnings of an SDI output.
struct SDIStatusLines: View {
    let report: SDIOutputReport
    let running: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack(spacing: 6) {
                Text(report.isSimulated ? "SDI output, Simulated" : "SDI output").font(.caption.bold())
                Text(report.modeName).font(.caption)
                if running {
                    Text("health \(healthText)").font(.caption.bold()).foregroundStyle(healthColor)
                    Text("frames repeated \(report.repeatedFrames)").font(.caption)
                }
            }
            ForEach(report.warnings, id: \.self) { warning in
                Text(warning).font(.caption).foregroundStyle(.orange).fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private var healthText: String {
        switch report.health { case .ok: "OK"; case .degraded: "degraded"; case .failing: "failing" }
    }
    private var healthColor: Color {
        switch report.health { case .ok: .green; case .degraded: .orange; case .failing: Tok.warning }
    }
}

/// OUT-005: the status of one mirror.
struct MirrorStatusLine: View {
    let mirror: MirrorReadout

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(statusText).font(.caption.bold()).foregroundStyle(color)
            if case .faulted(let message) = mirror.state {
                Text(message).font(.caption).foregroundStyle(Tok.warning).fixedSize(horizontal: false, vertical: true)
            }
            if mirror.state == .running || mirror.state == .hidden {
                Text(String(format: "presented %d   dropped %d   late %d", mirror.presented, mirror.dropped, mirror.late))
                    .font(.system(.caption, design: .monospaced))
            }
            if let sdi = mirror.sdi { SDIStatusLines(report: sdi, running: mirror.state == .running) }
        }
    }

    private var statusText: String {
        switch mirror.state {
        case .stopped: "Mirror \(mirror.index + 1): stopped"
        case .running: mirror.sdi?.isSimulated == true ? "Mirror \(mirror.index + 1): running (Simulated)" : "Mirror \(mirror.index + 1): running"
        case .hidden: "Mirror \(mirror.index + 1): hidden"
        case .faulted: "Mirror \(mirror.index + 1): fault"
        }
    }

    private var color: Color {
        switch mirror.state { case .stopped: .secondary; case .running: .green; case .hidden: .orange; case .faulted: Tok.warning }
    }
}

/// The destination picker for a screen (`mirror == nil`) or one of its mirrors, with the SDI keying and alpha controls
/// when the destination is SDI. A choice goes through `ScreenEditing`, so keying, alpha and mode stay valid.
struct DestinationEditor: View {
    let model: AppModel
    let profile: ScreenProfile
    let mirror: Int?

    private var destination: OutputDestination {
        if let mirror, profile.mirrors.indices.contains(mirror) { return profile.mirrors[mirror] }
        return profile.destination
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Picker(mirror == nil ? "Destination" : "Mirror destination", selection: Binding(get: { destination }, set: { choose($0) })) {
                ForEach(model.displayChoices) { Text($0.name).tag(OutputDestination.display($0.id)) }
                Text("Window").tag(OutputDestination.window)
                ForEach(model.sdiDevices) { device in
                    ForEach(ScreenEditing.connectorChoices(device: device, keying: destination.isKeyed), id: \.self) { connector in
                        Text(sdiOptionLabel(device, connector)).tag(sdiValue(device, connector))
                    }
                }
                if !options.contains(destination) {
                    Text(model.destinationName(destination)).tag(destination)
                }
            }
            .labelsHidden()
            .accessibilityLabel("\(mirror == nil ? "Destination" : "Mirror destination") for \(profile.name)")
            if case .sdi(let deviceID, let connector, let keying, let alpha) = destination {
                let device = model.sdiDevice(id: deviceID)
                HStack(spacing: 10) {
                    Toggle("Fill and key", isOn: Binding(get: { keying }, set: { setKeying($0) }))
                        .toggleStyle(.wfCheckbox)
                        .disabled(device?.supportsKeying == false)
                        .accessibilityLabel("Fill and key for \(profile.name)")
                    if keying {
                        Text(ScreenEditing.keyingCaption(connector: connector, device: device)).font(.caption).foregroundStyle(.secondary)
                    }
                }
                if keying {
                    Picker("Fill alpha", selection: Binding(get: { alpha }, set: { setAlpha($0) })) {
                        Text("Premultiplied").tag(SDIAlphaMode.premultiplied)
                        Text("Straight").tag(SDIAlphaMode.straight)
                    }
                    .pickerStyle(.segmented).frame(maxWidth: 300)
                    .accessibilityLabel("Fill alpha for \(profile.name)")
                }
            }
        }
    }

    private var options: [OutputDestination] {
        var all: [OutputDestination] = model.displayChoices.map { .display($0.id) } + [.window]
        for device in model.sdiDevices {
            for c in ScreenEditing.connectorChoices(device: device, keying: destination.isKeyed) { all.append(sdiValue(device, c)) }
        }
        return all
    }

    private func sdiValue(_ device: SDIDeviceSummary, _ connector: Int) -> OutputDestination {
        var keying = false
        var alpha = SDIAlphaMode.premultiplied
        if case .sdi(_, _, let k, let a) = destination { keying = k; alpha = a }
        return .sdi(deviceID: device.id, connector: connector, keying: keying && device.supportsKeying, fillAlphaMode: alpha)
    }

    private func sdiOptionLabel(_ device: SDIDeviceSummary, _ connector: Int) -> String {
        let simulated = device.isSimulated ? " (Simulated)" : ""
        let base = device.isSimulated && device.name.localizedCaseInsensitiveContains("simulated") ? device.name : device.name + simulated
        return destination.isKeyed ? "\(base), connectors \(connector) and \(connector + 1)" : "\(base), connector \(connector)"
    }

    private func choose(_ new: OutputDestination) {
        if case .sdi(let id, let connector, _, _) = new, mirror == nil, let device = model.sdiDevice(id: id) {
            model.updateProfile(ScreenEditing.choosingSDI(profile, device: device, connector: connector))
        } else if let mirror {
            model.updateProfile(ScreenEditing.settingMirror(profile, at: mirror, to: new))
        } else {
            var p = profile
            p.destination = new
            model.updateProfile(p)
        }
    }

    private func setKeying(_ on: Bool) {
        guard case .sdi(let id, _, _, _) = destination, let device = model.sdiDevice(id: id) else { return }
        if let mirror {
            model.updateProfile(ScreenEditing.settingMirrorKeying(profile, at: mirror, on: on, device: device))
        } else {
            model.updateProfile(ScreenEditing.settingKeying(profile, on: on, device: device))
        }
    }

    private func setAlpha(_ mode: SDIAlphaMode) {
        if let mirror {
            model.updateProfile(ScreenEditing.settingMirrorAlphaMode(profile, at: mirror, mode))
        } else {
            model.updateProfile(ScreenEditing.settingAlphaMode(profile, mode))
        }
    }
}

/// OUT-003: choose, create, rename and delete Looks. A Look applies to every screen at once.
struct LookPanel: View {
    @Bindable var model: AppModel
    @State private var name = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Look").font(.headline)
            HStack {
                Picker("Look", selection: Binding(get: { model.selectedLookID ?? UUID() }, set: { model.selectLook($0) })) {
                    ForEach(model.looks) { Text($0.name).tag($0.id) }
                }.frame(maxWidth: 260)
                Button("New") { model.addLook() }.help("Copy the current Look into a new one")
                Button("Delete") { if let id = model.selectedLookID { model.deleteLook(id) } }
                    .disabled(model.looks.count < 2).help("Delete the selected Look")
            }
            TextField("Rename Look", text: Binding(get: { model.currentLook?.name ?? "" },
                                                    set: { if let id = model.selectedLookID { model.renameLook(id, to: $0) } }))
                .textFieldStyle(.roundedBorder).frame(maxWidth: 260)
            Text("A Look sets the theme and visible layers of each screen below. Switching Look changes every screen at once.")
                .font(.caption).foregroundStyle(.secondary)
        }
    }
}

/// OUT-003: props are images (for example a logo) that stay above the slide across slide changes and Clear.
struct PropsPanel: View {
    @Bindable var model: AppModel

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("Props").font(.headline)
                Spacer()
                Button("Add image…") { model.chooseProp() }
            }
            if model.props.isEmpty {
                Text("No props. Add a logo image to keep it on screen above the slides.")
                    .font(.caption).foregroundStyle(.secondary)
            }
            ForEach(model.props) { prop in
                HStack {
                    Toggle(prop.name, isOn: Binding(get: { prop.isOn }, set: { model.setProp(prop.id, isOn: $0) }))
                        .toggleStyle(.wf)
                    Spacer()
                    if model.unavailableImages.contains(prop.imagePath) {
                        Text("File not readable").font(.caption).foregroundStyle(.orange)
                    }
                    Button("Remove") { model.removeProp(prop.id) }
                }
            }
        }
    }
}
