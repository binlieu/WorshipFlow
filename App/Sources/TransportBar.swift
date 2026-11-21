// OUT-004 / OUT-002: Go Live, Next, Previous, Clear, Stop and the live status, along the bottom of the window.
import SwiftUI
import Domain
import OperatorCore

struct TransportBar: View {
    @Bindable var app: AppModel
    @Bindable var workspace: WorkspaceModel

    var body: some View {
        HStack(spacing: 12) {
            Text(modeText).font(.headline).foregroundStyle(modeColor)
                .frame(width: 90, alignment: .leading)
                .accessibilityLabel("Show state: \(modeText)")
            Text(liveSummary).lineLimit(1).truncationMode(.tail).foregroundStyle(.secondary)
            Spacer()
            Button { Task { await workspace.previous() } } label: { Label("Previous", systemImage: "backward.fill") }
                .help("Left arrow")
            Button { Task { await workspace.goLive() } } label: { Label("Go Live", systemImage: "play.fill") }
                .help("Return: take the selected slide live").tint(.red)
            Button { Task { await workspace.next() } } label: { Label("Next", systemImage: "forward.fill") }
                .help("Right arrow or Space")
            Button { workspace.clear() } label: { Label("Clear", systemImage: "rectangle.slash") }
                .disabled(workspace.show.isStopped).help("Escape: hide the slide on every screen")
            Button { workspace.stop() } label: { Label("Stop", systemImage: "stop.fill") }
                .disabled(workspace.show.isStopped).help("Empty every screen")
            Divider().frame(height: 20)
            Button { app.ui.showQuickEdit = true } label: { Label("Quick edit live slide", systemImage: "pencil.line") }
                .disabled(workspace.show.liveSlide == nil)
                .help("Change the words on screen right now (Command-E)")
                .popover(isPresented: Binding(get: { app.ui.showQuickEdit }, set: { app.ui.showQuickEdit = $0 }), arrowEdge: .top) {
                    QuickEditView(workspace: workspace) { app.ui.showQuickEdit = false }
                }
            Divider().frame(height: 20)
            if app.screensOn {
                Button("Close screens") { app.stopScreens() }
            } else {
                Button("Open screens") { app.startScreens() }
            }
        }
        .padding(.horizontal, 14).padding(.vertical, 8)
        .background(.bar)
    }

    private var modeText: String {
        switch app.mode { case .stopped: "STOPPED"; case .live: "LIVE"; case .cleared: "CLEARED" }
    }

    private var modeColor: Color {
        switch app.mode { case .stopped: .secondary; case .live: .red; case .cleared: .orange }
    }

    private var liveSummary: String {
        if let slide = workspace.show.liveSlide {
            return slide.primary.replacingOccurrences(of: "\n", with: " ")
        }
        return app.mode == .cleared ? "Cleared: the screens are blank, your place is kept" : "Nothing is on the screens"
    }
}

/// The one action that changes what is on screen without going live again. It also saves the words.
struct QuickEditView: View {
    let workspace: WorkspaceModel
    let done: () -> Void
    @State private var primary = ""
    @State private var secondary = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Quick edit live slide").font(.headline)
            Text("This changes what the audience sees now, and saves the new words.")
                .font(.caption).foregroundStyle(.secondary)
            Text("First language").font(.caption)
            editor($primary)
            Text("Second language").font(.caption)
            editor($secondary)
            HStack {
                Spacer()
                Button("Cancel", action: done).keyboardShortcut(.cancelAction)
                Button("Apply to live") {
                    // Start from the live slide so its objects stay on screen; only the words change.
                    var content = workspace.show.liveSlide ?? SlideContent(primary: "")
                    content.primary = primary
                    content.secondary = secondary.isEmpty ? nil : secondary
                    Task { await workspace.quickEditLiveSlide(content); done() }
                }.keyboardShortcut(.defaultAction)
            }
        }
        .padding(14).frame(width: 440)
        .onAppear {
            primary = workspace.show.liveSlide?.primary ?? ""
            secondary = workspace.show.liveSlide?.secondary ?? ""
        }
    }

    private func editor(_ text: Binding<String>) -> some View {
        TextEditor(text: text).font(.body).frame(height: 76)
            .overlay(RoundedRectangle(cornerRadius: 4).stroke(.quaternary))
    }
}
