// FIX-M: what the views must not do during a drag or a drop, read from the source (a view's hover state cannot be driven without a hand;
// the running-app numbers come from scripts/measure-drags.sh and are in AI/reports/FIX-M-report.md).
import Testing
import Foundation

@Suite struct FIXM_DropSourceTests {
    private func source(_ name: String) throws -> String {
        var root = URL(fileURLWithPath: #filePath)
        for _ in 0..<5 { root.deleteLastPathComponent() }
        return try String(contentsOf: root.appendingPathComponent("App/Sources/\(name)"), encoding: .utf8)
    }

    @Test func everyDragSourceGivesASmallDragImageNotTheViewItself() throws {
        for name in ["SlideGridCell.swift", "MediaBinPanel.swift", "MediaDockView.swift", "CentrePane.swift", "EditMode.swift"] {
            for line in try source(name).split(separator: "\n") where line.contains(".draggable(") {
                #expect(line.contains("{ DragChip("), "\(name): a drag without its own small image: \(line)")
            }
        }
    }

    @Test func theDropHighlightIsAViewOfItsOwnAndNotStateOfThePanelItMarks() throws {
        for name in ["MediaBinPanel.swift", "MediaDockView.swift"] {
            let text = try source(name)
            #expect(!text.contains("isTargeted"), "\(name) keeps hover state in the panel, so a drag passing over re-evaluates its content")
            #expect(!text.contains("@State private var targeted"))
            #expect(text.contains(".fileDropTarget("))
        }
        let cell = try source("SlideGridCell.swift")
        #expect(cell.contains("struct FileDropTarget") && cell.contains("@State private var targeted"))
    }

    @Test func fileDropsMakeTheirBookmarksOffTheMainThreadAndInArrivalOrder() throws {
        let app = try source("AppModel.swift")
        for header in ["    func addMedia(_ urls: [URL]) {", "    func setSlideBackground(fileURLs: [URL], slideID: UUID) -> Bool {"] {
            let body = try #require(app.components(separatedBy: header).last?.components(separatedBy: "\n    }\n").first)
            #expect(!body.contains("MediaAccess.bookmark(for:"), "\(header) makes a bookmark on the main thread")
            #expect(body.contains("Task.detached") && body.contains("mediaAddTail"), "\(header) must hand the file work to a background task, queued in order")
        }
    }

    @Test func theSlideGridKeysCellsBySlideAndComparesThemByValue() throws {
        let whole = try source("CentrePane.swift"), cell = try source("SlideGridCell.swift")
        let grid = try #require(whole.components(separatedBy: "struct SlideGrid: View").last?.components(separatedBy: "struct SlideList: View").first)
        #expect(grid.contains("SlideCellKey.keys(for:") && grid.contains("CellSlot("))
        #expect(!grid.contains("ForEach(run.indices, id: \\.self)"), "cells keyed by position are all redrawn by a reorder")
        #expect(grid.contains(".equatable()") && cell.contains("struct SlideGridCell: View, @MainActor Equatable"))
    }

    @Test func hoverNeverReachesTheModelOrTheOutputs() throws {
        // The grid cells and the filmstrip cells have no `isTargeted` at all, so nothing runs per hover update but the system's own hit test.
        for name in ["SlideGridCell.swift", "EditMode.swift"] {
            let text = try source(name)
            let lines = text.split(separator: "\n").filter { $0.contains("dropDestination") && !$0.contains("onDrop(urls)") }
            for line in lines { #expect(!line.contains("isTargeted"), "\(name): \(line)") }
        }
    }
}
