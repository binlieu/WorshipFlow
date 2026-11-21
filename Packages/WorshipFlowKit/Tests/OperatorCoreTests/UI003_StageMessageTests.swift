// UI-003 / LIVE-03: the stage message in the model: send, clear, survive slide changes, cleared by Stop, reach stage
// screens only, and the last few kept for reuse.
import Testing
import Foundation
import Domain
import Persistence
@testable import OperatorCore

@MainActor
@Suite struct UI003_StageMessageTests {
    func ready(_ store: LibraryStore? = nil) async throws -> (StageModel, LibraryStore, TestClock) {
        let clock = TestClock()
        let store = try store ?? LibraryStore.inMemory()
        let model = StageModel(store: store, now: { clock.date }, calendar: StageModelTests.utc)
        await model.load()
        return (model, store, clock)
    }

    func liveState() -> ShowState {
        var s = ShowState()
        s.apply(.load(ShowDeck(presentationID: UUID(), slides: [SlideContent(primary: "One"), SlideContent(primary: "Two")])))
        s.apply(.trigger(index: 0))
        return s
    }

    func texts(_ scene: SceneDescription) -> [String] { scene.textLayers.map(\.text) }

    @Test func noMessageToStartWith() async throws {
        let (model, _, _) = try await ready()
        #expect(model.stageMessage == nil && model.recentMessages.isEmpty)
    }

    @Test func sendingShowsItOnAStageScreenAndTellsTheApp() async throws {
        let (model, _, _) = try await ready()
        var changes = 0
        model.onChange = { changes += 1 }
        model.sendMessage("  Wrap up in 2 min  ")
        #expect(model.stageMessage == "Wrap up in 2 min" && changes == 1)
        #expect(texts(model.stageScene(forScreen: UUID(), state: liveState(), notes: nil)).contains("Wrap up in 2 min"))
    }

    @Test func aBlankMessageIsNotSent() async throws {
        let (model, _, _) = try await ready()
        var changes = 0
        model.onChange = { changes += 1 }
        model.sendMessage("   \n ")
        #expect(model.stageMessage == nil && model.recentMessages.isEmpty && changes == 0)
        model.sendMessage("Keep")
        model.sendMessage("  ")
        #expect(model.stageMessage == "Keep")        // a blank send does not clear: Clear does
    }

    @Test func clearRemovesItAndOnlyIt() async throws {
        let (model, _, _) = try await ready()
        model.sendMessage("Hello")
        var changes = 0
        model.onChange = { changes += 1 }
        model.clearStageMessage()
        #expect(model.stageMessage == nil && changes == 1)
        #expect(model.recentMessages == ["Hello"])
        model.clearStageMessage()
        #expect(changes == 1)                         // nothing to clear: nothing published
        #expect(!texts(model.stageScene(forScreen: UUID(), state: liveState(), notes: nil)).contains("Hello"))
    }

    @Test func itSurvivesSlideChanges() async throws {
        let (model, _, _) = try await ready()
        model.sendMessage("Stay")
        var state = liveState()
        for _ in 0..<2 {
            #expect(texts(model.stageScene(forScreen: UUID(), state: state, notes: nil)).contains("Stay"))
            state.apply(.next)
        }
        state.apply(.clear)
        #expect(texts(model.stageScene(forScreen: UUID(), state: state, notes: nil)).contains("Stay"))
    }

    @Test func stopClearsIt() async throws {
        let (model, _, _) = try await ready()
        model.sendMessage("Bye")
        model.showStateChanged(isStopped: false)
        #expect(model.stageMessage == "Bye")
        var changes = 0
        model.onChange = { changes += 1 }
        model.showStateChanged(isStopped: true)
        #expect(model.stageMessage == nil && changes == 1)
        model.showStateChanged(isStopped: true)
        #expect(changes == 1)
    }

    @Test func aMessageSentWhileNothingIsLiveWaitsForTheShow() async throws {
        let (model, _, _) = try await ready()
        model.showStateChanged(isStopped: true)
        model.sendMessage("Early")
        model.showStateChanged(isStopped: true)       // an unchanged state is not a Stop
        #expect(model.stageMessage == "Early")
    }

    @Test func theLastFewAreKeptNewestFirstWithoutDuplicates() async throws {
        let (model, _, _) = try await ready()
        for i in 1...7 { model.sendMessage("m\(i)") }
        #expect(model.recentMessages == ["m7", "m6", "m5", "m4", "m3"])
        model.sendMessage("m5")
        #expect(model.recentMessages == ["m5", "m7", "m6", "m4", "m3"])
    }

    @Test func recentMessagesSurviveARelaunchButTheShownOneDoesNot() async throws {
        let (model, store, _) = try await ready()
        model.sendMessage("One")
        model.sendMessage("Two")
        await model.flush()
        let (again, _, _) = try await ready(store)
        #expect(again.recentMessages == ["Two", "One"])
        #expect(again.stageMessage == nil)
    }

    @Test func aMessageReachesStageScreensOnlyInPublishedScenes() async throws {
        let (model, _, _) = try await ready()
        model.sendMessage("Private to the band")
        let stage = ScreenProfile(name: "Band", role: .stage, destination: .window)
        let aud = ScreenProfile(name: "Hall", role: .audience, destination: .window)
        let brd = ScreenProfile(name: "Stream", role: .broadcast, destination: .window)
        let state = liveState()
        let published = PublishedScenes(state: state, clockText: nil, profiles: [stage, aud, brd],
                                        stageScenes: model.stageScenes(forScreens: [stage.id], state: state, notes: nil))
        #expect(texts(published.scene(forScreen: stage.id)).contains("Private to the band"))
        #expect(!texts(published.scene(forScreen: aud.id)).contains("Private to the band"))
        #expect(!texts(published.scene(forScreen: brd.id)).contains("Private to the band"))
    }

    @Test func aLayoutWithAMessageElementShowsItThereOnce() async throws {
        let (model, _, _) = try await ready()
        let layout = try #require(model.createLayout(name: "Band"))
        _ = model.addElement(.message, to: layout.id)
        model.sendMessage("Once")
        let scene = model.scene(layout: try #require(model.layout(withID: layout.id)), state: liveState(), notes: nil)
        #expect(texts(scene).filter { $0 == "Once" }.count == 1)
    }

    @Test func theTickerKeepsRunningForABannerOnlyWhenThereIsAClockOrTimer() async throws {
        // A message needs a republish when it is sent (onChange), not every second.
        let (model, _, _) = try await ready()
        #expect(model.needsPerSecondRefresh(forScreens: [UUID()]) == true)     // the built-in layout has a clock
    }
}
