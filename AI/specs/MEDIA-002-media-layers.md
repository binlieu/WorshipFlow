# Brief: MEDIA-002 — media transport, layers and engine (no interface)

Read first: `CLAUDE.md`, `AGENTS.md`, `docs/16-known-issues.md`, `AI/reports/OUT-001-report.md`, `AI/reports/OUT-003-report.md`, `Sources/Domain/SceneComposer.swift`, `Scene.swift`, `MediaAsset.swift`, all of `Sources/MediaEngine`, `Sources/RenderEngine`, `Sources/OutputEngine`, and the coordinator test `Tests/MediaRulesTests/MediaTransportTests.swift`.

Catalogue: MEDIA-01 (probing and thumbnails), MEDIA-02 (motion backgrounds), MEDIA-03 (foreground video with transport). Interface comes in a later slice.

## Goal

Make the coordinator test pass, and give the engine everything the media bin interface will need: probing, thumbnails, a transport-controlled player, still-image media, and a foreground media layer in the compositor and outputs.

## Do not modify

- Coordinator-owned tests, including every earlier one (they must keep passing unchanged). `Package.swift`, `project.yml`, `CLAUDE.md`, `docs/MASTER-SPEC.md`, `docs/adr/`.
- `App/`, `Sources/OperatorCore`, `Tests/OperatorCoreTests`, `Sources/Persistence`: another agent is working in the app and operator core now. Keep every existing public API source-compatible (add defaulted parameters and new members only), because the app calls `SceneComposer`, `Compositor`, `OutputCoordinator` and `LoopingVideoSource` as they are today.

## What to build

**`Domain`** (Foundation only; API fixed by the tests):
- `MediaTransport` (`play(at:)`, `pause(at:)`, `seek(to:at:)`, `stop()`, `position(at:)`, `status(at:)`, `remaining(at:)`, `loopCount(at:)`, `Status`: `idle`, `playing`, `paused`, `ended`). Anchor-based, like `ShowTimer`.
- `MediaSelection` (`assetID`, `kind: MediaKind`, `duration: Double?`), `MediaLayers` (`background`, `foreground`, each a selection with a transport; `setBackground(_:at:)`, `startForeground(_:at:)`, `pauseForeground(at:)`, `resumeForeground(at:)`, `seekForeground(to:at:)`, `stopForeground()`, `tick(at:)`).
- `SceneMedia` (`.video(UUID)`, `.image(UUID)`); `SceneDescription.backgroundMedia` and `.foregroundMedia` (defaults nil). `SceneComposer.scene(for:state:theme:look:props:media:clockText:)` with `media` defaulting to nil. When `backgroundMedia` is a video, `showsVideo` stays true so existing outputs keep working; when a theme's background is `.media` and no media background is chosen, behaviour is exactly as today.

**`MediaEngine`** (replace the placeholder in `Tests/MediaEngineTests` with real tests; synthesise a small test movie and image in the tests with AVAssetWriter and ImageIO, do not depend on `TestMedia/`):
- `MediaProbe.probe(url:) async throws -> MediaInfo` (kind, duration, pixel size, has audio) for video, image and audio files; a clear error for unsupported or unreadable files.
- `MediaThumbnailer`: a poster image for a video (at about ten per cent in, never a black first frame if avoidable) and a downsized image for stills, as `CGImage`, off the main thread.
- `VideoPlayerSource`: like `LoopingVideoSource` but driven by a `MediaTransport` (play, pause, seek, loop on or off), delivering pixel buffers the same way, reporting when a non-looping clip ends, and able to mute or route its audio to the default output for now. No decoding on the main thread.
- A registry that resolves an asset id to an open source so the render thread can ask for "the current frame of asset X" without knowing about files.

**`RenderEngine` and `OutputEngine`**:
- The compositor accepts an optional foreground video texture and optional still-image textures for background and foreground media, drawn in this order: background colour, background media (video or image, aspect-fill), theme background image, foreground media (aspect-fit over black), text layers, overlay images. Add offscreen tests using solid-colour textures.
- Outputs pull background and foreground frames through the registry per `SceneMedia` id. With no registry or no id, everything behaves as today. Keep frames alive until the GPU is done, as the existing code does.

## Constraints

Swift 6 language mode, strict concurrency, no force unwraps in the live path, justified `@unchecked Sendable` only, bounded queues. Do not commit or change git state. Do not consult any advisor tool. Do not run anything that opens windows or plays audio for more than a few seconds.

## Done means

1. `swift test --package-path Packages/WorshipFlowKit --filter 'MediaRulesTests|MediaEngineTests|RenderEngineTests|OutputEngineTests|CompositionTests|DomainTests'` passes; the full suite and `./scripts/check.sh` exit 0, or you state exactly which step could not run because of the other agent's unfinished work.
2. `AI/reports/MEDIA-002-report.md` records files, decisions, commands run with exit status, and everything not verified (in particular: nothing here has been seen on a real output).
