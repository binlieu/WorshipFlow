// HWTEST-001: the Hardware Test window, written for someone who has never seen the app. Everything it does is in
// `HardwareTestController`; this file only lays it out.
import SwiftUI
import AppKit
import UniformTypeIdentifiers
import OutputEngine

struct HardwareTestView: View {
    @Bindable var controller: HardwareTestController
    @State private var savedURL: URL?
    @State private var saveProblem: String?

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                header
                switch controller.phase {
                case .idle: setup
                case .running: running
                case .finished: finished
                }
            }
            .padding(24)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .frame(minWidth: 680, minHeight: 640)
    }

    // MARK: pieces

    private var header: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Hardware Test").font(.largeTitle.bold())
            Text("This checks how your Blackmagic DeckLink card works with WORSHIPFLOW and makes one file to send back. You do not need to understand the results: just run it and send the file.")
                .foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
        }
    }

    private var setup: some View {
        VStack(alignment: .leading, spacing: 18) {
            if let why = controller.refusal { notice(why, systemImage: "hand.raised.fill", tint: .orange) }
            unfinished
            if let saved = savedURL { notice("Saved: \(saved.lastPathComponent). Please send this file back.", systemImage: "checkmark.circle.fill", tint: .green) }
            cardStatus
            GroupBox("What you need") {
                VStack(alignment: .leading, spacing: 6) {
                    Label("No cables: the card is checked and each connector is run on its own (steps 1, 2, 3, 6 and 7).", systemImage: "0.circle")
                    Label("One short BNC cable: adds the basic loopback test (step 4).", systemImage: "1.circle")
                    Label("Two short BNC cables: adds the fill and key test (step 5). This gives the most useful results.", systemImage: "2.circle")
                }.frame(maxWidth: .infinity, alignment: .leading).padding(.top, 4)
            }
            GroupBox("Which connectors to join") {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Usually:   SDI 1  ──────▶  SDI 3")
                    Text("            SDI 2  ──────▶  SDI 4")
                    Text("SDI means the round BNC sockets on the card, numbered 1 to 4. Push each end in until it clicks. The app tells you exactly which sockets to join each time it asks, and may ask you to move the cables to check every socket.")
                        .font(.callout).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                }
                .font(.system(.body, design: .monospaced)).frame(maxWidth: .infinity, alignment: .leading).padding(.top, 4)
            }
            GroupBox("How long") {
                VStack(alignment: .leading, spacing: 8) {
                    Picker("Length", selection: $controller.preset) {
                        ForEach(HardwareTestPreset.allCases, id: \.self) { Text($0.title).tag($0) }
                    }
                    .pickerStyle(.radioGroup).labelsHidden()
                    Toggle("Also ask me to unplug the card during the test (about 2 more minutes)", isOn: $controller.includeUnplugTest)
                    Toggle("Also ask me what I see on a monitor or switcher, and let me attach photos", isOn: $controller.includeHumanChecks)
                }.frame(maxWidth: .infinity, alignment: .leading).padding(.top, 4)
            }
            HStack(spacing: 14) {
                Button { controller.start(simulated: false) } label: {
                    Text(controller.realRunTitle).font(.title2.bold()).frame(minWidth: 240, minHeight: 36)
                }
                .buttonStyle(.borderedProminent).controlSize(.extraLarge).disabled(!controller.canStartReal)
                .accessibilityIdentifier("hwtest.start")
                Button("Run against the simulated card") { controller.start(simulated: true) }
                    .disabled(!controller.canStartSimulated).accessibilityIdentifier("hwtest.simulated")
            }
            Text("The simulated card is a demonstration only: it uses no real card, and its report is marked SIMULATED in its file name and its first line.")
                .font(.callout).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
        }
    }

    /// FIX-D S6: a run that did not finish (or was never saved) is offered here, so a crash on first contact with the card
    /// still gives the developers a report.
    @ViewBuilder
    private var unfinished: some View {
        if let run = controller.unfinishedRun {
            VStack(alignment: .leading, spacing: 8) {
                notice((run.reachedTheEnd ? "A previous test was finished but its report was never saved. " : "A previous test did not finish. ") + run.description,
                       systemImage: "exclamationmark.arrow.triangle.2.circlepath", tint: .orange)
                HStack {
                    Button("Save its report…") { saveUnfinished() }.buttonStyle(.borderedProminent).accessibilityIdentifier("hwtest.saveUnfinished")
                    if let problem = saveProblem { Text(problem).font(.callout).foregroundStyle(.red) }
                }
                Text("Its files are in the folder \"\(run.folder.lastPathComponent)\" on your Desktop. Saving the report here puts them in one file to send back, then removes that folder.")
                    .font(.callout).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private var cardStatus: some View {
        let card = controller.cardState
        return VStack(alignment: .leading, spacing: 8) {
            switch card.state {
            case .cardFound:
                notice(card.text, systemImage: "checkmark.seal.fill", tint: .green)
            case .driverNotInstalled:
                notice(card.text, systemImage: "exclamationmark.triangle.fill", tint: .orange)
            case .noCardFound:
                notice(card.text, systemImage: "exclamationmark.triangle.fill", tint: .orange)
            }
            if card.state != .cardFound {
                Text("You can still press \"Create a report anyway\": a report that says no card was found is useful too. Or run the simulated card to see how the test works.")
                    .font(.callout).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            }
            Button("Rescan") { Task { await controller.rescan() } }.controlSize(.small).accessibilityIdentifier("hwtest.rescan")
        }
        .task { await controller.rescan() }
    }

    private func notice(_ text: String, systemImage: String, tint: Color) -> some View {
        Label { Text(text).fixedSize(horizontal: false, vertical: true) } icon: { Image(systemName: systemImage).foregroundStyle(tint) }
            .padding(12).frame(maxWidth: .infinity, alignment: .leading)
            .background(tint.opacity(0.12), in: RoundedRectangle(cornerRadius: 8))
    }

    private var running: some View {
        VStack(alignment: .leading, spacing: 14) {
            VStack(alignment: .leading, spacing: 6) {
                Text(controller.currentStepTitle.map { "Step \(controller.stepPosition) of \(controller.stepTotal): \($0)" } ?? "Finishing…")
                    .font(.title2.bold())
                ProgressView(value: controller.stepProgress)
                Text(controller.runWasSimulated ? "Running against the SIMULATED card. This is a demonstration." : "Please keep this window open and leave the card alone unless asked.")
                    .font(.callout).foregroundStyle(.secondary)
            }
            if let prompt = controller.pendingPrompt { promptCard(prompt) }
            stepList
            logView
            Button("Stop after this step") { controller.cancel() }.accessibilityIdentifier("hwtest.cancel")
        }
    }

    private func promptCard(_ prompt: HardwarePrompt) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(prompt.title).font(.title3.bold())
            Text(prompt.message).fixedSize(horizontal: false, vertical: true)
            HStack {
                switch prompt.kind {
                case .humanBars, .humanKeyEdges:
                    Button("Yes") { controller.answer(.yes) }.buttonStyle(.borderedProminent)
                    Button("No") { controller.answer(.no) }
                case .photo:
                    Button("Attach a photo…") {
                        let panel = NSOpenPanel()
                        panel.allowedContentTypes = [.image]
                        panel.allowsMultipleSelection = false
                        panel.message = "Choose a photo of the screen to attach to the report."
                        if panel.runModal() == .OK, let url = panel.url { controller.answer(.attachment(url.path)) }
                    }.buttonStyle(.borderedProminent)
                default:
                    Button(prompt.primaryLabel) { controller.answer(.proceed) }.buttonStyle(.borderedProminent)
                }
                if prompt.canSkip { Button("Skip") { controller.answer(.skip) } }
            }
        }
        .padding(14).frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.accentColor.opacity(0.12), in: RoundedRectangle(cornerRadius: 10))
        .accessibilityIdentifier("hwtest.prompt")
    }

    private var stepList: some View {
        VStack(alignment: .leading, spacing: 4) {
            ForEach(controller.results, id: \.number) { r in
                HStack(alignment: .firstTextBaseline) {
                    Image(systemName: icon(r.outcome)).foregroundStyle(color(r.outcome))
                    Text("\(r.number). \(r.title)").bold()
                    Text(r.outcome.label.lowercased()).foregroundStyle(.secondary)
                }
            }
        }
    }

    private var logView: some View {
        GroupBox("What is happening") {
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 2) {
                        ForEach(Array(controller.logLines.enumerated()), id: \.offset) { i, line in
                            Text(line).font(.system(.caption, design: .monospaced)).textSelection(.enabled).id(i)
                        }
                    }.frame(maxWidth: .infinity, alignment: .leading)
                }
                .frame(height: 170)
                .onChange(of: controller.logLines.count) { _, n in if n > 0 { proxy.scrollTo(n - 1, anchor: .bottom) } }
            }
        }
    }

    private var finished: some View {
        VStack(alignment: .leading, spacing: 14) {
            if controller.runWasSimulated {
                notice("This was a demonstration with the simulated card. Its report is marked SIMULATED and says nothing about a real card.", systemImage: "testtube.2", tint: .purple)
            }
            if let verdict = controller.verdictLine, !controller.runWasSimulated {
                let clean = verdict.hasPrefix("REAL DEVICE TESTED") && !verdict.contains("NOT RESTORED") && !verdict.contains("DID NOT FINISH")
                notice(verdict, systemImage: clean ? "checkmark.seal.fill" : "exclamationmark.triangle.fill", tint: clean ? .green : .orange)
            }
            Text("The test is finished.").font(.title2.bold())
            if let problem = controller.errorMessage { notice(problem, systemImage: "xmark.octagon.fill", tint: .red) }
            stepList
            HStack(spacing: 12) {
                Button("Save report…") { save() }.buttonStyle(.borderedProminent).controlSize(.large)
                    .disabled(controller.bundleURL == nil).accessibilityIdentifier("hwtest.save")
                Button("Show in Finder") { showInFinder() }.disabled(controller.bundleURL == nil && savedURL == nil)
                    .accessibilityIdentifier("hwtest.finder")
                Button("Run again") { savedURL = nil; saveProblem = nil; controller.refresh(); controller.resetToSetup() }
            }
            if let saved = savedURL { notice("Saved: \(saved.lastPathComponent). Please send this file back.", systemImage: "checkmark.circle.fill", tint: .green) }
            if let problem = saveProblem { notice(problem, systemImage: "xmark.octagon.fill", tint: .red) }
            if let text = controller.summaryText {
                GroupBox("What the report says") {
                    Text(text).font(.system(.caption, design: .monospaced)).textSelection(.enabled)
                        .frame(maxWidth: .infinity, alignment: .leading).padding(.top, 4)
                }
            }
        }
    }

    // MARK: actions

    private func save() {
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.zip]
        panel.nameFieldStringValue = controller.suggestedFileName
        panel.directoryURL = FileManager.default.urls(for: .desktopDirectory, in: .userDomainMask).first
        panel.message = "Save the report. Then send this one file back."
        guard panel.runModal() == .OK, let url = panel.url else { return }
        do {
            try controller.save(to: url)
            savedURL = url
            saveProblem = nil
        } catch { saveProblem = "The report could not be saved there: \(error.localizedDescription). Try another folder." }
    }

    private func saveUnfinished() {
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.zip]
        panel.nameFieldStringValue = controller.suggestedUnfinishedFileName
        panel.directoryURL = FileManager.default.urls(for: .desktopDirectory, in: .userDomainMask).first
        panel.message = "Save the report of the test that did not finish. Then send this one file back."
        guard panel.runModal() == .OK, let url = panel.url else { return }
        do {
            try controller.saveUnfinishedReport(to: url)
            savedURL = url
            saveProblem = nil
        } catch { saveProblem = "The report could not be saved there: \(error.localizedDescription). Try another folder." }
    }

    private func showInFinder() {
        if let url = savedURL ?? controller.bundleURL { NSWorkspace.shared.activateFileViewerSelecting([url]) }
    }

    private func icon(_ o: HardwareTestOutcome) -> String {
        switch o {
        case .passed: return "checkmark.circle.fill"
        case .failed: return "xmark.circle.fill"
        case .skipped: return "forward.circle"
        case .needsHuman: return "person.crop.circle.badge.questionmark"
        case .partial: return "circle.lefthalf.filled"
        }
    }

    private func color(_ o: HardwareTestOutcome) -> Color {
        switch o {
        case .passed: return .green
        case .failed: return .red
        case .skipped: return .secondary
        case .needsHuman: return .orange
        case .partial: return .orange
        }
    }
}
