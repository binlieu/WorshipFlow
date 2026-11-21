// LIB-004c item 7: the Translations screen. What is installed (name, language, verse count, the copyright line the file carried),
// Import… through an open panel with progress and a plain result, and Remove after asking. The app bundles no Bible text.
import SwiftUI
import UniformTypeIdentifiers
import OperatorCore
import ScriptureStore

/// The open panel for a translation file. The model reads and checks it.
@MainActor func chooseTranslationFile(_ scripture: ScriptureModel) {
    let panel = NSOpenPanel()
    panel.allowedContentTypes = [.json]
    panel.allowsMultipleSelection = false
    panel.canChooseDirectories = false
    panel.message = "Choose a WorshipFlow translation file (.json) you have the right to use"
    panel.begin { response in
        guard response == .OK, let url = panel.url else { return }
        Task { @MainActor in await scripture.importTranslation(from: url) }
    }
}

struct ScriptureTranslationsView: View {
    @Bindable var scripture: ScriptureModel

    var body: some View {
        VStack(alignment: .leading, spacing: Space.s4) {
            HStack {
                Text("Installed translations").font(.system(size: 15, weight: .semibold))
                Spacer()
                Button { chooseTranslationFile(scripture) } label: { Label("Import…", systemImage: "square.and.arrow.down") }
                    .buttonStyle(HeaderButtonStyle()).disabled(!scripture.canStartImport)
                    .help("Add a translation file. It is kept in your library; nothing is sent anywhere.")
            }
            ScriptureImportStatus(scripture: scripture)
            if let error = scripture.translationsError {
                Text(error).font(.caption).foregroundStyle(Tok.warning).fixedSize(horizontal: false, vertical: true)
            }
            if scripture.translations.isEmpty {
                VStack(spacing: 8) {
                    Text("No Bible translation is installed.").font(.title3)
                    Text(ScriptureModel.emptyHint).font(.caption).foregroundStyle(Tok.muted).multilineTextAlignment(.center).frame(maxWidth: 480)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                List {
                    ForEach(scripture.translations) { row($0) }
                }
                .listStyle(.plain).scrollContentBackground(.hidden)
                .accessibilityLabel("Installed translations")
            }
            Text("A USFM folder is turned into a translation file with the command-line tool wf-bible-import; then import the file here.")
                .font(.caption).foregroundStyle(Tok.muted)
        }
        .padding(Space.s5)
        .confirmationDialog(removalTitle, isPresented: Binding(get: { scripture.pendingRemoval != nil }, set: { if !$0 { scripture.cancelRemoval() } }),
                            titleVisibility: .visible) {
            Button("Remove", role: .destructive) { Task { await scripture.confirmRemoval() } }
            Button("Cancel", role: .cancel) { scripture.cancelRemoval() }
        } message: {
            Text("Its verses are deleted from your library. Playlist items that use it stay in the playlist and say the translation is not installed. You can import the file again later.")
        }
    }

    private var removalTitle: String { "Remove \(scripture.pendingRemoval?.name ?? "this translation")?" }

    private func row(_ t: StoredTranslation) -> some View {
        HStack(alignment: .top, spacing: Space.s4) {
            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 8) {
                    Text(t.name).font(.system(size: 14, weight: .semibold))
                    Badge(text: t.abbreviation, style: .outline(Tok.borderStrong)).foregroundStyle(Tok.muted)
                    if t.code == scripture.primaryCode { Badge(text: "FIRST", style: .preview) }
                    if t.code == scripture.secondaryCode { Badge(text: "SECOND", style: .preview) }
                }
                Text("\(TranslationRow.languageName(t.language)) · \(t.verseCount) verses · code \(t.code)")
                    .font(.system(size: 12)).foregroundStyle(Tok.muted)
                Text(TranslationRow.copyrightLine(t)).font(.system(size: 12)).foregroundStyle(Tok.muted)
                    .fixedSize(horizontal: false, vertical: true).textSelection(.enabled)
            }
            Spacer(minLength: 8)
            Button("Remove…", role: .destructive) { scripture.requestRemoval(t.code) }.buttonStyle(HeaderButtonStyle())
                .accessibilityLabel("Remove \(t.name)")
        }
        .padding(.vertical, 4)
        .accessibilityElement(children: .combine)
    }
}

/// Progress, the result, or the question about replacing, from the last import.
struct ScriptureImportStatus: View {
    @Bindable var scripture: ScriptureModel

    var body: some View {
        switch scripture.importState {
        case .idle:
            EmptyView()
        case .running(let done, let total):
            HStack(spacing: 8) {
                if total > 0 { ProgressView(value: Double(done), total: Double(total)).frame(maxWidth: 260) } else { ProgressView().controlSize(.small) }
                Text(total > 0 ? "Importing… \(done) of \(total) verses" : "Reading the file…").font(.caption).foregroundStyle(Tok.muted)
            }
            .accessibilityElement(children: .combine)
        case .finished(let text):
            message(text, color: Tok.statusOK, symbol: "checkmark.circle.fill")
        case .failed(let text):
            message(text, color: Tok.warning, symbol: "exclamationmark.triangle.fill")
        case .needsReplace(let code, let name):
            VStack(alignment: .leading, spacing: 6) {
                Text("A translation with the code “\(code)” is already installed. Replace it with “\(name)”?").font(.caption).fixedSize(horizontal: false, vertical: true)
                HStack {
                    Button("Replace") { Task { await scripture.confirmReplace() } }.buttonStyle(HeaderButtonStyle())
                    Button("Keep the installed one") { scripture.cancelReplace() }.buttonStyle(HeaderButtonStyle())
                }
            }
            .accessibilityElement(children: .contain)
        }
    }

    private func message(_ text: String, color: Color, symbol: String) -> some View {
        HStack(alignment: .top, spacing: 6) {
            Image(systemName: symbol).foregroundStyle(color).accessibilityHidden(true)
            Text(text).font(.caption).fixedSize(horizontal: false, vertical: true).textSelection(.enabled)
            Spacer(minLength: 4)
            Button("Dismiss") { scripture.dismissImportMessage() }.buttonStyle(.plain).font(.caption).foregroundStyle(Tok.muted)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel(text)
    }
}
