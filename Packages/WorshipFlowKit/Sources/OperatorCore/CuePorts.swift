// CUE-002b (item 1): the small doors the cue wiring uses to drive the models that already exist. Each model conforms
// to the one it owns, so a test can put a fake behind every door. Foundation, Domain and CueEngine only.
import Foundation
import Domain
import CueEngine
import MIDIIO

/// The show's transport. `next()` and `previous()` are the full operator commands (they can cross playlist items and so
/// wait); the `...IfInDeck` forms do only what needs no waiting, so a macro's batch can stay synchronous.
@MainActor
public protocol CueTransportPort: AnyObject {
    var isBlackedOut: Bool { get }
    func goLive() async
    /// Takes the preview deck live at an index (a double click on a slide).
    func triggerSlide(_ index: Int)
    func next() async
    func previous() async
    /// False when the step would cross into another playlist item and must be run with `next()` instead.
    func nextIfInDeck() -> Bool
    func previousIfInDeck() -> Bool
    /// Zero-based. Throws a `CueTargetError` saying why not.
    func goToSlide(_ index: Int) throws
    func clear()
    func clearAll()
    func stop()
    /// MEDIA-010: hides the live background. Cancels nothing and moves nothing. The default does nothing.
    func clearBackground()
    /// Toggles Blackout.
    func blackout()
    /// The id of the slide that is live now, when `event` still describes it; nil when the show has moved on.
    func liveSlideID(for event: SlideLiveEvent) -> UUID?
}

@MainActor
public protocol CueLookPort: AnyObject {
    func hasLook(_ id: UUID) -> Bool
    func selectLook(_ id: UUID)
    func hasProp(_ id: UUID) -> Bool
    func setProp(_ id: UUID, isOn: Bool)
}

@MainActor
public protocol CueStagePort: AnyObject {
    func hasTimer(_ id: UUID) -> Bool
    func startTimer(_ id: UUID)
    func pauseTimer(_ id: UUID)
    func resetTimer(_ id: UUID)
    func sendMessage(_ text: String)
    func clearStageMessage()
}

@MainActor
public protocol CueMediaPort: AnyObject {
    func hasAsset(_ id: UUID) -> Bool
    func hasSound(_ id: UUID) -> Bool
    func setBackground(_ id: UUID?)
    func playForeground(_ id: UUID)
    func stopForeground()
    func playSound(_ id: UUID)
    func stopSound(_ id: UUID)
    /// MEDIA-010: stops every sound cue (the audio player). The default does nothing.
    func clearMusic()
}

// MEDIA-010: the doors added later have a default, so an earlier conformer keeps compiling.
extension CueTransportPort { public func clearBackground() {} }
extension CueMediaPort { public func clearMusic() {} }

/// MIDI out: the router when MIDI is on. Throws a `CueTargetError` with text for the operator.
@MainActor
public protocol CueMIDIOutPort: AnyObject {
    func send(_ message: MIDIMessage) throws
}

extension MIDIRouter: CueMIDIOutPort {}

/// Everything the cue wiring drives.
@MainActor
public struct CuePorts {
    public var transport: any CueTransportPort
    public var looks: any CueLookPort
    public var stage: any CueStagePort
    public var media: any CueMediaPort
    /// Nil while MIDI is off.
    public var midiOut: @MainActor () -> (any CueMIDIOutPort)?

    public init(transport: any CueTransportPort, looks: any CueLookPort, stage: any CueStagePort, media: any CueMediaPort,
                midiOut: @escaping @MainActor () -> (any CueMIDIOutPort)?) {
        self.transport = transport
        self.looks = looks
        self.stage = stage
        self.media = media
        self.midiOut = midiOut
    }
}
