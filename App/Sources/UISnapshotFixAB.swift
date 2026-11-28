// FIX-AB (debug builds only): `UI_SNAPSHOT_FIXAB=1` with the ui-snapshots hook, against a temporary library and no sound. With 200 slides in the Show
// grid it moves the Preview selection by the keyboard's model path (`moveSelection`) and the live slide by Next, and after each step reports where the
// grid's scroll view is (offset, the largest offset, the visible height) and whether the followed cell's frame is inside the visible part. Nothing
// is started that makes sound; the library is the temporary one named by --library.
#if DEBUG || WF_MEASURE
import AppKit
import SwiftUI
import Domain
import OperatorCore

extension AppModel {
    func runFixABScenario(note: @MainActor (String) -> Void) async {
        guard let workspace, let window = Self.operatorWindow else { note("fixab: no workspace or window"); return }
        // UI_SNAPSHOT_FIXAB_SECTIONS=1: 100 labelled sections of two slides each (a real song has section headers, so several lazy grids).
        let sections = ProcessInfo.processInfo.environment["UI_SNAPSHOT_FIXAB_SECTIONS"] != nil
        let text = sections ? (1...100).map { "Verse \($0)\nFirst line of verse \($0)\nSecond line of verse \($0)" }.joined(separator: "\n\n")
                            : (1...200).map { "Line \($0) of the long song" }.joined(separator: "\n\n")
        guard let big = await workspace.importLyrics(title: "Two hundred", primaryText: text, secondaryText: nil, maxLines: sections ? 1 : 1) else { note("fixab: import failed"); return }
        await workspace.openPresentation(big.id)
        workspace.setMode(.show)
        workspace.selectSlide(0)
        try? await Task.sleep(for: .seconds(3))
        func scrollViews(_ v: NSView) -> [NSScrollView] { ((v as? NSScrollView).map { [$0] } ?? []) + v.subviews.flatMap(scrollViews) }
        guard let grid = scrollViews(window.contentView ?? NSView()).max(by: { ($0.documentView?.frame.height ?? 0) < ($1.documentView?.frame.height ?? 0) }) else { note("fixab: no scroll view"); return }
        func where_() -> String {
            let doc = grid.documentView?.frame.height ?? 0, vis = grid.contentView.bounds.height
            return String(format: "offset %.0f of max %.0f (visible %.0f, content %.0f), at the bottom: %@", grid.contentView.bounds.origin.y, max(0, doc - vis), vis, doc,
                          grid.contentView.bounds.origin.y >= max(0, doc - vis) - 2 ? "yes" : "no")
        }
        note("fixab setup: \(workspace.slides.count) slides, columns \(ui.gridColumns), \(where_())")
        let columns = max(1, ui.gridColumns)
        // Preview by the keyboard's path: Down, a row at a time.
        for step in 1...(199 / columns) {
            await workspace.moveSelection(.down, columns: columns)
            try? await Task.sleep(for: .milliseconds(150))
            if step % 8 == 0 || step == 199 / columns { note("fixab preview step \(step): selected \(workspace.showParts.selectedIndex), \(where_())") }
        }
        // Live by Next, from the top.
        workspace.goLive(at: 0)
        try? await Task.sleep(for: .seconds(1))
        note("fixab live at 0: selected \(workspace.showParts.selectedIndex), live \(workspace.showParts.liveIndex.map(String.init) ?? "none"), \(where_())")
        for step in 1...199 {
            await workspace.next()
            try? await Task.sleep(for: .milliseconds(100))
            if step % 40 == 0 || step == 199 { note("fixab live step \(step): selected \(workspace.showParts.selectedIndex), live \(workspace.showParts.liveIndex.map(String.init) ?? "none"), \(where_())") }
        }
        workspace.stop()
        note("fixab: done")
    }
}
#endif
