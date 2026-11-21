// STAGE-001b (LIVE-02, SCRN-03): the stage picture follows the timers, and only the stage picture.
import Testing
import Foundation
import Domain
import Persistence
@testable import OperatorCore

@MainActor
@Suite struct StagePublishingTests {
    let secretNotes = "SECRET-NOTES-ONLY-FOR-THE-STAGE"

    func liveState() -> ShowState {
        var state = ShowState()
        let deck = ShowDeck(presentationID: UUID(), slides: [SlideContent(primary: "Amazing grace", secondary: "Ân điển"),
                                                             SlideContent(primary: "How sweet the sound")])
        state.apply(.load(deck))
        state.apply(.trigger(index: 0))
        return state
    }

    func profiles() -> (audience: ScreenProfile, stage: ScreenProfile, broadcast: ScreenProfile) {
        (ScreenProfile(name: "Audience", role: .audience, destination: .window),
         ScreenProfile(name: "Stage", role: .stage, destination: .window),
         ScreenProfile(name: "Broadcast", role: .broadcast, destination: .window))
    }

    /// A stage model with a countdown running and a layout that shows it and the notes, chosen for `screen`.
    func setup(screen: UUID, clock: TestClock) async throws -> (StageModel, ShowTimer) {
        let model = StageModel(store: try LibraryStore.inMemory(), now: { clock.date }, calendar: StageModelTests.utc)
        await model.load()
        let layout = try #require(model.createLayout(name: "Band"))
        let timer = try #require(model.addCountdown(name: "Sermon", minutes: 10, seconds: 0))
        _ = model.addElement(.timer, to: layout.id, timerID: timer.id)
        _ = model.addElement(.notes, to: layout.id)
        model.setLayout(layout.id, forScreen: screen)
        model.startTimer(timer.id)
        return (model, timer)
    }

    func publish(_ model: StageModel, state: ShowState, notes: String?, p: (audience: ScreenProfile, stage: ScreenProfile, broadcast: ScreenProfile)) -> PublishedScenes {
        PublishedScenes(state: state, clockText: nil, profiles: [p.audience, p.stage, p.broadcast],
                        stageScenes: model.stageScenes(forScreens: [p.stage.id], state: state, notes: notes))
    }

    func texts(_ scene: SceneDescription) -> [String] { scene.textLayers.map(\.text) }

    @Test func thePublishedStageSceneChangesWhenATimerValueChanges() async throws {
        let p = profiles()
        let clock = TestClock()
        let (model, _) = try await setup(screen: p.stage.id, clock: clock)
        let first = publish(model, state: liveState(), notes: nil, p: p)
        #expect(texts(first.scene(forScreen: p.stage.id)).contains("10:00"))
        clock.advance(1)
        let second = publish(model, state: liveState(), notes: nil, p: p)
        #expect(texts(second.scene(forScreen: p.stage.id)).contains("9:59"))
        #expect(first != second)                                                    // the app republishes: the snapshot differs
        #expect(first.scene(forScreen: p.stage.id) != second.scene(forScreen: p.stage.id))
        #expect(texts(first.scene(forScreen: p.stage.id)).contains("10:00"))        // the old snapshot is untouched
        #expect(first.scene(forScreen: p.audience.id) == second.scene(forScreen: p.audience.id))
    }

    @Test func aSecondWithNoVisibleChangeProducesAnEqualSnapshot() async throws {
        let p = profiles()
        let clock = TestClock()
        let model = StageModel(store: try LibraryStore.inMemory(), now: { clock.date }, calendar: StageModelTests.utc)
        await model.load()
        let a = publish(model, state: liveState(), notes: nil, p: p)
        clock.advance(1)                                                            // built-in layout, clock without seconds
        let b = publish(model, state: liveState(), notes: nil, p: p)
        #expect(a == b)                                                             // the app can skip republishing
        model.setClockStyle(showsSeconds: true)
        let c = publish(model, state: liveState(), notes: nil, p: p)
        clock.advance(1)
        #expect(publish(model, state: liveState(), notes: nil, p: p) != c)          // with seconds on, every second differs
    }

