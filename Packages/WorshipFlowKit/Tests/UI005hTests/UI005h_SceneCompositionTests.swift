// UI-005h: what the composers hand the compositor for the new looks: the gradient under the loop, the lower third's plate with its
// text marked as plated, the stage's second language, NEXT label, timer and message band, and that speaker notes stay on the stage.
import Testing
import Foundation
import Domain

@Suite struct UI005h_SceneCompositionTests {
    let slide = UI005hFixtures.sampleSlide
    let state = UI005hFixtures.live()

    // MARK: Audience gradient

    @Test func theBuiltInAudienceSceneDrawsTheGradientAndStillPlaysTheLoop() {
        let scene = SceneComposer.scene(for: .audience, state: state, theme: .fullScreen, look: .standard, props: [])
        #expect(scene.backgroundGradient == Theme.fullScreen.mediaFallback && scene.backgroundGradient != nil)
        #expect(scene.showsVideo)                               // motion backgrounds behave as today
        #expect(scene.textLayers.map(\.text) == ["Through many dangers\ntoils and snares", "Qua bao hi\u{1EC3}m nguy\ngian kh\u{00F3} th\u{1EED} th\u{00E1}ch"])
        #expect(scene.textLayers.allSatisfy { !$0.inPlate } && scene.plate == nil)
        #expect(scene.textLayers.map(\.style.weight) == [600, 500])
    }

    @Test func aChosenBackgroundCoversTheGradientAndAHiddenBackgroundLayerDropsIt() {
        let clip = SceneMedia.video(UUID())
        var s = state
        s.apply(.load(ShowDeck(presentationID: UUID(), slides: [SlideContent(primary: "x", secondary: nil, objects: [], background: MediaSelection(assetID: clip.assetID, kind: .video, duration: nil))])))
        s.apply(.trigger(index: 0))
        let withClip = SceneComposer.scene(for: .audience, state: s, theme: .fullScreen, look: .standard, props: [])
        #expect(withClip.backgroundMedia == clip && withClip.backgroundGradient != nil)     // drawn first, then covered by the clip
        let noBackground = ScreenLook(themeID: nil, visibleLayers: [.slide, .props])
        #expect(SceneComposer.scene(for: .audience, state: state, theme: .fullScreen, look: noBackground, props: []).backgroundGradient == nil)
        var cleared = state; cleared.apply(.clearBackground)
        #expect(SceneComposer.scene(for: .audience, state: cleared, theme: .fullScreen, look: .standard, props: []).backgroundGradient == nil)
    }

    @Test func aGradientIsAThemeBackgroundKind() {
        let g = GradientBackground(stops: [.init(position: 0, color: .black), .init(position: 1, color: .white)], centerX: 0.5, centerY: 0.5, radiusX: 1, radiusY: 1)
        var theme = UI005hFixtures.userThemes[0]
        theme.background = .gradient(g)
        let scene = SceneComposer.scene(for: .audience, state: state, theme: theme, look: .standard, props: [])
        #expect(scene.backgroundGradient == g && !scene.showsVideo)
        #expect(Theme.fullScreen.background != theme.background)
    }

    @Test func aChurchsOwnThemeNeverGetsTheGradientOrAPlate() {
        for theme in UI005hFixtures.userThemes {
            for role in [ScreenRole.audience, .broadcast] {
                let scene = SceneComposer.scene(for: role, state: state, theme: theme, look: .standard, props: [])
                #expect(scene.backgroundGradient == nil && scene.plate == nil)
                #expect(scene.textLayers.allSatisfy { !$0.inPlate && $0.style.weight == nil && $0.style.lineHeight == nil })
            }
        }
    }

    // MARK: Lower third

