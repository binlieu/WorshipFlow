// FIX-W item 5 (OUT, SLIDE; REVIEW-5 M5 and L12): Edit's Broadcast and Stage previews are composed with the screen's own Look and, for the stage, the
// deck's section names, so each is what that screen would draw. The preview scene equals the real screen's scene for the same state.
import Testing
import Foundation
import Domain
import Persistence
@testable import OperatorCore

@MainActor
@Suite struct FIXW_EditPreviewTests {
    let fixed = Date(timeIntervalSinceReferenceDate: 800_000_000)
    let slides = [SlideContent(primary: "One"), SlideContent(primary: "Two"), SlideContent(primary: "Three")]
    let names: [String?] = ["Verse 1", "Chorus", nil]
    let audience = ScreenProfile(name: "Aud", role: .audience, destination: .window)
    let stageScreen = ScreenProfile(name: "Stage", role: .stage, destination: .window)
    let broadcast = ScreenProfile(name: "Stream", role: .broadcast, destination: .window)

    func makeStage() async throws -> StageModel {
        let date = fixed
        let stage = StageModel(store: try LibraryStore.inMemory(), now: { date })
        await stage.load()
        return stage
    }

    func state(index: Int, names: [String?] = []) -> ShowState {
        var state = ShowState()
        state.apply(.load(ShowDeck(presentationID: UUID(), slides: slides, sectionNames: names)))
        state.apply(.trigger(index: index))
        return state
    }

    // MARK: M5: the screen's own Look

    @Test func theBroadcastPreviewUsesTheBroadcastScreensOwnLook() throws {
        let profiles = [audience, stageScreen, broadcast]
        let showLook = Look(id: UUID(), name: "Worship", screens: [broadcast.id: ScreenLook(themeID: nil, visibleLayers: [.slide, .background])])
        let ownLook = Look(id: UUID(), name: "Lower third", screens: [broadcast.id: ScreenLook(themeID: Theme.fullScreen.id, visibleLayers: [.background])])
        let real = PublishedScenes(state: state(index: 1), clockText: nil, profiles: profiles, themes: Theme.builtIn, look: showLook, props: [],
                                   presentationThemeID: nil, screenLooks: [broadcast.id: ownLook]).scene(forScreen: broadcast.id)
        let preview = EditPreviewScene.scene(role: .broadcast, slide: slides[1], profiles: profiles, themes: Theme.builtIn, look: showLook, props: [],
                                             presentationThemeID: nil, media: nil, deck: slides, index: 1, stage: nil, notes: nil,
                                             screenLooks: [broadcast.id: ownLook])
        #expect(preview == real)
        let ignoring = EditPreviewScene.scene(role: .broadcast, slide: slides[1], profiles: profiles, themes: Theme.builtIn, look: showLook, props: [],
                                              presentationThemeID: nil, media: nil, deck: slides, index: 1, stage: nil, notes: nil)
        #expect(preview != ignoring, "the own Look changes what the broadcast screen draws, so the test can tell")
    }

    @Test func theStagePreviewTakesTheStageScreensOwnLookForItsProps() async throws {
        let stage = try await makeStage()
        let profiles = [audience, stageScreen]
        let prop = Prop(name: "Bug", imagePath: "", frame: NormalizedRect(x: 0, y: 0, width: 0.5, height: 0.1), targets: [.stage],
                        kind: .text, text: TextPropSpec(text: "LIVE"))
        let ownLook = Look(id: UUID(), name: "Stage props", screens: [stageScreen.id: ScreenLook(themeID: nil, visibleLayers: [.slide, .props])])
        let showLook = Look(id: UUID(), name: "No props", screens: [stageScreen.id: ScreenLook(themeID: nil, visibleLayers: [.slide])])
        var real = state(index: 0)
        real.apply(.trigger(index: 0))
        let stageScenes = stage.stageScenes(forScreens: [stageScreen.id], state: real, notes: nil)
        let want = PublishedScenes(state: real, clockText: nil, profiles: profiles, themes: Theme.builtIn, look: showLook, props: [prop], presentationThemeID: nil,
                                   stageScenes: stageScenes, screenLooks: [stageScreen.id: ownLook]).scene(forScreen: stageScreen.id)
        let got = EditPreviewScene.scene(role: .stage, slide: slides[0], profiles: profiles, themes: Theme.builtIn, look: showLook, props: [prop],
                                         presentationThemeID: nil, media: nil, deck: slides, index: 0, stage: stage, notes: nil,
                                         screenLooks: [stageScreen.id: ownLook])
        #expect(got == want)
        let ignoring = EditPreviewScene.scene(role: .stage, slide: slides[0], profiles: profiles, themes: Theme.builtIn, look: showLook, props: [prop],
                                              presentationThemeID: nil, media: nil, deck: slides, index: 0, stage: stage, notes: nil)
        #expect(got != ignoring, "the own Look puts the prop on the stage preview, so the test can tell")
    }

