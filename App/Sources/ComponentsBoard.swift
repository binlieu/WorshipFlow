// UI-005a (debug builds only): the component board of docs/UI (08-components, 10-components-light), drawn with the app's own shared
// components so it can be compared with the design picture by scripts/compare-design.sh. It is a test rig, not a screen.
#if DEBUG
import SwiftUI
import Domain
import OperatorCore

struct ComponentsBoard: View {
    var light = false

    private func card<C: View>(_ title: String, width: CGFloat, height: CGFloat, @ViewBuilder _ body: () -> C) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            SectionLabel(title).frame(height: 16)
            body()
            Spacer(minLength: 0)
        }
        .padding(16)
        .frame(width: width, height: height, alignment: .topLeading)
        .wfOutline(RoundedRectangle(cornerRadius: Radius.xl), stroke: Tok.border, fill: Tok.surface)
    }

    var body: some View {
        let col: CGFloat = (1440 - 64 - 36) / 3
        VStack(alignment: .leading, spacing: 0) {
            Text(light ? "Components — light" : "Components").font(.wf(26, .bold)).frame(height: 32).padding(.bottom, 20)
            VStack(alignment: .leading, spacing: 18) {
                HStack(alignment: .top, spacing: 18) {
                    card("Buttons", width: col, height: 213) {
                        HStack(spacing: 8) {
                            Button { } label: { HStack(spacing: 6) { Image(systemName: "plus"); Text("Add slide") } }.buttonStyle(HeaderButtonStyle())
                            Button { } label: { HStack(spacing: 6) { Image(systemName: "bolt"); Text("Run") } }.buttonStyle(HeaderButtonStyle(kind: .primary))
                            Button { } label: { Text("Configure…") }.buttonStyle(HeaderButtonStyle(kind: .ghost))
                            Button { } label: { HStack(spacing: 6) { Image(systemName: "rectangle.slash"); Text("Clear") } }.buttonStyle(HeaderButtonStyle()).disabled(true)
                        }
                        HStack(spacing: 8) {
                            Button { } label: { HStack(spacing: 6) { Image(systemName: "backward.fill"); Text("Previous"); KeyHint(key: "←") } }.buttonStyle(TransportButtonStyle())
                            Button { } label: { HStack(spacing: 6) { Image(systemName: "play.fill"); Text("Go Live"); KeyHint(key: "↩", onFill: true) } }.buttonStyle(TransportButtonStyle(prominent: true))
                            Button { } label: { HStack(spacing: 6) { Image(systemName: "forward.fill"); Text("Next"); KeyHint(key: "→") } }.buttonStyle(TransportButtonStyle())
                        }
                        Text("Go Live is the only filled red control in the app. Transport buttons are 36 pt tall; everything else is the 26 pt macOS regular control size.")
                            .font(.wf(12)).foregroundStyle(Tok.muted).lineSpacing(1)
                    }
                    card("Selection controls", width: col, height: 213) {
                        HStack(spacing: 8) {
                            WFSegmented(items: ["Audience", "Stage", "Broadcast"].map { .init(value: $0, title: $0, label: $0) }, selection: .constant("Broadcast"))
                            WFSegmented(items: [.init(value: 0, symbol: "square.grid.2x2", label: "Grid"), .init(value: 1, symbol: "list.bullet", label: "List")], selection: .constant(0))
                        }
                        HStack(spacing: 8) {
                            Toggle("On", isOn: .constant(true)).toggleStyle(.wf)
                            Toggle("Off", isOn: .constant(false)).toggleStyle(.wf)
                            Toggle("Slide", isOn: .constant(true)).toggleStyle(.wfCheckbox)
                            Toggle("Notes", isOn: .constant(false)).toggleStyle(.wfCheckbox)
                        }
                        HStack(spacing: 8) {
                            WFPopup(title: "1080p59.94") { Text("1080p59.94") }.frame(width: 190)
                            WFTextField(prompt: "Filter songs", text: .constant(""), symbol: "magnifyingglass").frame(width: 170)
                        }
                    }
                    card("Role and status", width: col, height: 213) {
                        HStack(spacing: 8) { Badge(text: "AUDIENCE", style: .outline(Tok.blue)); Badge(text: "STAGE", style: .outline(Tok.warning)); Badge(text: "BROADCAST", style: .outline(Tok.broadcast)) }
                        HStack(spacing: 8) { PillTag(text: "AUD", color: Tok.blue, lead: .dot); PillTag(text: "STG", color: Tok.warning, lead: .dot); PillTag(text: "BRD", color: Tok.broadcast, lead: .dot); PillTag(text: "Running", color: Tok.cyan, lead: .dot); PillTag(text: "Signal lost", color: Tok.warning, lead: .symbol("exclamationmark.triangle")); PillTag(text: "Off", color: Tok.muted) }
                        HStack(spacing: 8) { Badge(text: "LIVE", style: .live); Badge(text: "PREVIEW", style: .preview); Badge(text: "SIMULATED", style: .outline(Tok.broadcast)); Badge(text: "HARDWARE VERIFIED", style: .outline(Tok.cyan)) }
                        Badge(text: "NOT VERIFIED", style: .outline(Tok.muted))
                        Text("A role or state is never colour alone: every chip carries its word, and offline states add an icon.").font(.wf(12)).foregroundStyle(Tok.muted)
                    }
                }
                HStack(alignment: .top, spacing: 18) {
                    card("Slide thumbnail states", width: col * 2 + 18, height: 199) {
                        HStack(alignment: .top, spacing: 14) {
                            ForEach(Array(["Idle", "Preview · 2 pt blue", "Live · 3 pt red", "Transparent"].enumerated()), id: \.offset) { n, name in
                                VStack(alignment: .leading, spacing: 5) {
                                    ZStack {
                                        if n == 3 { CheckerboardView() } else { LinearGradient(colors: [Color(red: 0.18, green: 0.49, blue: 0.42), Color(red: 0.02, green: 0.06, blue: 0.11)], startPoint: .bottomTrailing, endPoint: .topLeading) }
                                        VStack(spacing: 4) {
                                            Text("My chains are gone").font(.wf(13, .semibold)).foregroundStyle(.white)
                                                .padding(.horizontal, 6).background(n == 3 ? Color(red: 0.03, green: 0.075, blue: 0.13).opacity(0.86) : .clear)
                                            Text("Xiềng xích đã tan").font(.wf(10.5, .medium)).foregroundStyle(Color(red: 1, green: 0.82, blue: 0.48))
                                                .padding(.horizontal, 6).background(n == 3 ? Color(red: 0.03, green: 0.075, blue: 0.13).opacity(0.86) : .clear)
                                        }
                                    }
                                    .aspectRatio(16.0 / 9.0, contentMode: .fit)
                                    .clipShape(RoundedRectangle(cornerRadius: 4))
                                    .overlay(alignment: .topLeading) {
                                        if n == 1 { ThumbTag(text: "PREVIEW", kind: .preview).padding(5) }
                                        if n == 2 { ThumbTag(text: "LIVE", kind: .live).padding(5) }
                                    }
                                    .wfThumbState(preview: n == 1, live: n == 2)
                                    Text(name).font(.wf(11, .semibold)).padding(.top, 3)
                                }
                                .frame(maxWidth: .infinity)
                            }
                        }
                        .frame(maxWidth: .infinity)
                    }
                    card("Messages", width: col, height: 199) {
                        MessageCard(message: "SDI 3 stopped sending. The show is still running on the other screens.")
                        HStack(spacing: 8) { Button("Retry output") { }.buttonStyle(HeaderButtonStyle()); Button("Details") { }.buttonStyle(HeaderButtonStyle(kind: .ghost)) }
                        Text("Errors appear in the operator window only, never on an output. Say what happened, what still works, and the next action.").font(.wf(12)).foregroundStyle(Tok.muted)
                    }
                }
                HStack(alignment: .top, spacing: 18) {
                    card("Colour — surfaces and text", width: col * 2 + 18, height: 187) {
                        let names: [(String, Color)] = [("bg", Tok.bg), ("surface", Tok.surface), ("surface-2", Tok.surface2), ("surface-3", Tok.surface3), ("border", Tok.border), ("border-strong", Tok.borderStrong),
                                                        ("text", Tok.text), ("muted", Tok.muted), ("cyan", Tok.cyan), ("blue", Tok.blue), ("warning", Tok.warning), ("live", Tok.live)]
                        LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 6), count: 6), spacing: 6) {
                            ForEach(names, id: \.0) { n in
                                VStack(alignment: .leading, spacing: 2) {
                                    RoundedRectangle(cornerRadius: 6).fill(n.1).frame(height: 44).overlay(RoundedRectangle(cornerRadius: 6).strokeBorder(Tok.border))
                                    Text(n.0).font(.wf(10)).foregroundStyle(Tok.muted)
                                }
                            }
                        }
                    }
                    card("Brand", width: col, height: 187) {
                        RoundedRectangle(cornerRadius: 6).fill(Tok.brandGradient).frame(height: 44)
                        Text("WorshipFlow").font(.wf(22, .heavy)).foregroundStyle(Tok.text)
                    }
                }
            }
        }
        .padding(32)
        .frame(width: 1440, height: 754, alignment: .topLeading)
        .background(Tok.bg)
    }
}
#endif
