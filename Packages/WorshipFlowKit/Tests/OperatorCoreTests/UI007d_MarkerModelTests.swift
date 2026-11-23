// UI-007d (MEDIA, CUE-33): markers of a clip, the observer that watches a live clip's position, and the one command path that runs a marker's
// actions. A fake scheduler (it only records start and stop), a hand-moved clock and an in-memory library: no timer, no wall clock, no player.
// Written before the implementation.
import Testing
import Foundation
import CueEngine
import CueStore
import Domain
import Persistence
@testable import OperatorCore

/// Records when the observer is started and stopped; the test calls the handler itself.
@MainActor
final class FakeMarkerScheduler: MarkerScheduling {
    private(set) var isRunning = false
    private(set) var starts = 0
    private(set) var stops = 0
    private(set) var interval: TimeInterval?
    private var handler: (@MainActor () -> Void)?
    func start(interval: TimeInterval, _ handler: @escaping @MainActor () -> Void) {
        guard !isRunning else { return }
        isRunning = true; starts += 1; self.interval = interval; self.handler = handler
    }
    func stop() {
        guard isRunning else { return }
        isRunning = false; stops += 1; handler = nil
    }
    func fire() { handler?() }
}

@MainActor
final class MarkerRig {
    let media: MediaRig
    let scheduler = FakeMarkerScheduler()
    let markers: MediaMarkerModel
    var fired: [MarkerFiring] = []
    var override: ((MediaLayerSlot) -> PlaybackSample?)?

    init() throws {
        media = try MediaRig()
        let scheduler = self.scheduler
        markers = MediaMarkerModel(store: media.store, media: media.model, scheduler: scheduler, sample: nil, fire: { _ in })
        markers.setFire { [unowned self] in fired.append($0) }
    }

    /// A video of 10 s with a marker at each of `times` (by default none).
    func clip(_ name: String = "clip.mov", markers times: [Double] = []) async -> MediaAsset {
        let asset = await media.add(name)
        for t in times { _ = await markers.add(to: asset.id, at: t) }
        return asset
    }
}

@MainActor
@Suite struct UI007d_MarkerModelTests {
    @Test func markersAreAddedAtTheplayheadMovedRenamedAndDeletedAndListedInTimeOrder() async throws {
        let rig = try MarkerRig()
        let clip = await rig.clip()
        let b = try #require(await rig.markers.add(to: clip.id, at: 6, name: "Fade out"))
        let a = try #require(await rig.markers.add(to: clip.id, at: 2))
        #expect(rig.markers.markers(for: clip.id).map(\.id) == [a.id, b.id])
        await rig.markers.move(a.id, to: 8)
        #expect(rig.markers.markers(for: clip.id).map(\.id) == [b.id, a.id])
        await rig.markers.rename(a.id, to: "  Lower third on ")
        #expect(rig.markers.markers(for: clip.id).last?.name == "Lower third on")
        await rig.markers.delete(b.id)
        #expect(rig.markers.markers(for: clip.id).map(\.id) == [a.id])
        // what the library holds is what is shown
        #expect(try await rig.media.store.mediaMarkers(forAsset: clip.id).map(\.id) == [a.id])
        #expect(rig.media.model.lastError == nil)
    }

    @Test func aMarkerOutsideTheClipIsRefusedWithWords() async throws {
        let rig = try MarkerRig()
        let clip = await rig.clip()
        #expect(await rig.markers.add(to: clip.id, at: 11) == nil)       // the clip is 10 s long
        #expect(rig.media.model.lastError != nil && rig.markers.markers(for: clip.id).isEmpty)
        rig.media.model.dismissError()
        let m = try #require(await rig.markers.add(to: clip.id, at: 3))
        await rig.markers.move(m.id, to: -1)
        #expect(rig.markers.markers(for: clip.id).first?.time == 3 && rig.media.model.lastError != nil)
    }

    @Test func markersComeBackAfterARelaunch() async throws {
        let rig = try MarkerRig()
        let clip = await rig.clip(markers: [1, 2])
        let again = MediaMarkerModel(store: rig.media.store, media: rig.media.model, scheduler: FakeMarkerScheduler(), sample: nil, fire: { _ in })
        await again.syncAssets([clip])
        #expect(again.markers(for: clip.id).map(\.time) == [1, 2])
    }

