// CUE-002b (debug builds only): `UI_SNAPSHOT_CUES=1` with the ui-snapshots hook runs the cue wiring in the real app against a
// temporary library, with window outputs and no sound: a macro run from the Cues tab, a slide action that changes the Look, a MIDI
// note arriving on the app's own virtual port, a scheduled event, and one remote-control request over the loopback interface with
// the server on an ephemeral port, then switched off again. It writes pictures through the hook's `capture`.
#if DEBUG
import AppKit
import CoreMIDI
import Domain
import CueEngine
import MIDIIO
import OperatorCore

extension AppModel {
    func runCuesScenario(note: @MainActor (String) -> Void, capture: @MainActor (String) async -> Void) async {
        guard let workspace, let cue, let stage, let settings else { note("cues: no models"); return }
        @MainActor func wait(_ seconds: Double, until condition: @MainActor () -> Bool) async -> Bool {
            let end = Date().addingTimeInterval(seconds)
            while Date() < end { if condition() { return true }; try? await Task.sleep(for: .milliseconds(100)) }
            return condition()
        }
        // Looks, a timer, and the macro the design shows (three steps).
        for name in ["Worship", "Sermon"] { addLook(); if let last = looks.last { renameLook(last.id, to: name) } }
        guard let worship = looks.first(where: { $0.name == "Worship" }), let sermon = looks.first(where: { $0.name == "Sermon" }) else { note("cues: looks missing"); return }
        let timer = stage.timers.first(where: { $0.name == "Service" }) ?? stage.addElapsed(name: "Service")
        guard let timer else { note("cues: no timer"); return }
        selectLook(sermon.id)
        guard let macro = await cue.createMacro(name: "Start worship set") else { note("cues: macro failed \(cue.lastError ?? "")"); return }
        await cue.setSteps([.selectLook(worship.id), .showMessage(id: CueActionEditing.stageMessageID, fields: ["text": "Welcome, we are starting"]), .startTimer(timer.id)], of: macro.id)
        _ = await cue.createMacro(name: "Sermon mode")
        note("cues: macro steps \(cue.macro(macro.id)?.steps.count ?? -1) (expected 3), look now \(currentLook?.name ?? "-") (expected Sermon)")

        // 1. The macro, from the Cues tab's button (the action the button runs).
        workspace.setMode(.show)
        ui.tabs.select(.cues)
        cue.submit(.runMacro(macro.id), from: .button)
        await cue.settled()
        note("cues: after the macro: look \(currentLook?.name ?? "-") (expected Worship), stage message \(stage.stageMessage ?? "none") (expected Welcome...), timer running \(stage.timers.first { $0.id == timer.id }?.isRunning ?? false) (expected true)")

        // 2. A slide action: slide 4 changes the Look when it goes live, not when it is selected.
        let slideID = workspace.slides[3].id
        try? await cue.setSlideActions([.selectLook(sermon.id)], for: slideID)
        workspace.selectSlide(3)
        await cue.settled()
        note("cues: slide 4 selected only: look \(currentLook?.name ?? "-") (expected Worship)")
        goLive()
        _ = await wait(3) { currentLook?.name == "Sermon" }
        note("cues: slide 4 live: look \(currentLook?.name ?? "-") (expected Sermon), live index \(show.liveIndex.map(String.init) ?? "-") (expected 3)")

        // 3. A scheduled event, a few seconds ahead.
        let soon = Date().addingTimeInterval(4)
        await cue.saveEvent(ScheduledEvent(name: "Doors open", timing: .once(soon), payload: .macro(macro.id)))
        await cue.saveEvent(ScheduledEvent(name: "Sunday service", timing: .weekly(weekdays: [.sunday], hour: 9, minute: 0, timeZoneID: TimeZone.current.identifier),
                                           payload: .macro(macro.id)))
        // 4. MIDI on the app's own virtual port, with names that cannot be mistaken for another app's.
        cue.midiPortsFactory = { try CoreMIDIPorts(clientName: "WorshipFlow cue run", virtualDestinationName: "WF cue run In", virtualSourceName: "WF cue run Out") }
        await cue.saveBinding(MIDIBinding(name: "Note D4", pattern: MIDIPattern(kind: .noteOn, channel: 1, number: 62), command: .transport(.next)))
        await cue.saveBinding(MIDIBinding(name: "Note C4", pattern: MIDIPattern(kind: .noteOn, channel: 1, number: 60), command: .macro(macro.id)))
        await cue.setMIDIEnabled(true)
        await cue.setVirtualPorts(true)
        try? await Task.sleep(for: .milliseconds(800))
        let before = show.liveIndex
        sendNoteToVirtualPort(named: "WF cue run In", note: 62, note: note)
        _ = await wait(3) { show.liveIndex != before }
        note("cues: MIDI note D4 on the virtual port: live index \(before.map(String.init) ?? "-") -> \(show.liveIndex.map(String.init) ?? "-") (expected 3 -> 4); midi activity \(cue.activity.contains { $0.source == .midi })")

        // 5. Remote control: loopback only, ephemeral port (launch arguments), one request, then off again. The MIDI note took the
        // song to its last slide, so step back one first and let the phone's request advance it again.
        cue.submit(.transport(.previous), from: .button)
        await cue.settled()
        let beforeRemote = show.liveIndex
        await cue.setRemoteEnabled(true)
        if let port = cue.remoteStatus.port, let code = cue.remotePairing()?.code {
            note("cues: remote on, port \(port > 0 ? "ephemeral" : "0"), addresses \(cue.remoteStatus.addresses)")
            let session = URLSession(configuration: .ephemeral)
            func call(_ path: String, token: String?, body: String) async -> (Int, Data) {
                var r = URLRequest(url: URL(string: "http://127.0.0.1:\(port)\(path)")!)
                r.httpMethod = "POST"; r.timeoutInterval = 10
                r.setValue("application/json", forHTTPHeaderField: "Content-Type")
                if let token { r.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization") }
                r.httpBody = Data(body.utf8)
                let result = try? await session.data(for: r)
                return ((result?.1 as? HTTPURLResponse)?.statusCode ?? 0, result?.0 ?? Data())
            }
            let paired = await call("/api/v1/pair", token: nil, body: "{\"code\":\"\(code)\",\"label\":\"Test phone (this Mac)\"}")
            let token = (try? JSONSerialization.jsonObject(with: paired.1) as? [String: Any])?["token"] as? String
            note("cues: pair status \(paired.0) (expected 200)")
            let sent = await call("/api/v1/transport", token: token, body: "{\"command\":\"next\"}")
            note("cues: remote next status \(sent.0) (expected 200): live index \(beforeRemote.map(String.init) ?? "-") -> \(show.liveIndex.map(String.init) ?? "-"); remote activity \(cue.activity.contains { $0.source == .remote })")
            ui.cuesSelection = .remote
            workspace.setMode(.cues)
            await capture("cues-remote")
            workspace.setMode(.show)
        } else {
            note("cues: remote did not start: \(cue.remoteStatus.error ?? "?")")
        }
        _ = await wait(6) { cue.activity.contains { $0.source == .schedule } }
        note("cues: scheduled event ran: \(cue.activity.contains { $0.source == .schedule }) (expected true)")

        // Pictures: the Cues mode on the macro, MIDI, and the Show mode's Cues tab.
        ui.cuesSelection = .macro(macro.id)
        workspace.setMode(.cues)
        await capture("cues")
        ui.cuesSelection = .midi
        await capture("cues-midi")
        ui.cuesSelection = .slideActions
        ui.cuesSlideID = slideID
        await capture("cues-slide-actions")
        ui.cuesSelection = .schedule
        await capture("cues-schedule")
        workspace.setMode(.show)
        ui.tabs.select(.cues)
        await capture("show-cues-tab")

        // Off again: the port is released and the virtual MIDI ports are disposed.
        let port = cue.remoteStatus.port
        await cue.setRemoteEnabled(false)
        await cue.setMIDIEnabled(false)
        var refused = false
        if let port {
            var r = URLRequest(url: URL(string: "http://127.0.0.1:\(port)/")!)
            r.timeoutInterval = 3
            refused = (try? await URLSession(configuration: .ephemeral).data(for: r)) == nil
        }
        note("cues: remote off: running \(cue.remoteStatus.isRunning), port refuses connections \(refused) (expected true); midi enabled \(cue.midiStatus.isEnabled) (expected false)")
    }

    /// Sends one note-on to the virtual destination of this process, from a second CoreMIDI client that is disposed afterwards.
    private func sendNoteToVirtualPort(named name: String, note number: UInt8, note log: @MainActor (String) -> Void) {
        var client = MIDIClientRef()
        guard MIDIClientCreate("WorshipFlow cue run sender" as CFString, nil, nil, &client) == noErr else { log("cues: no sender client"); return }
        defer { MIDIClientDispose(client) }
        var port = MIDIPortRef()
        guard MIDIOutputPortCreate(client, "out" as CFString, &port) == noErr else { log("cues: no sender port"); return }
        var found: MIDIEndpointRef = 0
        for i in 0..<MIDIGetNumberOfDestinations() {
            let d = MIDIGetDestination(i)
            var cfName: Unmanaged<CFString>?
            if MIDIObjectGetStringProperty(d, kMIDIPropertyName, &cfName) == noErr, let text = cfName?.takeRetainedValue() as String?, text == name { found = d }
        }
        guard found != 0 else { log("cues: virtual destination \(name) not found"); return }
        var buffer = [UInt8](repeating: 0, count: 256)
        let bytes: [UInt8] = [0x90, number, 100]
        buffer.withUnsafeMutableBytes { raw in
            let list = raw.baseAddress!.assumingMemoryBound(to: MIDIPacketList.self)
            let packet = MIDIPacketListInit(list)
            _ = MIDIPacketListAdd(list, 256, packet, 0, 3, bytes)
            MIDISend(port, found, list)
        }
    }
}
#endif
