// OUT-004 / PRES-05 / SLIDE-005: paste lyrics in one or two languages, choose lines per slide, see the split as you
// type, nudge a break, save. With an existing presentation it re-flows that presentation instead.
import SwiftUI
import Domain
import OperatorCore

struct ImportSheet: View {
    let app: AppModel
    let workspace: WorkspaceModel
    let existingID: UUID?

    @State private var title = ""
    @State private var primary = ""
    @State private var secondary = ""
    @State private var linesPerSlide = 2
    @State private var plan = ImportPlan(primary: "", secondary: nil, maxLines: 2)
    @State private var saving = false

    private var isReflow: Bool { existingID != nil }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(isReflow ? "Re-flow lyrics" : "Import lyrics").font(.title2.bold())
            if isReflow {
                Text("The slides are replaced by this split. Speaker notes on the old slides are not kept; sections with the same name keep their section order.")
                    .font(.caption).foregroundStyle(.secondary)
            } else {
                TextField("Title", text: $title).textFieldStyle(.roundedBorder)
            }
            HStack(spacing: 12) {
                editor("First language", text: $primary)
                editor("Second language (optional)", text: $secondary)
            }
            .frame(minHeight: 170, maxHeight: 220)
            HStack {
                Stepper("Lines per slide: \(linesPerSlide)", value: $linesPerSlide, in: 1...8)
                Spacer()
                Text("\(plan.slides.count) slide\(plan.slides.count == 1 ? "" : "s")").foregroundStyle(.secondary)
            }
            Text("Start a section with a label line such as Verse 1 or Chorus. Leave a blank line between sections.")
                .font(.caption).foregroundStyle(.secondary)
            preview
            HStack {
                Spacer()
                Button("Cancel") { app.ui.showImport = false }.keyboardShortcut(.cancelAction)
                Button(isReflow ? "Replace slides" : "Save presentation") { save() }
                    .keyboardShortcut(.defaultAction)
                    .disabled(saving || plan.slides.isEmpty || (!isReflow && title.trimmingCharacters(in: .whitespaces).isEmpty))
            }
        }
        .padding(18)
        .frame(width: 940, height: 700)
        .task {
            if let id = existingID {
                let text = await workspace.lyricsText(of: id)
                primary = text.primary
                secondary = text.secondary
            }
            rebuild()
        }
        .onChange(of: primary) { _, _ in rebuild() }
        .onChange(of: secondary) { _, _ in rebuild() }
        .onChange(of: linesPerSlide) { _, _ in rebuild() }
    }

    private func editor(_ label: String, text: Binding<String>) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(label).font(.caption).foregroundStyle(.secondary)
            TextEditor(text: text).font(.body)
                .overlay(RoundedRectangle(cornerRadius: 4).stroke(.quaternary))
                .accessibilityLabel(label)
        }
    }

    private func rebuild() {
        plan = ImportPlan(primary: primary, secondary: secondary, maxLines: linesPerSlide)
    }

    /// The resulting slides, with their section names and a pair of buttons to move the break after each one.
    private var preview: some View {
        let results = plan.results
        return List {
            ForEach(Array(results.enumerated()), id: \.offset) { i, result in
                VStack(alignment: .leading, spacing: 3) {
                    if let name = result.sectionName, i == 0 || plan.sectionName(ofSlide: i - 1) != name {
                        Text(name).font(.caption.bold()).foregroundStyle(.blue)
                    }
                    HStack(alignment: .top) {
                        Text("\(i + 1)").font(.caption.monospacedDigit()).frame(width: 24, alignment: .trailing).foregroundStyle(.secondary)
                        VStack(alignment: .leading, spacing: 1) {
                            Text(result.content.primary)
                            if let s = result.content.secondary { Text(s).foregroundStyle(.secondary) }
                        }
                        Spacer()
                        if plan.canMoveBreak(after: i) {
                            Button { plan.moveBreak(after: i, by: -1) } label: { Image(systemName: "arrow.up") }
                                .help("Move the break after this slide up one line")
                                .accessibilityLabel("Move break after slide \(i + 1) up")
                            Button { plan.moveBreak(after: i, by: 1) } label: { Image(systemName: "arrow.down") }
                                .help("Move the break after this slide down one line")
                                .accessibilityLabel("Move break after slide \(i + 1) down")
                        }
                    }
                }
            }
        }
        .overlay { if results.isEmpty { Text("The slides appear here as you type.").foregroundStyle(.secondary) } }
        .frame(minHeight: 200)
    }

    private func save() {
        saving = true
        let results = plan.results
        Task {
            if let id = existingID {
                if await workspace.reflowPresentation(id: id, results: results) { app.ui.showImport = false }
            } else if let p = await workspace.importLyrics(title: title, results: results) {
                await workspace.openPresentation(p.id)
                app.ui.showImport = false
            }
            saving = false
        }
    }
}
