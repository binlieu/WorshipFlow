// CUE-002b item 1: the cue target drives the existing models through small ports. Fakes only.
import Testing
import Foundation
import CueEngine
import MIDIIO
@testable import OperatorCore

@MainActor
@Suite struct CUE002b_TargetTests {
    func make(_ show: FakeShow, midi: Bool = true) -> ShowCueTarget {
        ShowCueTarget(transport: show, looks: show, stage: show, media: show, midiOut: { midi ? show : nil })
    }

    @Test func nextInsideTheDeckIsDoneAtOnce() throws {
        let show = FakeShow()
        let target = make(show)
        try target.perform(.transport(.next))
        #expect(show.log == ["next sync"])
        #expect(target.takeDeferred().isEmpty)
    }

    @Test func nextAcrossAnItemIsHandedBackForTheCommandPathToAwait() throws {
        let show = FakeShow()
        show.nextCrossesAnItem = true
        let target = make(show)
        try target.perform(.transport(.next))
        #expect(show.log.isEmpty)
        #expect(target.takeDeferred() == [.next])
        #expect(target.takeDeferred().isEmpty)               // taken once
    }

    @Test func goToSlideReportsWhyItCannot() {
        let show = FakeShow()
        let target = make(show)
        #expect(throws: CueTargetError.self) { try target.perform(.transport(.goToSlide(index: 0))) }
        show.liveIndex = 0
        #expect(throws: CueTargetError.self) { try target.perform(.transport(.goToSlide(index: 9))) }
        #expect((try? target.perform(.transport(.goToSlide(index: 2)))) != nil)
        #expect(show.log == ["goTo 2"])
    }

    @Test func blackoutOnOffAndToggleAreIdempotentWhereTheyShouldBe() throws {
        let show = FakeShow()
        let target = make(show)
        try target.perform(.transport(.blackout(.off)))
        #expect(show.log.isEmpty)                            // already off
        try target.perform(.transport(.blackout(.on)))
        try target.perform(.transport(.blackout(.on)))       // already on
        try target.perform(.transport(.blackout(.toggle)))
        #expect(show.log == ["blackout true", "blackout false"])
    }

    @Test func clearClearAllAndStopArePassedOn() throws {
        let show = FakeShow()
        let target = make(show)
        try target.perform(.transport(.clear))
        try target.perform(.transport(.clearAll))
        try target.perform(.transport(.stop))
        #expect(show.log == ["clear", "clearAll", "stop"])
    }

    @Test func aMissingLookPropTimerOrFileIsAnOperatorReadableFailure() {
        let show = FakeShow()
        let target = make(show)
        let id = UUID()
        for action in [CueAction.selectLook(id), .prop(id: id, isOn: true), .startTimer(id), .pauseTimer(id), .resetTimer(id),
                       .playForeground(assetID: id), .setBackground(assetID: id), .playAudio(assetID: id), .stopAudio(assetID: id)] {
            #expect(throws: CueTargetError.self, "\(action)") { try target.perform(action) }
        }
        #expect(show.log.isEmpty)
    }

    @Test func existingThingsAreDriven() throws {
        let show = FakeShow()
        let (look, prop, timer, clip, sound) = (UUID(), UUID(), UUID(), UUID(), UUID())
        show.looks = [look]; show.props = [prop]; show.timers = [timer]; show.assets = [clip]; show.sounds = [sound]
        let target = make(show)
        try target.perform(.selectLook(look))
        try target.perform(.prop(id: prop, isOn: false))
        try target.perform(.startTimer(timer))
        try target.perform(.pauseTimer(timer))
        try target.perform(.resetTimer(timer))
        try target.perform(.setBackground(assetID: clip))
        try target.perform(.setBackground(assetID: nil))
        try target.perform(.playForeground(assetID: clip))
        try target.perform(.stopForeground)
        try target.perform(.playAudio(assetID: sound))
        try target.perform(.stopAudio(assetID: sound))
        #expect(show.log.count == 11)
        #expect(show.log[0].hasPrefix("look") && show.log[1].hasSuffix("false") && show.log[7].hasPrefix("foreground"))
    }

    @Test func stageMessageUsesItsTextField() throws {
        let show = FakeShow()
        let target = make(show)
        try target.perform(.showMessage(id: UUID(), fields: ["text": "Wrap up in 2 min"]))
        try target.perform(.hideMessage(id: UUID()))
        #expect(show.log == ["message Wrap up in 2 min", "message cleared"])
        #expect(throws: CueTargetError.self) { try target.perform(.showMessage(id: UUID(), fields: [:])) }
    }

    @Test func midiOutGoesToTheRouterOrSaysMidiIsOff() throws {
        let show = FakeShow()
        let on = make(show)
        try on.perform(.midiOut(.noteOn(channel: 1, note: 60, velocity: 100)))
        #expect(show.log.count == 1)
        let off = make(show, midi: false)
        #expect(throws: CueTargetError.self) { try off.perform(.midiOut(.noteOn(channel: 1, note: 60, velocity: 100))) }
        show.midiError = "The device is offline."
        #expect(throws: CueTargetError.self) { try on.perform(.midiOut(.noteOn(channel: 1, note: 60, velocity: 100))) }
    }
}