    @Test func aMarkersActionsAreStoredAsTheCueActionsAndAnActionThatMovesTheShowIsRefused() async throws {
        let rig = try MarkerRig()
        let clip = await rig.clip()
        let m = try #require(await rig.markers.add(to: clip.id, at: 3))
        let look = UUID()
        #expect(await rig.markers.setActions([.selectLook(look), .stopForeground], for: m.id) == nil)
        #expect(rig.markers.actions(of: m.id) == [.selectLook(look), .stopForeground])
        #expect(rig.media.model.lastError == nil)
        let why = await rig.markers.setActions([.transport(.next)], for: m.id)        // a marker could advance the show on every pass of a loop
        #expect(rig.markers.actions(of: m.id) == [.selectLook(look), .stopForeground])
        #expect(try #require(why).contains("cannot move the show"))
        // a macro that holds a move is refused too
        let macro = Macro(name: "Advance", steps: [.transport(.next)])
        let library = MacroLibrary(unvalidated: [macro])
        #expect(await rig.markers.setActions([.runMacro(macro.id)], for: m.id, macros: library)?.contains("cannot run the macro") == true)
    }

    // MARK: The observer

    @Test func nothingTicksWhileIdleOrForAClipWithoutMarkers() async throws {
        let rig = try MarkerRig()
        let bare = await rig.clip("bare.mov")
        let marked = await rig.clip("marked.mov", markers: [4])
        rig.media.model.showStateChanged(isLive: true)
        #expect(!rig.scheduler.isRunning && rig.scheduler.starts == 0)
        rig.media.model.playForeground(bare.id)
        #expect(!rig.scheduler.isRunning)
        rig.media.model.stopForeground()
        rig.media.model.playForeground(marked.id)
        #expect(rig.scheduler.isRunning && rig.scheduler.starts == 1)
        rig.media.model.stopForeground()
        #expect(!rig.scheduler.isRunning && rig.scheduler.stops == 1)
    }

    @Test func theObserverRunsOnlyWhileAClipWithMarkersPlaysLive() async throws {
        let rig = try MarkerRig()
        let marked = await rig.clip(markers: [4])
        rig.media.model.setBackground(marked.id)
        #expect(!rig.scheduler.isRunning)                          // screens stopped: not live
        rig.media.model.showStateChanged(isLive: true)
        #expect(rig.scheduler.isRunning)
        rig.media.model.pauseBackground()
        #expect(!rig.scheduler.isRunning)                          // paused: nothing is moving
        rig.media.model.resumeBackground()
        #expect(rig.scheduler.isRunning)
        rig.media.model.showStateChanged(isLive: false)
        #expect(!rig.scheduler.isRunning)
    }

    @Test func addingTheFirstMarkToAPlayingClipStartsTheObserverAndDeletingTheLastStopsIt() async throws {
        let rig = try MarkerRig()
        let clip = await rig.clip()
        rig.media.model.showStateChanged(isLive: true)
        rig.media.model.playForeground(clip.id)
        #expect(!rig.scheduler.isRunning)
        let m = try #require(await rig.markers.add(to: clip.id, at: 5))
        #expect(rig.scheduler.isRunning)
        await rig.markers.delete(m.id)
        #expect(!rig.scheduler.isRunning)
    }

    @Test func aClipThatEndedStopsTheObserver() async throws {
        let rig = try MarkerRig()
        let clip = await rig.clip(markers: [4])
        rig.media.model.showStateChanged(isLive: true)
        rig.media.model.playForeground(clip.id)
        #expect(rig.scheduler.isRunning)
        rig.media.clock.advance(11)
        #expect(rig.media.model.tick())
        #expect(!rig.scheduler.isRunning)
    }

    @Test func thePreviewPlayerNeverStartsTheObserverOrFiresAMarker() async throws {
        let rig = try MarkerRig()
        let clip = await rig.clip(markers: [1])
        let preview = MediaPreviewModel(player: FakePreviewPlayer(), silent: true)
        preview.select(clip)
        preview.togglePlay()
        rig.media.model.showStateChanged(isLive: true)             // a show is live, the clip is only previewed
        rig.markers.tick()
        #expect(!rig.scheduler.isRunning && rig.fired.isEmpty)
    }

    // MARK: Firing

