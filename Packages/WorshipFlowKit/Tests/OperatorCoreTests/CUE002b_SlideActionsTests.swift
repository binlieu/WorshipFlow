// CUE-002b item 2: slide actions fire when their slide goes live, through the one command path; the warning before a re-flow.
import Testing
import Foundation
import Domain
import Persistence
import CueEngine
import CueStore
@testable import OperatorCore

@MainActor
@Suite struct CUE002b_SlideActionsTests {
    let song = "Verse 1\nOne line\n\nChorus\nTwo line\n\nEnding\nThree line"

    struct Rig {
        var workspace: WorkspaceModel
        var cue: CueModel
        var show: FakeShow
        var store: CueStore
        var library: LibraryStore
        var look: UUID
    }

    func rig() async throws -> Rig {
        let library = try LibraryStore.inMemory()
        let workspace = WorkspaceModel(store: library)
        await workspace.load()
        let p = try #require(await workspace.importLyrics(title: "Song", primaryText: song, secondaryText: nil, maxLines: 2))
        await workspace.openPresentation(p.id)
        let show = FakeShow()
        let look = UUID()
        show.looks = [look]
        let store = CueStore(library: library)
        let cue = CueModel(store: store, ports: CuePorts(transport: workspace, looks: show, stage: show, media: show, midiOut: { show }),
                           clock: TestCueClock())
        cue.connect(workspace)
        await cue.reload()
        return Rig(workspace: workspace, cue: cue, show: show, store: store, library: library, look: look)
    }

    @Test func aSlideActionRunsWhenItsSlideGoesLiveAndNotBefore() async throws {
        let r = try await rig()
        try await r.cue.setSlideActions([.selectLook(r.look)], for: r.workspace.slides[1].id)
        r.workspace.selectSlide(1)
        await r.cue.settled()
        #expect(r.show.log.isEmpty)                                     // preview only
        r.workspace.goLive(at: 1)
        await r.cue.settled()
        #expect(r.show.log == ["look \(r.look.uuidString.prefix(4))"])
    }

    @Test func nextRunsTheActionsOfTheSlideItLandsOn() async throws {
        let r = try await rig()
        try await r.cue.setSlideActions([.selectLook(r.look)], for: r.workspace.slides[1].id)
        r.cue.submit(.goLive, from: .key)                               // slide 0
        r.cue.submit(.transport(.next), from: .midi)                    // slide 1
        r.cue.submit(.transport(.next), from: .remote)                  // slide 2: none
        await r.cue.settled()
        #expect(r.show.log == ["look \(r.look.uuidString.prefix(4))"])
        #expect(r.cue.activity.contains { $0.source == .slideAction })
    }

    @Test func aQuickEditAndAClearDoNotRunSlideActions() async throws {
        let r = try await rig()
        try await r.cue.setSlideActions([.selectLook(r.look)], for: r.workspace.slides[0].id)
        r.workspace.selectSlide(0)
        r.workspace.goLive(at: 0)
        await r.cue.settled()
        r.show.log.removeAll()
        r.workspace.apply(.quickEdit(index: 0, content: SlideContent(primary: "Edited")))
        r.workspace.clear()
        await r.cue.settled()
        #expect(r.show.log.isEmpty)
    }

    @Test func aSlideActionCannotMoveTheShow() async throws {
        let r = try await rig()
        try? await r.cue.setSlideActions([.transport(.next)], for: r.workspace.slides[0].id)
        #expect(r.cue.lastError?.contains("cannot move the show") == true)
        #expect(r.cue.slideActions.actions(for: r.workspace.slides[0].id).isEmpty)
    }

    @Test func aMacroWithATransportIsRefusedAsASlideAction() async throws {
        let r = try await rig()
        let macro = Macro(name: "Moves", steps: [.transport(.next)])
        try await r.store.saveMacro(macro)
        await r.cue.reload()
        try? await r.cue.setSlideActions([.runMacro(macro.id)], for: r.workspace.slides[0].id)
        #expect(r.cue.lastError?.contains("Moves") == true)
    }

    @Test func aSlideActionRunsAfterTheCommandThatTookTheSlideLiveAndBeforeTheNextOne() async throws {
        let r = try await rig()
        try await r.cue.setSlideActions([.selectLook(r.look)], for: r.workspace.slides[0].id)
        r.cue.submit(.goLive, from: .button)                            // slide 0: its action comes next
        let timer = UUID()
        r.show.timers = [timer]
        r.cue.submit(.runActions([.startTimer(timer)], .operatorTrigger), from: .midi)
        await r.cue.settled()
        #expect(r.show.log == ["look \(r.look.uuidString.prefix(4))", "timer start"])
    }

    @Test func aReflowReloadsTheActionsSoTheyFollowTheirSlides() async throws {
        let r = try await rig()
        let id = try #require(r.workspace.openPresentationID)
        let kept = r.workspace.slides[1].content.primary
        try await r.cue.setSlideActions([.selectLook(r.look)], for: r.workspace.slides[1].id)
        let ok = await r.workspace.reflowPresentation(id: id, primaryText: song.replacingOccurrences(of: "One line", with: "Uno line"),
                                                      secondaryText: nil, maxLines: 2)
        #expect(ok)
        await r.cue.settled()
        await r.cue.reloadSettled()
        let moved = try #require(r.workspace.slides.first { $0.content.primary == kept })
        #expect(r.cue.slideActions.actions(for: moved.id) == [.selectLook(r.look)])
    }

    @Test func theReflowWarningCountsTheActionsOnSlidesWhoseWordsChange() async throws {
        let r = try await rig()
        let id = try #require(r.workspace.openPresentationID)
        try await r.cue.setSlideActions([.selectLook(r.look), .stopForeground], for: r.workspace.slides[0].id)
        let changed = Reflow.contents(primary: song.replacingOccurrences(of: "One line", with: "Uno line"), secondary: nil, maxLines: 2)
        let losses = await r.workspace.reflowSlideActionLosses(id: id, results: changed)
        #expect(losses.count == 1 && losses.first?.actionCount == 2)
        let same = Reflow.contents(primary: song, secondary: nil, maxLines: 2)
        #expect(await r.workspace.reflowSlideActionLosses(id: id, results: same).isEmpty)
    }
}
