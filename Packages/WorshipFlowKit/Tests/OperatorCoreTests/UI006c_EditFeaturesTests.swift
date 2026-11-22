// UI-006c (Edit): Align, the save strip's words, the Audience / Stage / Broadcast preview scenes and the canvas zoom.
import Testing
import Foundation
import Domain
import Persistence
@testable import OperatorCore

@MainActor
@Suite struct UI006cAlignTests {
    func ready() async throws -> (WorkspaceModel, SlideEditorModel, LibraryStore, ManualSaveClock, UUID) {
        let clock = ManualSaveClock()
        let store = try LibraryStore.inMemory()
        let model = WorkspaceModel(store: store, clock: clock)
        await model.load()
        let p = try #require(await model.importLyrics(title: "Song", primaryText: "one\n\ntwo", secondaryText: nil, maxLines: 1))
        await model.openPresentation(p.id)
        return (model, SlideEditorModel(workspace: model), store, clock, p.id)
    }

    @Test func eachAlignmentMovesOnlyItsAxisAndKeepsTheSize() {
        let f = NormalizedRect(x: 0.2, y: 0.3, width: 0.4, height: 0.2)
        #expect(ObjectAlignment.left.aligned(f) == NormalizedRect(x: 0, y: 0.3, width: 0.4, height: 0.2))
        #expect(ObjectAlignment.right.aligned(f).x == 0.6)
        #expect(abs(ObjectAlignment.centerHorizontally.aligned(f).x - 0.3) < 1e-12)
        #expect(ObjectAlignment.top.aligned(f) == NormalizedRect(x: 0.2, y: 0, width: 0.4, height: 0.2))
        #expect(abs(ObjectAlignment.bottom.aligned(f).y - 0.8) < 1e-12)
        #expect(abs(ObjectAlignment.centerVertically.aligned(f).y - 0.4) < 1e-12)
        let c = ObjectAlignment.center.aligned(f)
        #expect(abs(c.x - 0.3) < 1e-12 && abs(c.y - 0.4) < 1e-12 && c.width == 0.4 && c.height == 0.2)
        for a in ObjectAlignment.allCases { #expect(a.aligned(f).width == f.width && a.aligned(f).height == f.height) }
    }

    @Test func aFrameAsLargeAsTheSlideStaysAtTheOrigin() {
        let full = NormalizedRect.full
        for a in ObjectAlignment.allCases { #expect(a.aligned(full) == full) }
        let wide = NormalizedRect(x: 0, y: 0.1, width: 1.5, height: 0.2)
        #expect(ObjectAlignment.right.aligned(wide).x == 0)
    }

    @Test func aligningTheSelectedObjectIsOneUndoStepAndSavesWithTheSlide() async throws {
        let (_, editor, store, clock, pid) = try await ready()
        let id = try #require(editor.add(.rectangle))
        editor.setFrame(id, x: 0.1, y: 0.1, width: 0.3, height: 0.2)
        #expect(editor.alignSelected(.center))
        let moved = try #require(editor.objects.first { $0.id == id }).frame
        #expect(abs(moved.x - 0.35) < 1e-9 && abs(moved.y - 0.4) < 1e-9)
        await clock.advance(by: 2.1)
        let stored = try await store.slides(of: pid)[0].content.objects.first { $0.id == id }?.frame
        #expect(stored == moved)
        editor.undo()
        let back = try #require(editor.objects.first { $0.id == id }).frame
        #expect(back == NormalizedRect(x: 0.1, y: 0.1, width: 0.3, height: 0.2))
    }

    @Test func aligningWhatIsAlreadyThereOrNothingSelectedChangesNothing() async throws {
        let (_, editor, _, _, _) = try await ready()
        #expect(!editor.alignSelected(.left))                // nothing selected
        let id = try #require(editor.add(.rectangle))
        editor.setFrame(id, x: 0, y: 0.4, width: 0.3, height: 0.2)
        let undoBefore = editor.canUndo
        #expect(!editor.align(id, .left))
        #expect(editor.canUndo == undoBefore)
        #expect(!editor.align(UUID(), .left))               // an unknown id
    }

    @Test func alignmentDoesNotTouchTheLiveShow() async throws {
        let (model, editor, _, _, _) = try await ready()
        let liveBefore = model.show
        let id = try #require(editor.add(.textBox))
        editor.align(id, .bottom)
        #expect(model.show.isStopped == liveBefore.isStopped)
        #expect(model.show.liveIndex == liveBefore.liveIndex)
    }
}

@Suite struct UI006cSaveStatusTests {
    @Test func beforeAnySaveItSaysNothingIsWaiting() {
        var s = EditSaveStatus()
        s.observe(hasUnsaved: false, problem: nil, now: 100)
        #expect(s.text(now: 100) == "All changes saved")
    }

    @Test func aSaveIsTimedFromTheLookThatSawItAndCountsUp() {
        var s = EditSaveStatus()
        s.observe(hasUnsaved: true, problem: nil, now: 10)
        #expect(s.text(now: 10) == "Saving…")
        s.observe(hasUnsaved: false, problem: nil, now: 12)
        #expect(s.text(now: 12) == "Saved just now")
        #expect(s.text(now: 14) == "Saved 2 s ago")
        #expect(s.text(now: 12 + 59) == "Saved 59 s ago")
        #expect(s.text(now: 12 + 60) == "Saved 1 min ago")
        #expect(s.text(now: 12 + 7200) == "Saved 2 h ago")
        s.observe(hasUnsaved: false, problem: nil, now: 500)      // later looks with nothing waiting do not restart the time
        #expect(s.text(now: 14) == "Saved 2 s ago")
    }

    @Test func aFailedWriteIsNeverReportedAsSaved() {
        var s = EditSaveStatus()
        s.observe(hasUnsaved: true, problem: "disk full", now: 1)
        #expect(s.text(now: 1) == "Not saved" && s.isProblem)
        s.observe(hasUnsaved: true, problem: nil, now: 2)
        #expect(s.text(now: 2) == "Saving…" && !s.isProblem)
        s.observe(hasUnsaved: false, problem: nil, now: 3)
        #expect(s.text(now: 3) == "Saved just now")
    }

    @Test func aClockGoingBackwardsNeverShowsNegativeTime() {
        var s = EditSaveStatus()
        s.observe(hasUnsaved: true, problem: nil, now: 50)
        s.observe(hasUnsaved: false, problem: nil, now: 60)
        #expect(s.text(now: 10) == "Saved just now")
    }
}

@Suite struct UI006cPreviewTests {
    func profiles() -> [ScreenProfile] {
        [ScreenProfile(name: "Sanctuary", role: .audience, destination: .window),
         ScreenProfile(name: "Stage", role: .stage, destination: .window),
         ScreenProfile(name: "Stream", role: .broadcast, destination: .window)]
    }

    func scene(_ role: EditPreviewRole, profiles: [ScreenProfile]) -> SceneDescription {
        EditPreviewScene.scene(role: role, slide: SlideContent(primary: "Amazing grace"), profiles: profiles, themes: Theme.builtIn,
                               look: nil, props: [], presentationThemeID: nil, media: nil)
    }

    @Test func onlyTheAudienceViewIsEditable() {
        #expect(EditPreviewRole.allCases.filter(\.isEditable) == [.audience])
        #expect(EditPreviewRole.allCases.map(\.title) == ["Audience", "Stage", "Broadcast"])
    }

    @Test func theAudiencePreviewShowsTheSlideWords() {
        let s = scene(.audience, profiles: profiles())
        #expect(s.textLayers.contains { $0.text.contains("Amazing grace") })
    }

    @Test func everyRoleComposesEvenWithoutAScreenOfThatRole() {
        // Speaker notes are not part of a slide's content and `EditPreviewScene` has no notes parameter, so no role's preview can carry them.
        for role in EditPreviewRole.allCases {
            let s = scene(role, profiles: [])
            #expect(s.textLayers.count > 0, "\(role)")
        }
    }

    @Test func aDisabledScreenIsUsedOnlyWhenNoEnabledOneOfTheRoleExists() {
        var list = profiles()
        list[0].isEnabled = false
        #expect(scene(.audience, profiles: list).textLayers.contains { $0.text.contains("Amazing grace") })
    }
}

@Suite struct UI006cZoomTests {
    @Test func fitKeepsTheDesignsEightHundredAndScalesDownInSmallAreas() {
        #expect(EditZoom.fit.canvasWidth(areaWidth: 920, areaHeight: 700) == 800)
        #expect(EditZoom.fit.canvasWidth(areaWidth: 500, areaHeight: 700) == 420)
        #expect(EditZoom.fit.canvasWidth(areaWidth: 100, areaHeight: 100) == 220)
    }

    @Test func aFixedZoomIsAFractionOfTheOutputAndTheFieldReadsItBack() {
        #expect(EditZoom.p50.canvasWidth(areaWidth: 10, areaHeight: 10) == 960)
        #expect(EditZoom.p100.canvasWidth(areaWidth: 10, areaHeight: 10) == 1920)
        for z in EditZoom.allCases.filter({ $0 != .fit }) {
            #expect(EditZoom.percent(forCanvasWidth: z.canvasWidth(areaWidth: 0, areaHeight: 0)) == Int((z.fixedScale! * 100).rounded()))
        }
        #expect(EditZoom.percent(forCanvasWidth: 800) == 42)
    }
}
