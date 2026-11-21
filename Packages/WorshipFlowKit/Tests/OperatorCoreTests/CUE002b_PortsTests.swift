// CUE-002b items 1 and 2: the real models behind the cue ports, and the "a slide went live" signal slide actions hang on.
import Testing
import Foundation
import Domain
import Persistence
import CueEngine
@testable import OperatorCore

@MainActor
@Suite struct CUE002b_PortsTests {
    let song = "Verse 1\nOne line\n\nChorus\nTwo line\n\nEnding\nThree line"

    func ready() async throws -> (WorkspaceModel, LibraryStore) {
        let store = try LibraryStore.inMemory()
        let model = WorkspaceModel(store: store)
        await model.load()
        let p = try #require(await model.importLyrics(title: "Song", primaryText: song, secondaryText: nil, maxLines: 2))
        await model.openPresentation(p.id)
        #expect(model.slides.count == 3)
        return (model, store)
    }

    @Test func nextAndPreviousStayInsideTheDeckUntilItsEnds() async throws {
        let (w, _) = try await ready()
        #expect(w.nextIfInDeck())                              // nothing live: the first slide goes live
        #expect(w.show.liveIndex == 0)
        #expect(w.previousIfInDeck() == false)                 // at the start: crossing back needs the playlist
        #expect(w.show.liveIndex == 0)
        #expect(w.nextIfInDeck() && w.nextIfInDeck())
        #expect(w.show.liveIndex == 2)
        #expect(w.nextIfInDeck() == false)                     // at the end
        #expect(w.show.liveIndex == 2)
        #expect(w.previousIfInDeck() && w.show.liveIndex == 1)
    }

    @Test func goToSlideTakesTheOpenSongLiveAtThatSlideOrSaysWhyNot() async throws {
        let (w, _) = try await ready()
        try w.goToSlide(1)
        #expect(w.show.liveIndex == 1)
        #expect(throws: CueTargetError.self) { try w.goToSlide(3) }
        #expect(throws: CueTargetError.self) { try w.goToSlide(-1) }
        #expect(w.show.liveIndex == 1)
    }

    @Test func goToSlideRefusesWhenAnotherSongIsOnScreen() async throws {
        let (w, _) = try await ready()
        try w.goToSlide(0)
        let other = try #require(await w.importLyrics(title: "Other", primaryText: "A\nB", secondaryText: nil, maxLines: 2))
        await w.openPresentation(other.id)
        #expect(throws: CueTargetError.self) { try w.goToSlide(0) }
        #expect(w.show.liveDeck?.presentationID != other.id)
    }

    @Test func aSlideWentLiveSignalFiresForTriggerAndNextButNotForPreviewOrClear() async throws {
        let (w, _) = try await ready()
        var events: [SlideLiveEvent] = []
        w.onSlideWentLive = { events.append($0) }
        w.selectSlide(1)
        #expect(events.isEmpty)                                // preview only
        w.goLive(at: 1)
        #expect(events.map(\.index) == [1])
        _ = w.nextIfInDeck()
        #expect(events.map(\.index) == [1, 2])
        w.clear()
        w.blackout()
        #expect(events.count == 2)                             // clear and blackout are not "a slide went live"
        w.apply(.quickEdit(index: 2, content: SlideContent(primary: "Changed")))
        #expect(events.count == 2)                             // a quick edit is not either
    }

    @Test func theLiveSlideIdIsGivenOnlyWhileTheEventStillDescribesTheLiveSlide() async throws {
        let (w, _) = try await ready()
        var event: SlideLiveEvent?
        w.onSlideWentLive = { event = $0 }
        w.goLive(at: 2)
        let e = try #require(event)
        #expect(w.liveSlideID(for: e) == w.slides[2].id)
        _ = w.previousIfInDeck()
        #expect(w.liveSlideID(for: e) == nil)                  // the show moved on
    }

    @Test func settingsStageAndMediaPortsAnswerFromTheirModels() async throws {
        let store = try LibraryStore.inMemory()
        let settings = SettingsModel(store: store, defaultProfiles: { [] })
        await settings.load()
        let look = try #require(settings.looks.first)
        #expect(settings.hasLook(look.id) && !settings.hasLook(UUID()) && !settings.hasProp(UUID()))
        let stage = StageModel(store: store)
        await stage.load()
        let timer = try #require(stage.addElapsed(name: "Service"))
        #expect(stage.hasTimer(timer.id) && !stage.hasTimer(UUID()))
        stage.startTimer(timer.id)
        #expect(stage.timers.first { $0.id == timer.id }?.isRunning == true)
        stage.sendMessage("Hello")
        #expect(stage.stageMessage == "Hello")
    }
}
