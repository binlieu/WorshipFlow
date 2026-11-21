// CUE-002b (items 4 and 5): the control inputs in the Cues mode: MIDI and the remote control. Both are OFF until the operator turns
// them on here. The decisions (what a status means, what a binding is, what the server reports) are in OperatorCore.
import SwiftUI
import CueEngine
import MIDIIO
import RemoteControl
import OperatorCore

// MARK: MIDI

struct MIDISection: View {
    let app: AppModel
    let cue: CueModel

    private static let commands: [MIDICommand] = [
        .transport(.next), .transport(.previous), .transport(.clear), .transport(.clearAll), .transport(.blackout(.toggle)), .transport(.stop),
    ]

    var body: some View {
        VStack(alignment: .leading, spacing: Space.s5) {
            Text("MIDI").font(.system(size: 22, weight: .bold))
            Toggle(isOn: Binding(get: { cue.midi.isEnabled }, set: { on in Task { @MainActor in await cue.setMIDIEnabled(on) } })) {
                Text("Use MIDI").font(.system(size: 14, weight: .semibold))
            }
            .toggleStyle(.switch)
            if !cue.midi.isEnabled {
                CueNote(text: "MIDI is off: nothing is listening to any device, and WorshipFlow has no MIDI ports. Turn it on to bind pads and keys to the show.")
            } else {
                status
                devices
            }
            bindings
        }
    }

    @ViewBuilder private var status: some View {
        let s = cue.midiStatus
        VStack(alignment: .leading, spacing: 4) {
            switch s.source {
            case .none: Label("No input device chosen.", systemImage: "circle.dashed").foregroundStyle(Tok.muted)
            case .connected(let name): Label("\(name) is connected.", systemImage: "checkmark.circle.fill").foregroundStyle(Tok.statusOK)
            case .waiting(let name):
                Label("\(name ?? "The chosen device") is offline. It reconnects by itself when it returns.", systemImage: "exclamationmark.triangle.fill").foregroundStyle(Tok.warning)
            case .failed(let message): Label(message, systemImage: "exclamationmark.triangle.fill").foregroundStyle(Tok.warning)
            }
            switch s.destination {
            case .none: EmptyView()
            case .ready(let name): Label("Output \(name) is ready.", systemImage: "checkmark.circle").foregroundStyle(Tok.muted)
            case .offline(let name): Label("Output \(name ?? "device") is offline.", systemImage: "exclamationmark.triangle.fill").foregroundStyle(Tok.warning)
            }
            if let error = s.error { Text(error).foregroundStyle(Tok.warning) }
        }
        .font(.system(size: 13))
    }

