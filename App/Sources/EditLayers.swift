// UI-007c (SLIDE): the Layers list at the bottom of the Edit inspector, drawn from docs/UI/mockups/02-editor.html (`.ly` rows of 26 pt, the chosen one
// on `surface-3`, "top first"): each object of the slide with its name, an eye to hide it (struck through when hidden), a lock, and arrows to move it
// in the stack; the slide's own words are rows above the objects that select their box. The rules live in `SlideEditorModel`
// (`UI007c_EditObjects.swift`); a row is a value, so a cell never indexes the model's list (KI-193).
import SwiftUI
import Domain
import OperatorCore

struct EditLayersSection: View {
    let app: AppModel
    @Bindable var editor: SlideEditorModel

    var body: some View {
        let rows = editor.layerRows(mediaTitle: { app.videoTitle($0) })
        EditSection(rectID: "ed.insp.layers") {
            HStack(alignment: .firstTextBaseline, spacing: 0) {
                EditHeading(text: "Layers", rectID: "ed.insp.layers.h")
                Spacer(minLength: 0)
                Text("top first").font(.wf(11)).foregroundStyle(Tok.muted).wfLine().padding(.bottom, 6)
            }
            if rows.isEmpty {
                Text("This slide has no objects. Add one with Text, Shape, Image or Video in the bar above.")
                    .font(.wf(12)).foregroundStyle(Tok.muted).fixedSize(horizontal: false, vertical: true)
            } else {
                VStack(spacing: 2) {
                    ForEach(rows) { row in EditLayerRowView(editor: editor, row: row) }
                }
                .accessibilityElement(children: .contain)
                .accessibilityLabel("Layers, top first")
            }
            if let id = editor.selectedObjectID, let row = rows.first(where: { $0.objectID == id }) {
                EditRow(label: "Name", rectID: "ed.insp.layers.name") {
                    EditNameField(value: row.customName ?? "", placeholder: row.title) { editor.setName(id, $0) }
                }
                .id(id)
                .padding(.top, 8)
            }
        }
    }
}

private struct EditLayerRowView: View {
    let editor: SlideEditorModel
    let row: EditLayerRow

    private var symbol: String {
        switch row.kind {
        case .text: "textformat"
        case .shape: "square.on.circle"
        case .image: "photo"
        case .video: "film"
        case .words: "text.alignleft"
        }
    }

    var body: some View {
        HStack(spacing: 8) {
            Button { select() } label: {
                HStack(spacing: 8) {
                    Image(systemName: symbol).font(.wf(12)).frame(width: 14, height: 14).foregroundStyle(row.isHidden ? Tok.muted : Tok.text)
                    Text(row.title).font(.wf(12)).strikethrough(row.isHidden).foregroundStyle(row.isHidden ? Tok.muted : Tok.text)
                        .lineLimit(1).truncationMode(.tail).wfLine()
                    Spacer(minLength: 0)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("\(row.title)\(row.isHidden ? ", hidden" : "")\(row.isLocked ? ", locked" : "")")
            .accessibilityHint("Selects it on the slide")
            .accessibilityAddTraits(row.isSelected ? [.isSelected] : [])
            if let id = row.objectID {
                if row.isSelected {
                    iconButton("chevron.up", label: "Move \(row.title) forward", help: "Bring forward (one step toward the front)", enabled: row.canMoveUp) { editor.moveLayer(id, up: true) }
                    iconButton("chevron.down", label: "Move \(row.title) backward", help: "Send backward (one step toward the back)", enabled: row.canMoveDown) { editor.moveLayer(id, up: false) }
                }
                iconButton(row.isHidden ? "eye.slash" : "eye", label: row.isHidden ? "Show \(row.title)" : "Hide \(row.title)",
                           help: row.isHidden ? "Show it on every screen again" : "Hide it on every screen (it stays on the slide)", enabled: true, active: row.isHidden) { editor.setHidden(id, !row.isHidden) }
                iconButton(row.isLocked ? "lock.fill" : "lock.open", label: row.isLocked ? "Unlock \(row.title)" : "Lock \(row.title)",
                           help: row.isLocked ? "Unlock it so it can be moved, resized and deleted" : "Lock it so it cannot be moved, resized or deleted from the canvas", enabled: true, active: row.isLocked) { editor.setLocked(id, !row.isLocked) }
            }
        }
        .padding(.horizontal, 6)
        .frame(height: 26)
        .background { if row.isSelected { RoundedRectangle(cornerRadius: 6).fill(Tok.surface3) } }
        .accessibilityElement(children: .contain)
    }

    private func select() {
        if let id = row.objectID { editor.select(id) } else { editor.selectLyric(row.lyricBox) }
    }

    private func iconButton(_ symbol: String, label: String, help: String, enabled: Bool, active: Bool = false, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol).font(.wf(11)).frame(width: 18, height: 18)
                .foregroundStyle(active ? Tok.text : Tok.muted).contentShape(Rectangle())
        }
        .buttonStyle(.plain).disabled(!enabled).opacity(enabled ? 1 : 0.35)
        .help(help).accessibilityLabel(label)
    }
}

/// The name field: the operator's own name for the object; empty gives the object its own title back. Commits on Return and when it loses focus.
struct EditNameField: View {
    let value: String
    let placeholder: String
    let commit: (String) -> Void
    @State private var text = ""
    @FocusState private var focused: Bool

    var body: some View {
        TextField(placeholder, text: $text).textFieldStyle(.plain).font(.wf(12)).foregroundStyle(Tok.text)
            .focused($focused)
            .onSubmit { apply() }
            .onChange(of: focused) { _, now in if !now { apply() } }
            .onAppear { text = value }
            .onChange(of: value) { _, new in if !focused { text = new } }
            .wfField()
            .accessibilityLabel("Layer name")
            .help("A name for this object in the Layers list. Leave it empty to use its own.")
    }

    private func apply() {
        guard text != value else { return }
        commit(text)
    }
}
