// OUT-004 / PRES-05 / SLIDE-005: paste lyrics in one or two languages, choose lines per slide, see the split as you
// type, nudge a break, save. With an existing presentation it re-flows that presentation instead.
import SwiftUI
import Domain
import OperatorCore
import Persistence

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
    /// Speaker notes and objects the replacement would discard (KI-019), listed before saving.
    @State private var losses: [ReflowLoss] = []
    @State private var lossToken = 0
    /// R11: section orders (and the playlist items that play them) the replacement would shorten or empty.
    @State private var impact: [SectionOrderLoss] = []
    /// CUE-002b (KI-075): slides whose actions this re-flow would drop.
    @State private var actionLosses: [SlideActionLoss] = []

    private var isReflow: Bool { existingID != nil }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(isReflow ? "Re-flow lyrics" : "Import lyrics").font(.title2.bold())
            if isReflow {
                Text("The slides are replaced by this split. A slide whose words are unchanged, in the same section, keeps its speaker notes and objects. Sections with the same name keep their section order.")
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
            if !impact.isEmpty { impactList }
            if !losses.isEmpty { lossList }
            if !actionLosses.isEmpty { actionLossList }
            HStack {
                Spacer()
                Button("Cancel") { app.ui.showImport = false }.keyboardShortcut(.cancelAction)
                Button(isReflow ? (losses.isEmpty && impact.isEmpty && actionLosses.isEmpty ? "Replace slides" : "Replace slides and discard these") : "Save presentation") { save() }
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
        guard let id = existingID else { return }
        lossToken += 1
        let token = lossToken
        let results = plan.results
        Task {
            let found = results.isEmpty ? [] : await workspace.reflowLosses(id: id, results: results)
            let damaged = results.isEmpty ? [] : await workspace.reflowImpact(id: id, results: results)
            let dropped = results.isEmpty ? [] : await workspace.reflowSlideActionLosses(id: id, results: results)
            if token == lossToken { losses = found; impact = damaged; actionLosses = dropped }
        }
    }

    /// R11: section orders that lose sections, and playlist items that would end up showing nothing.
    private var impactList: some View {
        VStack(alignment: .leading, spacing: 3) {
            Label("These section orders will lose sections, because their names are not in the new text:",
                  systemImage: "exclamationmark.triangle.fill")
                .font(.caption.bold()).foregroundStyle(.orange)
            ScrollView {
                VStack(alignment: .leading, spacing: 2) {
                    ForEach(Array(impact.enumerated()), id: \.offset) { _, loss in
                        Text(describe(loss)).font(.caption).frame(maxWidth: .infinity, alignment: .leading)
                    }
                }
            }.frame(maxHeight: 64)
        }
        .padding(6)
        .background(Color.orange.opacity(0.12), in: RoundedRectangle(cornerRadius: 4))
        .accessibilityElement(children: .combine)
    }

    private func describe(_ loss: SectionOrderLoss) -> String {
        let lost = loss.lostSections.joined(separator: ", ")
        var text = "Section order \"\(loss.arrangementName)\" loses \(lost)."
        if loss.becomesEmpty { text += " It would be empty." }
        if !loss.playlistItemTitles.isEmpty {
            let titles = loss.playlistItemTitles.map { "\"\($0)\"" }.joined(separator: ", ")
            text += loss.becomesEmpty ? " Playlist items \(titles) would show no slides." : " Used by playlist items \(titles)."
        }
        return text
    }

    /// Notes and objects on slides whose words changed. They are gone once the slides are replaced.
    private var lossList: some View {
        VStack(alignment: .leading, spacing: 3) {
            Label("These speaker notes and objects will be discarded, because their slide's words changed or moved to another section:",
                  systemImage: "exclamationmark.triangle.fill")
                .font(.caption.bold()).foregroundStyle(.orange)
            ScrollView {
                VStack(alignment: .leading, spacing: 2) {
                    ForEach(Array(losses.enumerated()), id: \.offset) { _, loss in
                        Text(describe(loss)).font(.caption).frame(maxWidth: .infinity, alignment: .leading)
                    }
                }
            }.frame(maxHeight: 64)
        }
        .padding(6)
        .background(Color.orange.opacity(0.12), in: RoundedRectangle(cornerRadius: 4))
        .accessibilityElement(children: .combine)
    }

    /// CUE-002b (KI-075): slide actions are kept with a slide whose words did not change; the others are dropped.
    private var actionLossList: some View {
        VStack(alignment: .leading, spacing: 3) {
            Label("These slide actions will be dropped, because their slide\u{2019}s words changed or moved to another section:",
                  systemImage: "exclamationmark.triangle.fill")
                .font(.caption.bold()).foregroundStyle(.orange)
            ScrollView {
                VStack(alignment: .leading, spacing: 2) {
                    ForEach(Array(actionLosses.enumerated()), id: \.offset) { _, loss in
                        let section = loss.sectionName.map { "\($0): " } ?? ""
                        let words = loss.primary.replacingOccurrences(of: "\n", with: " ")
                        Text("\(section)\"\(words)\" had \(loss.actionCount) action\(loss.actionCount == 1 ? "" : "s")")
                            .font(.caption).frame(maxWidth: .infinity, alignment: .leading)
                    }
                }
            }.frame(maxHeight: 64)
        }
        .padding(6)
        .background(Color.orange.opacity(0.12), in: RoundedRectangle(cornerRadius: 4))
        .accessibilityElement(children: .combine)
    }

    private func describe(_ loss: ReflowLoss) -> String {
        var parts: [String] = []
        if !loss.notes.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { parts.append("note \"\(loss.notes)\"") }
        if loss.objectCount > 0 { parts.append("\(loss.objectCount) object\(loss.objectCount == 1 ? "" : "s")") }
        let section = loss.sectionName.map { "\($0): " } ?? ""
        let words = loss.primary.replacingOccurrences(of: "\n", with: " ")
        return "\(section)\"\(words)\" had \(parts.joined(separator: " and "))"
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
