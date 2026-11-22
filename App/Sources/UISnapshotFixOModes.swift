// FIX-O (debug builds only): `UI_SNAPSHOT_FIXO_MODES=1` with the ui-snapshots hook drives Go Live, Next, Previous, Blackout and Clear through
// the model in every mode and looks for views that did not follow. A missed observation shows up as a stale view, which unit tests do not see.
// SwiftUI offers no accessibility tree to a process nobody is inspecting, so the hook reads pixels and geometry, not the model:
//  1. the state tag is checked by whether its rectangle exists (the view is only there while Blackout or Clear is on), and the Blackout
//     button by its colour, against what the model says;
//  2. the mode's own content, as updated step by step, is drawn and compared pixel by pixel with the same mode built fresh (switch away
//     and back): any region that differs is a part that did not follow. The toolbar and the transport bar are left out of that comparison
//     (they are never rebuilt by a mode change; 1 covers them).
// Nothing here runs without the flag.
#if DEBUG
import AppKit
import Domain
import OperatorCore

extension AppModel {
    /// The window's content as pixels (rows top to bottom) and the points-to-pixels scale.
    @MainActor static func windowPixels(_ window: NSWindow) -> (rep: NSBitmapImageRep, scale: Double)? {
        guard let view = window.contentView, let rep = view.bitmapImageRepForCachingDisplay(in: view.bounds) else { return nil }
        view.cacheDisplay(in: view.bounds, to: rep)
        return (rep, Double(rep.pixelsWide) / Double(max(view.bounds.width, 1)))
    }

    /// Pixels that differ by more than a small tolerance between two draws of the same size inside `region` (window points), and where.
    @MainActor static func pixelDifference(_ a: (rep: NSBitmapImageRep, scale: Double), _ b: (rep: NSBitmapImageRep, scale: Double), region: CGRect) -> (count: Int, box: CGRect?) {
        guard a.rep.pixelsWide == b.rep.pixelsWide, a.rep.pixelsHigh == b.rep.pixelsHigh, let pa = a.rep.bitmapData, let pb = b.rep.bitmapData else { return (-1, nil) }
        let spp = a.rep.samplesPerPixel, rowA = a.rep.bytesPerRow, rowB = b.rep.bytesPerRow
        let x0 = max(0, Int(region.minX * a.scale)), x1 = min(a.rep.pixelsWide, Int(region.maxX * a.scale))
        let y0 = max(0, Int(region.minY * a.scale)), y1 = min(a.rep.pixelsHigh, Int(region.maxY * a.scale))
        var count = 0, minX = Int.max, minY = Int.max, maxX = -1, maxY = -1
        for y in y0..<max(y0, y1) {
            for x in x0..<max(x0, x1) {
                let ia = y * rowA + x * spp, ib = y * rowB + x * spp
                var differs = false
                for c in 0..<min(spp, 3) where abs(Int(pa[ia + c]) - Int(pb[ib + c])) > 6 { differs = true }
                if differs { count += 1; minX = min(minX, x); maxX = max(maxX, x); minY = min(minY, y); maxY = max(maxY, y) }
            }
        }
        guard count > 0 else { return (0, nil) }
        return (count, CGRect(x: Double(minX) / a.scale, y: Double(minY) / a.scale, width: Double(maxX - minX + 1) / a.scale, height: Double(maxY - minY + 1) / a.scale))
    }

    /// The mean colour of a region, as "r g b" 0...255.
    @MainActor static func meanColour(_ px: (rep: NSBitmapImageRep, scale: Double), in rect: CGRect) -> [Int] {
        guard let p = px.rep.bitmapData else { return [0, 0, 0] }
        let spp = px.rep.samplesPerPixel, row = px.rep.bytesPerRow
        let x0 = max(0, Int(rect.minX * px.scale)), x1 = min(px.rep.pixelsWide, Int(rect.maxX * px.scale))
        let y0 = max(0, Int(rect.minY * px.scale)), y1 = min(px.rep.pixelsHigh, Int(rect.maxY * px.scale))
        var sum = [0, 0, 0], n = 0
        for y in y0..<max(y0, y1) { for x in x0..<max(x0, x1) { for c in 0..<3 { sum[c] += Int(p[y * row + x * spp + c]) }; n += 1 } }
        return n == 0 ? [0, 0, 0] : sum.map { $0 / n }
    }

