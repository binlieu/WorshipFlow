// CUE-002b (item 1): the `CueTarget` the executor delivers batches to. It translates each action into a call on the models'
// ports and reports what cannot be done as text for the operator. It decides nothing about order: the engine does.
import Foundation
import CueEngine

@MainActor
public final class ShowCueTarget: CueTarget {
    private let transport: any CueTransportPort
    private let looks: any CueLookPort
    private let stage: any CueStagePort
    private let media: any CueMediaPort
    private let midiOut: @MainActor () -> (any CueMIDIOutPort)?
    private var deferred: [CueTransport] = []

    public init(transport: any CueTransportPort, looks: any CueLookPort, stage: any CueStagePort, media: any CueMediaPort,
                midiOut: @escaping @MainActor () -> (any CueMIDIOutPort)?) {
        self.transport = transport
        self.looks = looks
        self.stage = stage
        self.media = media
        self.midiOut = midiOut
    }

    /// Steps that cross into another playlist item need to wait for the library. The target cannot wait, so it hands them to
    /// the command path, which awaits them before the command ends. Returns each only once.
    public func takeDeferred() -> [CueTransport] {
        defer { deferred = [] }
        return deferred
    }

    public func beginBatch() {}
    public func endBatch() {}

    public func perform(_ action: CueAction) throws {
        switch action {
        case .transport(let t): try perform(t)
        case .selectLook(let id):
            guard looks.hasLook(id) else { throw CueTargetError("That Look no longer exists.") }
            looks.selectLook(id)
        case .prop(let id, let on):
            guard looks.hasProp(id) else { throw CueTargetError("That prop no longer exists.") }
            looks.setProp(id, isOn: on)
        case .showMessage(_, let fields):
            guard let text = fields["text"]?.trimmingCharacters(in: .whitespacesAndNewlines), !text.isEmpty else {
                throw CueTargetError("The stage message has no text.")
            }
            stage.sendMessage(text)
        case .hideMessage: stage.clearStageMessage()
        case .startTimer(let id): try timer(id) { stage.startTimer($0) }
        case .pauseTimer(let id): try timer(id) { stage.pauseTimer($0) }
        case .resetTimer(let id): try timer(id) { stage.resetTimer($0) }
        case .playForeground(let id):
            guard media.hasAsset(id) else { throw CueTargetError("That picture or video is no longer in the media bin.") }
            media.playForeground(id)
        case .setBackground(let id):
            if let id {
                guard media.hasAsset(id) else { throw CueTargetError("That picture or video is no longer in the media bin.") }
                media.setBackground(id)
            } else {
                media.setBackground(nil)
            }
        case .stopForeground: media.stopForeground()
        case .playAudio(let id):
            guard media.hasSound(id) else { throw CueTargetError("That sound is no longer in the media bin.") }
            media.playSound(id)
        case .stopAudio(let id):
            guard media.hasSound(id) else { throw CueTargetError("That sound is no longer in the media bin.") }
            media.stopSound(id)
        case .midiOut(let message):
            guard let out = midiOut() else { throw CueTargetError("MIDI is off, so the message was not sent. Turn it on in the Cues mode.") }
            try out.send(message)
        case .runMacro, .wait, .unknown:
            throw CueTargetError("This action is handled before it reaches the screens.")
        }
    }

    private func timer(_ id: UUID, _ body: (UUID) -> Void) throws {
        guard stage.hasTimer(id) else { throw CueTargetError("That timer no longer exists.") }
        body(id)
    }

    func perform(_ t: CueTransport) throws {
        switch t {
        case .next: if !transport.nextIfInDeck() { deferred.append(.next) }
        case .previous: if !transport.previousIfInDeck() { deferred.append(.previous) }
        case .goToSlide(let index): try transport.goToSlide(index)
        case .clear: transport.clear()
        case .clearAll: transport.clearAll()
        case .blackout(let mode):
            switch mode {
            case .toggle: transport.blackout()
            case .on: if !transport.isBlackedOut { transport.blackout() }
            case .off: if transport.isBlackedOut { transport.blackout() }
            }
        case .stop: transport.stop()
        }
    }
}
