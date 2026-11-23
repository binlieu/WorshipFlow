// UI-005f: the selected screen under the signal map: its header, the two-column form, the counters and the three keyed previews, at the
// rectangles of docs/UI/mockups/03-screens-outputs.html. Rows the design draws that the app cannot back are left out and their room is kept:
// Colour (its room holds "Connected to", the label the operator types for the map), the second Pixel-format control is read-only text, the
// Notes layer (speaker notes never reach a broadcast screen), a choice for "If output fails" (what the app does is stated, not chosen),
// "Remove screen" and the schedule-lead statistic.
import SwiftUI
import Domain
import OutputEngine
import OperatorCore
import SDIEngine

struct ScreensDetail: View {
    let app: AppModel
    let profile: ScreenProfile
    let readout: ScreenReadout
    @State private var confirmRemove = false

    private var running: Bool { readout.state == .running || readout.state == .hidden }
    private var isSDI: Bool { profile.destination.isSDI }
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
        VStack(alignment: .leading, spacing: 0) {
            header
            notices
            form
            counters
            if let captions = ScreensPresentation.keyedCaptions(destination: profile.destination, device: deviceInfo) { keyedPreviews(captions) }
            // UI-007f: the Look this screen uses and the operator's own notes (key label, signal chain), below the designed area.
            ScreensNotes(app: app, profile: profile).id(profile.id)
        }
    }

    // MARK: Header

    private var header: some View {
        HStack(spacing: 8) {
            Text(profile.name).font(.wf(15, .bold)).lineLimit(1).frame(height: 16).fixedSize().wfRect("sc.detail.title", size: 15, weight: 700)
            RoleChip(role: profile.role).wfRect("sc.detail.role", size: 10, weight: 700, radius: Radius.sm)
            statusPill
            Spacer(minLength: 0)
            if running {
                Button { app.stopScreen(profile.id) } label: { Text("Stop output") }.buttonStyle(HeaderButtonStyle())
                    .wfRect("sc.detail.stop", size: 12, weight: 500, radius: Radius.md)
            } else if profile.isEnabled {
                Button { app.restartScreen(profile.id) } label: { Text("Start output") }.buttonStyle(HeaderButtonStyle())
                    .wfRect("sc.detail.stop", size: 12, weight: 500, radius: Radius.md)
            }
            // UI-006f: "Remove screen", asked first. Ghost and muted, not red: red is only for on air. The last screen cannot be removed.
            let removable = ScreenListEditing.canRemove(profile.id, from: app.profiles)
            Button { confirmRemove = true } label: { Text("Remove screen") }
                .buttonStyle(HeaderButtonStyle(kind: .ghost))
                .disabled(!removable)
                .help(removable ? "Remove this screen's settings" : "The last screen cannot be removed.")
                .accessibilityLabel("Remove screen \(profile.name)")
                .wfRect("sc.detail.remove", size: 12, weight: 500, radius: Radius.md)
                .confirmationDialog("Remove \(profile.name)?", isPresented: $confirmRemove, titleVisibility: .visible) {
                    Button("Remove screen", role: .destructive) {
                        let next = ScreenListEditing.selection(afterRemoving: profile.id, from: app.profiles)
                        app.settings?.removeProfile(profile.id)
                        app.ui.selectedScreenID = next
                    }
                    Button("Cancel", role: .cancel) {}
                } message: {
                    Text("Its output stops and its destination, mirrors and notes are forgotten. This cannot be undone. Your slides and media are not touched.")
                }
        }
        .padding(.horizontal, 14).padding(.top, 8)
        .frame(height: 34, alignment: .top)
        .wfRect("sc.detail.bar")
    }

    private var statusPill: some View {
        let simulated = readout.sdi?.isSimulated == true
        let (text, color): (String, Color) = switch readout.state {
        case .stopped: (profile.isEnabled ? "Stopped" : "Disabled", Tok.muted)
        case .running: (simulated ? "Running (simulated)" : "Running", Tok.statusOK)
        case .hidden: ("Hidden", Tok.warning)
        case .faulted: ("Fault", Tok.warning)
        }
        return PillTag(text: text, color: color, lead: .dot, rectID: "sc.detail.status")
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

    /// A fault, a hidden window or something left out of the picture is told next to the screen it belongs to (nothing is drawn when all is well).
    @ViewBuilder private var notices: some View {
        if message != nil || !readout.renderProblems.isEmpty {
            VStack(alignment: .leading, spacing: 2) {
                if let message { Text(message).font(.wf(12)).foregroundStyle(Tok.warning).fixedSize(horizontal: false, vertical: true) }
                ForEach(readout.renderProblems, id: \.self) { Text("Left out of this screen: \($0)").font(.wf(12)).foregroundStyle(Tok.warning) }
            }
            .padding(.horizontal, 14).padding(.top, 8)
        }
    }

    // MARK: Form

    private func binding<T>(_ keyPath: WritableKeyPath<ScreenProfile, T>) -> Binding<T> {
        Binding(get: { profile[keyPath: keyPath] }, set: { value in var p = profile; p[keyPath: keyPath] = value; app.updateProfile(p) })
    }

    private var form: some View {
        HStack(alignment: .top, spacing: 28) {
            leftColumn.frame(maxWidth: .infinity, alignment: .topLeading)
            rightColumn.frame(maxWidth: .infinity, alignment: .topLeading)
        }
        .padding(14)
        .wfRect("sc.form")
    }

    private var leftColumn: some View {
        VStack(alignment: .leading, spacing: 0) {
            ScreensFormRow(label: "Name", rectID: "sc.form.l0") {
                WFTextField(prompt: "Name", text: binding(\.name)).accessibilityLabel("Name")
                    .wfRect("sc.form.name", size: 12, weight: 400, radius: Radius.md)
            }
            ScreensFormRow(label: "Role", rectID: "sc.form.l1") {
                WFSegmented(items: ScreenRole.allCases.map { .init(value: $0, title: $0.rawValue.capitalized, label: $0.rawValue.capitalized) },
                            selection: binding(\.role), accessibilityName: "Role for \(profile.name)", rectID: "sc.form.role", outerPadding: 0)
                Spacer(minLength: 0)
            }
            ScreensFormRow(label: "Destination", rectID: "sc.form.l2") {
                DestinationPopup(model: app, profile: profile, mirror: nil, rectID: "sc.form.dest")
            }
            if isSDI {
                ScreensFormRow(label: "Video mode", rectID: "sc.form.l3") {
                    modePicker
                    // The design's second control is the pixel format. The renderer composes 8-bit BGRA; that is stated, not chosen.
                    ScreensReadOnlyField(text: "8-bit BGRA", help: "WorshipFlow composes 8-bit BGRA frames. The card's own conversion is not checked on hardware.",
                                         rectID: "sc.form.pixel").frame(width: 132.8)
                }
            } else { Color.clear.frame(height: 32) }
            // The design's Colour row has nothing the app can truthfully show; its room holds the label the operator types for the map.
            ScreensFormRow(label: "Connected to", rectID: "sc.form.l4") {
                WFTextField(prompt: "Optional: what this plugs into", text: noteBinding(mirror: nil))
                    .accessibilityLabel("Connected to, a note for \(profile.name)")
                    .wfRect("sc.form.note", size: 12, weight: 400, radius: Radius.md)
            }
            if isSDI {
                ScreensFormRow(label: "Audio", rectID: "sc.form.l5") {
                    ScreensReadOnlyField(text: "No embedded audio", help: "WorshipFlow sends no audio on SDI.", rectID: "sc.form.audio")
                }
            } else { Color.clear.frame(height: 32) }
        }
    }

    private func noteBinding(mirror: Int?) -> Binding<String> {
        Binding(get: { profile.connectedNote(mirror: mirror) ?? "" },
                set: { var p = profile; p.setConnectedNote($0, mirror: mirror); app.updateProfile(p) })
    }

    private var modePicker: some View {
        let modes = device.map { ScreenEditing.modes(for: $0) } ?? VideoModeDescription.allKnown
        return WFPopup(title: profile.videoMode.name + (modes.contains(profile.videoMode) ? "" : " (not supported)"),
                       accessibilityName: "Video mode for \(profile.name)", rectID: "sc.form.mode") {
            ForEach(modes, id: \.self) { mode in
                Button { var p = profile; p.videoMode = mode; app.updateProfile(p) } label: {
                    if mode == profile.videoMode { Label(mode.name, systemImage: "checkmark") } else { Text(mode.name) }
                }
            }
        }
    }

    private var keying: (on: Bool, connector: Int, alpha: SDIAlphaMode)? {
        if case .sdi(_, let connector, let keying, let alpha) = profile.destination { return (keying, connector, alpha) }
        return nil
    }

    private var rightColumn: some View {
        VStack(alignment: .leading, spacing: 0) {
            if let k = keying {
                ScreensFormRow(label: "Fill and key", rectID: "sc.form.r0") {
                    Toggle("Fill and key", isOn: Binding(get: { k.on }, set: { setKeying($0) })).toggleStyle(.wfBare).fixedSize()
                        .disabled(device?.supportsKeying == false)
                        .accessibilityLabel("Fill and key for \(profile.name)")
                        .wfRect("sc.form.keying", radius: 9)
                    Text(k.on ? ScreenEditing.keyingCaption(connector: k.connector, device: device) : "Off: one connector, no key")
                        .font(.wf(12)).foregroundStyle(Tok.muted).lineLimit(1).wfLine().frame(maxWidth: .infinity, alignment: .leading)
                        .wfRect("sc.form.keying.caption", size: 12, weight: 400)
                }
                if k.on {
                    ScreensFormRow(label: "Fill alpha", rectID: "sc.form.r1") {
                        WFSegmented(items: [.init(value: SDIAlphaMode.premultiplied, title: "Premultiplied", label: "Premultiplied"),
                                            .init(value: SDIAlphaMode.straight, title: "Straight", label: "Straight")],
                                    selection: Binding(get: { k.alpha }, set: { app.updateProfile(ScreenEditing.settingAlphaMode(profile, $0)) }),
                                    accessibilityName: "Fill alpha for \(profile.name)", rectID: "sc.form.alpha", outerPadding: 0)
                        Spacer(minLength: 0)
                    }
                } else { Color.clear.frame(height: 32) }
            } else { Color.clear.frame(height: 64) }
            if profile.role == .stage { stageRows } else { lookRows }
            ScreensFormRow(label: "If output fails", rectID: "sc.form.r4") {
                ScreensReadOnlyField(text: "Keep the show running, show a warning here", help: ScreensPresentation.outputFailureText, rectID: "sc.form.fail")
            }
            ScreensFormRow(label: "Mirror", rectID: "sc.form.r5") { mirrors }
        }
    }

    /// The per-screen setting the app has is the theme inside the current Look (Looks themselves switch every screen at once), so the row
    /// is named "Theme"; the Look list is at the bottom of this mode.
    @ViewBuilder private var lookRows: some View {
        ScreensFormRow(label: "Theme", rectID: "sc.form.r2") {
            let current = app.screenLook(for: profile.id).themeID
            let title = current.flatMap { id in app.themes.first { $0.id == id }?.name } ?? "Default for this screen"
            WFPopup(title: title, accessibilityName: "Theme in this Look for \(profile.name)", rectID: "sc.form.look") {
                Button { app.setTheme(nil, forScreen: profile.id) } label: {
                    if current == nil { Label("Default for this screen", systemImage: "checkmark") } else { Text("Default for this screen") }
                }
                ForEach(app.themes) { theme in
                    Button { app.setTheme(theme.id, forScreen: profile.id) } label: {
                        if current == theme.id { Label(theme.name, systemImage: "checkmark") } else { Text(theme.name) }
                    }
                }
            }
        }
        ScreensFormRow(label: "Layers", rectID: "sc.form.r3") {
            HStack(spacing: 8) {
                layer("Background", .background, "sc.form.layer.0"); layer("Slide", .slide, "sc.form.layer.1"); layer("Props", .props, "sc.form.layer.2")
                // The design's fourth layer is Notes: speaker notes never reach a broadcast or audience screen, so it is not built.
                Spacer(minLength: 0)
            }
        }
    }

    @ViewBuilder private var stageRows: some View {
        ScreensFormRow(label: "Stage layout", rectID: "sc.form.r2") {
            if let stage = app.stage {
                let current = stage.layoutID(forScreen: profile.id)
                WFPopup(title: stage.layouts.first { $0.id == current }?.name ?? "Standard", accessibilityName: "Stage layout for \(profile.name)", rectID: "sc.form.look") {
                    ForEach(stage.layouts) { layout in
                        Button { stage.setLayout(layout.id, forScreen: profile.id) } label: {
                            if current == layout.id { Label(layout.name, systemImage: "checkmark") } else { Text(layout.name) }
                        }
                    }
                }
            } else { Spacer(minLength: 0) }
        }
        ScreensFormRow(label: "Layers", rectID: "sc.form.r3") {
            Text("Themes, Looks and props do not apply.").font(.wf(12)).foregroundStyle(Tok.muted).lineLimit(1)
            Button { app.workspace?.setMode(.stage) } label: { Text("Edit layouts…") }.buttonStyle(HeaderButtonStyle(kind: .ghost))
            Spacer(minLength: 0)
        }
    }

    private func layer(_ title: String, _ layer: LayerKind, _ id: String) -> some View {
        Toggle(isOn: Binding(get: { app.screenLook(for: profile.id).visibleLayers.contains(layer) },
                             set: { app.setLayer(layer, visible: $0, forScreen: profile.id) })) {
            Text(title).font(.wf(13)).foregroundStyle(Tok.text).wfLine()
        }
        .toggleStyle(.wfCheckbox).fixedSize().wfRect(id)
    }

    private func setKeying(_ on: Bool) {
        guard let device else { return }
        app.updateProfile(ScreenEditing.settingKeying(profile, on: on, device: device))
    }

    private var mirrors: some View {
        VStack(alignment: .leading, spacing: Space.s3) {
            ForEach(Array(profile.mirrors.enumerated()), id: \.offset) { index, _ in
                VStack(alignment: .leading, spacing: 6) {
                    HStack {
                        Text("Mirror \(index + 1)").font(.wf(12, .semibold))
                        Spacer()
                        Button { app.updateProfile(ScreenEditing.removingMirror(profile, at: index)) } label: { Text("Remove") }
                            .buttonStyle(HeaderButtonStyle(kind: .ghost)).accessibilityLabel("Remove mirror \(index + 1) of \(profile.name)")
                    }
                    DestinationEditor(model: app, profile: profile, mirror: index)
                    WFTextField(prompt: "Optional: what this plugs into", text: noteBinding(mirror: index))
                        .accessibilityLabel("Connected to, a note for mirror \(index + 1) of \(profile.name)")
                    if index < readout.mirrors.count { MirrorStatusLine(mirror: readout.mirrors[index]) }
                }
                .padding(Space.s3)
                .wfOutline(RoundedRectangle(cornerRadius: Radius.md), stroke: Tok.border)
            }
            Button { app.updateProfile(ScreenEditing.addingMirror(profile)) } label: {
                HStack(spacing: 6) { Image(systemName: "plus").font(.wf(11)).frame(width: 12, height: 12); Text("Add mirror") }
            }
            .buttonStyle(HeaderButtonStyle()).help("Show the same scene on one more destination")
            .accessibilityLabel("Add mirror to \(profile.name)")
            .wfRect("sc.form.mirror", size: 12, weight: 500, radius: Radius.md)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    // MARK: Counters

    private static func grouped(_ n: Int) -> String {
        let digits = String(n)
        var out = "", count = 0
        for ch in digits.reversed() { if count > 0, count % 3 == 0 { out.append(" ") }; out.append(ch); count += 1 }
        return String(out.reversed())
    }

    private var counters: some View {
        HStack(spacing: 8) {
            counter("fps", String(format: readout.sdi != nil ? "%.2f" : "%.0f", readout.refreshRate), readout.sdi != nil ? "frames per second" : "Hz", tone: .neutral)
            counter("presented", Self.grouped(readout.presented), "frames presented", tone: .neutral)
            counter("dropped", "\(readout.dropped)", "dropped", tone: readout.dropped > 0 ? .warn : .ok)
            counter("late", "\(readout.late)", "late", tone: readout.late > 0 ? .warn : .ok)
            // The design's fifth statistic is the mean schedule lead, which the app does not measure: that room shows the repeated-frame
            // count of an SDI output (which it does count), and stays empty for a display.
            if let sdi = readout.sdi { counter("fifth", "\(sdi.repeatedFrames)", "repeated", tone: sdi.repeatedFrames > 0 ? .warn : .ok) }
            else { Color.clear.frame(maxWidth: .infinity) }
        }
        .padding(.horizontal, 14).padding(.bottom, 14)
        .opacity(running ? 1 : 0.5)
        .accessibilityElement(children: .contain)
        .wfRect("sc.stat")
    }

    private enum Tone { case neutral, ok, warn }

    private func counter(_ id: String, _ value: String, _ label: String, tone: Tone) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(value).font(.wfMono(17, .bold)).foregroundStyle(tone == .warn ? Tok.warning : (tone == .ok ? Tok.statusOK : Tok.text))
                .lineLimit(1).frame(height: 22, alignment: .leading).wfRect("sc.stat.\(id).value", size: 17, weight: 700)
            // The design's label is an inline box 13 pt tall, 2.3 pt below the top of its 16 pt line.
            Text(label).font(.wf(11)).foregroundStyle(Tok.muted).lineLimit(1).frame(height: 13, alignment: .topLeading)
                .wfRect("sc.stat.\(id).label", size: 11, weight: 400)
                .padding(.top, 2.3).frame(height: 16, alignment: .top)
        }
        .padding(.horizontal, 10).padding(.vertical, 8)
        .frame(maxWidth: .infinity, alignment: .topLeading).frame(height: 54.8, alignment: .top)
        .background(Tok.surface2, in: RoundedRectangle(cornerRadius: Radius.lg))
        .wfRect("sc.stat.\(id)", radius: Radius.lg)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(value) \(label)")
    }

    // MARK: Keyed previews

    private func keyedPreviews(_ c: ScreensPresentation.KeyedCaptions) -> some View {
        let scene = app.scene(forScreen: profile.id)
        let straight: Bool = { if case .sdi(_, _, _, let a) = profile.destination { return a == .straight } else { return false } }()
        let _ = app.liveRevision
        return HStack(alignment: .top, spacing: 14) {
            preview("composite", scene, .composite, c.composite, c.compositeDetail, straight, marked: false)
            preview("fill", scene, .fill, c.fill, c.fillDetail, straight, marked: true)
            preview("key", scene, .key, c.key, c.keyDetail, straight, marked: true)
            (Text(ScreensPresentation.blackIsNotTransparency.headline).fontWeight(.bold).foregroundStyle(Tok.text)
             + Text("\n" + ScreensPresentation.blackIsNotTransparency.body).foregroundStyle(Tok.muted))
                .screensLines(12, lineHeight: 17)
                .frame(maxWidth: .infinity, alignment: .topLeading)
                .wfRect("sc.prev.text", size: 12, weight: 400)
        }
        .padding(.horizontal, 14)
        .wfRect("sc.prev")
    }

    private func preview(_ id: String, _ scene: SceneDescription, _ channel: PreviewChannel, _ title: String, _ detail: String, _ straight: Bool, marked: Bool) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            ScenePreview(scene: scene, width: 320, cached: false, frames: app.mediaFrames, keyed: true, channel: channel, straightAlpha: straight)
                .frame(width: 270, height: 151.875)
                .clipShape(RoundedRectangle(cornerRadius: Radius.sm))
                .overlay { RoundedRectangle(cornerRadius: Radius.sm).inset(by: -0.5).stroke(Tok.border, lineWidth: 1) }      // `.thumb` outline, outside the box
                .wfRect("sc.prev.\(id)", radius: Radius.sm)
            HStack(spacing: 6) {
                if marked { RoundedRectangle(cornerRadius: 2).fill(Tok.roleBroadcast).frame(width: 8, height: 8).wfRect("sc.prev.\(id).sq", radius: 2) }
                Text(title).font(.wf(11, .semibold)).foregroundStyle(Tok.text).lineLimit(1).frame(height: 16).wfRect("sc.prev.\(id).title", size: 11, weight: 600)
                Text(detail).font(.wf(11)).foregroundStyle(Tok.muted).lineLimit(1)
                Spacer(minLength: 0)
            }
            .frame(height: 16)
            .wfRect("sc.prev.\(id).cap", size: 11, weight: 400)
        }
        .frame(width: 270)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(title), \(detail)")
    }
}