    @Test func overrunTimerIsDrawnInTheWarningColour() async throws {
        let p = profiles()
        let clock = TestClock()
        let (model, timer) = try await setup(screen: p.stage.id, clock: clock)
        let layout = model.layout(forScreen: p.stage.id)
        clock.advance(601)
        let scene = publish(model, state: liveState(), notes: nil, p: p).scene(forScreen: p.stage.id)
        let layer = try #require(scene.textLayers.first { $0.text == "-0:01" })
        #expect(layer.style.color == layout.warningColor)
        _ = timer
    }

    @Test func stageShowsNotesButAudienceAndBroadcastNeverShowNotesOrTimers() async throws {
        let p = profiles()
        let clock = TestClock()
        let (model, _) = try await setup(screen: p.stage.id, clock: clock)
        let published = publish(model, state: liveState(), notes: secretNotes, p: p)
        let stage = texts(published.scene(forScreen: p.stage.id))
        #expect(stage.contains(secretNotes) && stage.contains("10:00"))
        for screen in [p.audience, p.broadcast] {
            let text = texts(published.scene(forScreen: screen.id)).joined(separator: "\n")
            #expect(!text.contains(secretNotes))
            #expect(!text.contains("10:00") && !text.contains("9:5") && !text.contains("Sermon"))
            #expect(text.contains("Amazing grace"))                                   // they do show the slide
        }
        // Also with a timer running and notes present at every step of the service.
        var state = liveState()
        state.apply(.next)
        clock.advance(30)
        let later = publish(model, state: state, notes: secretNotes, p: p)
        for screen in [p.audience, p.broadcast] {
            let text = texts(later.scene(forScreen: screen.id)).joined(separator: "\n")
            #expect(!text.contains(secretNotes) && !text.contains("9:30"))
        }
    }

    @Test func aStageScreenWithoutAnEntryFallsBackToTheBuiltInScene() throws {
        let p = profiles()
        let state = liveState()
        let published = PublishedScenes(state: state, clockText: "9:00", profiles: [p.stage])
        #expect(published.scene(forScreen: p.stage.id) == SceneComposer.scene(for: .stage, state: state, clockText: "9:00"))
    }

    @Test func theBuiltInLayoutThroughTheModelMatchesTheBuiltInStageScene() async throws {
        let model = StageModel(store: try LibraryStore.inMemory(), now: { Date(timeIntervalSinceReferenceDate: 0) },
                               calendar: StageModelTests.utc)
        await model.load()
        let state = liveState()
        let ours = model.stageScene(forScreen: UUID(), state: state, notes: nil)
        #expect(ours == SceneComposer.scene(for: .stage, state: state, clockText: "12:00 AM"))
    }

    // MARK: Notes of the live slide

    @Test func theLiveSlidesNotesReachTheStageAndFollowTheSlide() async throws {
        let store = try LibraryStore.inMemory()
        let workspace = WorkspaceModel(store: store)
        await workspace.load()
        #expect(workspace.liveNotes == nil)
        _ = await workspace.createPresentation(title: "Song")
        await workspace.addSlide(SlideContent(primary: "One"))
        await workspace.addSlide(SlideContent(primary: "Two"))
        await workspace.updateSlide(at: 0, content: SlideContent(primary: "One"), notes: "Notes for one")
        await workspace.updateSlide(at: 1, content: SlideContent(primary: "Two"), notes: "   ")
        #expect(workspace.liveNotes == nil)                                         // nothing live yet
        workspace.goLive(at: 0)
        #expect(workspace.liveNotes == "Notes for one")
        await workspace.next()
        #expect(workspace.liveNotes == nil)                                         // blank notes are no notes
        workspace.selectSlide(0)
        workspace.goLive(at: 0)
        workspace.clear()
        #expect(workspace.liveNotes == nil)                                         // cleared hides everything
        workspace.goLive(at: 0)
        workspace.stop()
        #expect(workspace.liveNotes == nil)
    }
}
