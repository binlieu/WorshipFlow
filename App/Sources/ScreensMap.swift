// UI-005f: the signal map, drawn as docs/UI/mockups/03-screens-outputs.html draws it: the Mac node, a 2 pt wire, one tile per connector with
// its role colour, a 2 pt wire and the destination node. What the design draws that the app cannot know is NOT drawn and its room is
// kept: the Thunderbolt enclosure node and the SDI-to-HDMI converter nodes. Since UI-007f the operator can type a chain of such boxes (v15
// `signalChains`); each is drawn between the connector and the destination, marked "typed by you". The destination node is the label the operator
// typed in "Connected to" (the key connector has its own). Nothing here is detected from the equipment.
import SwiftUI
import Domain
import OutputEngine
import OperatorCore
import SDIEngine

struct ScreensSignalMap: View {
    let app: AppModel
    let selected: ScreenProfile?
    @State private var pending: SDIPreset?

    private static let chainBoxesShown = 3      // UI-007f: the map row has room for three typed boxes; the settings list the rest
    private let wireLength: CGFloat = 28 + 150 + 28      // the design's wire, enclosure column, wire; and the same at the converter column

    var body: some View {
        let map = app.signalMap
        VStack(alignment: .leading, spacing: 0) {
            bar(map)
            mapGrid(map)
            footer(map)
            if let preset = pending, let device {
                proposal(SDIPresets.proposal(preset, device: device, profiles: app.profiles)).padding(.horizontal, 14).padding(.bottom, 10)
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel(map.isSimulated ? "Signal map, simulated" : "Signal map")
    }

    // MARK: Header bar

    private func bar(_ map: SignalMap) -> some View {
        HStack(spacing: 8) {
            Text("Signal map").font(.wf(17, .bold)).frame(height: 22).wfRect("sc.map.title", size: 17, weight: 700)
            if map.isSimulated { Badge(text: "SIMULATED", style: .outline(Tok.roleBroadcast), rectID: "sc.map.badge") }
            Spacer(minLength: 0)
            Text("DeckLink channels come from Desktop Video, not from the display list.")
                .font(.wf(12)).foregroundStyle(Tok.muted).lineLimit(1).wfLine().wfRect("sc.map.note", size: 12, weight: 400)
            Button { app.rescanSDI() } label: {
                HStack(spacing: 6) {
                    Image(systemName: "arrow.triangle.2.circlepath").frame(width: 15, height: 15).wfRect("sc.map.rescan.icon")
                    Text("Rescan devices")
                }
            }
            .buttonStyle(HeaderButtonStyle()).help("Look for SDI cards again")
            .wfRect("sc.map.rescan", size: 12, weight: 500, radius: Radius.md)
            // UI-006f: labels every connected display for three seconds; offered only while the screens are closed.
            let identifyAllowed = ScreenIdentify.isAllowed(screensOpen: app.screensOn)
            Button {
                ScreensIdentifier.shared.show(profiles: app.profiles, operatorDisplay: ScreensIdentifier.operatorDisplayID())
            } label: { Text("Identify screens") }
            .buttonStyle(HeaderButtonStyle())
            .disabled(!identifyAllowed)
            .help(identifyAllowed ? "Show each display's screen name for three seconds. SDI outputs have no display to label." : ScreenIdentify.blockedReason)
            .accessibilityLabel("Identify screens")
            .accessibilityHint(identifyAllowed ? "Shows a label on every connected display for three seconds" : ScreenIdentify.blockedReason)
            .wfRect("sc.map.identify", size: 12, weight: 500, radius: Radius.md)
        }
        .padding(.horizontal, 14).padding(.vertical, 8)
        .frame(height: 43, alignment: .top)
        .overlay(alignment: .bottom) { Rectangle().fill(Tok.border).frame(height: 1) }
        .wfRect("sc.map.bar")
    }

    // MARK: Rows

    private struct Row: Identifiable {
        enum Content { case caption(String), tile(SignalTile) }
        let id: String
        let content: Content
    }

    private func rows(_ map: SignalMap) -> [Row] {
        var out: [Row] = []
        for block in map.devices {
            if map.devices.count > 1 { out.append(Row(id: "cap-\(block.id)", content: .caption(block.caption))) }
            out += block.tiles.map { Row(id: $0.id, content: .tile($0)) }
        }
        out += map.directPaths.map { Row(id: $0.id, content: .tile($0)) }
        return out
    }

    private func mapGrid(_ map: SignalMap) -> some View {
        let all = rows(map)
        return HStack(spacing: 0) {
            macNode(map).frame(width: 150)
            if all.isEmpty { Color.clear.frame(width: wireLength, height: 1) } else { wire.frame(width: wireLength) }
            if all.isEmpty {
                Text("Nothing is routed. Enable a screen to see its path.").font(.wf(12)).foregroundStyle(Tok.muted)
                    .frame(maxWidth: .infinity, alignment: .leading)
            } else {
                VStack(spacing: 8) {
                    ForEach(all) { row in
                        switch row.content {
                        case .caption(let text): Text(text).font(.wf(12)).foregroundStyle(Tok.muted).frame(maxWidth: .infinity, alignment: .leading).wfLine()
                        case .tile(let tile): tileRow(tile)
                        }
                    }
                }
            }
        }
        .padding(14)
        .wfRect("sc.map.grid")
    }

    private var wire: some View { Rectangle().fill(Tok.borderStrong).frame(height: 2) }

    private func macNode(_ map: SignalMap) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            Image(systemName: "cpu").font(.wf(18)).frame(width: 20, height: 20).foregroundStyle(Tok.text).accessibilityHidden(true)
                .wfRect("sc.map.mac.icon").frame(height: 27, alignment: .top)
            Text(map.hostTitle).screensLines(12, .bold, lineHeight: 15).frame(maxWidth: .infinity, alignment: .leading)
                .wfRect("sc.map.mac.title", size: 12, weight: 700)
            Text("WorshipFlow render engine").foregroundStyle(Tok.muted).screensLines(11, lineHeight: 15).frame(maxWidth: .infinity, alignment: .leading)
                .wfRect("sc.map.mac.sub", size: 11, weight: 400)
            Text(map.summary).foregroundStyle(Tok.muted).screensLines(11, lineHeight: 15, mono: true).frame(maxWidth: .infinity, alignment: .leading)
                .wfRect("sc.map.mac.mono", size: 11, weight: 400).padding(.top, 4)
        }
        .modifier(ScreensNodeChrome())
        .wfRect("sc.map.mac", radius: Radius.lg)
        .accessibilityElement(children: .combine)
    }

