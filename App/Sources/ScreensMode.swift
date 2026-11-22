// UI-002 Part 2 / ADR-0007 / UI-005f: the Screens mode, drawn to docs/UI/screens/03-screens-outputs.png (and 11 for light). A screens list
// on the left (299 pt, the design's width); on the right the signal map, the selected screen's settings, its counters and the keyed
// previews. The map is drawn from `SignalMapPresenter` (OutputEngine); this file and its neighbours decide nothing, they draw.
// What the design draws and the app cannot back is left out and its room kept (see AI/reports/UI-005f-report.md).
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
                .padding(.trailing, 1)          // the column's 1 pt border is outside its 299 pt of content, as in ui.css
                .frame(width: 300)
                .wfRect("sc.side")
                .overlay(alignment: .trailing) { Rectangle().fill(Tok.border).frame(width: 1) }
            GeometryReader { geo in
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    ScreensSignalMap(app: app, selected: selected)
                    Rectangle().fill(Tok.border).frame(height: 1)
                    if let profile = selected, let readout = app.readouts.first(where: { $0.id == profile.id }) {
                        ScreensDetail(app: app, profile: profile, readout: readout)
                    } else {
                        Text("No screens.").foregroundStyle(Tok.muted).padding(Space.s6)
                    }
                    ScreensExtras(app: app, selected: selected)
                }
                .frame(width: geo.size.width, alignment: .topLeading)
            }
            .scrollIndicators(.hidden)
            }      // a legacy scroller would take 15 pt of the designed 1140; the content scrolls by wheel, trackpad and keys
            .background(Tok.bg)
            .wfRect("sc.main")
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
            // UI-006f: "Add screen" at the right of this row (a new screen is off and in a window). Open and close screens is the toolbar's button.
            HStack(spacing: 0) {
                SectionLabel("Screens", rectID: "sc.list.title")
                Spacer(minLength: 0)
                Button {
                    if let added = app.settings?.addProfile() { app.ui.selectedScreenID = added.id }
                } label: {
                    HStack(spacing: 4) { Image(systemName: "plus").font(.wf(11, .semibold)); Text("Add screen") }
                }
                .buttonStyle(HeaderButtonStyle())
                .disabled(app.settings == nil)
                .help("Add a screen. It starts off, in a window, until you choose where it goes and turn it on.")
                .accessibilityLabel("Add screen")
                .wfRect("sc.list.add", size: 12, weight: 500, radius: Radius.md)
            }
            .padding(.horizontal, 12).frame(height: 42)
            VStack(spacing: 0) {
                Rectangle().fill(Tok.border).frame(height: 1)
                ScrollView {
                    VStack(spacing: 4) {
                        ForEach(Array(app.profiles.enumerated()), id: \.element.id) { index, profile in row(profile, index: index) }
                    }
                    .padding(.horizontal, 12).padding(.top, 10)
                }
                .scrollBounceBehavior(.basedOnSize)
                verification
            }
            .wfRect("sc.list.body")
        }
        .background(Tok.surface)
    }

    private func row(_ profile: ScreenProfile, index: Int) -> some View {
        let isSelected = profile.id == selectedID
        let id = "sc.row.\(index)"
        let readout = app.readouts.first { $0.id == profile.id }
        let simulated = readout.map { $0.sdi?.isSimulated == true || $0.mirrors.contains { $0.sdi?.isSimulated == true } } ?? false
        return HStack(spacing: 10) {
            LiveScreenPreview(app: app, screenID: profile.id, cornerRadius: Radius.sm)
                .frame(width: 96, height: 54)
                .overlay(alignment: .topLeading) { if simulated { SimulatedTag().padding(5) } }
                .overlay { RoundedRectangle(cornerRadius: Radius.sm).inset(by: -0.5).stroke(Tok.border, lineWidth: 1) }      // `.thumb` outline, outside the box
                .wfRect("\(id).thumb", radius: Radius.sm)
            VStack(alignment: .leading, spacing: 0) {
                HStack(spacing: 8) {
                    Text(profile.name).screensLines(13, .bold).lineLimit(2).fixedSize(horizontal: false, vertical: true)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .wfRect("\(id).name", size: 13, weight: 700)
                    Toggle("Enabled", isOn: Binding(get: { profile.isEnabled }, set: { var p = profile; p.isEnabled = $0; app.updateProfile(p) }))
                        .toggleStyle(.wfBare).fixedSize()
                        .accessibilityLabel("\(profile.name) enabled")
                        .wfRect("\(id).toggle", radius: 9)
                }
                HStack(spacing: 0) {
                    Badge(text: profile.role.rawValue.uppercased(), style: .outline(profile.role.tokenColor), rectID: "\(id).role")
                    Spacer(minLength: 0)
                }
                .padding(.top, 3)
                Text(destinationText(profile)).foregroundStyle(Tok.muted).screensLines(11).lineLimit(2)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .wfRect("\(id).dest", size: 11, weight: 400)
                    .padding(.top, 3)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(10)
        .background(isSelected ? Tok.surface3 : .clear, in: RoundedRectangle(cornerRadius: Radius.lg))
        .wfRect(id, radius: Radius.lg)
        .contentShape(Rectangle())
        .onTapGesture { app.ui.selectedScreenID = profile.id }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("\(profile.name), \(profile.role.rawValue) screen, \(app.destinationName(profile.destination))\(simulated ? ", simulated" : "")")
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }

    /// `SDI 3 · 1080p59.94`, `SDI 1 + 2 · Fill + Key`; a display or window is named as the destination picker names it.
    private func destinationText(_ profile: ScreenProfile) -> String {
        guard case .sdi(let deviceID, let connector, let keying, _) = profile.destination else { return app.destinationName(profile.destination) }
        let card = app.sdiDevices.count > 1 ? (app.sdiDevice(id: deviceID)?.name).map { "\($0) · " } ?? "" : ""
        return keying ? "\(card)SDI \(connector) + \(connector + 1) · Fill + Key" : "\(card)SDI \(connector) · \(profile.videoMode.name)"
    }

    private var device: SDIDeviceInfo? {
        let profile = app.profiles.first { $0.id == selectedID }
        for d in [profile?.destination].compactMap({ $0 }) + (profile?.mirrors ?? []) {
            if case .sdi(let id, _, _, _) = d, let status = app.sdiStatuses.first(where: { $0.id == id }) { return status.info }
        }
        return app.sdiStatuses.first?.info
    }

    /// `.card` with 10 pt padding: the warning icon and "Verification", the text with "Hardware Verified" in the text colour, two buttons.
    private var verification: some View {
        let v = ScreensPresentation.verification(for: device)
        return VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 8) {
                Image(systemName: "exclamationmark.triangle").font(.wf(13)).frame(width: 15, height: 15).accessibilityHidden(true)
                    .wfRect("sc.verify.icon")
                Text("Verification").font(.wf(12, .bold)).wfLine().wfRect("sc.verify.title", size: 12, weight: 700)
                Spacer(minLength: 0)
            }
            .frame(height: 16)
            .overlay(alignment: .trailing) { if device?.isSimulated == true { Badge(text: "SIMULATED", style: .outline(Tok.roleBroadcast)) } }
            VStack(alignment: .leading, spacing: 4) {
                emphasised(v.text).screensLines(12).fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .wfRect("sc.verify.text", size: 12, weight: 400)
                if let exportMessage { Text(exportMessage).font(.wf(11)).foregroundStyle(Tok.muted).fixedSize(horizontal: false, vertical: true) }
            }
            .padding(.top, 4)
            HStack(spacing: 8) {
                Button(action: openTest) { Text("Run signal test…") }.buttonStyle(HeaderButtonStyle()).fixedSize()
                    .help("Opens the Hardware Test window").wfRect("sc.verify.run", size: 12, weight: 500, radius: Radius.md)
                Button(action: export) { Text("Export log bundle") }.buttonStyle(HeaderButtonStyle(kind: .ghost)).fixedSize()
                    .help("Saves the environment and the SDI devices as a zip file. No video is sent.")
                    .accessibilityLabel("Export log bundle")
                    .wfRect("sc.verify.export", size: 12, weight: 500, radius: Radius.md)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.top, 8)
        }
        .padding(11)
        .wfOutline(RoundedRectangle(cornerRadius: Radius.xl), stroke: Tok.border, fill: Tok.surface)
        .wfRect("sc.verify", radius: Radius.xl)
        .padding(.horizontal, 12).padding(.bottom, 10)
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Verification: \(v.level)")
    }

    /// "Hardware Verified" is set in the text colour and bold, as the design has it; the rest is muted.
    private func emphasised(_ text: String) -> Text {
        let key = "Hardware Verified"
        guard let range = text.range(of: key) else { return Text(text).foregroundStyle(Tok.muted) }
        return Text(String(text[..<range.lowerBound])).foregroundStyle(Tok.muted)
            + Text(key).fontWeight(.bold).foregroundStyle(Tok.text)
            + Text(String(text[range.upperBound...])).foregroundStyle(Tok.muted)
    }
}

