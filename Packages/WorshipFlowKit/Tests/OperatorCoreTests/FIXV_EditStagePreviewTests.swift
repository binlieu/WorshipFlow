// FIX-V item 5 (REVIEW-4 M1): Edit's Stage preview drew the built-in Standard layout (no next line, no chosen layout, no Hide or Auto-fit). It is
// now the stage screen's own scene for the same state. Tested by digest: preview scene equals the real stage screen's scene.
import Testing
import Foundation
import Domain
import Persistence
@testable import OperatorCore

@MainActor
@Suite struct FIXV_EditStagePreviewTests {
    let fixed = Date(timeIntervalSinceReferenceDate: 800_000_000)
    let slides = [SlideContent(primary: "One"), SlideContent(primary: "Two"), SlideContent(primary: "Three")]
    let audience = ScreenProfile(name: "Aud", role: .audience, destination: .window)
    let stageScreen = ScreenProfile(name: "Stage", role: .stage, destination: .window)
    let broadcast = ScreenProfile(name: "Stream", role: .broadcast, destination: .window)

    func makeStage() async throws -> StageModel {
        let date = fixed
        let stage = StageModel(store: try LibraryStore.inMemory(), now: { date })
        await stage.load()
        return stage
    }

    /// What the real stage screen draws when `index` is live: the app's publish path.
    func real(_ stage: StageModel, index: Int, notes: String?, profiles: [ScreenProfile]) -> SceneDescription {
        var state = ShowState()
        state.apply(.load(ShowDeck(presentationID: UUID(), slides: slides)))
        state.apply(.trigger(index: index))
        return PublishedScenes(state: state, clockText: nil, profiles: profiles,
                               stageScenes: stage.stageScenes(forScreens: [stageScreen.id], state: state, notes: notes)).scene(forScreen: stageScreen.id)
    }

    func preview(_ stage: StageModel, index: Int, notes: String?, profiles: [ScreenProfile], role: EditPreviewRole = .stage) -> SceneDescription {
        EditPreviewScene.scene(role: role, slide: slides[index], profiles: profiles, themes: Theme.builtIn, look: nil, props: [], presentationThemeID: nil,
                               media: nil, deck: slides, index: index, stage: stage, notes: notes)
    }

    @Test func theStandardLayoutPreviewHasTheNextLineLikeTheRealScreen() async throws {
        let stage = try await makeStage()
        let profiles = [audience, stageScreen]
        let p = preview(stage, index: 1, notes: nil, profiles: profiles)
        #expect(p == real(stage, index: 1, notes: nil, profiles: profiles))
        #expect(p.textLayers.contains { $0.text == "Three" }, "the next slide is drawn")
    }

    @Test func theChosenLayoutIsDrawnNotTheStandardOne() async throws {
        let stage = try await makeStage()
        let layout = try #require(stage.addPreset(.band, named: "Band"))
        stage.setLayout(layout.id, forScreen: stageScreen.id)
        let profiles = [audience, stageScreen]
        let chosen = preview(stage, index: 0, notes: nil, profiles: profiles)
        #expect(chosen == real(stage, index: 0, notes: nil, profiles: profiles))
        let other = ScreenProfile(name: "Other", role: .stage, destination: .window)       // no choice: the built-in layout
        #expect(chosen != preview(stage, index: 0, notes: nil, profiles: [audience, other]), "a stage screen on another layout draws differently")
    }

    @Test func aHiddenNextElementIsHiddenInThePreviewToo() async throws {
        let stage = try await makeStage()
        let layout = try #require(stage.addPreset(.band, named: "Band"))
        stage.setLayout(layout.id, forScreen: stageScreen.id)
        let next = try #require(layout.elements.first { $0.kind == .nextSlide })
        stage.setHidden(true, for: next.id, in: layout.id)
        let profiles = [audience, stageScreen]
        let p = preview(stage, index: 0, notes: nil, profiles: profiles)
        #expect(p == real(stage, index: 0, notes: nil, profiles: profiles))
        #expect(!p.textLayers.contains { $0.text == "Two" }, "no next line")
    }

    @Test func autoFitCarriesOverToThePreview() async throws {
        let stage = try await makeStage()
        let layout = try #require(stage.addPreset(.band, named: "Band"))
        stage.setLayout(layout.id, forScreen: stageScreen.id)
        let current = try #require(layout.elements.first { $0.kind == .currentSlide })
        stage.setAutoFit(true, for: current.id, in: layout.id)
        let profiles = [audience, stageScreen]
        #expect(preview(stage, index: 1, notes: nil, profiles: profiles) == real(stage, index: 1, notes: nil, profiles: profiles))
    }

    @Test func aLayoutWithANotesElementShowsTheNotesOnlyOnTheStagePreview() async throws {
        let stage = try await makeStage()
        let layout = try #require(stage.addPreset(.speaker, named: "Speaker"))
        stage.setLayout(layout.id, forScreen: stageScreen.id)
        let profiles = [audience, stageScreen, broadcast]
        let notes = "Pray before the second verse"
        let p = preview(stage, index: 1, notes: notes, profiles: profiles)
        #expect(p == real(stage, index: 1, notes: notes, profiles: profiles))
        #expect(p.textLayers.contains { $0.text.contains("Pray before") })
        for role in [EditPreviewRole.audience, .broadcast] {
            let other = preview(stage, index: 1, notes: notes, profiles: profiles, role: role)
            #expect(!other.textLayers.contains { $0.text.contains("Pray before") }, "\(role) never carries notes")
        }
    }

    @Test func theEditedSlideIsTheCurrentOneEvenBeforeItIsSaved() async throws {
        let stage = try await makeStage()
        var draft = slides[1]
        draft.primary = "Two, being typed"
        let p = EditPreviewScene.scene(role: .stage, slide: draft, profiles: [audience, stageScreen], themes: Theme.builtIn, look: nil, props: [],
                                       presentationThemeID: nil, media: nil, deck: slides, index: 1, stage: stage, notes: nil)
        #expect(p.textLayers.contains { $0.text == "Two, being typed" } && p.textLayers.contains { $0.text == "Three" })
    }

    @Test func withoutADeckThePreviewIsAOneSlideDeckAsBefore() async throws {
        let stage = try await makeStage()
        let p = EditPreviewScene.scene(role: .stage, slide: slides[1], profiles: [audience, stageScreen], themes: Theme.builtIn, look: nil, props: [],
                                       presentationThemeID: nil, media: nil, deck: nil, index: nil, stage: stage, notes: nil)
        #expect(p.textLayers.contains { $0.text == "Two" } && !p.textLayers.contains { $0.text == "Three" })
    }
}
