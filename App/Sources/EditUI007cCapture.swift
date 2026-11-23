// UI-007c (debug builds only): `UI_SNAPSHOT_DESIGN=1 UI_SNAPSHOT_UI007C=1` with the ui-snapshots hook drives the Edit mode's new features in the real
// app against a throw-away library: the Layers list, lock and hide, Fit and Background fill, and a video object (poster in Edit, playing on Live through
// the media registry, closed again on Stop). Every line it writes is something the run observed; pictures go to the snapshot folder. The Mac's screen
// may be locked, so nothing here clicks: the editor model's own calls stand in for the operator's hands, which is said in the report.
// Run by scripts/ui007c-run.sh by hand.
#if DEBUG || WF_MEASURE
import AppKit
import SwiftUI
import CoreGraphics
import ImageIO
import UniformTypeIdentifiers
import Domain
import MediaEngine
import OperatorCore

extension AppModel {
    func runUI007cScenario(note: @MainActor (String) -> Void, capture: @MainActor (String) async -> Void) async {
        guard let workspace, let editor = slideEditor else { note("ui007c: no workspace or editor"); return }
        workspace.setMode(.edit)
        workspace.selectSlide(3)
        try? await Task.sleep(for: .milliseconds(600))
        guard let clip = media?.assets.first(where: { $0.kind == .video }) else { note("ui007c: no video clip in the bin"); return }
        note("ui007c: bin clip \(clip.name), video clips offered by the Video button: \(binVideos.count)")

        // Text with Fit and a Background fill, a locked rectangle, a hidden ellipse, and the video object.
        let words = editor.add(.textBox)
        if let words {
            editor.setText(words, "A long line of words that does not fit its small box at the size it was given")
            editor.setFrame(words, x: 0.05, y: 0.62, width: 0.4, height: 0.16)
            editor.setFontSize(words, 96)
            editor.setFit(words, .shrinkToFit)
            editor.setBackgroundFill(words, ColorRGBA(red: 0.02, green: 0.13, blue: 0.22, alpha: 0.85))
            editor.setName(words, "Caption")
        }
        let box = editor.add(.rectangle)
        if let box { editor.setFrame(box, x: 0.55, y: 0.62, width: 0.2, height: 0.2); editor.setLocked(box, true) }
        let ghost = editor.add(.ellipse)
        if let ghost { editor.setFrame(ghost, x: 0.8, y: 0.62, width: 0.15, height: 0.2); editor.setHidden(ghost, true) }
        insertVideoObject(clip)
        let video = editor.selectedObjectID
        if let video { editor.setFrame(video, x: 0.55, y: 0.1, width: 0.4, height: 0.4) }
        note("ui007c: objects \(editor.objects.count), rows \(editor.layerRows(mediaTitle: { self.videoTitle($0) }).map(\.title))")

        // A locked object does not move, and says why.
        if let box, let frame = editor.objects.first(where: { $0.id == box })?.frame {
            editor.select(box)
            editor.move(box, from: frame, dx: 0.1, dy: 0.1)
            let nudged = editor.nudgeSelection(columns: 1, rows: 0, big: true)
            let after = editor.objects.first(where: { $0.id == box })?.frame
            note("ui007c: locked rectangle moved \(after != frame), arrow taken \(nudged), message: \(editor.lastMessage ?? "none")")
            editor.dismissMessage()
        }

        // The poster is made on a background task: wait for it (a guard against a hang, not a time limit under test).
        var poster = VideoPosters.shared.path(for: clip)
        for _ in 0..<100 where poster == nil { try? await Task.sleep(for: .milliseconds(200)); poster = VideoPosters.shared.path(for: clip) }
        note("ui007c: poster \(poster != nil ? "written" : "NOT written")")
        try? await Task.sleep(for: .milliseconds(800))
        setAppearance(.dark)
        if let video { editor.select(video) }
        await capture("ui007c-edit-video-dark")
        if let words { editor.select(words) }
        await capture("ui007c-edit-text-dark")
        if let box { editor.select(box) }
        await capture("ui007c-edit-locked-dark")
        setAppearance(.light)
        await capture("ui007c-edit-locked-light")
        setAppearance(.dark)

        // Live: the clip is opened for playback by the publish, a frame arrives, and Stop closes it.
        workspace.selectSlide(3)
        await workspace.goLive()
        var opened = false, delivered = false
        for _ in 0..<150 where !delivered {
            opened = mediaRegistry.objectVideos.openAssetIDs.contains(clip.id)
            delivered = mediaRegistry.currentObjectPixelBuffer(for: clip.id) != nil
            if !delivered { try? await Task.sleep(for: .milliseconds(200)) }
        }
        note("ui007c: live, clip opened \(opened), frame delivered \(delivered), unavailable \(mediaRegistry.objectVideos.unavailableAssetIDs.count)")
        if let audience = profiles.first(where: { $0.role == .audience }) {
            let scene = self.scene(forScreen: audience.id)
            note("ui007c: audience scene video layers \(scene.videoObjectLayers.count), object layers \(scene.objectLayers.count) (the hidden ellipse is not among them)")
            if let image = await PreviewRenderer.shared.image(for: scene, width: 960, height: 540, cached: false, frames: mediaFrames),
               let dir = ProcessInfo.processInfo.environment["UI_SNAPSHOT_DIR"] {
                let url = URL(fileURLWithPath: dir).appendingPathComponent("ui007c-live-audience.png")
                if let target = CGImageDestinationCreateWithURL(url as CFURL, UTType.png.identifier as CFString, 1, nil) {
                    CGImageDestinationAddImage(target, image.image, nil)
                    note("ui007c: live audience picture written: \(CGImageDestinationFinalize(target))")
                }
            }
        }
        workspace.stop()
        try? await Task.sleep(for: .milliseconds(600))
        note("ui007c: after Stop, clips open \(mediaRegistry.objectVideos.openAssetIDs.count)")
    }
}
#endif