    @Test func aScreenWithNoOwnLookStillFollowsTheShowsLook() throws {
        let profiles = [audience, broadcast]
        let showLook = Look(id: UUID(), name: "Worship", screens: [broadcast.id: ScreenLook(themeID: Theme.lowerThird.id, visibleLayers: [.slide])])
        let real = PublishedScenes(state: state(index: 0), clockText: nil, profiles: profiles, themes: Theme.builtIn, look: showLook, props: [],
                                   presentationThemeID: nil).scene(forScreen: broadcast.id)
        let preview = EditPreviewScene.scene(role: .broadcast, slide: slides[0], profiles: profiles, themes: Theme.builtIn, look: showLook, props: [],
                                             presentationThemeID: nil, media: nil, deck: slides, index: 0, stage: nil, notes: nil, screenLooks: [:])
        #expect(preview == real)
    }

    // MARK: L12: section names in the stage preview

    @Test func theStagePreviewDrawsTheSectionAndNextSectionLikeTheRealStageScreen() async throws {
        let stage = try await makeStage()
        let layout = try #require(stage.createLayout(name: "Sections"))
        _ = stage.addElement(.sectionName, to: layout.id)
        _ = stage.addElement(.nextSectionName, to: layout.id)
        stage.setLayout(layout.id, forScreen: stageScreen.id)
        let profiles = [audience, stageScreen]
        let live = state(index: 0, names: names)
        let real = PublishedScenes(state: live, clockText: nil, profiles: profiles,
                                   stageScenes: stage.stageScenes(forScreens: [stageScreen.id], state: live, notes: nil)).scene(forScreen: stageScreen.id)
        let preview = EditPreviewScene.scene(role: .stage, slide: slides[0], profiles: profiles, themes: Theme.builtIn, look: nil, props: [],
                                             presentationThemeID: nil, media: nil, deck: slides, index: 0, stage: stage, notes: nil, sectionNames: names)
        #expect(preview == real)
        let texts = preview.textLayers.map(\.text)
        #expect(texts.contains("Verse 1") && texts.contains("Chorus"), "the section and the next section are drawn: \(texts)")
        let without = EditPreviewScene.scene(role: .stage, slide: slides[0], profiles: profiles, themes: Theme.builtIn, look: nil, props: [],
                                             presentationThemeID: nil, media: nil, deck: slides, index: 0, stage: stage, notes: nil)
        #expect(!without.textLayers.map(\.text).contains("Verse 1"), "the default keeps the old behaviour: no names, nothing drawn")
    }

    @Test func theSectionNamesNeverReachAnAudienceOrBroadcastPreview() throws {
        let profiles = [audience, stageScreen, broadcast]
        for role in [EditPreviewRole.audience, .broadcast] {
            let scene = EditPreviewScene.scene(role: role, slide: slides[0], profiles: profiles, themes: Theme.builtIn, look: nil, props: [],
                                               presentationThemeID: nil, media: nil, deck: slides, index: 0, stage: nil, notes: nil, sectionNames: names)
            #expect(!scene.textLayers.map(\.text).contains { $0.contains("Verse 1") || $0.contains("Chorus") })
        }
    }
}
