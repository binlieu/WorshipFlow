// LIB-005 (debug builds only): `UI_PROGRAM_EXERCISE=<scratch folder>` exercises program export and import in the running app,
// against whatever `--library` the app was started with (use a scratch one). It makes invented songs and pictures, exports
// the playlist through the same sheet model the menu uses, edits one song, opens the package again through the import sheet
// (summary, conflict, default answer), refuses a hostile package, and writes two pictures of the sheets. Nothing here runs
// without the variable.
#if DEBUG
import AppKit
import SwiftUI
import Domain
import OperatorCore
import ProgramPackage

extension AppModel {
    func runProgramExerciseIfRequested() {
        guard let dir = ProcessInfo.processInfo.environment["UI_PROGRAM_EXERCISE"], !dir.isEmpty else { return }
        Task { @MainActor in
            func note(_ text: String) { FileHandle.standardError.write(Data("[program-exercise] \(text)\n".utf8)) }
            while !workspaceLoaded { try? await Task.sleep(for: .milliseconds(100)) }
            guard let workspace, let store = libraryStore else { note("no workspace"); return }
            let model = ProgramTransferModel.shared
            let root = URL(fileURLWithPath: dir, isDirectory: true)
            try? FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
            for _ in 0..<60 where NSApp.windows.isEmpty { try? await Task.sleep(for: .milliseconds(250)) }
            let window = Self.operatorWindow
            window?.setContentSize(NSSize(width: 1200, height: 800))
            window?.orderFrontRegardless()

            // Invented content: two songs, a picture on one slide, both in the playlist.
            func png(_ name: String, _ color: NSColor) -> URL {
                let url = root.appendingPathComponent(name)
                let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: 64, pixelsHigh: 64, bitsPerSample: 8, samplesPerPixel: 4,
                                           hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
                NSGraphicsContext.saveGraphicsState()
                NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
                color.setFill(); NSRect(x: 0, y: 0, width: 64, height: 64).fill()
                NSGraphicsContext.restoreGraphicsState()
                try? rep.representation(using: .png, properties: [:])?.write(to: url)
                return url
            }
            let picture = png("sample-picture.png", .systemTeal)
            guard let one = await workspace.importLyrics(title: "Invented Song One", primaryText: "Verse 1:\nFirst invented line\nSecond invented line\n\nChorus:\nChorus invented words", secondaryText: nil, maxLines: 2),
                  let two = await workspace.importLyrics(title: "Invented Song Two", primaryText: "Only invented words here", secondaryText: nil, maxLines: 2) else { note("import failed"); return }
            if var slide = try? await store.slides(of: one.id).first {
                slide.content.objects = [SlideObject(frame: NormalizedRect(x: 0.6, y: 0.1, width: 0.3, height: 0.3), content: .image(ImageObject(path: picture.path)))]
                try? await store.updateSlide(slide)
            }
            await workspace.addToPlaylist(one.id)
            await workspace.addHeader("Worship")
            await workspace.addToPlaylist(two.id)
            note("playlist items before export: \(workspace.playlistItems.map(\.title))")

            @MainActor func capture(_ name: String) async {
                try? await Task.sleep(for: .seconds(1.2))
                guard let sheet = window?.attachedSheet, let view = sheet.contentView?.superview ?? sheet.contentView else { note("no sheet to capture for \(name)"); return }
                for _ in 0..<3 {
                    view.layoutSubtreeIfNeeded(); sheet.displayIfNeeded()
                    try? await Task.sleep(for: .milliseconds(400))
                }
                // The layer tree is drawn directly, as the UI snapshots do: SwiftUI draws into layers that cacheDisplay misses.
                let scale = 2
                let width = Int(view.bounds.width) * scale, height = Int(view.bounds.height) * scale
                guard let layer = view.layer, let space = CGColorSpace(name: CGColorSpace.sRGB),
                      let ctx = CGContext(data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0, space: space,
                                          bitmapInfo: CGImageAlphaInfo.premultipliedFirst.rawValue | CGBitmapInfo.byteOrder32Little.rawValue) else {
                    note("no layer to capture for \(name)"); return
                }
                ctx.scaleBy(x: CGFloat(scale), y: CGFloat(scale))
                layer.render(in: ctx)
                guard let image = ctx.makeImage(), let data = NSBitmapImageRep(cgImage: image).representation(using: .png, properties: [:]) else { return }
                try? data.write(to: root.appendingPathComponent(name))
                note("picture \(name) \(width)x\(height)")
            }

            // Export, through the sheet's own model.
            model.startExport(app: self, playlistID: nil)
            for _ in 0..<100 where model.exportPlan == nil { try? await Task.sleep(for: .milliseconds(100)) }
            guard let plan = model.exportPlan else { note("export plan did not come"); return }
            note("export plan: items \(plan.itemCount), presentations \(plan.presentationCount), files \(plan.files.count), bytes \(plan.totalBytes), missing \(plan.missing.count), sheet open: \(ui.programSheet == .export)")
            await capture("export-sheet.png")
            let package = root.appendingPathComponent("Exercise.worshipflowprogram")
            model.export(plan, to: package, replaceExisting: false)
            for _ in 0..<100 where model.exportWork.isRunning || model.exportWork == .idle { try? await Task.sleep(for: .milliseconds(100)) }
            note("export result: \(model.exportWork)")
            note("package: \((FileManager.default.enumerator(atPath: package.path)?.allObjects as? [String] ?? []).sorted())")
            model.closeExport(app: self)

            // Change a song here, then import the package again: one conflict, one already present.
            if var slide = try? await store.slides(of: one.id).last {
                slide.content.primary = "Changed after the export"
                try? await store.updateSlide(slide)
            }
            model.beginImport(app: self, url: package)
            for _ in 0..<100 where model.importSummary == nil && model.importProblem == nil { try? await Task.sleep(for: .milliseconds(100)) }
            if let s = model.importSummary {
                note("import summary: playlist \(s.playlist), new \(s.newPresentations), already \(s.alreadyPresent), conflicting \(s.conflicting), hasConflicts \(s.hasConflicts), media to copy \(s.mediaFilesToCopy)")
            } else { note("import problem: \(model.importProblem ?? "?")") }
            await capture("import-sheet.png")
            model.performImport(app: self)
            for _ in 0..<100 where model.importWork.isRunning || model.importWork == .idle { try? await Task.sleep(for: .milliseconds(100)) }
            note("import result: \(model.importWork)")
            note("workspace after import: presentations \(workspace.presentations.map(\.title).sorted()), playlists \(workspace.playlists.map(\.name)), selected \(workspace.playlists.first { $0.id == workspace.selectedPlaylistID }?.name ?? "-"), items \(workspace.playlistItems.map(\.title))")
            model.closeImport(app: self)

            // A hostile package is refused in plain words and nothing changes.
            let hostile = root.appendingPathComponent("Hostile.worshipflowprogram")
            try? FileManager.default.copyItem(at: package, to: hostile)
            if let text = try? String(contentsOf: hostile.appendingPathComponent("program.json"), encoding: .utf8),
               let doc = try? JSONDecoder().decode(ProgramDocument.self, from: Data(text.utf8)), let file = doc.media.first?.file {
                try? text.replacingOccurrences(of: "\"\(file)\"", with: "\"media/../../escape.bin\"")
                    .write(to: hostile.appendingPathComponent("program.json"), atomically: true, encoding: .utf8)
            }
            let before = workspace.presentations.count
            model.beginImport(app: self, url: hostile)
            for _ in 0..<100 where model.importSummary == nil && model.importProblem == nil { try? await Task.sleep(for: .milliseconds(100)) }
            note("hostile package: \(model.importProblem ?? "NOT REFUSED")")
            note("presentations unchanged: \(workspace.presentations.count == before)")
            model.closeImport(app: self)
            note("done")
        }
    }
}
#endif
