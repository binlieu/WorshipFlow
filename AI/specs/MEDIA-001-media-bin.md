# Brief: MEDIA-001 — media bin, backgrounds and foreground video in the workspace

Read first: `CLAUDE.md`, `AGENTS.md`, `docs/16-known-issues.md` (KI-022, KI-032, KI-033), `AI/reports/MEDIA-002-report.md`, `AI/reports/SYS-002-report.md`, `AI/reports/STAGE-001b-report.md`, `Sources/Domain/MediaTransport.swift`, `MediaLayers.swift`, `MediaAsset.swift`, all of `Sources/MediaEngine`, `Sources/OutputEngine/MediaFrames.swift`, `Sources/OperatorCore`, and `App/Sources`.

Catalogue: MEDIA-01 (media bin), MEDIA-02 (motion backgrounds), MEDIA-03 (foreground videos).

## Goal

The operator can add images and videos to a media bin, set one as the background, play one in the foreground with transport controls, and see both on the outputs.

## What to build

**`OperatorCore`** (with tests you write, in new files under `Tests/OperatorCoreTests`):
- `MediaModel` (`@MainActor @Observable`): the bin (from `LibraryStore.mediaAssets`), add (probe through an injected prober so tests need no real files; store name, kind, path, bookmark, duration, pixel size), rename, remove (reference only, never the file), filter by kind; `MediaLayers` state with `setBackground`, `clearBackground`, `playForeground`, `pause`, `resume`, `seek`, `stopForeground`, and a `tick(now:)` that ends a finished clip and reports a change; the chosen background persisted and restored on relaunch (the foreground never is). A missing or unreadable file gives an operator-readable error and never a crash.
- Scenes are published with `media:` so audience and broadcast screens follow the rules already tested in `MediaRulesTests`. Add model-level tests: starting a clip hides lyrics on the audience scene, ending restores them, Stop removes media from scenes, the stage never shows media.
- The existing single "background video" chooser becomes "set as background" in the bin; keep the soak mode's `--video` argument working.

**App**:
- `extension MediaRegistry: MediaFrameSource {}` and pass the registry to every output, as `MEDIA-002`'s report describes. Open and close player sources as layers change; resolve security-scoped bookmarks and stop access when a source closes.
- A media bin panel: thumbnail grid (from `MediaThumbnailer`, generated off the main thread, cached), add through an open panel and by dropping files onto the panel, kind filter, context menu (Set as background, Play in foreground, Rename, Remove from bin).
- A foreground transport strip that appears while a clip is loaded: play or pause, a scrubber, elapsed and remaining time, Stop.
- Live previews show the current media frame behind or instead of the words where cheap (closes KI-022 if done; otherwise say so).
- Foreground audio plays through the default output device with a volume slider and mute; background loops are muted. Device selection is a later slice.

## Do not modify

- Coordinator-owned tests. `Package.swift`, `project.yml`, `CLAUDE.md`, `docs/MASTER-SPEC.md`, `docs/adr/`.
- `Sources/Domain`, `Sources/RenderEngine`, `Sources/Persistence`, and the test targets `SlideObjectTests`, `RenderEngineTests`, `PersistenceTests`: another agent is adding slide objects there now, keeping existing APIs source-compatible. You may make small source-compatible additions in `Sources/MediaEngine` and `Sources/OutputEngine` if genuinely needed. If the package fails to compile solely because of the other agent's unfinished files, wait a few minutes and retry.

## Seeing it run

Create test media first with `./scripts/make-test-media.sh` if `TestMedia/loop-1080p5994.mov` is missing, and a second short clip with ffmpeg (about 6 seconds, different colours, with a quiet tone on its audio track) in the scratch area, plus a PNG. Launch the Debug app with a temporary `--library`, add the three files, set the loop as background, go live on a song in window outputs, play the short clip in the foreground and let it end. Keep the system volume as it is but set the app's own volume slider low before playing. Save `AI/reports/MEDIA-001-bin.png` (the bin with thumbnails) and `AI/reports/MEDIA-001-foreground.png` (the workspace while the clip plays, live preview visible); look at them, describe them, and say whether the words came back after the clip ended. Quit the app. Keep each run under two minutes, never cover a display full-screen, never switch display modes, and leave nothing behind under `~/Library/Application Support/WORSHIPFLOW`.

## Constraints

Swift 6 language mode, strict concurrency, no force unwraps in the live path, justified `@unchecked Sendable` only, no decoding on the main thread. Views stay thin; decisions live in `OperatorCore` with tests. Do not commit or change git state. Do not consult any advisor tool.

## Done means

1. `swift test --package-path Packages/WorshipFlowKit --filter 'OperatorCoreTests|MediaEngineTests|OutputEngineTests'` passes with your new tests; the full suite and `./scripts/check.sh` exit 0, or you state exactly which step could not run and why.
2. Both screenshots exist and you have described them.
3. `AI/reports/MEDIA-001-report.md` records what was built, which paths you exercised in the running app, commands run with exit status, and everything not verified.
