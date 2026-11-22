// FIX-Q: what the slide grid's own body must not read, from the source (a view body's run count cannot be seen from a unit test; the running-app
// numbers come from scripts/fixq-run.sh and are in AI/reports/FIX-Q-report.md).
import Testing
import Foundation

@Suite struct FIXQ_ViewSourceTests {
    private func root() -> URL {
        var url = URL(fileURLWithPath: #filePath)
        for _ in 0..<5 { url.deleteLastPathComponent() }
        return url
    }
    private func source(_ name: String) throws -> String { try String(contentsOf: root().appendingPathComponent("App/Sources/\(name)"), encoding: .utf8) }

    @Test func theGridsOwnBodyReadsNeitherTheSelectionTheLivePlaceNorTheMode() throws {
        let text = try source("CentrePane.swift")
        let start = try #require(text.range(of: "struct SlideGrid: View"))
        let end = try #require(text.range(of: "/// FIX-I item 6: the background entries"))
        let grid = String(text[start.lowerBound..<end.lowerBound])
        for pattern in ["selectedIndex", "liveIndex", "app.mode", "liveDeckID", "isSelected(at", "isLive(at", "liveMode: LiveMode"] {
            // The one place the selection is read is the scroll helper, a view of its own (it is above `struct SlideGrid`, so not in this slice).
            #expect(!grid.contains(pattern), "SlideGrid reads `\(pattern)`: Next, Previous or a selection would run the grid's body and walk all its cells")
        }
        #expect(text.contains("private struct ScrollToSelection: View"))
        #expect(text.contains("mode: live == i ? liveMode : .live"), "FIX-O's guard text stays in the source (as a comment, now that the cell decides it)")
    }

    @Test func eachCellAsksForItsOwnMarks() throws {
        let cell = try source("SlideGridCell.swift")
        #expect(cell.contains("showParts.isSelected(at: index)"))
        #expect(cell.contains("showParts.isLive(at: index)"))
        #expect(!cell.contains("let selected: Bool") && !cell.contains("let live: Bool"), "the cell takes no selection or live value from the grid")
    }

    @Test func theSlideActionsListWorksOutTheChosenSlideOnceNotPerRow() throws {
        let text = try source("CuesEditors.swift")
        let start = try #require(text.range(of: "private var slideList: some View"))
        let list = String(text[start.lowerBound...].prefix(900))
        #expect(list.contains("let chosenID = chosenSlide?.id"))
        #expect(!list.contains("chosenSlide?.id == slide.id"))
    }

    @Test func theMediaControllerRowTheCueCardAndTheSoundRowsTickOnlyWhileSomethingPlays() throws {
        // A timeline that ticks ten times a second with nothing to show made SwiftUI update the whole window ten times a second (about 16 ms of the
        // main thread each, with a 200-slide grid on screen): measured in FIX-Q as 110 ms of main-thread CPU per 0.7 s idle in Show, 7 ms without it.
        let dock = try source("MediaDockView.swift")
        #expect(dock.contains("TickingWhile(active: hasSource, every: 0.1)"))
        #expect(!dock.contains("TimelineView(.periodic(from: .now, by: 0.1))"))
        #expect(dock.contains("MediaController.pick(foregroundLoaded: media.layerParts.foreground != nil, currentAudioCue: audio?.currentID"))
        #expect(try source("MediaAudioColumn.swift").contains("TickingWhile(active: audio.currentID != nil, every: 0.1)"))
        #expect(try source("AudioPanel.swift").contains("TickingWhile(active: audio.isActive(asset.id), every: 0.1)"))
        let controls = try source("WFControls.swift")
        let start = try #require(controls.range(of: "struct TickingWhile<Content: View>: View"))
        let body = String(controls[start.lowerBound...].prefix(600))
        #expect(body.contains("if active {") && body.contains("TimelineView(.periodic(from: .now, by: every))") && body.contains("} else {\n            content()"))
    }

    @Test func previewWorkNeverRunsInsideThePublicationOfTheLiveScenes() throws {
        // Measured in FIX-Q (Release, 200 slides): command to publication 0.3 to 0.8 ms; the rest of a Next is view updates. This keeps it so: the
        // publication composes the live scenes and hands them over, and the preview scenes (image and text warming) are made later, in a task that
        // waits first.
        let text = try source("AppModel.swift")
        let publish = try #require(text.range(of: "    private func publish() {"))
        let publishBody = String(text[publish.lowerBound...].prefix(900))
        #expect(!publishBody.contains("previewScenes()") && !publishBody.contains("thumbnailScene") && !publishBody.contains("ImageWarmer") && !publishBody.contains("TextWarmer"))
        let warm = try #require(text.range(of: "    private func scheduleImageWarm() {"))
        let warmBody = String(text[warm.lowerBound...].prefix(500))
        #expect(warmBody.contains("Task { @MainActor") && warmBody.contains("Task.sleep"))
        let changed = try #require(text.range(of: "    private func showChanged(_ state: ShowState) {"))
        let changedBody = String(text[changed.lowerBound...].prefix(1800))
        let warmAt = try #require(changedBody.range(of: "scheduleImageWarm()"))
        let publishAt = try #require(changedBody.range(of: "publish()"))
        #expect(warmAt.lowerBound < publishAt.lowerBound, "the warm-up only schedules a delayed task, so it may be written first; it must never do its work before the publication")
    }
}