    private var devices: some View {
        let s = cue.midiStatus
        return VStack(alignment: .leading, spacing: Space.s4) {
            Picker("Input device", selection: Binding(get: { cue.midi.inputID }, set: { id in
                Task { @MainActor in await cue.chooseMIDIInput(id.map { MIDIEndpointID($0) }) }
            })) {
                Text("None").tag(Int32?.none)
                ForEach(s.inputs) { Text($0.isOnline ? $0.name : "\($0.name) (offline)").tag(Int32?.some($0.id.rawValue)) }
                if let id = cue.midi.inputID, !s.inputs.contains(where: { $0.id.rawValue == id }) { Text("\(cue.midi.inputName ?? "Device") (not found)").tag(Int32?.some(id)) }
            }
            Picker("Output device", selection: Binding(get: { cue.midi.outputID }, set: { id in
                Task { @MainActor in await cue.chooseMIDIOutput(id.map { MIDIEndpointID($0) }) }
            })) {
                Text("None").tag(Int32?.none)
                ForEach(s.outputs) { Text($0.isOnline ? $0.name : "\($0.name) (offline)").tag(Int32?.some($0.id.rawValue)) }
                if let id = cue.midi.outputID, !s.outputs.contains(where: { $0.id.rawValue == id }) { Text("\(cue.midi.outputName ?? "Device") (not found)").tag(Int32?.some(id)) }
            }
            Toggle(isOn: Binding(get: { cue.midi.virtualPorts }, set: { on in Task { @MainActor in await cue.setVirtualPorts(on) } })) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Virtual ports for other programs on this Mac")
                    Text("\u{201C}\(s.virtualInputName)\u{201D} takes MIDI from them, \u{201C}\(s.virtualOutputName)\u{201D} sends MIDI to them.").font(.caption).foregroundStyle(Tok.muted)
                }
            }
            .toggleStyle(.switch)
        }
        .frame(maxWidth: 520, alignment: .leading)
    }

    private var bindings: some View {
        VStack(alignment: .leading, spacing: Space.s3) {
            HStack {
                SectionLabel("Bindings")
                Spacer()
                if cue.midiStatus.isLearning {
                    Text("Press a pad or key\u{2026}").font(.system(size: 13, weight: .semibold)).foregroundStyle(Tok.cyan)
                    Button("Cancel") { cue.cancelLearning() }.buttonStyle(HeaderButtonStyle())
                } else {
                    Button("Learn\u{2026}") { Task { @MainActor in _ = await cue.learnBinding(command: .transport(.next)) } }
                        .buttonStyle(HeaderButtonStyle()).disabled(!cue.midiStatus.isEnabled)
                        .help(cue.midiStatus.isEnabled ? "Press a pad or key; it becomes a binding for Next slide, which you can change" : "Turn MIDI on to learn a pad")
                }
            }
            if cue.bindings.bindings.isEmpty { Text("No bindings yet.").font(.system(size: 13)).foregroundStyle(Tok.muted) }
            ForEach(cue.bindings.bindings) { binding in row(binding) }
            if !cue.bindingConflicts.isEmpty {
                CueNote(text: "Two bindings use the same pad. Both would run. Change one so a pad does one thing.", systemImage: "exclamationmark.triangle")
            }
        }
    }

    private func row(_ binding: MIDIBinding) -> some View {
        let options = Self.commands + (Self.commands.contains(binding.command) ? [] : [binding.command])
        return HStack(spacing: Space.s4) {
            Text(MIDIText.pattern(binding.pattern)).font(.wfMonoData).frame(width: 150, alignment: .leading)
            Picker("Command", selection: Binding(get: { binding.command }, set: { new in
                var b = binding; b.command = new
                Task { @MainActor in await cue.saveBinding(b) }
            })) {
                Section("Show") { ForEach(options.filter { if case .transport = $0 { true } else { false } }, id: \.self) { Text(MIDIText.command($0, macros: cue.macros)).tag($0) } }
                Section("Macros") { ForEach(cue.macros) { Text($0.name).tag(MIDICommand.macro($0.id)) } }
                if case .macro(let id) = binding.command, cue.macro(id) == nil { Text("Macro \u{00B7} (deleted)").tag(binding.command) }
            }
            .labelsHidden().frame(maxWidth: 260)
            Spacer()
            if cue.conflictingBindingIDs.contains(binding.id) {
                Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(Tok.warning).help("Another binding uses the same pad").accessibilityLabel("Conflict")
            }
            Button { Task { @MainActor in await cue.deleteBinding(binding.id) } } label: { Image(systemName: "trash") }
                .buttonStyle(.plain).foregroundStyle(Tok.muted).help("Delete binding").accessibilityLabel("Delete binding \(MIDIText.pattern(binding.pattern))")
        }
        .padding(.horizontal, Space.s4).frame(minHeight: 44)
        .background(Tok.surface, in: RoundedRectangle(cornerRadius: Radius.lg))
        .overlay(RoundedRectangle(cornerRadius: Radius.lg).stroke(cue.conflictingBindingIDs.contains(binding.id) ? Tok.warning : Tok.border, lineWidth: 1))
    }
}

// MARK: Remote control

struct RemoteSection: View {
    let app: AppModel
    let cue: CueModel
    @State private var portText = ""
    @State private var revokeAll = false

