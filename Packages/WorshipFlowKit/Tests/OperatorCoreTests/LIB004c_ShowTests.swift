// LIB-004c item 3: a passage in the centre pane behaves as a song does. Choosing a slide is preview only; Go Live, Next and
// Previous go through the one command path; Next at the last slide stays.
import Testing
import Foundation
import Domain
import CueEngine
import CueStore
import Persistence
import ScriptureEngine
@testable import OperatorCore

@MainActor
@Suite struct LIB004c_ShowTests {
    func cue(_ r: L4C.Rig) -> CueModel {
        let fake = FakeShow()
        let model = CueModel(store: CueStore(library: r.store), ports: CuePorts(transport: r.workspace, looks: fake, stage: fake, media: fake, midiOut: { fake }),
                             clock: TestCueClock())
        model.connect(r.workspace)
        return model
    }

    @Test func showingAPassageFillsPreviewOnlyAndLeavesLiveAlone() async throws {
        let r = try await L4C.rig()
        let song = try #require(await r.workspace.importLyrics(title: "A", primaryText: "a1\n\na2", secondaryText: nil, maxLines: 1))
        await r.workspace.openPresentation(song.id)
        await r.workspace.goLive()
        let liveBefore = r.workspace.show.liveSlide
        let deckBefore = r.workspace.show.liveDeck
        #expect(liveBefore?.primary == "a1")

        await r.scripture.show("Psalm 23:1-3")
        let passage = try #require(r.scripture.passage)
        #expect(r.workspace.show.previewDeck?.slides == passage.contents)
        #expect(r.workspace.show.liveDeck == deckBefore && r.workspace.show.liveSlide == liveBefore)
        #expect(r.workspace.openScripture?.title == passage.title)
    }

    @Test func selectingAScriptureSlideChangesPreviewOnlyNeverLive() async throws {
        let r = try await L4C.rig()
        let song = try #require(await r.workspace.importLyrics(title: "A", primaryText: "a1\n\na2", secondaryText: nil, maxLines: 1))
        await r.workspace.openPresentation(song.id)
        await r.workspace.goLive()
        await r.scripture.show("Psalm 23:1-3")
        r.scripture.selectSlide(2)
        #expect(r.workspace.show.selectedIndex == 2)
        #expect(r.workspace.show.liveSlide?.primary == "a1" && r.workspace.show.liveIndex == 0)
        #expect(r.workspace.show.liveDeck?.slides.map(\.primary) == ["a1", "a2"])
    }

    @Test func selectingASlideWithNothingLiveGoesNowhere() async throws {
        let r = try await L4C.rig()
        await r.scripture.show("Psalm 23:1-3")
        r.scripture.selectSlide(1)
        #expect(r.workspace.show.selectedIndex == 1)
        #expect(r.workspace.show.liveDeck == nil && r.workspace.show.liveIndex == nil)
    }

    @Test func goLiveThenNextWalksThePassageThroughTheSharedCommandPath() async throws {
        let r = try await L4C.rig()
        let commands = cue(r)
        await r.scripture.show("Psalm 23:1-3")
        let passage = try #require(r.scripture.passage)
        r.scripture.selectSlide(0)
        _ = await commands.run(.goLive, from: .button)
        #expect(r.workspace.show.liveIndex == 0 && r.workspace.show.liveSlide == passage.contents[0])
        _ = await commands.run(.transport(.next), from: .key)
        #expect(r.workspace.show.liveIndex == 1 && r.workspace.show.liveSlide == passage.contents[1])
        _ = await commands.run(.transport(.next), from: .midi)
        #expect(r.workspace.show.liveIndex == 2)
        _ = await commands.run(.transport(.previous), from: .remote)
        #expect(r.workspace.show.liveIndex == 1)
        #expect(r.workspace.livePositionLine?.contains("slide 2 of 3") == true, "\(String(describing: r.workspace.livePositionLine))")
    }

    @Test func nextPastTheLastSlideStaysAndSaysNothingAlarming() async throws {
        let r = try await L4C.rig()
        let commands = cue(r)
        await r.scripture.show("Psalm 23:1-3")
        r.scripture.selectSlide(2)
        _ = await commands.run(.goLive, from: .button)
        _ = await commands.run(.transport(.next), from: .key)
        _ = await commands.run(.transport(.next), from: .key)
        #expect(r.workspace.show.liveIndex == 2 && r.workspace.show.liveSlide != nil)
        #expect(r.workspace.lastError == nil)
    }

    @Test func nextWithNothingLiveTakesTheFirstSlideLiveAsForASong() async throws {
        let r = try await L4C.rig()
        await r.scripture.show("Psalm 23:1-3")
        await r.workspace.next()
        #expect(r.workspace.show.liveIndex == 0)
        #expect(r.workspace.livePositionLine != nil)
    }

    @Test func clearAndStopWorkOnAPassageToo() async throws {
        let r = try await L4C.rig()
        await r.scripture.show("Psalm 23:1-3")
        await r.workspace.goLive()
        r.workspace.clear()
        #expect(r.workspace.show.isCleared && r.workspace.show.liveDeck != nil)
        r.workspace.stop()
        #expect(r.workspace.show.liveDeck == nil && r.workspace.livePositionLine == nil)
        #expect(r.workspace.show.previewDeck != nil, "preview keeps the passage")
    }

    @Test func openingASongAfterwardsLeavesThePassageLiveAndClosesThePassageView() async throws {
        let r = try await L4C.rig()
        await r.scripture.show("Psalm 23:1-3")
        await r.workspace.goLive()
        let song = try #require(await r.workspace.importLyrics(title: "A", primaryText: "a1\n\na2", secondaryText: nil, maxLines: 1))
        await r.workspace.openPresentation(song.id)
        #expect(r.workspace.openScripture == nil)
        #expect(r.workspace.show.liveDeck?.slides.count == 3)
    }

    @Test func aPassageCanBeEditedOnlyAfterItIsSavedAsAPresentation() async throws {
        let r = try await L4C.rig()
        await r.scripture.show("Psalm 23:1-3")
        #expect(r.workspace.slides.isEmpty && r.workspace.openPresentationID == nil)
        await r.workspace.addSlide(SlideContent(primary: "x"))     // nothing to add to: no write, no crash
        #expect(r.workspace.openScripture != nil)
    }
}