    @Test func theLowerThirdSceneCarriesThePlateAndItsTwoPlatedLines() throws {
        let live = UI005hFixtures.live(UI005hFixtures.lowerThirdSlide)
        let scene = SceneComposer.scene(for: .broadcast, state: live, theme: .lowerThird, look: .standard, props: [])
        #expect(scene.plate == Theme.lowerThird.plate && scene.plate != nil)
        #expect(scene.backgroundColor == .clear && scene.backgroundGradient == nil && !scene.showsVideo)
        #expect(scene.textLayers.map(\.text) == [UI005hFixtures.lowerThirdSlide.primary, UI005hFixtures.lowerThirdSlide.secondary])
        #expect(scene.textLayers.allSatisfy { $0.inPlate && $0.alignment == .leading })
        #expect(scene.textLayers.map(\.style.fontSize) == [67.2, 49.92])
    }

    @Test func aLowerThirdWithoutASecondLanguageHasOnePlatedLine() {
        let live = UI005hFixtures.live(SlideContent(primary: "Only English"), next: nil)
        let scene = SceneComposer.scene(for: .broadcast, state: live, theme: .lowerThird, look: .standard, props: [])
        #expect(scene.plate != nil && scene.textLayers.map(\.text) == ["Only English"] && scene.textLayers.allSatisfy(\.inPlate))
    }

    @Test func noPlateIsDrawnWithoutWordsStoppedBlackedOutOrCleared() {
        let theme = Theme.lowerThird
        func plate(_ s: ShowState) -> TextPlate? { SceneComposer.scene(for: .broadcast, state: s, theme: theme, look: .standard, props: []).plate }
        #expect(plate(ShowState()) == nil)                                                 // stopped
        var s = UI005hFixtures.live(); s.apply(.blackout); #expect(plate(s) == nil)       // blackout
        var c = UI005hFixtures.live(); c.apply(.clear); #expect(plate(c) == nil)           // clear: the words are gone, so is the plate
        #expect(plate(UI005hFixtures.live(SlideContent(primary: "  ", secondary: " "), next: nil)) == nil)   // blank slide
        let noSlideLayer = ScreenLook(themeID: nil, visibleLayers: [.background, .props])
        #expect(SceneComposer.scene(for: .broadcast, state: UI005hFixtures.live(), theme: theme, look: noSlideLayer, props: []).plate == nil)
    }

    // MARK: Stage

    func stageContext(message: String? = nil, notes: String? = nil, timers: [ShowTimer]? = nil) -> StageContext {
        let timer = ShowTimer(id: UUID(), name: "Sermon", kind: .countdown(seconds: 632))
        return StageContext(state: state, now: 0, timeOfDayText: "9:14", timers: timers ?? [timer], message: message, notes: notes)
    }
    func px(_ f: NormalizedRect) -> (x: Double, y: Double, w: Double, h: Double) { (f.x * D.w, f.y * D.h, f.width * D.w, f.height * D.h) }

