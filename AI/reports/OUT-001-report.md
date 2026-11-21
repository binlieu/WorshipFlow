# OUT-001 render spike: implementation report

Implementer report. Verification levels claimed: Implemented; Unit Tested (package tests); the 60-minute soak, second-display run and hardware are Not Verified.

## Files created

Domain: `Packages/WorshipFlowKit/Sources/Domain/{SlideContent,Scene}.swift`
RenderEngine: `Sources/RenderEngine/{TextRasterizer,Compositor}.swift`
MediaEngine: `Sources/MediaEngine/LoopingVideoSource.swift` (also holds `VideoTextureConverter`)
OutputEngine: `Sources/OutputEngine/{FrameStatistics,OutputTarget,OutputRenderer,RunLoopThread,MetalOutput,DisplayOutput,WindowOutput}.swift`
Tests added: `Tests/RenderEngineTests/TextCacheTests.swift` (cache and 1080-line scaling)
App: `App/Sources/{WorshipFlowApp,AppModel,ContentView,SceneBuilder,SampleSlides,SoakConfig,MemoryProbe,VideoSupport}.swift`
Script: `scripts/make-test-media.sh`
Generated (not hand-edited): `WORSHIPFLOW.xcodeproj` via `xcodegen generate`.
Untouched: coordinator tests, Package.swift, project.yml, CLAUDE.md, docs/.

## Decisions

- `OutputEngine` does not depend on `MediaEngine` (Package.swift unchanged). OutputEngine defines `VideoSourceFactory` / `VideoTextureProvider`; the app adapts `LoopingVideoSource` to them (`VideoSupport.swift`, `@retroactive` conformance). `LoopingVideoSource` hands out the newest `CVPixelBuffer`; each render thread owns a `VideoTextureConverter` (`CVMetalTextureCache`).
- Looping: `AVQueuePlayer` + `AVPlayerLooper`; an `AVPlayerItemVideoOutput` (BGRA, Metal compatible) is moved to each new current item via KVO. Frames are pulled on demand under a lock from the render threads; nothing decodes or polls on the main thread.
- Display link: `NSView.displayLink` scheduled on a dedicated run-loop thread, so ticks, scene building, encoding and presentation run off the main thread. A tick is skipped (never blocked) when 2 frames are in flight.
- Presentation timing for `FrameStatistics` comes from `CAMetalDrawable.addPresentedHandler` `presentedTime`, so drops are real missed presentations, not skipped ticks alone.
- Compositor: one render pass per frame; premultiplied "over" blending; text rasterised once per (text, scaled style, max width, alignment) and cached (64 entries); text is scaled by `height / 1080`; each text layer is scissored to its frame. `SceneDescription` gained `showsVideo`; `TextLayer` gained `verticalAlignment` (both defaulted, so the coordinator tests compile unchanged). `TextRasterizer.rasterize` has an extra defaulted `alignment` parameter.
- `DisplayOutput` window level is `CGShieldingWindowLevel()` (above menu bar, Dock and full-screen apps), `.canJoinAllSpaces` + `.fullScreenAuxiliary`.
- Soak exits 1 (and says so in the report) if the audience output stops or zero frames were presented, instead of reporting a vacuous pass.
- Go Live with one display, or no chosen display, runs the audience output in a window. Choosing the display that carries the operator window shows a warning.
- Clear blanks text on both audience and stage outputs; video keeps running. Selecting or advancing a slide while live takes it live.

## Commands run and exit status

- `./scripts/check.sh` : exit 0 (final lines: `== domain boundary`, `== generate project`, `== app build`, `== OK`). Package tests: 21 tests in 5 suites passed (19 coordinator + 2 added).
- `./scripts/make-test-media.sh` : exit 0, about 2 minutes; ffprobe: h264, 1920x1080, 60000/1001, 1199 frames, 20.003 s.
- `WORSHIPFLOW --soak 30 --video TestMedia/loop-1080p5994.mov` (Debug build) : exit 0, report below.
- `--soak 6/8/12/20 --screen 1` and `--screen 0` runs during development (see below).

## Soak report (windowed, 30 s, Debug build, 100 Hz display)

```
duration: 30.2 s (requested 30.0 s)
display mode: window output, 100 Hz display
slide advances: 5
video: TestMedia/loop-1080p5994.mov, distinct frames delivered: 1786
presented: 2996
dropped: 9
late: 7
max interval: 40.00 ms (target 10.00 ms)
memory resident min: 102.8 MB, max: 110.6 MB (4 samples)
status: completed
```
Written to `AI/reports/soak-window-30s.log` (gitignored pattern). Drops are not zero: the cause was not isolated (earlier runs of 8 and 12 s showed 0 to 3 drops, which were start-up and, before an ink-bounds optimisation, text rasterisation on the render thread in a Debug build). The 3 s drop count at start-up in several runs suggests window warm-up. A Release-build run was not done.

## Not verified / not done

- 60-minute soak, GPU load, Release build performance: not run (brief says coordinator runs the long one; GPU load is not measured by the app).
- Display output on the second display (`--screen 1`): the output window reported `occluded true` and presented 0 frames (ticks and GPU submits continued). `--screen 0` (main display) presented 603 frames in 6 s with the same code, so the display path works. Likely cause: another app is in a full-screen Space on display 2 (a screenshot of display 2 showed that app). This is an untested hypothesis; I did not exit the other app's full-screen mode. So "lyrics over video on the second display" is NOT seen running on the second display; it was seen in the output window on display 1 (screenshot reviewed) and the main-display run only reported counters.
- Stage window (second output window toggle) and its composition: built, not run; no click-through of the operator UI was done. Keyboard shortcuts (space, arrows, Escape): implemented via a local key monitor, not exercised.
- Unplugging a display / closing a window mid-run: handled in code (`willClose` and screen-parameter notifications stop the output and report), not exercised.
- Video loop seamlessness at the 20 s boundary: AVPlayerLooper is used; not measured. Distinct frames delivered: 1786 in 30 s (about 59.5 per second).
- Vietnamese rendering in the stacked-mark slide was seen only in the operator list, not on the output.
- Swift 6 strict concurrency: builds clean in SwiftPM and Xcode, with `@unchecked Sendable` limited to `LoopingVideoSource`, `OutputRenderer`, `RunLoopThread`, `LiveBox`, each commented.