    func runFixOModesScenario(note: @MainActor (String) -> Void) async {
        guard let workspace, let window = Self.operatorWindow else { note("fixo-modes: no workspace or window"); return }
        let pointer = RealPointer(window: window)
        NSApp.activate(ignoringOtherApps: true)
        window.makeKeyAndOrderFront(nil)
        let text = (1...12).map { "Line \($0) of the song" }.joined(separator: "\n\n")
        guard let song = await workspace.importLyrics(title: "Modes", primaryText: text, secondaryText: nil, maxLines: 1) else { note("fixo-modes: import failed"); return }
        await workspace.openPresentation(song.id)
        await workspace.addToPlaylist(song.id)
        try? await Task.sleep(for: .seconds(2))
        func settle(_ ms: Int = 600) async { try? await Task.sleep(for: .milliseconds(ms)) }
        let size = window.contentView?.bounds.size ?? CGSize(width: 1440, height: 900)
        // Mode content only: below the toolbar, above the transport bar.
        let content = CGRect(x: 0, y: (pointer.rect("tb.stateTag") == nil ? 56 : 56), width: size.width, height: size.height - 56 - 64)

        func truth() -> String {
            let s = workspace.showParts
            let mode = s.isStopped ? "stopped" : (s.isBlackedOut ? "blackout" : (s.isCleared ? "cleared" : "live"))
            return "\(mode), live \(s.liveIndex.map { String($0 + 1) } ?? "-"), selected \(s.selectedIndex + 1)"
        }
        var blackoutOff: [Int]?, blackoutOn: [Int]?
        func near(_ a: [Int], _ b: [Int]) -> Int { zip(a, b).map { abs($0 - $1) }.reduce(0, +) }

        var stale = 0, steps = 0
        let modes: [WorkspaceMode] = [.show, .edit, .media, .stage, .cues, .screens]
        for mode in modes {
            workspace.setMode(mode)
            workspace.selectSlide(0)
            workspace.stop()
            await settle(900)
            let other: WorkspaceMode = mode == .show ? .edit : .show
            let script: [(String, @MainActor () async -> Void)] = [
                ("Go Live at 3", { workspace.goLive(at: 2) }),
                ("Next", { await workspace.next() }),
                ("Next", { await workspace.next() }),
                ("Previous", { await workspace.previous() }),
                ("Blackout", { workspace.blackout() }),
                ("Blackout again", { workspace.blackout() }),
                ("Clear", { workspace.clear() }),
                ("Go Live at 6 (lifts Clear)", { workspace.goLive(at: 5) }),
                ("Clear background", { workspace.clearBackground() }),
                ("Next (restores background)", { await workspace.next() }),
                ("Blackout", { workspace.blackout() }),
                ("Next (lifts Blackout)", { await workspace.next() }),
                ("Stop", { workspace.stop() }),
            ]
            for (name, step) in script {
                await step()
                await settle()
                let s = workspace.showParts
                var problems: [String] = []
                let tag = pointer.rect("tb.stateTag") != nil
                if tag != (s.isBlackedOut || s.isCleared) { problems.append("state tag shown \(tag) but model blackout \(s.isBlackedOut) cleared \(s.isCleared)") }
                guard let stepped = Self.windowPixels(window) else { note("fixo-modes: no pixels"); return }
                var button = "-"
                if let r = pointer.rect("tp.blackout") {
                    let colour = Self.meanColour(stepped, in: r)
                    button = colour.map(String.init).joined(separator: " ")
                    if s.isStopped == false {
                        if s.isBlackedOut { blackoutOn = blackoutOn ?? colour } else if blackoutOff == nil || !s.isBlackedOut { blackoutOff = blackoutOff ?? colour }
                        if let on = blackoutOn, let off = blackoutOff, near(on, off) > 20 {
                            let looksOn = near(colour, on) < near(colour, off)
                            if looksOn != s.isBlackedOut { problems.append("Blackout button looks \(looksOn ? "on" : "off") but model \(s.isBlackedOut)") }
                        }
                    }
                }
                workspace.setMode(other); await settle(500); workspace.setMode(mode); await settle(700)
                guard let fresh = Self.windowPixels(window) else { note("fixo-modes: no pixels"); return }
                let diff = Self.pixelDifference(stepped, fresh, region: content)
                if diff.count != 0 { problems.append("content differs from a fresh build in \(diff.count) px, box \(diff.box.map { "x \(Int($0.minX)) y \(Int($0.minY)) w \(Int($0.width)) h \(Int($0.height))" } ?? "-")") }
                steps += 1
                if !problems.isEmpty { stale += 1 }
                note("fixo-modes[\(mode.rawValue)] \(name): model \(truth()) | tag \(tag), Blackout button colour \(button) | \(problems.isEmpty ? "all parts followed" : "STALE: " + problems.joined(separator: "; "))")
            }
        }
        note("fixo-modes: \(steps) steps in \(modes.count) modes, \(stale) with a part that did not follow")
    }
}
#endif
