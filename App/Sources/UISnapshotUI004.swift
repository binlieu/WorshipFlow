// UI-004 (debug builds only): `UI_SNAPSHOT_UI004=1` with the ui-snapshots hook (and `UI_SNAPSHOT_MEDIA=<video>` so the media
// controller has a pill to draw) takes the pictures the rounded-border check needs: the toolbar's mode switcher and role
// pills and the media controller's AUD pill, in dark and in light appearance. The picture is the whole window at 2x; the
// crops are cut from it afterwards.
#if DEBUG || WF_MEASURE
import AppKit
import Domain
import OperatorCore

extension AppModel {
    func runUI004Scenario(note: @MainActor (String) -> Void, capture: @MainActor (String) async -> Void) async {
        guard let workspace else { note("ui004: no workspace"); return }
        workspace.setMode(.show)
        for (name, choice) in [("dark", AppearanceChoice.dark), ("light", AppearanceChoice.light)] {
            setAppearance(choice)
            try? await Task.sleep(for: .milliseconds(600))
            await capture("window-\(name)")
        }
        setAppearance(.dark)

        await runDragExercise(note: note, capture: capture)

        // The About window, opened through the real Help menu item, in dark and in light. Its picture is the window's own layer.
        func menuItem(titled title: String) -> NSMenuItem? {
            func find(_ menu: NSMenu?) -> NSMenuItem? {
                for item in menu?.items ?? [] {
                    if item.title == title { return item }
                    if let hit = find(item.submenu) { return hit }
                }
                return nil
            }
            return find(NSApp.mainMenu)
        }
        guard let item = menuItem(titled: "About and version…"), let menu = item.menu else { note("ui004: no About menu item"); return }
        menu.performActionForItem(at: menu.index(of: item))
        for _ in 0..<40 where !NSApp.windows.contains(where: { $0.title == "About WorshipFlow" && $0.isVisible }) { try? await Task.sleep(for: .milliseconds(100)) }
        guard let about = NSApp.windows.first(where: { $0.title == "About WorshipFlow" }) else { note("ui004: the About window did not open"); return }
        note("ui004: About window open, id \(about.identifier?.rawValue ?? "-"), size \(Int(about.frame.width))x\(Int(about.frame.height))")
        for (name, choice) in [("dark", AppearanceChoice.dark), ("light", AppearanceChoice.light)] {
            setAppearance(choice)
            try? await Task.sleep(for: .seconds(1.2))
            about.contentView?.superview?.layoutSubtreeIfNeeded()
            about.displayIfNeeded()
            guard let view = about.contentView?.superview ?? about.contentView, let layer = view.layer,
                  let space = CGColorSpace(name: CGColorSpace.sRGB),
                  let ctx = CGContext(data: nil, width: Int(view.bounds.width) * 2, height: Int(view.bounds.height) * 2, bitsPerComponent: 8, bytesPerRow: 0,
                                      space: space, bitmapInfo: CGImageAlphaInfo.premultipliedFirst.rawValue | CGBitmapInfo.byteOrder32Little.rawValue) else { continue }
            ctx.scaleBy(x: 2, y: 2)
            layer.render(in: ctx)
            if let image = ctx.makeImage(), let data = NSBitmapImageRep(cgImage: image).representation(using: .png, properties: [:]),
               let dir = Self.snapshotDirectory {
                try? data.write(to: URL(fileURLWithPath: dir).appendingPathComponent("\(ProcessInfo.processInfo.environment["UI_SNAPSHOT_PREFIX"] ?? "UI-004")-about-\(name).png"))
                note("ui004: wrote about-\(name).png")
            }
        }
        setAppearance(.dark)
        about.close()
    }
}

extension AppModel {
    /// The slide editor's drag, driven through the model (the hook cannot move a real pointer): the per-event cost of the two paths,
    /// whether Live stays as it was, and pictures in the middle of a drag and after it.
    func runDragExercise(note: @MainActor (String) -> Void, capture: @MainActor (String) async -> Void) async {
        guard let workspace, let editor = slideEditor else { note("ui004 drag: no editor"); return }
        workspace.selectSlide(3)                       // the live slide is another one
        insertObject(.rectangle)
        guard let id = editor.selectedObjectID, let start = editor.selectedObject?.frame else { note("ui004 drag: no object"); return }
        try? await Task.sleep(for: .milliseconds(800))
        let liveBefore = show.liveDeck, liveIndex = show.liveIndex
        let events = 60
        func ms(_ body: () -> Void) -> Double {
            let t0 = DispatchTime.now().uptimeNanoseconds
            body()
            return Double(DispatchTime.now().uptimeNanoseconds - t0) / 1_000_000
        }
        // The path every drag event took before: a full write of the slide (publish, preview restore, show change, save schedule).
        let perEventWrite = ms { for i in 1...events { editor.setFrame(id, x: start.x + Double(i) * 0.004, y: start.y, width: start.width, height: start.height) } }
        editor.setFrame(id, x: start.x, y: start.y, width: start.width, height: start.height)
        try? await Task.sleep(for: .milliseconds(300))
        // What a second of dragging costs the renderer: the same 60 events, one every 16 ms, down the old path and the new one.
        func renders(_ drag: @MainActor (Int) -> Void) async -> Int {
            try? await Task.sleep(for: .milliseconds(600))
            let before = PreviewRenderer.shared.requestCount
            for i in 1...events { drag(i); try? await Task.sleep(for: .milliseconds(16)) }
            try? await Task.sleep(for: .milliseconds(600))
            return PreviewRenderer.shared.requestCount - before
        }
        let rendersOld = await renders { i in editor.setFrame(id, x: start.x + Double(i) * 0.004, y: start.y, width: start.width, height: start.height) }
        editor.setFrame(id, x: start.x, y: start.y, width: start.width, height: start.height)
        editor.beginInteraction()
        let rendersNew = await renders { i in editor.move(id, from: start, dx: Double(i) * 0.004, dy: 0) }
        editor.endInteraction()
        try? await Task.sleep(for: .milliseconds(600))
        editor.undo()
        note("ui004 drag: picture renders asked for during a 1 s drag (60 events), old path \(rendersOld), new path \(rendersNew); after the release the picture is drawn again")
        // The path now: the frame is kept apart and written once at the end.
        editor.beginInteraction()
        let perEventDrag = ms { for i in 1...events { editor.move(id, from: start, dx: Double(i) * 0.004, dy: 0) } }
        note("ui004 drag: \(events) events: write-per-event \(String(format: "%.1f", perEventWrite)) ms in all (\(String(format: "%.2f", perEventWrite / Double(events))) per event); kept apart \(String(format: "%.1f", perEventDrag)) ms in all (\(String(format: "%.3f", perEventDrag / Double(events))) per event)")
        let storedDuring = workspace.slides[workspace.show.selectedIndex].content.objects.first(where: { $0.id == id })?.frame
        note("ui004 drag: mid-drag the stored slide is unchanged \(storedDuring == start), the editor shows it moved \(editor.selectedObject?.frame != start)")
        await capture("drag-mid")
        let ended = ms { editor.endInteraction() }
        note("ui004 drag: release wrote once in \(String(format: "%.1f", ended)) ms; stored slide moved \(workspace.slides[workspace.show.selectedIndex].content.objects.first(where: { $0.id == id })?.frame != start); live deck unchanged \(show.liveDeck == liveBefore), live index unchanged \(show.liveIndex == liveIndex)")
        await capture("drag-after")
        editor.undo()
        note("ui004 drag: one undo puts it back \(editor.selectedObject?.frame == start)")
        editor.undo()
        workspace.setMode(.show)
    }
}
#endif
