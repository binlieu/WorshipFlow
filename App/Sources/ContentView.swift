// OUT-002: operator window. Errors and faults are shown here, never as an alert or sheet on an output window (NFR-08).
import SwiftUI
import Domain
import OutputEngine

struct ContentView: View {
    @Bindable var model: AppModel

    var body: some View {
        HSplitView {
            slideList
                .frame(minWidth: 280, idealWidth: 340)
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    showControls
                    Divider()
                    LookPanel(model: model)
                    Divider()
                    PropsPanel(model: model)
                    Divider()
                    ScreensPanel(model: model)
                    if !model.messages.isEmpty {
                        Divider()
                        ForEach(Array(model.messages.enumerated()), id: \.offset) { _, m in
                            Text(m).font(.caption).foregroundStyle(.orange)
                        }
                    }
                }
                .padding(16)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .frame(minWidth: 460)
        }
        .frame(minWidth: 800, minHeight: 520)
    }

    private var slideList: some View {
        List {
            ForEach(Array(model.slides.enumerated()), id: \.offset) { index, slide in
                HStack(alignment: .top, spacing: 8) {
                    Image(systemName: "circle.fill")
                        .font(.caption2)
                        .foregroundStyle(liveMarkerColor(index))
                        .opacity(model.liveIndex == index ? 1 : 0)
                        .accessibilityHidden(true)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(slide.primary).font(.headline)
                        if let s = slide.secondary { Text(s).font(.subheadline).foregroundStyle(.secondary) }
                    }
                }
                .padding(.vertical, 3)
                .frame(maxWidth: .infinity, alignment: .leading)
                .contentShape(Rectangle())
                .background(index == model.selectedIndex ? Color.accentColor.opacity(0.25) : Color.clear)
                .onTapGesture { model.select(index) }
                .accessibilityElement(children: .combine)
                .accessibilityValue(accessibilityValue(index))
                .accessibilityAddTraits(index == model.selectedIndex ? .isSelected : [])
            }
        }
    }

    private func liveMarkerColor(_ index: Int) -> Color { model.mode == .cleared ? .orange : .red }

    private func accessibilityValue(_ index: Int) -> String {
        guard model.liveIndex == index else { return "" }
        return model.mode == .cleared ? "live place, cleared" : "live"
    }

    private var showControls: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text(modeText).font(.title2.bold()).foregroundStyle(modeColor)
                Spacer()
                Text("Selecting a slide only changes the preview.").font(.caption).foregroundStyle(.secondary)
            }
            HStack {
                Button("Go Live") { model.goLive() }.help("Return: take the selected slide live")
                Button("Previous") { model.previous() }.help("Left arrow")
                Button("Next") { model.next() }.help("Right arrow or Space")
                Button("Clear") { model.clear() }.disabled(model.mode == .stopped).help("Escape: hide the slide on every screen")
                Button("Stop") { model.stopShow() }.disabled(model.mode == .stopped).help("Empty every screen")
            }
            Text("Return: go live    Space / Right: next    Left: previous    Escape: clear")
                .font(.caption).foregroundStyle(.secondary)
            HStack {
                Button("Choose background video…") { model.chooseVideo() }
                Text(model.videoURL?.lastPathComponent ?? "No video: solid background")
                    .font(.caption).foregroundStyle(.secondary).lineLimit(1).truncationMode(.middle)
                if model.videoURL != nil { Button("Remove") { model.setVideo(nil) } }
            }
        }
    }

    private var modeText: String {
        switch model.mode { case .stopped: "STOPPED"; case .live: "LIVE"; case .cleared: "CLEARED" }
    }
    private var modeColor: Color {
        switch model.mode { case .stopped: .secondary; case .live: .red; case .cleared: .orange }
    }
}

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
            ForEach(model.readouts) { readout in
                if let profile = model.profiles.first(where: { $0.id == readout.id }) {
                    ScreenRow(model: model, profile: profile, readout: readout)
                    Divider()
                }
            }
        }
    }
}

struct ScreenRow: View {
    let model: AppModel
    let profile: ScreenProfile
    let readout: ScreenReadout

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Toggle("Enabled", isOn: binding(\.isEnabled)).toggleStyle(.checkbox)
                TextField("Name", text: binding(\.name)).textFieldStyle(.roundedBorder).frame(maxWidth: 180)
                Picker("Role", selection: binding(\.role)) {
                    ForEach(ScreenRole.allCases, id: \.self) { Text($0.rawValue.capitalized).tag($0) }
                }.frame(maxWidth: 190)
            }
            Picker("Destination", selection: binding(\.destination)) {
                ForEach(model.displayChoices) { Text($0.name).tag(OutputDestination.display($0.id)) }
                Text("Window").tag(OutputDestination.window)
                if case .display(let id) = profile.destination, !model.displayChoices.contains(where: { $0.id == id }) {
                    Text("Display \(id) (not connected)").tag(profile.destination)
                }
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
            if let message {
                Text(message).font(.caption).foregroundStyle(statusColor).fixedSize(horizontal: false, vertical: true)
            }
            if isRunning {
                Text(counters).font(.system(.caption, design: .monospaced)).foregroundStyle(readout.state == .hidden ? .secondary : .primary)
            }
        }
    }

    private var themeBinding: Binding<UUID?> {
        Binding(get: { model.screenLook(for: profile.id).themeID },
                set: { model.setTheme($0, forScreen: profile.id) })
    }

    private func layerToggle(_ title: String, _ layer: LayerKind) -> some View {
        Toggle(title, isOn: Binding(get: { model.screenLook(for: profile.id).visibleLayers.contains(layer) },
                                    set: { model.setLayer(layer, visible: $0, forScreen: profile.id) }))
            .toggleStyle(.checkbox)
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
        case .running: "Running"
        case .hidden: "Hidden"
        case .faulted: "Fault"
        }
    }

    private var statusColor: Color {
        switch readout.state {
        case .stopped: .secondary
        case .running: .green
        case .hidden: .orange
        case .faulted: .red
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
        return String(format: "%.0f Hz   presented %d   dropped %d   late %d   max interval %.1f ms",
                      readout.refreshRate, readout.presented, readout.dropped, readout.late, readout.maxIntervalMs)
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
                Picker("Look", selection: Binding(get: { model.selectedLookID }, set: { model.selectLook($0) })) {
                    ForEach(model.looks) { Text($0.name).tag($0.id) }
                }.frame(maxWidth: 260)
                Button("New") { model.addLook() }.help("Copy the current Look into a new one")
                Button("Delete") { model.deleteLook(model.selectedLookID) }
                    .disabled(model.looks.count < 2).help("Delete the selected Look")
            }
            TextField("Rename Look", text: Binding(get: { model.currentLook?.name ?? "" },
                                                    set: { model.renameLook(model.selectedLookID, to: $0) }))
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
                        .toggleStyle(.switch)
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