    // MARK: One connector

    private struct TileFace {
        var title: String
        var sub: String
        var color: Color
        var icon: String?
        var ring: Bool
    }

    private func face(_ tile: SignalTile) -> TileFace {
        let profile = tile.screenID.flatMap { id in app.profiles.first { $0.id == id } }
        let roleColor = profile?.role.tokenColor ?? Tok.cyan
        switch tile.kind {
        case .unused:
            return TileFace(title: tile.title, sub: tile.subtitle, color: Tok.muted, icon: nil, ring: true)
        case .output:
            let prefix = tile.title.components(separatedBy: " · ").first ?? tile.title
            let role = profile.map { $0.role.rawValue.capitalized } ?? ""
            return TileFace(title: "\(prefix) · \(tile.subtitle)", sub: role, color: roleColor, icon: profile.map { Self.roleSymbol($0.role) }, ring: true)
        case .fill:
            let name = tile.subtitle.components(separatedBy: " · paired with").first ?? tile.subtitle
            return TileFace(title: tile.title, sub: name, color: Tok.roleBroadcast, icon: "square.2.layers.3d", ring: true)
        case .key:
            let pair = tile.subtitle.range(of: "paired with").map { String(tile.subtitle[$0.lowerBound...]) } ?? tile.subtitle
            return TileFace(title: tile.title, sub: pair, color: Tok.roleBroadcast, icon: "key", ring: true)
        case .display:
            return TileFace(title: tile.title, sub: tile.subtitle, color: roleColor, icon: "display", ring: false)
        case .window:
            return TileFace(title: tile.title, sub: tile.subtitle, color: roleColor, icon: "macwindow", ring: false)
        }
    }

    private static func roleSymbol(_ role: ScreenRole) -> String {
        switch role { case .audience: "display"; case .stage: "music.mic"; case .broadcast: "square.2.layers.3d" }
    }

