// FIX-O (KI-180): a change to one part of the show state, the slide list or the media layers notifies only the readers of that part.
// Counted with `withObservationTracking`: one tracker per part, each reads only its part; after a change the set of trackers that fired
// is compared with the set the change is supposed to reach.
import Testing
import Foundation
import Observation
import Domain
import Persistence
@testable import OperatorCore

final class FIXO_Flag: @unchecked Sendable { var fired = false }

@MainActor
enum FIXO {
    /// Reads `part` under its own tracker, runs `change`, and says whether the tracker fired.
    static func parts<Part: Hashable>(_ readers: [Part: () -> Void], after change: () -> Void) -> Set<Part> {
        var flags: [Part: FIXO_Flag] = [:]
        for (part, read) in readers {
            let flag = FIXO_Flag()
            flags[part] = flag
            withObservationTracking(read) { flag.fired = true }
        }
        change()
        return Set(flags.filter { $0.value.fired }.keys)
    }

    static func deck(_ id: UUID = UUID(), _ count: Int = 6, prefix: String = "Line") -> ShowDeck {
        ShowDeck(presentationID: id, slides: (0..<count).map { SlideContent(primary: "\(prefix) \($0)") })
    }
}

enum ShowPart: String, CaseIterable, Hashable {
    case selectedIndex, liveIndex, isStopped, liveDeckID, liveDeck, previewDeck, isCleared, isBlackedOut, isBackgroundCleared, hasLiveWords, liveSlide, whole
}

@MainActor
@Suite struct FIXO_ShowPartsTests {
    func readers(_ show: ObservedShow) -> [ShowPart: () -> Void] {
        [.selectedIndex: { _ = show.selectedIndex }, .liveIndex: { _ = show.liveIndex }, .isStopped: { _ = show.isStopped },
         .liveDeckID: { _ = show.liveDeckID }, .liveDeck: { _ = show.liveDeck }, .previewDeck: { _ = show.previewDeck },
         .isCleared: { _ = show.isCleared }, .isBlackedOut: { _ = show.isBlackedOut }, .isBackgroundCleared: { _ = show.isBackgroundCleared },
         .hasLiveWords: { _ = show.hasLiveWords }, .liveSlide: { _ = show.liveSlide }, .whole: { _ = show.state }]
    }

    /// A show with a six-slide preview, live at slide 1.
    func rig() -> ObservedShow {
        let show = ObservedShow()
        let deck = FIXO.deck()
        show.apply(.load(deck))
        show.apply(.trigger(index: 1))
        return show
    }

    func reached(_ show: ObservedShow, _ command: ShowCommand) -> Set<ShowPart> {
        FIXO.parts(readers(show)) { show.apply(command) }
    }

    @Test func selectingMovesOnlyTheSelection() {
        let show = rig()
        #expect(reached(show, .select(index: 4)) == [.selectedIndex, .whole])
    }

    @Test func nextMovesTheLivePlaceAndThePreviewSelectionAndNothingElse() {
        let show = rig()
        // The live words change with the place (liveSlide), but "are there words" (hasLiveWords) and which deck is live do not.
        #expect(reached(show, .next) == [.liveIndex, .selectedIndex, .liveSlide, .whole])
        #expect(reached(show, .previous) == [.liveIndex, .selectedIndex, .liveSlide, .whole])
    }

    @Test func aRefreshOfThePreviewDeckTouchesOnlyThePreviewDeck() {
        let show = rig()
        var edited = FIXO.deck(show.previewDeck?.presentationID ?? UUID(), 6, prefix: "Edited")
        edited.slides[0].primary = "Changed"
        let fresh = ShowDeck(presentationID: show.current.previewDeck!.presentationID, slides: edited.slides)
        #expect(reached(show, .restore(deck: fresh, selectedIndex: 1)) == [.previewDeck, .whole])
    }

