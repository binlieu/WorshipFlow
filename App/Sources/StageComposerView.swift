// UI-005e (catalogue LIVE-03): the stage message as the Stage mode draws it: the section at the bottom of the layout column with the design's
// 48 pt field, Send and Clear. It uses the same `StageModel` calls as the composer in the Show inspector (`StageMessageView`), so the message
// reaches stage screens only, survives slide changes and is cleared by Stop. The field keeps what was sent, so the operator sees the words on
// the stage screens; the caption says "On stage now" in the warning tone while they are up, "Stage only" otherwise.
import SwiftUI
import OperatorCore

struct StageComposerView: View {
    @Bindable var stage: StageModel
    @State private var text = ""

    private var onStage: Bool { stage.stageMessage != nil }
    private var typed: String { text.trimmingCharacters(in: .whitespacesAndNewlines) }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                SectionLabel("Stage message", rectID: "st.msg.h")
                Spacer()
                recents
            }
            TextField("", text: $text, prompt: Text("Wrap up in 2 min…").foregroundStyle(Tok.muted), axis: .vertical)
                .textFieldStyle(.plain).font(.wf(12)).lineLimit(1...2)
                .padding(.horizontal, 9).padding(.top, 5)
                .frame(maxWidth: .infinity, minHeight: 48, maxHeight: 48, alignment: .topLeading)
                .wfOutline(RoundedRectangle(cornerRadius: Radius.md), stroke: Tok.borderStrong, fill: Tok.bg)
                .wfRect("st.msg.field", size: 12, weight: 400, radius: Radius.md)
                .onSubmit(submit)
                .accessibilityLabel("Stage message text")
            HStack(spacing: 8) {
                Button(action: submit) {
                    HStack(spacing: 6) { Image(systemName: "text.bubble").frame(width: 15, height: 15); Text("Send") }.fixedSize()
                }
                .buttonStyle(HeaderButtonStyle(kind: .primary)).wfRect("st.msg.send", size: 12, weight: 500, radius: Radius.md)
                .disabled(typed.isEmpty).help("Show this message on the stage screens")
                Button { stage.clearStageMessage() } label: { Text("Clear").fixedSize() }
                    .buttonStyle(HeaderButtonStyle()).wfRect("st.msg.clear", size: 12, weight: 500, radius: Radius.md)
                    .disabled(!onStage).help("Take the message off the stage screens")
                Spacer(minLength: 0)
                Text(onStage ? "On stage" : "Stage only").font(.wf(11)).foregroundStyle(onStage ? Tok.warning : Tok.muted).wfLine()
                    .wfRect("st.msg.note", size: 11, weight: 400)
            }
            .frame(height: Space.controlHeight)
        }
        .padding(.horizontal, 12).padding(.vertical, 10)
        .onAppear { if let current = stage.stageMessage { text = current } }
    }

    @ViewBuilder private var recents: some View {
        if !stage.recentMessages.isEmpty {
            Menu {
                ForEach(stage.recentMessages, id: \.self) { m in Button(m) { text = m } }
            } label: { Image(systemName: "clock.arrow.circlepath").foregroundStyle(Tok.muted) }
                .menuStyle(.borderlessButton).menuIndicator(.hidden).fixedSize()
                .help("Reuse a recent message").accessibilityLabel("Recent stage messages")
        }
    }

    private func submit() {
        guard !typed.isEmpty else { return }
        stage.sendMessage(text)
    }
}