/// The small pill that says a picture comes from a simulated device (never a real one).
struct SimulatedTag: View {
    var body: some View {
        Text("SIMULATED").font(.wf(8, .heavy)).tracking(0.5).foregroundStyle(Tok.roleBroadcast).padding(.horizontal, 4).padding(.vertical, 1)
            .background(Tok.bg.opacity(0.85), in: RoundedRectangle(cornerRadius: Radius.xs))
            .overlay(RoundedRectangle(cornerRadius: Radius.xs).strokeBorder(Tok.roleBroadcast, lineWidth: 1))
            .fixedSize()
            .accessibilityHidden(true)
    }
}

// MARK: Below the designed area

/// Everything that works and has no place in the design's picture stays reachable here, under the previews: image and card warnings,
/// the card's fill and key route as it reports it, the preset proposal, then the Look list, Props and Developer (the Show inspector
/// shows the Looks and props too; Developer moves to Settings in a later slice).
private struct ScreensExtras: View {
    let app: AppModel
    let selected: ScreenProfile?

    var body: some View {
        VStack(alignment: .leading, spacing: Space.s5) {
            if !app.unavailableImages.isEmpty {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Images that cannot be read (the rest of the screen still shows):").font(.wf(10, .bold)).foregroundStyle(Tok.warning)
                    ForEach(app.unavailableImages, id: \.self) { Text($0).font(.wfSmall).foregroundStyle(Tok.warning).lineLimit(1).truncationMode(.middle) }
                }
            }
            if let environment = app.sdiEnvironment, environment.state == .driverNotInstalled || environment.state == .noCardFound {
                SDIEnvironmentLine(text: environment.message) { app.rescanSDI() }
            }
            if let notice = app.sdiProfileNotice {
                Text(notice).font(.wfSmall).foregroundStyle(Tok.muted).fixedSize(horizontal: false, vertical: true)
                    .accessibilityIdentifier("sdi.profileNotice")
            }
            let routes = app.signalMap.devices.flatMap { block in block.routeLines.map { (block.name, $0) } }
            if !routes.isEmpty {
                VStack(alignment: .leading, spacing: 2) {
                    ForEach(Array(routes.enumerated()), id: \.offset) { _, line in
                        Text("\(line.0): \(line.1)").font(.wf(11)).foregroundStyle(Tok.muted)
                    }
                }
                .accessibilityElement(children: .combine)
                .accessibilityLabel("Fill and key route as the card reports it")
            }
            HStack(alignment: .top, spacing: Space.s6) {
                LookPanel(model: app).frame(maxWidth: .infinity, alignment: .topLeading)
                PropsPanel(model: app).frame(maxWidth: .infinity, alignment: .topLeading)
            }
            DeveloperSection(model: app)
        }
        .padding(.horizontal, 14).padding(.bottom, 14)
        .padding(.top, 38)      // the designed area ends 24 pt above the window's foot; these start below the fold, one scroll away
    }
}
