// UI-001 Part 1: Blackout in the operator model and key routing.
import Testing
import Foundation
import Domain
import Persistence
@testable import OperatorCore

@Suite struct UI001_BlackoutKeyTests {
    @Test func bIsKeyCode11() {
        #expect(KeyboardKey(keyCode: 11) == .b)
    }

    @Test func bTogglesBlackoutWhenNothingIsBeingTyped() {
        #expect(KeyRouting.decision(for: .b, textInputFocused: false, sheetOpen: false) == .transport(.blackout))
        #expect(KeyRouting.transportCommand(for: .b, textInputFocused: false, sheetOpen: false) == .blackout)
    }

    @Test func bIsTypedTextInAFieldAndNotInASheet() {
        #expect(KeyRouting.decision(for: .b, textInputFocused: true, sheetOpen: false) == .passThrough)
        #expect(KeyRouting.decision(for: .b, textInputFocused: true, searchFieldFocused: true, sheetOpen: false) == .passThrough)
        #expect(KeyRouting.decision(for: .b, textInputFocused: false, sheetOpen: true) == .passThrough)
    }

    @Test func bIsNotBlackoutWithCommandControlOptionOrShift() {
        #expect(KeyRouting.decision(for: .b, textInputFocused: false, sheetOpen: false, commandModifierDown: true) == .passThrough)
        #expect(KeyRouting.decision(for: .b, textInputFocused: false, sheetOpen: false, shiftDown: true) == .passThrough)
    }

    @Test func holdingBDoesNotToggleAgain() {
        #expect(KeyRouting.decision(for: .b, textInputFocused: false, sheetOpen: false, isRepeat: true) == .ignore)
    }
}

@MainActor
@Suite struct UI001_BlackoutModelTests {
    private func liveSong() async throws -> WorkspaceModel {
        let store = try LibraryStore.inMemory()
        let model = WorkspaceModel(store: store)
        await model.load()
        let p = try #require(await model.importLyrics(title: "Song", primaryText: "one\n\ntwo\n\nthree", secondaryText: nil, maxLines: 1))
        await model.openPresentation(p.id)
        await model.goLive()
        return model
    }

    @Test func blackoutTogglesAndTellsTheApp() async throws {
        let model = try await liveSong()
        var notifications = 0
        model.onShowChange = { _ in notifications += 1 }
        model.blackout()
        #expect(model.show.isBlackedOut && notifications == 1)
        #expect(model.show.liveIndex == 0 && model.show.liveDeck != nil)
        model.blackout()
        #expect(model.show.isBlackedOut == false && notifications == 2)
    }

    @Test func nextAndGoLiveLiftIt() async throws {
        let model = try await liveSong()
        model.blackout()
        await model.next()
        #expect(model.show.isBlackedOut == false && model.show.liveIndex == 1)
        model.blackout()
        await model.goLive()
        #expect(model.show.isBlackedOut == false)
    }

    @Test func clearKeepsItAndStopEndsIt() async throws {
        let model = try await liveSong()
        model.blackout()
        model.clear()
        #expect(model.show.isBlackedOut && model.show.isCleared)
        model.stop()
        #expect(model.show.isBlackedOut == false && model.show.isStopped)
    }

    @Test func blackoutAloneChangesWhatTheScreensMustRepublish() async throws {
        let model = try await liveSong()
        var gate = LivePublicationGate()
        let first = gate.shouldPublish(LiveOutputKey(state: model.show, notes: nil))
        let same = gate.shouldPublish(LiveOutputKey(state: model.show, notes: nil))
        model.blackout()
        let on = gate.shouldPublish(LiveOutputKey(state: model.show, notes: nil))
        model.blackout()
        let off = gate.shouldPublish(LiveOutputKey(state: model.show, notes: nil))
        #expect(first && !same && on && off)
    }

    @Test func publishedScenesGoBlackOnAudienceAndTransparentOnBroadcast() async throws {
        let model = try await liveSong()
        model.blackout()
        let audience = ScreenProfile(name: "A", role: .audience, destination: .window)
        let broadcast = ScreenProfile(name: "B", role: .broadcast, destination: .window)
        let scenes = PublishedScenes(state: model.show, clockText: nil, profiles: [audience, broadcast])
        #expect(scenes.scene(forScreen: audience.id) == SceneDescription(backgroundColor: .black, showsVideo: false, textLayers: []))
        #expect(scenes.scene(forScreen: broadcast.id) == SceneDescription(backgroundColor: .clear, showsVideo: false, textLayers: []))
    }
}