    @Test func aMarkerFiresOnceWhenTheLiveClipCrossesItAndAtNoOtherTime() async throws {
        let rig = try MarkerRig()
        let clip = await rig.clip("Baptism testimony.mov", markers: [4])
        let id = try #require(rig.markers.markers(for: clip.id).first?.id)
        await rig.markers.setActions([.stopForeground], for: id)
        rig.media.model.showStateChanged(isLive: true)
        rig.media.model.playForeground(clip.id)
        rig.markers.tick()
        #expect(rig.fired.isEmpty)
        rig.media.clock.advance(3.9)
        rig.markers.tick()
        #expect(rig.fired.isEmpty)
        rig.media.clock.advance(0.2)                                // 4.1 s in
        rig.markers.tick()
        #expect(rig.fired.count == 1)
        let f = try #require(rig.fired.first)
        #expect(f.markerID == id && f.clipName == "Baptism testimony" && f.time == 4 && f.actions == [.stopForeground])
        rig.media.clock.advance(1)
        rig.markers.tick(); rig.markers.tick()
        #expect(rig.fired.count == 1)
    }

    @Test func markInIsHonouredSoAMarkerBeforeItNeverFiresAndOneAtItFiresAtTheStart() async throws {
        let rig = try MarkerRig()
        let clip = await rig.clip(markers: [1, 3, 8])
        await rig.media.model.setMarkIn(3, for: clip.id)
        await rig.media.model.setMarkOut(6, for: clip.id)
        rig.media.model.showStateChanged(isLive: true)
        rig.media.model.playForeground(clip.id)
        rig.markers.tick()
        #expect(rig.fired.map(\.time) == [3])                       // at the in mark, when the clip starts
        rig.media.clock.advance(2.9)
        rig.markers.tick()
        #expect(rig.fired.map(\.time) == [3])                       // 1 is before the in mark, 8 is after the out mark: never
    }

    @Test func aMarkerDoesNotFireWhenTheOperatorSeeksOverItButDoesWhenPlayedPastItAgain() async throws {
        let rig = try MarkerRig()
        let clip = await rig.clip(markers: [4, 8])
        rig.media.model.showStateChanged(isLive: true)
        rig.media.model.playForeground(clip.id)
        rig.markers.tick()
        rig.media.model.seek(to: 6)                                 // jumps over 4
        rig.markers.tick()
        #expect(rig.fired.isEmpty)
        rig.media.clock.advance(2.1)                                // 8.1 s: the next marker fires
        rig.markers.tick()
        #expect(rig.fired.map(\.time) == [8])
        rig.media.model.seek(to: 1)
        rig.markers.tick()
        rig.media.clock.advance(3.2)                                // 4.2 s: crossing 4 again counts
        rig.markers.tick()
        #expect(rig.fired.map(\.time) == [8, 4])
    }

    @Test func aBackgroundLoopFiresEachMarkerOncePerPass() async throws {
        let rig = try MarkerRig()
        let clip = await rig.clip(markers: [4])
        await rig.media.model.setMarkIn(2, for: clip.id)
        await rig.media.model.setMarkOut(6, for: clip.id)           // a pass is 4 s
        rig.media.model.showStateChanged(isLive: true)
        rig.media.model.setBackground(clip.id)
        for _ in 0..<3 {
            rig.markers.tick()
            rig.media.clock.advance(2.1); rig.markers.tick()        // crosses 4
            rig.media.clock.advance(1.9); rig.markers.tick()        // the pass ends and the next begins
        }
        #expect(rig.fired.count == 3)
    }

    @Test func nothingFiresForAClipThatIsNotLive() async throws {
        let rig = try MarkerRig()
        let clip = await rig.clip(markers: [1])
        rig.media.model.setBackground(clip.id)                      // chosen, the screens are stopped
        rig.media.clock.advance(2)
        rig.markers.tick()
        #expect(rig.fired.isEmpty)
    }

    @Test func aTestPositionCanBeInjectedInPlaceOfTheModelsOwnClock() async throws {
        let rig = try MarkerRig()
        let clip = await rig.clip(markers: [5])
        var position = 0.0
        rig.markers.setSample { [clip] slot in
            slot == .foreground ? PlaybackSample(assetID: clip.id, epoch: 1, seekCount: 0, position: position, loopCount: 0, isPlaying: true,
                                                 rangeStart: 0, rangeEnd: 10) : nil
        }
        rig.media.model.showStateChanged(isLive: true)
        rig.media.model.playForeground(clip.id)
        for p in [0.0, 4.9, 5.0, 5.1] { position = p; rig.markers.tick() }
        #expect(rig.fired.count == 1)
    }
}

// MARK: One command path