    @Test func clearBlackoutAndClearBackgroundEachTouchOnlyTheirOwnPart() {
        let show = rig()
        #expect(reached(show, .clear) == [.isCleared, .hasLiveWords, .liveSlide, .whole])
        #expect(reached(show, .blackout) == [.isBlackedOut, .whole])
        #expect(reached(show, .clearBackground) == [.isBackgroundCleared, .whole])
        #expect(reached(show, .liftHolds) == [.isCleared, .isBlackedOut, .isBackgroundCleared, .hasLiveWords, .liveSlide, .whole])
    }

    @Test func aQuickEditTouchesTheLiveDeckAndThePreviewDeckButNotThePlace() {
        let show = rig()
        let edit = ShowCommand.quickEdit(index: 1, content: SlideContent(primary: "Live fix"))
        #expect(reached(show, edit) == [.liveDeck, .previewDeck, .liveSlide, .whole])
    }

    @Test func goingLiveAndStoppingTouchWhatTheyChange() {
        let show = ObservedShow()
        show.apply(.load(FIXO.deck()))
        #expect(reached(show, .trigger(index: 2)) == [.selectedIndex, .liveIndex, .isStopped, .liveDeckID, .liveDeck, .hasLiveWords, .liveSlide, .whole])
        #expect(reached(show, .stop) == [.liveIndex, .isStopped, .liveDeckID, .liveDeck, .hasLiveWords, .liveSlide, .whole])
    }

    @Test func aCommandThatChangesNothingNotifiesNoOne() {
        let show = rig()
        #expect(reached(show, .select(index: 99)).isEmpty)                  // out of range: ignored
        #expect(reached(show, .select(index: show.selectedIndex)).isEmpty)  // the same place
        #expect(reached(show, .restoreBackground).isEmpty)
        let stopped = ObservedShow()
        #expect(reached(stopped, .blackout).isEmpty && reached(stopped, .clear).isEmpty)       // ignored while nothing is live
    }

    @Test func triggeringTheSamePreviewDeckAgainDoesNotTouchTheLiveDeck() {
        let show = rig()
        // Taking the preview deck live again at the place it is already live at changes nothing a reader of the live deck sees.
        #expect(reached(show, .trigger(index: 1)).isEmpty)
        // At another place it moves the place (and the selection), but the live deck itself is the same value.
        #expect(reached(show, .trigger(index: 3)) == [.selectedIndex, .liveIndex, .liveSlide, .whole])
    }
}

@MainActor
@Suite struct FIXO_SettledStateTests {
    /// A fixed pseudo-random command sequence: the recorded sequence the old path (the plain value) and the new path (the observed parts)
    /// both replay.
    func recorded(_ count: Int) -> [ShowCommand] {
        var seed: UInt64 = 0x9E3779B97F4A7C15
        func next(_ bound: Int) -> Int { seed = seed &* 6364136223846793005 &+ 1442695040888963407; return Int((seed >> 33) % UInt64(bound)) }
        let id = UUID(), other = UUID()
        var out: [ShowCommand] = []
        for _ in 0..<count {
            switch next(14) {
            case 0: out.append(.load(FIXO.deck(id, 3 + next(6))))
            case 1: out.append(.select(index: next(8)))
            case 2: out.append(.trigger(index: next(8)))
            case 3, 4: out.append(.next)
            case 5: out.append(.previous)
            case 6: out.append(.clear)
            case 7: out.append(.clearAll)
            case 8: out.append(.blackout)
            case 9: out.append(.clearBackground)
            case 10: out.append(.restoreBackground)
            case 11: out.append(next(3) == 0 ? .stop : .liftHolds)
            case 12: out.append(.quickEdit(index: next(6), content: SlideContent(primary: "Q\(next(100))")))
            default: out.append(.restore(deck: FIXO.deck(next(2) == 0 ? id : other, 2 + next(7), prefix: "R"), selectedIndex: next(8)))
            }
        }
        return out
    }

