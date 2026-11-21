// UI-003 (catalogue LIVE-03): the stage message. A text field, Send and Clear in the Show inspector. It reaches stage
// screens only (never audience or broadcast), survives slide changes and is cleared by Stop. The last few messages are
// kept for reuse. The decisions and tests are in `StageModel`.
import SwiftUI
import OperatorCore

struct StageMessageView: View {
    @Bindable var stage: StageModel
    @State private var text = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                SectionLabel("Stage message")
                Spacer()
                Text("Stage screens only").font(.wfCaption).foregroundStyle(Tok.muted)
            }
            ViewThatFits(in: .horizontal) {
                HStack(spacing: 6) { field; recents; sendButton }
                VStack(alignment: .leading, spacing: 6) {
                    field
                    HStack(spacing: 6) { recents; Spacer(minLength: 0); sendButton }
                }
            }
            if let current = stage.stageMessage {
                HStack(spacing: 6) {
                    Image(systemName: "text.bubble.fill").foregroundStyle(Tok.warning).accessibilityHidden(true)
                    Text("On stage now: \(current)").font(.system(size: 12)).lineLimit(2).foregroundStyle(Tok.text)
                    Spacer(minLength: 4)
                    Button("Clear") { stage.clearStageMessage() }.buttonStyle(HeaderButtonStyle())
                        .help("Take the message off the stage screens")
                }
                .accessibilityElement(children: .combine)
            }
        }
    }

    private var field: some View {
        TextField("Wrap up in 2 min…", text: $text)
            .textFieldStyle(.plain).padding(.horizontal, 8).frame(height: Space.controlHeight).frame(minWidth: 140)
            .background(Tok.bg, in: RoundedRectangle(cornerRadius: Radius.md))
            .overlay(RoundedRectangle(cornerRadius: Radius.md).stroke(Tok.borderStrong, lineWidth: 1))
            .onSubmit(submit)
            .accessibilityLabel("Stage message text")
    }

    @ViewBuilder private var recents: some View {
        if !stage.recentMessages.isEmpty {
            Menu {
                ForEach(stage.recentMessages, id: \.self) { m in Button(m) { text = m } }
            } label: { Image(systemName: "clock.arrow.circlepath") }
                .menuStyle(.borderlessButton).menuIndicator(.hidden).fixedSize()
                .help("Reuse a recent message").accessibilityLabel("Recent stage messages")
        }
    }

    private var sendButton: some View {
        Button(action: submit) { Label("Send", systemImage: "text.bubble").fixedSize() }
            .buttonStyle(HeaderButtonStyle())
            .disabled(text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            .help("Show this message on the stage screens")
    }

    private func submit() {
        stage.sendMessage(text)
        text = ""
    }
}