@MainActor
@Suite struct UI007d_MarkerCommandPathTests {
    func make() throws -> (CueModel, FakeShow, CueStore) {
        let show = FakeShow()
        let library = try LibraryStore.inMemory()
        let store = CueStore(library: library)
        let model = CueModel(store: store, ports: CuePorts(transport: show, looks: show, stage: show, media: show, midiOut: { show }), clock: TestCueClock())
        return (model, show, store)
    }

    func firing(_ actions: [CueAction], name: String? = "Lower third on") -> MarkerFiring {
        MarkerFiring(assetID: UUID(), clipName: "Baptism testimony", markerID: UUID(), markerName: name, time: 12.5, actions: actions)
    }

    @Test func aMarkersActionsRunThroughTheOneCommandPathAndShowInActivity() async throws {
        let (model, show, _) = try make()
        let timer = UUID(); show.timers = [timer]
        model.submit(.markerReached(firing([.startTimer(timer)])), from: .marker)
        await model.settled()
        #expect(show.log == ["timer start"])
        let line = try #require(model.activity.first)
        #expect(line.source == .marker && !line.isProblem)
        #expect(line.text.contains("Lower third on") && line.text.contains("Baptism testimony") && line.text.contains("00:12.5"))
        #expect(CommandSource.marker.label == "marker")
    }

    @Test func aMarkerWaitsItsTurnBehindACommandThatIsAlreadyRunning() async throws {
        let (model, show, _) = try make()
        let timer = UUID(); show.timers = [timer]
        model.submit(.goLive, from: .button)
        model.submit(.markerReached(firing([.startTimer(timer)])), from: .marker)
        model.submit(.transport(.next), from: .midi)
        await model.settled()
        #expect(show.log == ["goLive begin", "goLive end", "timer start", "next begin", "next end"])
    }

    @Test func aMarkerThatHoldsAnActionThatMovesTheShowIsNotRunAndSaysWhy() async throws {
        let (model, show, _) = try make()
        model.submit(.markerReached(firing([.transport(.next)])), from: .marker)
        await model.settled()
        #expect(show.log.isEmpty)
        let line = try #require(model.activity.last)
        #expect(line.isProblem && line.text.contains("cannot move the show"))
    }

    @Test func aMarkerThatRunsAMacroWithAMoveInItIsNotRunEither() async throws {
        let (model, show, store) = try make()
        let macro = Macro(name: "Advance", steps: [.transport(.next)])
        try await store.saveMacro(macro)
        await model.reload()
        model.submit(.markerReached(firing([.runMacro(macro.id)])), from: .marker)
        await model.settled()
        #expect(show.log.isEmpty && model.activity.last?.isProblem == true)
    }

    @Test func aMarkerWithNoActionsRunsNothingAndSaysNothingWentWrong() async throws {
        let (model, show, _) = try make()
        model.submit(.markerReached(firing([])), from: .marker)
        await model.settled()
        #expect(show.log.isEmpty && model.notices.isEmpty)
    }

    @Test func aMarkerCanBeRefusedWhileTheHardwareTestRuns() async throws {
        let (model, show, _) = try make()
        model.hardwareTestIsRunning = { true }
        model.submit(.markerReached(firing([.stopForeground])), from: .marker)
        await model.settled()
        #expect(show.log.isEmpty)
        #expect(model.activity.last?.isProblem == true)
    }

    @Test func theMarkerActionEditorOffersWhatASlideActionOffersAndNoMovesOfTheShow() {
        for kind in CueActionKind.allCases {
            #expect(CueActionEditing.isAllowed(kind, in: .marker) == !kind.isTransport)
        }
    }

    @Test func aFiringModelWiredToTheCueModelRunsTheMarkersActions() async throws {
        let rig = try MarkerRig()
        let (cue, show, _) = try make()
        rig.markers.setFire { cue.submit(.markerReached($0), from: .marker) }
        let timer = UUID(); show.timers = [timer]
        let clip = await rig.clip(markers: [2])
        let id = try #require(rig.markers.markers(for: clip.id).first?.id)
        await rig.markers.setActions([.startTimer(timer)], for: id)
        rig.media.model.showStateChanged(isLive: true)
        rig.media.model.playForeground(clip.id)
        rig.markers.tick()
        rig.media.clock.advance(2.1)
        rig.markers.tick()
        await cue.settled()
        #expect(show.log == ["timer start"])
        #expect(cue.activity.first?.source == .marker)
    }
}
