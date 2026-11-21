// UI-001 Part 1: Blackout. Black on audience, transparent on broadcast, the stage keeps its words and says BLACKOUT.
import Testing
import Foundation
@testable import Domain

@Suite struct UI001_BlackoutStateTests {
    let deck = ShowDeck(presentationID: UUID(), slides: ["A1", "A2", "A3"].map { SlideContent(primary: $0) })

    func live(at index: Int = 1) -> ShowState {
        var s = ShowState()
        s.apply(.load(deck)); s.apply(.trigger(index: index))
        return s
    }

    @Test func blackoutTogglesAndKeepsDeckIndexAndSlide() {
        var s = live()
        #expect(s.isBlackedOut == false)
        s.apply(.blackout)
        #expect(s.isBlackedOut)
        #expect(s.liveDeck == deck && s.liveIndex == 1 && s.liveSlide?.primary == "A2" && s.nextSlide?.primary == "A3")
        #expect(s.isStopped == false && s.isCleared == false)
        s.apply(.blackout)
        #expect(s.isBlackedOut == false)
        #expect(s.liveSlide?.primary == "A2")
    }

    @Test func blackoutWithNothingLiveIsIgnored() {
        var s = ShowState()
        s.apply(.blackout)
        #expect(s == ShowState())
        s.apply(.load(deck)); let before = s
        s.apply(.blackout)
        #expect(s == before)
    }

    @Test func triggerNextAndPreviousRestoreThePicture() {
        for command: ShowCommand in [.trigger(index: 2), .next, .previous] {
            var s = live(); s.apply(.blackout)
            s.apply(command)
            #expect(s.isBlackedOut == false, "\(command)")
            #expect(s.liveSlide != nil)
        }
    }

    @Test func nextFromTheLastSlideThatDoesNotMoveKeepsTheBlackout() {
        var s = live(at: 2); s.apply(.blackout)
        s.apply(.next)
        #expect(s.isBlackedOut && s.liveIndex == 2)
    }

    @Test func clearAndClearAllKeepItBlackedOutAndTakeEffectWhenItLifts() {
        for command: ShowCommand in [.clear, .clearAll] {
            var s = live(); s.apply(.blackout)
            s.apply(command)
            #expect(s.isBlackedOut && s.isCleared, "\(command)")
            s.apply(.blackout)
            #expect(s.isBlackedOut == false && s.isCleared && s.liveSlide == nil && s.liveIndex == 1, "\(command)")
        }
    }

    @Test func stopEndsIt() {
        var s = live(); s.apply(.blackout)
        s.apply(.stop)
        #expect(s.isBlackedOut == false && s.isStopped)
        s.apply(.blackout)
        #expect(s.isBlackedOut == false)
    }

    @Test func loadingSelectingAndQuickEditDoNotLiftIt() {
        var s = live(); s.apply(.blackout)
        s.apply(.load(deck)); s.apply(.select(index: 0))
        #expect(s.isBlackedOut)
        s.apply(.quickEdit(index: 1, content: SlideContent(primary: "edited")))
        #expect(s.isBlackedOut && s.liveDeck?.slides[1].primary == "edited")
        s.apply(.restore(deck: deck, selectedIndex: 0))
        #expect(s.isBlackedOut)
    }
}

@Suite struct UI001_BlackoutSceneTests {
    func state(blackedOut: Bool) -> ShowState {
        var s = ShowState()
        s.apply(.load(ShowDeck(presentationID: UUID(), slides: [
            SlideContent(primary: "Amazing grace", secondary: "Ân điển", objects: [
                SlideObject(frame: NormalizedRect(x: 0.1, y: 0.1, width: 0.2, height: 0.2),
                            content: .shape(ShapeObject(shape: .rectangle, fill: .white))),
            ]),
            SlideContent(primary: "Next line"),
        ])))
        s.apply(.trigger(index: 0))
        if blackedOut { s.apply(.blackout) }
        return s
    }
    let prop = Prop(name: "Logo", imagePath: "/tmp/logo.png", frame: NormalizedRect(x: 0.8, y: 0.05, width: 0.15, height: 0.1))

    @Test func audienceIsOpaqueBlackWithNothingDrawn() {
        var layers = MediaLayers()
        layers.setBackground(MediaSelection(assetID: UUID(), kind: .video, duration: 10), at: 0)
        let scene = SceneComposer.scene(for: .audience, state: state(blackedOut: true), theme: Theme.fullScreen, look: .standard,
                                        props: [prop], media: layers, clockText: "10:00")
        #expect(scene == SceneDescription(backgroundColor: .black, showsVideo: false, textLayers: []))
        #expect(scene.backgroundColor.alpha == 1)
    }

    @Test func broadcastIsFullyTransparentWithNothingDrawn() {
        let scene = SceneComposer.scene(for: .broadcast, state: state(blackedOut: true), theme: Theme.lowerThird, look: .standard,
                                        props: [prop], media: nil, clockText: nil)
        #expect(scene == SceneDescription(backgroundColor: .clear, showsVideo: false, textLayers: []))
    }

    @Test func theEarlierEntryPointBlacksOutToo() {
        let a = SceneComposer.scene(for: .audience, state: state(blackedOut: true))
        let b = SceneComposer.scene(for: .broadcast, state: state(blackedOut: true))
        #expect(a == SceneDescription(backgroundColor: .black, showsVideo: false, textLayers: []))
        #expect(b == SceneDescription(backgroundColor: .clear, showsVideo: false, textLayers: []))
    }

    @Test func liftingTheBlackoutRestoresTheSamePicture() {
        var s = state(blackedOut: true)
        let before = SceneComposer.scene(for: .audience, state: state(blackedOut: false))
        s.apply(.blackout)
        #expect(SceneComposer.scene(for: .audience, state: s) == before)
    }

    @Test func stageKeepsItsWordsAndAddsBlackoutInTheWarningColour() {
        let plain = SceneComposer.scene(for: .stage, state: state(blackedOut: false), clockText: "10:00")
        let dark = SceneComposer.scene(for: .stage, state: state(blackedOut: true), clockText: "10:00")
        #expect(dark.textLayers.count == plain.textLayers.count + 1)
        #expect(Array(dark.textLayers.prefix(plain.textLayers.count)) == plain.textLayers)
        let word = dark.textLayers.last
        #expect(word?.text == "BLACKOUT")
        #expect(word?.style.color == StageLayout.standard.warningColor)
        #expect(dark.backgroundColor == plain.backgroundColor)
    }

    @Test func stageLayoutComposerShowsBlackoutInTheLayoutsWarningColour() {
        var layout = StageLayout.standard
        layout.warningColor = ColorRGBA(red: 0.1, green: 0.9, blue: 0.2)
        func scene(_ s: ShowState) -> SceneDescription {
            StageComposer.scene(layout: layout, context: StageContext(state: s, now: 0, timeOfDayText: "10:00", timers: [],
                                                                      message: nil, notes: nil))
        }
        let plain = scene(state(blackedOut: false)), dark = scene(state(blackedOut: true))
        #expect(Array(dark.textLayers.prefix(plain.textLayers.count)) == plain.textLayers)
        #expect(dark.textLayers.last?.text == "BLACKOUT")
        #expect(dark.textLayers.last?.style.color == layout.warningColor)
        #expect(plain.textLayers.contains { $0.text == "BLACKOUT" } == false)
    }
}
