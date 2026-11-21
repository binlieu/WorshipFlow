// OUT-001: operator window.
import SwiftUI

struct ContentView: View {
    @Bindable var model: AppModel

    var body: some View {
        HSplitView {
            slideList
                .frame(minWidth: 280, idealWidth: 340)
            controls
                .frame(minWidth: 380)
        }
        .frame(minWidth: 760, minHeight: 460)
    }

    private var slideList: some View {
        List {
            ForEach(Array(model.slides.enumerated()), id: \.offset) { index, slide in
                VStack(alignment: .leading, spacing: 2) {
                    Text(slide.primary).font(.headline)
                    if let s = slide.secondary { Text(s).font(.subheadline).foregroundStyle(.secondary) }
                }
                .padding(.vertical, 3)
                .frame(maxWidth: .infinity, alignment: .leading)
                .contentShape(Rectangle())
                .background(index == model.selectedIndex ? Color.accentColor.opacity(0.25) : Color.clear)
                .onTapGesture { model.select(index) }
                .accessibilityAddTraits(index == model.selectedIndex ? .isSelected : [])
            }
        }
    }

    private var controls: some View {
        VStack(alignment: .leading, spacing: 14) {
            Picker("Display", selection: $model.selectedScreenIndex) {
                ForEach(Array(model.screenNames.enumerated()), id: \.offset) { i, name in Text(name).tag(i) }
            }
            .disabled(model.mode != .stopped)
            if model.chosenScreenIsOperatorScreen && model.screens.count > 1 {
                Text("This is the display the operator window is on. The output would cover it.")
                    .font(.caption).foregroundStyle(.orange)
            }
            if model.screens.count < 2 {
                Text("Only one display: the audience output runs in a window.").font(.caption).foregroundStyle(.secondary)
            }

            HStack {
                Button("Go Live") { model.goLive() }
                    .disabled(model.mode != .stopped)
                    .keyboardShortcut(.return, modifiers: .command)
                Button("Clear") { model.clear() }
                    .disabled(model.mode == .stopped)
                Button("Stop") { model.stopLive() }
                    .disabled(model.mode == .stopped)
                Spacer()
                Text(modeText).font(.headline).foregroundStyle(modeColor)
            }

            HStack {
                Button("Choose background video…") { model.chooseVideo() }
                Text(model.videoURL?.lastPathComponent ?? "No video: solid background")
                    .font(.caption).foregroundStyle(.secondary).lineLimit(1).truncationMode(.middle)
                if model.videoURL != nil { Button("Remove") { model.setVideo(nil) } }
            }

            Toggle("Second output window (stage composition)", isOn: $model.showSecondWindow)

            Text("Space / Right: next    Left: previous    Escape: clear").font(.caption).foregroundStyle(.secondary)

            Divider()
            Text("Output statistics").font(.headline)
            if model.readouts.isEmpty {
                Text("No output running.").foregroundStyle(.secondary)
            } else {
                ForEach(model.readouts) { r in
                    VStack(alignment: .leading, spacing: 2) {
                        Text("\(r.name) (\(r.status)) at \(String(format: "%.0f", r.refreshHz)) Hz").font(.subheadline.bold())
                        Text("presented \(r.presented)   dropped \(r.dropped)   late \(r.late)   max interval \(String(format: "%.1f", r.maxIntervalMs)) ms")
                            .font(.system(.body, design: .monospaced))
                    }
                }
            }
            if !model.messages.isEmpty {
                Divider()
                ForEach(Array(model.messages.enumerated()), id: \.offset) { _, m in
                    Text(m).font(.caption).foregroundStyle(.orange)
                }
            }
            Spacer()
        }
        .padding(16)
    }

    private var modeText: String {
        switch model.mode { case .stopped: "STOPPED"; case .live: "LIVE"; case .cleared: "CLEARED" }
    }
    private var modeColor: Color {
        switch model.mode { case .stopped: .secondary; case .live: .red; case .cleared: .orange }
    }
}
