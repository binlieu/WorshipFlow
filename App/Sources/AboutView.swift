// UI-004: the About window. What the app is, which build this is (with a Copy button, so the owner can read it out or paste it
// into a message), who made it, the licence and the third-party notices. The words come from `AboutInfo` and `BuildInfo`.
import SwiftUI
import AppKit
import Domain

struct AboutView: View {
    let app: AppModel      // so the window follows the appearance choice (dark, light, system) like the workspace
    private let build = BuildInfo.current
    @State private var copied = false

    var body: some View {
        VStack(spacing: Space.s4) {
            Image(nsImage: NSApp.applicationIconImage).resizable().frame(width: 96, height: 96)
                .accessibilityHidden(true)
            Text("WorshipFlow").font(.wf(24, .bold))
            Text(AboutInfo.summary).font(.wf(13)).foregroundStyle(Tok.muted).multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)

            VStack(spacing: Space.s3) {
                Text(build.line).font(.wfMonoData).textSelection(.enabled).multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
                Button(copied ? "Copied" : "Copy") {
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(build.line, forType: .string)
                    copied = true
                }
                .buttonStyle(HeaderButtonStyle())
                .accessibilityLabel("Copy the version line")
            }
            .padding(Space.s4).frame(maxWidth: .infinity)
            .wfOutline(RoundedRectangle(cornerRadius: Radius.md), stroke: Tok.border, fill: Tok.surface2)

            VStack(spacing: Space.s2) {
                Text(AboutInfo.developerLine).font(.wf(13, .semibold))
                Link(AboutInfo.developerEmail, destination: AboutInfo.developerMailURL)
                Link(AboutInfo.projectURL.absoluteString, destination: AboutInfo.projectURL)
                Text(AboutInfo.licenceLine).font(.wf(12)).foregroundStyle(Tok.muted)
            }
            .font(.wf(13))

            Divider()
            VStack(alignment: .leading, spacing: Space.s2) {
                SectionLabel("Third-party notices")
                ForEach(AboutInfo.thirdPartyNotices, id: \.self) { notice in
                    Text(notice).font(.wf(11)).foregroundStyle(Tok.muted).fixedSize(horizontal: false, vertical: true)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(Space.s6)
        .font(.wfBody)
        .frame(width: 460)
        .background(Tok.bg)
        .preferredColorScheme(ContentView.scheme(app.appearance))
    }
}
