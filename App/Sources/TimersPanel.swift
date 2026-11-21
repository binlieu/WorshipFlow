// STAGE-001b (LIVE-02, LIVE-04): timers and the stage clock style, in the right-hand column. Values are read from
// `StageModel` (decisions and tests live there); the list redraws every second only while a timer is running.
import SwiftUI
import Domain
import OperatorCore

struct TimersPanel: View {
    let app: AppModel
    @Bindable var stage: StageModel
    @State private var adding = false
    @State private var kind = NewTimerKind.countdown
    @State private var name = ""
    @State private var minutes = 5
    @State private var seconds = 0
    @State private var targetTime = Date()
    @State private var renaming: UUID?
    @State private var renameText = ""

    enum NewTimerKind: String, CaseIterable, Identifiable {
        case countdown = "Countdown", elapsed = "Elapsed", toTime = "To a time"
        var id: String { rawValue }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                SectionLabel("Timers and clock")
                Spacer()
                Button(adding ? "Cancel" : "Add timer…") { adding.toggle() }
            }
            if adding { addForm }
            if stage.timers.isEmpty && !adding {
                Text("No timers. Add a countdown, an elapsed timer or a countdown to a time, then show it with a Timer element in a stage layout.")
                    .font(.caption).foregroundStyle(.secondary)
            }
            if stage.timers.contains(where: \.isRunning) {
                TimelineView(.periodic(from: .now, by: 1)) { _ in rows }
            } else {
                rows
            }
            Divider()
            Text("Stage clock").font(.subheadline.bold())
            HStack {
                Picker("", selection: Binding(get: { stage.clockStyle.twentyFourHour },
                                                   set: { stage.setClockStyle(twentyFourHour: $0) })) {
                    Text("12 hour").tag(false)
                    Text("24 hour").tag(true)
                }.pickerStyle(.segmented).frame(maxWidth: 190).accessibilityLabel("Clock hours")
                Toggle("Seconds", isOn: Binding(get: { stage.clockStyle.showsSeconds }, set: { stage.setClockStyle(showsSeconds: $0) }))
                    .toggleStyle(.checkbox)
            }
            Text("Now: \(stage.timeOfDayText(at: stage.now))").font(.caption).foregroundStyle(.secondary)
        }
    }

    private var rows: some View {
        let seconds = stage.nowSeconds
        return VStack(alignment: .leading, spacing: 6) {
            ForEach(stage.timerRows(at: seconds)) { row in
                VStack(alignment: .leading, spacing: 4) {
                    HStack {
                        if renaming == row.id {
                            TextField("Name", text: $renameText).textFieldStyle(.roundedBorder)
                                .onSubmit { commitRename(row.id) }
                            Button("Save") { commitRename(row.id) }
                        } else {
                            Text(row.name).font(.subheadline.bold()).lineLimit(1)
                            Spacer()
                            Text(row.text)
                                .font(.system(.title3, design: .monospaced))
                                .foregroundStyle(row.isOverrun ? Color(StageLayout.standard.warningColor) : Color.primary)
                                .accessibilityLabel("\(row.name) value \(row.text)\(row.isOverrun ? ", over time" : "")")
                        }
                    }
                    HStack(spacing: 6) {
                        Text(row.kindLabel).font(.caption).foregroundStyle(.secondary)
                        Spacer()
                        if !row.followsClock {
                            if row.isRunning {
                                Button("Pause") { stage.pauseTimer(row.id) }.accessibilityLabel("Pause \(row.name)")
                            } else {
                                Button("Start") { stage.startTimer(row.id) }.accessibilityLabel("Start \(row.name)")
                            }
                            Button("Reset") { stage.resetTimer(row.id) }.accessibilityLabel("Reset \(row.name)")
                        }
                        Button("Rename") {
                            renaming = row.id
                            renameText = row.name
                        }.accessibilityLabel("Rename \(row.name)")
                        Button("Delete", role: .destructive) { stage.deleteTimer(row.id) }.accessibilityLabel("Delete \(row.name)")
                    }.controlSize(.small)
                }
                Divider()
            }
        }
    }

    private func commitRename(_ id: UUID) {
        stage.renameTimer(id, to: renameText)
        renaming = nil
    }

    private var addForm: some View {
        VStack(alignment: .leading, spacing: 8) {
            Picker("Kind", selection: $kind) {
                ForEach(NewTimerKind.allCases) { Text($0.rawValue).tag($0) }
            }.pickerStyle(.segmented).accessibilityLabel("Timer kind")
            TextField("Name (optional)", text: $name).textFieldStyle(.roundedBorder)
            switch kind {
            case .countdown:
                HStack {
                    Stepper("Minutes \(minutes)", value: $minutes, in: 0...5_999).accessibilityLabel("Minutes")
                    Stepper("Seconds \(seconds)", value: $seconds, in: 0...59).accessibilityLabel("Seconds")
                }
            case .toTime:
                DatePicker("Time today", selection: $targetTime, displayedComponents: .hourAndMinute)
            case .elapsed:
                Text("Counts up from zero when you start it.").font(.caption).foregroundStyle(.secondary)
            }
            Button("Add") {
                let made: ShowTimer?
                switch kind {
                case .countdown: made = stage.addCountdown(name: name, minutes: minutes, seconds: seconds)
                case .elapsed: made = stage.addElapsed(name: name)
                case .toTime:
                    let parts = Calendar.current.dateComponents([.hour, .minute], from: targetTime)
                    made = stage.addCountdown(name: name, toHour: parts.hour ?? 0, minute: parts.minute ?? 0)
                }
                if made != nil {
                    name = ""
                    adding = false
                }
            }.keyboardShortcut(.defaultAction)
        }
        .padding(8)
        .background(RoundedRectangle(cornerRadius: 6).fill(Color.secondary.opacity(0.08)))
    }
}
