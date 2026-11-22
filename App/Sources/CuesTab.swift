// CUE-002b (item 6): the Cues tab of the Show mode: a button for each macro, which runs it on click, and the next scheduled event.
import SwiftUI
import OperatorCore

struct CuesTabView: View {
    let app: AppModel
    @Bindable var workspace: WorkspaceModel

    var body: some View {
        if let cue = app.cue {
            VStack(alignment: .leading, spacing: Space.s4) {
                if cue.macros.isEmpty {
                    Text("No macros yet. Make one in the Cues mode (Command-5) and it appears here as a button.")
                        .font(.wf(12)).foregroundStyle(Tok.muted).fixedSize(horizontal: false, vertical: true)
                } else {
                    ForEach(cue.macros) { macro in
                        Button { cue.submit(.runMacro(macro.id), from: .button) } label: {
                            HStack(spacing: Space.s3) {
                                Image(systemName: "bolt.fill").foregroundStyle(Tok.cyan).frame(width: 18)
                                Text(macro.name).lineLimit(1)
                                Spacer()
                                Text("\(macro.steps.count)").font(.wf(12)).foregroundStyle(Tok.muted)
                            }
                            .frame(maxWidth: .infinity)
                        }
                        .buttonStyle(HeaderButtonStyle()).frame(height: 32)
                        .help("Run \(macro.name)")
                        .accessibilityLabel("Run macro \(macro.name)")
                    }
                }
                Divider()
                nextEvent(cue)
                if let slide = workspace.slides[safeIndex: workspace.showParts.selectedIndex], !cue.slideActions.actions(for: slide.id).isEmpty {
                    let n = cue.slideActions.actions(for: slide.id).count
                    Label("The selected slide runs \(n) action\(n == 1 ? "" : "s") when it goes live.", systemImage: "bolt").font(.wf(12)).foregroundStyle(Tok.muted)
                }
                Button("Open the Cues mode") { workspace.setMode(.cues) }.buttonStyle(.plain).foregroundStyle(Tok.muted).font(.wf(12))
            }
        } else {
            Text("Macros are not available.").font(.wf(12)).foregroundStyle(Tok.muted)
        }
    }

    @ViewBuilder private func nextEvent(_ cue: CueModel) -> some View {
        if let next = cue.nextScheduledEvent() {
            HStack(spacing: Space.s3) {
                Image(systemName: "calendar").foregroundStyle(Tok.muted).frame(width: 18)
                VStack(alignment: .leading, spacing: 1) {
                    Text("Next scheduled event").font(.wf(11)).foregroundStyle(Tok.muted)
                    Text("\(next.name), \(ScheduleText.next(next.date, now: Date(), calendar: .current))").font(.wf(13, .semibold))
                }
            }
            .accessibilityElement(children: .combine)
        } else {
            Label("No scheduled event in the next week.", systemImage: "calendar").font(.wf(12)).foregroundStyle(Tok.muted)
        }
    }
}

private extension Array {
    subscript(safeIndex index: Int) -> Element? { indices.contains(index) ? self[index] : nil }
}
