// UI-007f (SC-25, SC-31, SC-51): under the selected screen's previews, below the designed area (the design's rows are not moved): the Look this
// screen uses, the label for where its key goes, and the signal chain. The Look is a real setting; the key label and the chain are the OPERATOR'S
// OWN NOTES. WorshipFlow cannot see an enclosure, a converter or a switcher input, so every such line says "typed by you" and none of it is read
// from equipment or checked.
import SwiftUI
import Domain
import OperatorCore

struct ScreensNotes: View {
    let app: AppModel
    let profile: ScreenProfile

    private struct Destination: Identifiable {
        let mirror: Int?
        let destination: OutputDestination
        var id: Int { (mirror ?? -1) + 1 }
        var title: String { mirror.map { "Mirror \($0 + 1)" } ?? "Primary destination" }
    }

    private var destinations: [Destination] {
        [Destination(mirror: nil, destination: profile.destination)]
            + profile.mirrors.enumerated().map { Destination(mirror: $0.offset, destination: $0.element) }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: Space.s4) {
            lookSection
            Rectangle().fill(Tok.border).frame(height: 1)
            VStack(alignment: .leading, spacing: 2) {
                Text("Your notes on the signal path").font(.wf(13, .bold))
                Text("Typed by you. WorshipFlow cannot see an enclosure, a converter or a switcher input, so none of this is detected or checked.")
                    .font(.wf(12)).foregroundStyle(Tok.muted).fixedSize(horizontal: false, vertical: true)
            }
            ForEach(destinations) { destination in destinationNotes(destination) }
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .topLeading)
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Look and notes for \(profile.name)")
    }

    // MARK: Look

    private var lookSection: some View {
        let summary = app.settings?.screenLookSummary(for: profile.id) ?? ScreenLooks.Summary(lookName: nil, isOwn: false)
        return VStack(alignment: .leading, spacing: 6) {
            Text("Look for this screen").font(.wf(13, .bold))
            HStack(spacing: 8) {
                Text("Look").font(.wf(12)).foregroundStyle(Tok.muted).frame(width: 96, alignment: .trailing)
                WFPopup(title: summary.isOwn ? (summary.lookName ?? "No Look") : "Follow the show's Look",
                        accessibilityName: "Look for \(profile.name)") {
                    Button { app.settings?.setScreenLook(nil, forScreen: profile.id) } label: {
                        if !summary.isOwn { Label("Follow the show's Look", systemImage: "checkmark") } else { Text("Follow the show's Look") }
                    }
                    Divider()
                    ForEach(app.looks) { look in
                        Button { app.settings?.setScreenLook(look.id, forScreen: profile.id) } label: {
                            if summary.isOwn, profile.screenLookID == look.id { Label(look.name, systemImage: "checkmark") } else { Text(look.name) }
                        }
                    }
                }
                .frame(maxWidth: 280)
                Spacer(minLength: 0)
            }
            Text(profile.role == .stage
                 ? "In use: \(summary.text). A stage screen draws its own layout; a Look decides only which props sit on top of it."
                 : "In use: \(summary.text). Changing the show's Look does not change a screen that has its own. It reaches the output the same way as choosing a Look for the whole show.")
                .font(.wf(12)).foregroundStyle(Tok.muted).fixedSize(horizontal: false, vertical: true)
                .padding(.leading, 104)
                .accessibilityLabel("Look in use for \(profile.name): \(summary.text)")
        }
    }

    // MARK: One destination

    @ViewBuilder private func destinationNotes(_ d: Destination) -> some View {
        let chain = profile.signalChain(mirror: d.mirror)
        VStack(alignment: .leading, spacing: 6) {
            Text(d.title).font(.wf(12, .semibold))
            if d.destination.isKeyed {
                HStack(spacing: 8) {
                    Text("Key goes to").font(.wf(12)).foregroundStyle(Tok.muted).frame(width: 96, alignment: .trailing)
                    CommitField(prompt: "Optional: where the key goes (blank: same as the fill)", value: profile.connectedKeyNote(mirror: d.mirror) ?? "",
                                label: "Key connected to, a note for \(d.title.lowercased()) of \(profile.name)") { text in
                        var p = profile
                        p.setConnectedKeyNote(text, mirror: d.mirror)
                        app.updateProfile(p)
                    }
                    .frame(maxWidth: 420)
                    Spacer(minLength: 0)
                }
            }
            ForEach(Array(chain.enumerated()), id: \.offset) { index, node in
                HStack(spacing: 8) {
                    Text(index == 0 ? "Signal chain" : "").font(.wf(12)).foregroundStyle(Tok.muted).frame(width: 96, alignment: .trailing)
                    Text("\(index + 1)").font(.wfMono(11)).foregroundStyle(Tok.muted).frame(width: 14)
                    WFPopup(title: SignalChainEditing.kindName(node.kind), accessibilityName: "Kind of box \(index + 1), \(d.title.lowercased())") {
                        ForEach(ChainNode.Kind.allCases, id: \.self) { kind in
                            Button { change(d) { SignalChainEditing.setting(kind: kind, at: index, in: $0) } } label: {
                                if kind == node.kind { Label(SignalChainEditing.kindName(kind), systemImage: "checkmark") } else { Text(SignalChainEditing.kindName(kind)) }
                            }
                        }
                    }
                    .frame(width: 120)
                    CommitField(prompt: "What it is (your words)", value: node.label,
                                label: "Name of box \(index + 1), \(d.title.lowercased()) of \(profile.name)") { text in
                        change(d) { SignalChainEditing.setting(label: text, at: index, in: $0) }
                    }
                    .frame(maxWidth: 280)
                    Button { change(d) { SignalChainEditing.moving(index, by: -1, in: $0) } } label: { Image(systemName: "arrow.up") }
                        .buttonStyle(HeaderButtonStyle(kind: .ghost)).disabled(index == 0)
                        .accessibilityLabel("Move box \(index + 1) earlier").help("Earlier in the path (closer to the card)")
                    Button { change(d) { SignalChainEditing.moving(index, by: 1, in: $0) } } label: { Image(systemName: "arrow.down") }
                        .buttonStyle(HeaderButtonStyle(kind: .ghost)).disabled(index == chain.count - 1)
                        .accessibilityLabel("Move box \(index + 1) later").help("Later in the path (closer to the screen)")
                    Button { change(d) { SignalChainEditing.removing(at: index, from: $0) } } label: { Text("Remove") }
                        .buttonStyle(HeaderButtonStyle(kind: .ghost)).accessibilityLabel("Remove box \(index + 1) of \(d.title.lowercased())")
                    Spacer(minLength: 0)
                }
            }
            HStack(spacing: 8) {
                Text(chain.isEmpty ? "Signal chain" : "").font(.wf(12)).foregroundStyle(Tok.muted).frame(width: 96, alignment: .trailing)
                Menu {
                    ForEach(ChainNode.Kind.allCases, id: \.self) { kind in
                        Button(SignalChainEditing.kindName(kind)) { change(d) { SignalChainEditing.adding(kind, to: $0) } }
                    }
                } label: {
                    HStack(spacing: 6) { Image(systemName: "plus").font(.wf(11)); Text("Add a box") }
                }
                .menuStyle(.button).buttonStyle(HeaderButtonStyle()).fixedSize()
                .disabled(!SignalChainEditing.canAdd(to: chain))
                .help(SignalChainEditing.canAdd(to: chain) ? "Add an enclosure, converter or other box to your note, in the order the signal passes through them"
                                                            : "A chain keeps at most \(SignalChainEditing.maxLength) boxes.")
                .accessibilityLabel("Add a box to the signal chain of \(d.title.lowercased()) of \(profile.name)")
                if chain.isEmpty { Text("None typed.").font(.wf(12)).foregroundStyle(Tok.muted) }
                Spacer(minLength: 0)
            }
        }
        .padding(Space.s3)
        .frame(maxWidth: .infinity, alignment: .leading)
        .wfOutline(RoundedRectangle(cornerRadius: Radius.md), stroke: Tok.border)
    }

    private func change(_ d: Destination, _ edit: ([ChainNode]) -> [ChainNode]) {
        var p = profile
        p.setSignalChain(edit(p.signalChain(mirror: d.mirror)), mirror: d.mirror)
        app.updateProfile(p)
    }
}

/// A text field that keeps what is typed in a draft and commits it when the operator presses Return, leaves the field, or (FIX-Y, REVIEW-5 L14) the
/// field goes away with focus still in it (another screen was clicked in the list): the commit closure belongs to the screen the field was made for, so
/// the note is written to that screen. Nothing is written on every keystroke, so the outputs are not re-planned while typing.
private struct CommitField: View {
    let prompt: String
    let value: String
    let label: String
    let commit: (String) -> Void
    @State private var draft = ""
    @State private var written: String?
    @FocusState private var focused: Bool

    var body: some View {
        WFTextField(prompt: prompt, text: $draft)
            .focused($focused)
            .accessibilityLabel(label)
            .onAppear { draft = value }
            .onChange(of: value) { _, new in written = nil; if !focused { draft = new } }
            .onSubmit { flush() }
            .onChange(of: focused) { _, now in if !now { flush() } }
            .onDisappear { flush() }
    }

    private func flush() {
        guard let text = NoteDraft.pending(draft: draft, value: value, written: written) else { return }
        written = text
        commit(text)
    }
}