    var body: some View {
        VStack(alignment: .leading, spacing: Space.s5) {
            Text("Remote control").font(.system(size: 22, weight: .bold))
            Toggle(isOn: Binding(get: { cue.remote.isEnabled }, set: { on in Task { @MainActor in await cue.setRemoteEnabled(on) } })) {
                Text("Let a phone on this network control the show").font(.system(size: 14, weight: .semibold))
            }
            .toggleStyle(.switch)
            Text("The connection is plain HTTP: anyone on the same Wi-Fi can read it and reuse a paired phone\u{2019}s access until you revoke it, so use it only on a network you trust.")
                .font(.system(size: 13)).foregroundStyle(Tok.muted).fixedSize(horizontal: false, vertical: true)
            if let error = cue.remoteStatus.error { Label(error, systemImage: "exclamationmark.triangle.fill").foregroundStyle(Tok.warning).font(.system(size: 13)) }
            HStack {
                Text("Port").font(.system(size: 13))
                TextField("8765", text: $portText).textFieldStyle(.roundedBorder).frame(width: 90)
                    .onSubmit { if let p = UInt16(portText) { Task { @MainActor in await cue.setRemotePort(p) } } else { portText = String(cue.remote.port) } }
                Text("1024 to 65535. Press Return to apply.").font(.caption).foregroundStyle(Tok.muted)
            }
            .onAppear { portText = String(cue.remote.port) }
            if cue.remoteStatus.isRunning {
                pairing
                devices
            } else if !cue.remote.isEnabled {
                CueNote(text: "Remote control is off: nothing is listening on the network.")
            }
        }
    }

    private var pairing: some View {
        VStack(alignment: .leading, spacing: Space.s3) {
            SectionLabel("Pair a phone")
            TimelineView(.periodic(from: .now, by: 1)) { context in
                let pairing = cue.remotePairing()
                VStack(alignment: .leading, spacing: 4) {
                    Text(Self.spaced(pairing?.code ?? "")).font(.system(size: 48, weight: .bold, design: .monospaced)).textSelection(.enabled)
                        .accessibilityLabel("Pairing code \(pairing?.code.map(String.init).joined(separator: " ") ?? "")")
                    if let pairing {
                        let left = max(0, Int(pairing.expiresAt.timeIntervalSince(context.date)))
                        Text("Changes in \(left / 60):\(String(format: "%02d", left % 60)), and after each pairing.").font(.system(size: 12)).foregroundStyle(Tok.muted)
                    }
                }
            }
            if cue.remoteStatus.addresses.isEmpty {
                Text("No network address was found. Connect this Mac to the same Wi-Fi or network as the phone.").font(.system(size: 13)).foregroundStyle(Tok.warning)
            } else {
                Text("On the phone, open:").font(.system(size: 13)).foregroundStyle(Tok.muted)
                ForEach(cue.remoteStatus.addresses, id: \.self) { Text($0).font(.system(size: 15, weight: .semibold, design: .monospaced)).textSelection(.enabled) }
            }
        }
    }

    private var devices: some View {
        VStack(alignment: .leading, spacing: Space.s3) {
            HStack {
                SectionLabel("Paired devices")
                Spacer()
                Button("Revoke all") { revokeAll = true }.buttonStyle(HeaderButtonStyle()).disabled(cue.remoteStatus.devices.isEmpty)
            }
            if cue.remoteStatus.devices.isEmpty { Text("No phone is paired.").font(.system(size: 13)).foregroundStyle(Tok.muted) }
            ForEach(cue.remoteStatus.devices) { device in
                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(device.label).font(.system(size: 14, weight: .semibold))
                        Text("Paired \(device.createdAt.formatted(date: .abbreviated, time: .shortened)) \u{00B7} last used \(device.lastUsed.map { $0.formatted(.relative(presentation: .named)) } ?? "never")")
                            .font(.system(size: 12)).foregroundStyle(Tok.muted)
                    }
                    Spacer()
                    Button("Revoke") { Task { @MainActor in await cue.revokeDevice(device.id) } }.buttonStyle(HeaderButtonStyle())
                        .accessibilityLabel("Revoke \(device.label)")
                }
                .padding(.horizontal, Space.s4).frame(minHeight: 48)
                .background(Tok.surface, in: RoundedRectangle(cornerRadius: Radius.lg))
                .overlay(RoundedRectangle(cornerRadius: Radius.lg).stroke(Tok.border, lineWidth: 1))
            }
        }
        .alert("Revoke every paired phone?", isPresented: $revokeAll) {
            Button("Revoke all", role: .destructive) { Task { @MainActor in await cue.revokeAllDevices() } }
            Button("Cancel", role: .cancel) {}
        } message: { Text("Each phone must be paired again with a new code.") }
    }

    private static func spaced(_ code: String) -> String {
        guard code.count == 6 else { return code }
        return "\(code.prefix(3)) \(code.suffix(3))"
    }
}
