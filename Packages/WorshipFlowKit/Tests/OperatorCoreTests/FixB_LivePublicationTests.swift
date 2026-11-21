// FIX-B R15: typing must not republish the live scenes when nothing live changed.
import Testing
import Foundation
import Domain
import Persistence
@testable import OperatorCore

@MainActor
@Suite struct LivePublicationTests {
    /// What the app does for every change of `show`: ask the gate, and publish only when it says so.
    @MainActor final class Recorder {
        var notifications = 0
        var publications = 0
        var gate = LivePublicationGate()
        func attach(to model: WorkspaceModel) {
            model.onShowChange = { [unowned self, unowned model] _ in
                notifications += 1
                if gate.shouldPublish(LiveOutputKey(state: model.show, notes: model.liveNotes)) { publications += 1 }
            }
        }
    }

    private func liveSong(slides: Int = 6) async throws -> (WorkspaceModel, Recorder) {
        let store = try LibraryStore.inMemory()
        let model = WorkspaceModel(store: store)
        await model.load()
        let text = (1...slides).map { "line \($0)" }.joined(separator: "\n\n")
        let p = try #require(await model.importLyrics(title: "Song", primaryText: text, secondaryText: nil, maxLines: 1))
        await model.openPresentation(p.id)
        await model.goLive()
        let recorder = Recorder()
        recorder.attach(to: model)
        _ = recorder.gate.shouldPublish(LiveOutputKey(state: model.show, notes: model.liveNotes))   // the publish that went live
        return (model, recorder)
    }

    @Test func typingInASlideThatIsNotLiveRepublishesNothing() async throws {
        let (model, recorder) = try await liveSong()
        let target = model.slides[3].id
        for i in 1...20 { model.editSlide(id: target, content: SlideContent(primary: String(repeating: "x", count: i))) }
        #expect(recorder.notifications == 20)           // the preview changed every time ...
        #expect(recorder.publications == 0)             // ... and the screens were not touched
    }

    @Test func typingInTheLiveSlideInPreviewStillLeavesTheScreensAlone() async throws {
        let (model, recorder) = try await liveSong()
        let live = model.slides[0].id
        for i in 1...5 { model.editSlide(id: live, content: SlideContent(primary: "edit \(i)")) }
        #expect(recorder.publications == 0)             // PRES-07: only a quick edit changes what is on screen
        #expect(model.show.liveSlide?.primary == "line 1")
    }

    @Test func movingThePreviewSelectionRepublishesNothing() async throws {
        let (model, recorder) = try await liveSong()
        model.selectSlide(4)
        model.selectSlide(2)
        #expect(recorder.publications == 0)
    }

    @Test func everythingThatChangesTheScreensStillRepublishes() async throws {
        let (model, recorder) = try await liveSong()
        await model.next()
        #expect(recorder.publications == 1)
        await model.previous()
        #expect(recorder.publications == 2)
        model.clear()
        #expect(recorder.publications == 3)
        model.stop()
        #expect(recorder.publications == 4)
        await model.goLive()
        #expect(recorder.publications == 5)
        await model.quickEditLiveSlide(SlideContent(primary: "changed on air"))
        #expect(recorder.publications == 6)
    }

    @Test func speakerNotesOfTheLiveSlideStillReachTheStageScreen() async throws {
        let (model, recorder) = try await liveSong()
        model.editSlide(id: model.slides[0].id, content: model.slides[0].content, notes: "sing it softly")
        #expect(model.liveNotes == "sing it softly")
        #expect(recorder.publications == 1)             // the stage shows the live slide's notes
        model.editSlide(id: model.slides[0].id, content: model.slides[0].content, notes: "sing it softly!")
        #expect(recorder.publications == 2)
        model.editSlide(id: model.slides[2].id, content: SlideContent(primary: "other"), notes: "not live")
        #expect(recorder.publications == 2)
    }

    @Test func theFirstChangeAlwaysPublishes() {
        var gate = LivePublicationGate()
        let first = gate.shouldPublish(LiveOutputKey(state: ShowState(), notes: nil))
        let second = gate.shouldPublish(LiveOutputKey(state: ShowState(), notes: nil))
        #expect(first && !second)
    }
}