    private func tileRow(_ tile: SignalTile) -> some View {
        let f = face(tile)
        let key = tile.connector.map(String.init) ?? "d\(tile.id.suffix(6))"
        return HStack(spacing: 0) {
            HStack(spacing: 8) {
                if f.ring { ScreensBNC(color: f.color).wfRect("sc.map.conn.\(key).bnc") }
                else { Image(systemName: f.icon ?? "display").font(.wf(13)).foregroundStyle(f.color).frame(width: 20, height: 20) }
                VStack(alignment: .leading, spacing: 0) {
                    // The design's title is an inline box 14.1 pt tall, 0.9 pt below the top of its 16 pt line.
                    Text(f.title).font(.wf(12, .bold)).foregroundStyle(Tok.text).lineLimit(1).frame(height: 14.1, alignment: .topLeading)
                        .wfRect("sc.map.conn.\(key).title", size: 12, weight: 700)
                        .padding(.top, 0.9).frame(height: 16, alignment: .top)
                    Text(tile.faultText ?? f.sub).font(.wf(11)).foregroundStyle(tile.faultText == nil ? Tok.muted : Tok.warning).lineLimit(1)
                        .frame(height: 16, alignment: .leading)
                        .wfRect("sc.map.conn.\(key).sub", size: 11, weight: 400)
                }
                Spacer(minLength: 0)
                if tile.isSimulated { Badge(text: "SIMULATED", style: .outline(Tok.roleBroadcast)) }
                if f.ring, let icon = f.icon {
                    Image(systemName: icon).font(.wf(13)).foregroundStyle(f.color).frame(width: 15, height: 15).accessibilityHidden(true)
                        .wfRect("sc.map.conn.\(key).icon")
                }
            }
            .padding(.horizontal, 11)
            .frame(maxWidth: .infinity).frame(height: 46)
            .background(Tok.surface2, in: RoundedRectangle(cornerRadius: Radius.lg))
            .overlay(RoundedRectangle(cornerRadius: Radius.lg).strokeBorder(f.color, lineWidth: 1.5))
            .wfRect("sc.map.conn.\(key)", radius: Radius.lg)
            .contentShape(Rectangle())
            .onTapGesture { if let id = tile.screenID { app.ui.selectedScreenID = id } }
            // UI-007f: the boxes the operator typed between this connector and where it goes, each marked "typed by you"; none when none was typed.
            ForEach(Array(tile.chain.prefix(Self.chainBoxesShown).enumerated()), id: \.offset) { index, node in
                Rectangle().fill(Tok.borderStrong).frame(width: 14, height: 2)
                ScreensChainBox(node: node, rectID: "sc.map.chain.\(key).\(index)").frame(width: 130)
            }
            if tile.chain.count > Self.chainBoxesShown {
                Text("+\(tile.chain.count - Self.chainBoxesShown) more").font(.wf(11)).foregroundStyle(Tok.muted).lineLimit(1).fixedSize()
                    .padding(.leading, 6).help("The rest of the chain is listed under this screen's settings.")
            }
            if let note = tile.connectedTo, !note.isEmpty {
                wire.frame(width: wireLength)
                ScreensTypedNode(text: note, rectID: "sc.map.dest.\(key)").frame(width: 170)
            } else {
                Color.clear.frame(width: wireLength + 170, height: 1)
            }
        }
        .frame(height: 48)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(f.title), \(tile.faultText ?? f.sub)\(tile.isSimulated ? ", simulated" : "")\(tile.chain.isEmpty ? "" : ", through " + tile.chain.map { SignalChainEditing.title($0) }.joined(separator: ", then ") + ", typed by you")\(tile.connectedTo.map { ", connected to \($0), typed by you" } ?? "")")
    }

    // MARK: Footer and presets

    private var device: SDIDeviceStatus? {
        let profile = selected
        for d in [profile?.destination].compactMap({ $0 }) + (profile?.mirrors ?? []) {
            if case .sdi(let id, _, _, _) = d, let status = app.sdiStatuses.first(where: { $0.id == id }) { return status }
        }
        return app.sdiStatuses.first
    }

    private var current: SDIPreset {
        let onCard = app.profiles.contains { $0.isEnabled && $0.destination.isKeyed }
        return onCard ? .fillKeyBroadcast : .independent
    }

    private func footer(_ map: SignalMap) -> some View {
        let text: String = {
            if map.devices.isEmpty { return "No SDI card is in use. Displays and windows are drawn by the same engine." }
            return map.devices.map { b in
                if !b.isConnected { return b.caption }
                return b.name.localizedCaseInsensitiveContains("connector") ? b.name : "\(b.name) · \(b.tiles.count) SDI connectors"
            }.joined(separator: " · ")
        }()
        return HStack(spacing: 8) {
            Text(text).font(.wf(12)).foregroundStyle(Tok.muted).lineLimit(1).wfLine().wfRect("sc.map.foot.text", size: 12, weight: 400)
            Spacer(minLength: 0)
            if device != nil {
                WFSegmented(items: SDIPreset.allCases.map { .init(value: $0, title: $0 == .independent ? "4 independent outputs" : "Fill + Key broadcast", label: $0.title) },
                            selection: Binding(get: { pending ?? current }, set: { new in pending = (new == current ? nil : new) }),
                            accessibilityName: "Plan for the card", rectID: "sc.map.preset", outerPadding: 0)
                    .help("Shows what the plan would change before anything changes")
            }
        }
        .padding(.horizontal, 14).padding(.bottom, 10)
        .frame(minHeight: 40)
        .wfRect("sc.map.foot")
    }

    private func proposal(_ p: PresetProposal) -> some View {
        VStack(alignment: .leading, spacing: Space.s3) {
            Text(p.preset.title).font(.wf(13, .semibold))
            Text(p.summary).font(.wf(12)).foregroundStyle(Tok.muted)
            ForEach(p.changes) { c in
                Text("\(c.screenName): \(c.before) → \(c.after)").font(.wf(12))
            }
            ForEach(p.notes, id: \.self) { Text($0).font(.wf(12)).foregroundStyle(Tok.warning) }
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
        .wfOutline(RoundedRectangle(cornerRadius: Radius.lg), stroke: Tok.border, fill: Tok.surface2)
    }
}