    @Test func theObservedPartsSettleToExactlyTheStateTheValueReaches() {
        let observed = ObservedShow()
        var plain = ShowState()
        for command in recorded(600) {
            plain.apply(command)
            observed.apply(command)
            #expect(observed.current == plain)
            #expect(observed.state == plain)
            #expect(observed.selectedIndex == plain.selectedIndex && observed.liveIndex == plain.liveIndex)
            #expect(observed.isStopped == plain.isStopped && observed.isCleared == plain.isCleared)
            #expect(observed.isBlackedOut == plain.isBlackedOut && observed.isBackgroundCleared == plain.isBackgroundCleared)
            #expect(observed.liveDeck == plain.liveDeck && observed.previewDeck == plain.previewDeck && observed.liveDeckID == plain.liveDeck?.presentationID)
            #expect(observed.liveSlide == plain.liveSlide && observed.liveSlideAtPlace == plain.liveSlideAtPlace && observed.nextSlide == plain.nextSlide)
            #expect(observed.hasLiveWords == (plain.liveSlide != nil))
            if observed.current != plain { return }
        }
    }

    @Test func aSetThatSkipsCommandsStillSettlesExactly() {
        // `set` takes a whole state: any state, not only one a single command reaches.
        let observed = ObservedShow()
        var plain = ShowState()
        for (i, command) in recorded(300).enumerated() {
            plain.apply(command)
            if i % 7 == 0 { observed.set(plain); #expect(observed.current == plain && observed.liveSlide == plain.liveSlide) }
        }
    }

    @Test func theWorkspaceSettlesToTheSameStateAsTheValueAndPublishesEachChange() async throws {
        let store = try LibraryStore.inMemory()
        let model = WorkspaceModel(store: store, clock: ManualSaveClock())
        await model.load()
        var published: [ShowState] = []
        model.onShowChange = { published.append($0) }
        var plain = ShowState()
        for command in recorded(300) {
            plain.apply(command)
            model.apply(command)
            #expect(model.show == plain)
            #expect(model.showParts.current == plain)
            #expect(published.last == plain)
        }
        #expect(published.count == 300)
    }
}

@MainActor
@Suite struct FIXO_SlideListTests {
    enum Part: Hashable { case all, count, isEmpty, order, slide0, slide2, slide5 }

    func readers(_ list: ObservedSlideList) -> [Part: () -> Void] {
        [.all: { _ = list.all }, .count: { _ = list.count }, .isEmpty: { _ = list.isEmpty }, .order: { _ = list.order },
         .slide0: { _ = list.slide(at: 0) }, .slide2: { _ = list.slide(at: 2) }, .slide5: { _ = list.slide(at: 5) }]
    }
    func list(_ n: Int = 6) -> ObservedSlideList {
        let presentation = UUID()
        let list = ObservedSlideList()
        list.set((0..<n).map { Slide(presentationID: presentation, sortOrder: $0, content: SlideContent(primary: "Line \($0)")) })
        return list
    }

    @Test func editingOneSlideReachesTheListAndThatSlideOnly() {
        let list = list()
        var slides = list.current
        slides[2].content.primary = "Edited"
        let reached = FIXO.parts(readers(list)) { list.set(slides) }
        #expect(reached == [.all, .slide2])
    }

    @Test func addingASlideReachesTheCountTheOrderAndTheListAndEveryReaderOfAPosition() {
        let list = list()
        var slides = list.current
        slides.append(Slide(presentationID: slides[0].presentationID, sortOrder: 6, content: SlideContent(primary: "New")))
        let reached = FIXO.parts(readers(list)) { list.set(slides) }
        #expect(reached == [.all, .count, .order, .slide0, .slide2, .slide5])         // a position's reader depends on the order
    }

    @Test func movingASlideReachesTheOrderAndTheSlidesThatShiftedButNotTheCount() {
        let list = list()
        var moved = list.current
        let slide = moved.remove(at: 5); moved.insert(slide, at: 0)
        for i in moved.indices { moved[i].sortOrder = i }
        let reached = FIXO.parts(readers(list)) { list.set(moved) }
        #expect(reached == [.all, .order, .slide0, .slide2, .slide5])       // every position between moved; the count did not
    }