    @Test func theBuiltInStageCompositionHasEveryElementTheDesignDraws() throws {
        let scene = StageComposer.scene(layout: .standard, context: stageContext())
        let layers = scene.textLayers
        #expect(scene.backgroundColor == ColorRGBA(red: 0, green: 0, blue: 0) && scene.backgroundGradient == nil && scene.plate == nil)
        #expect(layers.map(\.text) == ["Through many dangers\ntoils and snares", "Qua bao hi\u{1EC3}m nguy \u{00B7} gian kh\u{00F3} th\u{1EED} th\u{00E1}ch",
                                       "NEXT", "'Tis grace has brought me safe thus far", "9:14", "10:32"])
        try #require(layers.count == 6)
        let (current, second, label, next, clock, timer) = (layers[0], layers[1], layers[2], layers[3], layers[4], layers[5])
        #expect(D.near(current.style.fontSize, 116.58, 0.02) && current.style.weight == 700 && current.style.lineHeight == 1.15 && D.same(current.style.color, .white))
        #expect(current.alignment == .leading && current.verticalAlignment == .top)
        #expect(D.near(px(current.frame).x, 76.8, 0.1) && D.near(px(current.frame).y, 76.8, 0.1) && D.near(px(current.frame).w, 1766.4, 0.1))
        #expect(D.near(second.style.fontSize, 63.59, 0.02) && second.style.weight == 600 && D.same(second.style.color, D.yellow))
        #expect(second.alignment == .leading && D.near(px(second.frame).x, 76.8, 0.1))
        #expect(D.near(label.style.fontSize, 26.50, 0.02) && label.style.weight == 700 && label.style.letterSpacing == 0.08 && D.same(label.style.color, D.muted))
        #expect(D.near(px(label.frame).x, 76.8, 0.1) && D.near(px(label.frame).y, 796, 0.2))
        #expect(D.near(next.style.fontSize, 67.12, 0.02) && next.style.weight == 700 && D.same(next.style.color, D.muted))     // muted: the green is gone
        #expect(D.near(px(next.frame).x, 76.8, 0.1) && D.near(px(next.frame).y, 837.5, 0.3))
        #expect(D.near(clock.style.fontSize, 70.66, 0.02) && clock.style.weight == 700 && clock.alignment == .trailing && D.same(clock.style.color, .white))
        #expect(D.near(px(clock.frame).x + px(clock.frame).w, 1843.2, 0.2) && D.near(px(clock.frame).y, 64.8, 0.2))
        #expect(D.near(timer.style.fontSize, 105.98, 0.02) && timer.style.weight == 700 && timer.alignment == .trailing && D.same(timer.style.color, D.cyan))
        #expect(D.near(px(timer.frame).x + px(timer.frame).w, 1843.2, 0.2) && D.near(px(timer.frame).y, 163.7, 0.3))
        // The section label "CHORUS x2" needs the section name and repeat count, which the show state does not carry: it is listed as open.
        #expect(!layers.contains { $0.text.contains("CHORUS") })
    }

    @Test func theTimerReadsTheFirstCountdownAndDrawsNothingWithoutOne() {
        let none = StageComposer.scene(layout: .standard, context: stageContext(timers: []))
        #expect(!none.textLayers.contains { $0.text == "10:32" } && none.textLayers.count == 5)
        let elapsed = ShowTimer(id: UUID(), name: "Service", kind: .elapsed)
        let countdown = ShowTimer(id: UUID(), name: "Sermon", kind: .countdown(seconds: 90))
        let scene = StageComposer.scene(layout: .standard, context: stageContext(timers: [elapsed, countdown]))
        #expect(scene.textLayers.last?.text == "1:30")
        var over = countdown
        over.start(at: -200)                                   // ran 200 s of 90: over by 110 s
        let overScene = StageComposer.scene(layout: .standard, context: stageContext(timers: [over]))
        #expect(overScene.textLayers.last?.text == "-1:50" && overScene.textLayers.last.map { D.same($0.style.color, StageLayout.standard.warningColor) } == true)
    }

    @Test func theNextLineAndItsLabelAreAbsentOnTheLastSlide() {
        var last = state; last.apply(.next)
        let ctx = StageContext(state: last, now: 0, timeOfDayText: "9:14", timers: [], message: nil, notes: nil)
        let scene = StageComposer.scene(layout: .standard, context: ctx)
        #expect(!scene.textLayers.contains { $0.text == "NEXT" } && scene.textLayers.first?.text == "'Tis grace has brought me safe thus far")
    }

    @Test func theStageMessageIsTheWarningBand() throws {
        let scene = StageComposer.scene(layout: .standard, context: stageContext(message: "Repeat chorus \u{00D7}2, then bridge"))
        let plate = try #require(scene.plate)
        #expect(D.near(plate.x, 0) && D.near(plate.width, 1) && D.near(plate.bottomMargin, 0) && plate.cornerRadius == 0 && plate.bar == nil)
        #expect(D.same(plate.fill, D.yellow) && D.near(plate.paddingX, 76.8, 0.1) && D.near(plate.paddingY, 17.66, 0.05))
        let text = try #require(scene.textLayers.first { $0.text.hasPrefix("Repeat") })
        #expect(text.inPlate && text.alignment == .leading && D.near(text.style.fontSize, 45.93, 0.02) && text.style.weight == 700)
        #expect(D.same(text.style.color, D.onBrand) && text.style.lineHeight == 1.3)
        #expect(StageComposer.scene(layout: .standard, context: stageContext(message: "  ")).plate == nil)
        // Blackout keeps the band's message and the word BLACKOUT, as before.
        var dark = state; dark.apply(.blackout)
        let ctx = StageContext(state: dark, now: 0, timeOfDayText: "9:14", timers: [], message: "Wrap up", notes: nil)
        #expect(StageComposer.scene(layout: .standard, context: ctx).textLayers.contains { $0.text == "BLACKOUT" })
    }

    @Test func aLayoutTheOperatorMadeIsNotAlteredByTheNewBuiltInLayout() throws {
        let s = SceneStyles.standard
        let mine = StageLayout(id: UUID(), name: "Mine", background: s.stageBackground, elements: [
            StageElement(id: UUID(), kind: .currentSlide, frame: s.stageCurrentFrame, style: s.stageCurrent, alignment: .leading),
            StageElement(id: UUID(), kind: .nextSlide, frame: s.stageNextFrame, style: s.stageNext, alignment: .leading, showsSecondLanguage: false),
            StageElement(id: UUID(), kind: .timeOfDay, frame: s.stageClockFrame, style: s.stageClock, alignment: .trailing),
        ])
        let scene = StageComposer.scene(layout: mine, context: stageContext(message: "Wrap up"))
        #expect(scene.plate == nil && scene.backgroundColor == s.stageBackground)
        try #require(scene.textLayers.count == 4)
        #expect(scene.textLayers.map(\.text) == ["Through many dangers\ntoils and snares\nQua bao hi\u{1EC3}m nguy\ngian kh\u{00F3} th\u{1EED} th\u{00E1}ch", "'Tis grace has brought me safe thus far", "9:14", "Wrap up"])
        #expect(scene.textLayers[0].style == s.stageCurrent && scene.textLayers[1].style == s.stageNext && scene.textLayers[1].style.color == ColorRGBA(red: 0.35, green: 0.85, blue: 0.55))
        #expect(scene.textLayers[3].style.color == mine.warningColor && scene.textLayers[3].style.fontSize == 64 && scene.textLayers.allSatisfy { !$0.inPlate })
    }

    // MARK: Speaker notes

    @Test func speakerNotesReachOnlyAStageLayoutThatHasANotesElement() {
        let secret = "SPEAKER-NOTE slow down here"
        // The built-in stage layout has no notes element, so even a stage screen does not show them.
        let builtIn = StageComposer.scene(layout: .standard, context: stageContext(notes: secret))
        #expect(!builtIn.textLayers.contains { $0.text.contains("SPEAKER-NOTE") })
        var layout = StageLayout.standard
        layout.elements.append(StageElement(id: UUID(), kind: .notes, frame: NormalizedRect(x: 0.1, y: 0.6, width: 0.8, height: 0.2),
                                            style: TextStyle(fontName: "Helvetica Neue", fontSize: 40, color: .white), alignment: .leading))
        #expect(StageComposer.scene(layout: layout, context: stageContext(notes: secret)).textLayers.contains { $0.text == secret })
        // Audience and broadcast scenes are composed from the show state and a theme alone: there is no way for notes to enter, in any built-in
        // or classic theme, with the band message on the stage the same moment.
        for theme in Theme.builtIn + Theme.classic {
            for role in [ScreenRole.audience, .broadcast] {
                let scene = SceneComposer.scene(for: role, state: state, theme: theme, look: .standard, props: [])
                #expect(!scene.textLayers.contains { $0.text.contains("SPEAKER-NOTE") })
            }
        }
        let band = StageComposer.scene(layout: .standard, context: stageContext(message: "Repeat chorus", notes: secret))
        #expect(band.textLayers.contains { $0.text == "Repeat chorus" })
        for role in [ScreenRole.audience, .broadcast] {
            #expect(!SceneComposer.scene(for: role, state: state, theme: .fullScreen, look: .standard, props: []).textLayers.contains { $0.text == "Repeat chorus" })
        }
    }
}
