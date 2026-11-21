// CUE-002b: fakes for the ports the cue wiring drives, so every decision is tested without a window, a device or a sound.
import Foundation
import Domain
import CueEngine
import MIDIIO
@testable import OperatorCore

final class TestCueClock: CueClock, @unchecked Sendable {
    var seconds: TimeInterval = 1000
    func now() -> TimeInterval { seconds }
}

/// One object that plays every port, and writes down what it was asked to do, in order.
@MainActor
final class FakeShow: CueTransportPort, CueLookPort, CueStagePort, CueMediaPort, CueMIDIOutPort {
    var log: [String] = []
    var isBlackedOut = false
    var liveIndex: Int?
    var liveCount = 3
    var looks: Set<UUID> = []
    var props: Set<UUID> = []
    var timers: Set<UUID> = []
    var assets: Set<UUID> = []
    var sounds: Set<UUID> = []
    var slideForEvent: UUID?
    /// How many times `next()` and the like give way to other tasks, so an interleaving command would show in the log.
    var yields = 6
    var midiError: String?

    private func slow(_ name: String) async {
        log.append("\(name) begin")
        for _ in 0..<yields { await Task.yield() }
        log.append("\(name) end")
    }

    // Transport
    func goLive() async { await slow("goLive") }
    func triggerSlide(_ index: Int) { log.append("trigger \(index)") }
    func next() async { await slow("next") }
    func previous() async { await slow("previous") }
    var nextCrossesAnItem = false
    func nextIfInDeck() -> Bool { if nextCrossesAnItem { return false }; log.append("next sync"); return true }
    func previousIfInDeck() -> Bool { log.append("previous sync"); return true }
    func goToSlide(_ index: Int) throws {
        guard liveIndex != nil else { throw CueTargetError("Nothing is live, so there is no slide to go to.") }
        guard (0..<liveCount).contains(index) else { throw CueTargetError("There is no slide \(index + 1).") }
        log.append("goTo \(index)")
    }
    func clear() { log.append("clear") }
    func clearAll() { log.append("clearAll") }
    func stop() { log.append("stop") }
    func blackout() { isBlackedOut.toggle(); log.append("blackout \(isBlackedOut)") }
    func liveSlideID(for event: SlideLiveEvent) -> UUID? { slideForEvent }

    // Looks and props
    func hasLook(_ id: UUID) -> Bool { looks.contains(id) }
    func selectLook(_ id: UUID) { log.append("look \(id.uuidString.prefix(4))") }
    func hasProp(_ id: UUID) -> Bool { props.contains(id) }
    func setProp(_ id: UUID, isOn: Bool) { log.append("prop \(id.uuidString.prefix(4)) \(isOn)") }

    // Stage
    func hasTimer(_ id: UUID) -> Bool { timers.contains(id) }
    func startTimer(_ id: UUID) { log.append("timer start") }
    func pauseTimer(_ id: UUID) { log.append("timer pause") }
    func resetTimer(_ id: UUID) { log.append("timer reset") }
    func sendMessage(_ text: String) { log.append("message \(text)") }
    func clearStageMessage() { log.append("message cleared") }

    // Media and audio
    func hasAsset(_ id: UUID) -> Bool { assets.contains(id) }
    func hasSound(_ id: UUID) -> Bool { sounds.contains(id) }
    func setBackground(_ id: UUID?) { log.append("background \(id.map { String($0.uuidString.prefix(4)) } ?? "none")") }
    func playForeground(_ id: UUID) { log.append("foreground \(id.uuidString.prefix(4))") }
    func stopForeground() { log.append("foreground stop") }
    func playSound(_ id: UUID) { log.append("sound \(id.uuidString.prefix(4))") }
    func stopSound(_ id: UUID) { log.append("sound stop \(id.uuidString.prefix(4))") }

    // MIDI out
    func send(_ message: MIDIMessage) throws {
        if let midiError { throw CueTargetError(midiError) }
        log.append("midi \(message)")
    }
}