    @Test func emptyingTheListReachesIsEmptyAndWritingTheSameListNotifiesNoOne() {
        let list = list()
        #expect(FIXO.parts(readers(list)) { list.set(list.current) }.isEmpty)
        let reached = FIXO.parts(readers(list)) { list.set([]) }
        #expect(reached == [.all, .count, .isEmpty, .order, .slide0, .slide2, .slide5])
    }

    @Test func aWorkspaceEditReachesTheEditedSlideAndNotTheOthers() async throws {
        let store = try LibraryStore.inMemory()
        let model = WorkspaceModel(store: store, clock: ManualSaveClock())
        await model.load()
        let text = (1...8).map { "Line \($0)" }.joined(separator: "\n\n")
        let p = try #require(await model.importLyrics(title: "Song", primaryText: text, secondaryText: nil, maxLines: 1))
        await model.openPresentation(p.id)
        let target = model.slides[5]
        let reached = FIXO.parts(readers(model.slideList)) {
            var content = target.content; content.primary = "Typed"
            model.editSlide(id: target.id, content: content)
        }
        #expect(reached == [.all, .slide5])
        #expect(model.slides[5].content.primary == "Typed" && model.slideList.slide(at: 5)?.content.primary == "Typed")
    }
}

@MainActor
@Suite struct FIXO_LayerPartsTests {
    enum Part: Hashable { case background, foreground, both }
    func readers(_ layers: ObservedLayers) -> [Part: () -> Void] {
        [.background: { _ = layers.background }, .foreground: { _ = layers.foreground }, .both: { _ = layers.layers }]
    }
    let clip = MediaSelection(assetID: UUID(), kind: .video, duration: 10)
    let still = MediaSelection(assetID: UUID(), kind: .image, duration: nil)

    @Test func eachLayerNotifiesOnlyItsOwnReaders() {
        let layers = ObservedLayers()
        var next = layers.current
        next.setBackground(still, at: 0)
        #expect(FIXO.parts(readers(layers)) { layers.set(next) } == [.background, .both])
        next.startForeground(clip, at: 1)
        #expect(FIXO.parts(readers(layers)) { layers.set(next) } == [.foreground, .both])
        next.pauseForeground(at: 2)                                                     // the transport of the clip moved
        #expect(FIXO.parts(readers(layers)) { layers.set(next) } == [.foreground, .both])
        next.stopForeground()
        #expect(FIXO.parts(readers(layers)) { layers.set(next) } == [.foreground, .both])
        #expect(FIXO.parts(readers(layers)) { layers.set(next) }.isEmpty)               // nothing changed
    }

    @Test func theMediaModelKeepsTheSameLayersAsBefore() async throws {
        let store = try LibraryStore.inMemory()
        let media = MediaModel(store: store, prober: FakeProber(), isAvailable: { _ in true })
        #expect(media.layers == MediaLayers() && media.layerParts.current == MediaLayers())
        #expect(media.hasLiveBackgroundOverride == false)
    }
}

@MainActor
@Suite struct FIXO_WorkspacePartsTests {
    enum Part: Hashable { case slides, playlist, selectedIndex, previewDeck, liveIndex, isStopped, liveDeck, holds, openPresentation }

