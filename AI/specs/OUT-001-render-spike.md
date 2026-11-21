# Brief: OUT-001 render spike

Read first: `CLAUDE.md`, `AGENTS.md`, `docs/features/OUT-001-render-spike.md`, `docs/adr/0001-stack-and-layout.md`, and the three test files under `Packages/WorshipFlowKit/Tests/`.

## Goal

Implement the render spike so that the coordinator's tests pass and the app shows bilingual lyrics over a looping video on a second display, with a different composition in an output window.

## Do not modify

- Anything under `Packages/WorshipFlowKit/Tests/` that says "Owned by the coordinator". You may add new test files.
- `Packages/WorshipFlowKit/Package.swift` target list (you may add `linkerSettings` or resources if truly needed; say so in the report).
- `CLAUDE.md`, `docs/MASTER-SPEC.md`, `docs/adr/`.

## What to build

The tests define the public API exactly. Implement it; do not rename things to suit yourself.

**`Domain`** (Foundation only; no AppKit, Metal, AVFoundation, CoreGraphics types in public API):
- `SlideContent`, `ColorRGBA`, `NormalizedRect` (with `pixelRect(width:height:)` returning integer `x, y, width, height`), `TextStyle`, `TextAlignment`, `TextLayer`, `SceneDescription`, `ScreenRole` (`audience`, `stage`, `broadcast`).
- All `Sendable`, `Equatable`, `Codable` where reasonable.

**`RenderEngine`**:
- `TextRasterizer.rasterize(_:style:maxWidth:)` using Core Text. Returns `width`, `height`, `inkBounds` (pixel coordinates in the bitmap, origin top-left), `lineCount`, and premultiplied pixel data. Pad the bitmap so outline and stacked marks are never clipped. Font fallback must work.
- `Compositor`: `init(device: MTLDevice? = nil) throws`, shaders compiled from Swift source strings (ADR-0001). `renderImage(scene:width:height:)` returns a `RenderedFrame` with `width`, `height` and `pixel(x:y:)` giving `red, green, blue, alpha` as `UInt8`, premultiplied, origin top-left. Also a method that renders a scene into a caller-supplied `MTLTexture`, optionally with a background video texture, for the live path.
- Text is scaled relative to a 1080-line reference so the same style looks the same at any output size.
- Cache rasterised text textures by content and style; do not re-rasterise every frame.

**`MediaEngine`**:
- A looping video source built on AVFoundation that hands the newest decoded frame to the compositor as a Metal texture (`AVPlayerItemVideoOutput` plus `CVMetalTextureCache`, or better). Seamless loop (`AVPlayerLooper` or equivalent). No decoding on the main thread.

**`OutputEngine`**:
- `FrameStatistics` exactly as the tests require. A drop is a whole target interval with no presentation: `droppedFrames += round(gap / interval) - 1` when that is positive. A late frame is a presentation whose gap from the previous one exceeded 1.5 intervals.
- An `OutputTarget` protocol with two implementations: `DisplayOutput` (borderless window covering a chosen `NSScreen`, above the menu bar and Dock, `CAMetalLayer`, driven by a display link) and `WindowOutput` (ordinary resizable window, 16:9). Each owns a `FrameStatistics` and takes its scene from a provider closure, so two outputs can show different compositions of the same slide.
- Rendering and presentation happen off the main thread. Closing the window or unplugging the display must not crash; the output stops and reports it.

**App** (`App/Sources`, SwiftUI with AppKit where needed):
- An operator window with: a list of sample bilingual slides (English primary, Vietnamese secondary; write your own short sample lines, do not paste copyrighted lyrics — "Amazing Grace" is public domain and its Vietnamese hymn translation lines used in the tests are fine), a display picker, buttons for Go Live, Clear and Stop, a "choose background video" button, a toggle for the second output window, and a live readout of presented, dropped and late frames per output plus the display's refresh rate.
- Audience output: text centred over the video. Window output: stage style, large current line top-left and the next slide's line below it in a second colour, on a dark background.
- Keyboard: right arrow or space for next, left arrow for previous, Escape for Clear.
- Soak mode: launching the app binary with `--soak <seconds> --screen <index> [--video <path>] [--report <path>]` goes live without interaction, advances a slide every 5 seconds, samples resident memory every 10 seconds, and on finishing writes a plain-text report (duration, display mode and refresh rate, presented, dropped, late, max interval, memory min and max) and exits 0. If `--screen` is absent, use a window output.

**Script** `scripts/make-test-media.sh`: uses `ffmpeg` to create `TestMedia/loop-1080p5994.mov`, a 20-second 1920×1080 59.94 fps H.264 clip of a slow moving gradient or `testsrc2`-style pattern that loops cleanly. `TestMedia/` is git-ignored.

## Constraints

- Swift 6 language mode, strict concurrency. No force unwraps in the live path. No `@unchecked Sendable` without a comment saying why it is safe.
- No third-party dependencies.
- The repository volume is case-sensitive: match file-name case exactly in imports and paths.
- Do not edit the `.xcodeproj` by hand. `xcodegen generate` regenerates it from `project.yml`; edit `project.yml` if the app needs a setting.
- Do not commit. Do not run a soak longer than 60 seconds; the coordinator runs the long one.

## Done means

1. `./scripts/check.sh` exits 0. Paste its final lines into the report.
2. A 30-second windowed soak (`--soak 30`) exits 0 and writes a report. Include it.
3. `AI/reports/OUT-001-report.md` records: files created, decisions made, commands run with exit status, anything not done, and anything you could not verify. State plainly which checks you ran and which you did not.
