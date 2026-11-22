// MEDIA-010 (debug builds only): `UI_SNAPSHOT_MEDIA010=1` with the ui-snapshots hook drives the live media control in the real
// app against a temporary library: the bin player, a bin choice as a live override, the three layer clears, a hot folder
// (`UI_SNAPSHOT_HOTFOLDER=<folder>`) and a slide's own background. Pictures go through the hook's `capture`.
#if DEBUG
import AppKit
import Domain
import OperatorCore

extension AppModel {
    func runMedia010Scenario(note: @MainActor (String) -> Void, capture: @MainActor (String) async -> Void) async {
        guard let workspace, let media, let preview = binPreview else { note("media010: no models"); return }
        @MainActor func wait(_ seconds: Double, until condition: @MainActor () -> Bool) async -> Bool {
            let end = Date().addingTimeInterval(seconds)
            while Date() < end { if condition() { return true }; try? await Task.sleep(for: .milliseconds(100)) }
            return condition()
        }
        let storedBefore = workspace.slides.map(\.content)
        guard let video = media.assets.first(where: { $0.kind == .video }) else { note("media010: no video in the bin"); return }

        media.dropBackgroundOverride()          // the hook's own set-up chose a background; start from none
        // 1. Select it in the Media mode: the sidebar player shows it. Nothing goes live.
        workspace.setMode(.media)
        selectBinItem(video.id)
        preview.togglePlay()
        _ = await wait(3) { preview.isPlaying && preview.position > 0.3 }
        note("media010: selected \(video.name): player shows \(preview.asset?.name ?? "-"), playing \(preview.isPlaying), position \(String(format: "%.1f", preview.position)), muted \(preview.isMuted), live background \(media.layers.background != nil) (expected false)")
        await capture("bin-player")
        preview.togglePlay()

        // 2. Double click = send live as a background: a live override. The presentation is not written.
        performDockAction(MediaDock.action(for: video, layer: .background))
        workspace.setMode(.show)
        try? await Task.sleep(for: .milliseconds(800))
        note("media010: override on \(media.hasLiveBackgroundOverride), slides unchanged \(workspace.slides.map(\.content) == storedBefore) (expected true), background muted \(media.isBackgroundMuted) (expected true)")
        media.setBackgroundMuted(false)
        note("media010: unmuted -> heard muted \(media.backgroundHeardMuted) (expected false)")
        media.setBackgroundMuted(true)
        await capture("show-override")

        // 3. The Clear menu entries, then the layer clears through the one command path.
        clearBackground()
        try? await Task.sleep(for: .milliseconds(500))
        note("media010: Clear background -> cleared \(show.isBackgroundCleared) (expected true), words still live \(show.liveSlide != nil) (expected true)")
        await workspace.next()
        try? await Task.sleep(for: .milliseconds(300))
        note("media010: Next -> cleared \(show.isBackgroundCleared) (expected false)")
        media.dropBackgroundOverride()

        // 4. A hot folder: the bin follows it, a file being copied is held back, Play folder plays its videos in name order.
        if let path = ProcessInfo.processInfo.environment["UI_SNAPSHOT_HOTFOLDER"], let hot = hotFolders {
            followFolder(URL(fileURLWithPath: path, isDirectory: true))
            _ = await wait(5) { hot.folders.count == 1 }
            for _ in 0..<3 { await hot.rescan(); try? await Task.sleep(for: .milliseconds(300)) }
            if let state = hot.folders.first {
                note("media010: hot folder \(state.folder.name): status \(state.status), items \(state.items.map(\.name)), held back \(state.heldBack)")
                ui.binFolderID = state.id
                workspace.setMode(.media)
                media.playFolder(state.id, on: .background)
                try? await Task.sleep(for: .milliseconds(900))
                note("media010: Play folder -> playing \(media.playingFolderID == state.id), background \(media.layers.background.flatMap { media.asset($0.selection.assetID)?.name } ?? "-")")
                await capture("hot-folder")
                media.stopFolder()
            } else { note("media010: hot folder was not added") }
        }

        // 5. A slide's own background: dropped on slide 2 (the same call the drop makes). Live is unchanged.
        workspace.setMode(.show)
        if workspace.slides.count > 1 {
            await workspace.goLive()
            let liveBefore = show.liveDeck
            _ = setSlideBackground(mediaID: video.id, slideID: workspace.slides[1].id)
            try? await Task.sleep(for: .milliseconds(600))
            note("media010: slide 2 has its own background \(workspace.slides[1].content.background != nil), live deck unchanged \(show.liveDeck == liveBefore) (expected true)")
            await capture("slide-background")
        }
    }
}
#endif