    func rig() async throws -> WorkspaceModel {
        let store = try LibraryStore.inMemory()
        let model = WorkspaceModel(store: store, clock: ManualSaveClock())
        await model.load()
        let text = (1...12).map { "Line \($0)" }.joined(separator: "\n\n")
        let p = try #require(await model.importLyrics(title: "Song", primaryText: text, secondaryText: nil, maxLines: 1))
        await model.openPresentation(p.id)
        await model.addToPlaylist(p.id)
        return model
    }
    func readers(_ m: WorkspaceModel) -> [Part: () -> Void] {
        [.slides: { _ = m.slides }, .playlist: { _ = m.playlistItems }, .selectedIndex: { _ = m.showParts.selectedIndex },
         .previewDeck: { _ = m.showParts.previewDeck }, .liveIndex: { _ = m.showParts.liveIndex }, .isStopped: { _ = m.showParts.isStopped },
         .liveDeck: { _ = m.showParts.liveDeck }, .holds: { _ = m.showParts.isCleared; _ = m.showParts.isBlackedOut; _ = m.showParts.isBackgroundCleared },
         .openPresentation: { _ = m.openPresentationID }]
    }

    @Test func selectingASlideReachesOnlyTheSelection() async throws {
        let model = try await rig()
        #expect(FIXO.parts(readers(model)) { model.selectSlide(5) } == [.selectedIndex])
    }

    @Test func typingIntoAnInactiveSlideReachesTheSlidesAndThePreviewDeckAndNeverTheLiveShow() async throws {
        let model = try await rig()
        model.goLive(at: 2)
        let liveBefore = model.showParts.current.liveDeck, indexBefore = model.showParts.current.liveIndex
        let target = model.slides[8]
        let reached = FIXO.parts(readers(model)) {
            var content = target.content; content.primary = "Typed over there"
            model.editSlide(id: target.id, content: content)
        }
        #expect(reached == [.slides, .previewDeck])
        #expect(model.showParts.current.liveDeck == liveBefore && model.showParts.current.liveIndex == indexBefore)   // Live is unchanged by an edit
    }

    /// Reads every part under its own tracker, runs the async `change`, and returns the parts that fired.
    func reachedBy(_ model: WorkspaceModel, _ change: () async -> Void) async -> Set<Part> {
        var fired: [Part: FIXO_Flag] = [:]
        for (part, read) in readers(model) { let flag = FIXO_Flag(); fired[part] = flag; withObservationTracking(read) { flag.fired = true } }
        await change()
        return Set(fired.filter { $0.value.fired }.keys)
    }

    @Test func aSlideReorderReachesTheSlidesAndThePreviewDeckButNotThePlaylistOrTheLiveShow() async throws {
        let model = try await rig()
        model.goLive(at: 2)
        let liveBefore = model.showParts.current.liveDeck
        let reached = await reachedBy(model) { await model.moveSlide(from: 9, to: 4) }
        #expect(reached == [.slides, .previewDeck])
        #expect(model.showParts.current.liveDeck == liveBefore && model.showParts.current.liveIndex == 2)
    }

    @Test func goingLiveNeverTouchesTheSlideListOrThePlaylistOrThePreviewDeck() async throws {
        let model = try await rig()
        let reached = await reachedBy(model) { model.goLive(at: 2) }
        #expect(reached == [.selectedIndex, .liveIndex, .isStopped, .liveDeck])
    }

    @Test func nextMovesOnlyTheLivePlaceAndTheSelection() async throws {
        let model = try await rig()
        model.goLive(at: 2)
        let reached = await reachedBy(model) { await model.next() }
        #expect(reached == [.liveIndex, .selectedIndex])
    }

    @Test func aPlaylistReorderReachesThePlaylistAndNothingOfTheShowOrTheSlides() async throws {
        let model = try await rig()
        let song = try #require(model.presentations.first)
        await model.addToPlaylist(song.id)
        await model.addToPlaylist(song.id)
        let first = try #require(model.playlistItems.first)
        let reached = await reachedBy(model) { await model.movePlaylistItem(id: first.id, to: 2) }
        #expect(reached == [.playlist])
    }

    @Test func blackoutAndClearReachOnlyTheirHoldsWhileLive() async throws {
        let model = try await rig()
        model.goLive(at: 2)
        #expect(await reachedBy(model) { model.blackout() } == [.holds])
        #expect(await reachedBy(model) { model.blackout() } == [.holds])
        #expect(await reachedBy(model) { model.clear() } == [.holds])
    }
}
