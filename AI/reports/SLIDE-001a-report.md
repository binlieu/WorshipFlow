# SLIDE-001a report: slide objects (shapes, images, text boxes), fills and effects

Levels claimed: Implemented; Unit Tested (model, composer, compositor on the real Metal device offscreen, store). There is no editor interface in this slice and nothing was seen running in the app.

## Files

Changed, Domain (`Packages/WorshipFlowKit/Sources/Domain/`):
- `SlideContent.swift`: `objects` (defaulted init param `objects:`), tolerant decode, empty objects omitted on encode, z-order helpers, `isBlank` false with objects.
- `Scene.swift`: `TextShadow`, `TextStyle.shadow` (defaulted init param), `TextLayer.opacity` (defaulted init param, tolerant decode), `SceneDescription.objectLayers` (defaulted init param, tolerant decode).
- `SceneComposer.swift`: objects added to the scene inside the existing slide-layer / no-foreground-clip branch, left out on a broadcast whose theme background is `.transparent`.

Created, Domain: `SlideObject.swift` (`SlideObject`, `.Content`, `TextObject`, `ShapeObject` with `Shape`, `ImageObject`, `ShapeLayer`, `SceneObjectLayer`, `SlideObject.sceneLayer`).

RenderEngine: created `ShapeRasterizer.swift` (Core Graphics shapes; `ColorRGBA.cgColor` moved here from `TextRasterizer.swift`, now internal rather than fileprivate). Changed `TextRasterizer.swift` (shadow, padding) and `Compositor.swift` (object pass, shape cache, per-draw opacity and clip).

Persistence: `Schema.swift` (migration `v5`), `Records.swift` (`SlideRecord.objects`, custom `encode`, `SlideObjectsJSON`), `LibraryStore+Content.swift` (`appendSlide`, `updateSlide`), `SearchIndex.swift` (`reindex` folds text-box words, `slideHasObjectsColumn`).

Docs: `docs/19-data-dictionary.md` (v5 section, `bodyFolded` note).

Created tests: `Tests/SlideObjectTests/SlideObjectExtraTests.swift`, `Tests/RenderEngineTests/SlideObjectRenderTests.swift`, `Tests/PersistenceTests/SlideObjectStoreExtraTests.swift`.

Not touched: the coordinator test, `v1` to `v4`, `Package.swift`, `App/`, `OperatorCore`, `MediaEngine`, `OutputEngine`, git state.

## Decisions

- Source compatibility: only defaulted parameters and new members/types were added. `SlideContent(primary:secondary:)` and `TextStyle(fontName:fontSize:color:outlineWidth:outlineColor:)` still compile. See "Build note" below about stale objects.
- JSON: `SlideContent` with no objects encodes exactly as before (`{"primary":"A"}`). Object content uses Swift's synthesized enum encoding (`{"text":{"_0":{...}}}`); documented in the data dictionary.
- `TextLayer` gained `opacity` (default 1) so a text box's object opacity applies to the whole text group in the shader. The brief did not list it; the alternative (multiplying colour alphas) gives wrong results where outline and fill overlap.
- Shadow: offsets and blur in points at 1080 lines, scaled by the compositor like font size. Positive `offsetY` moves the shadow down the screen. Drawn with `CGContext.setShadow` inside a transparency layer so one shadow covers outline plus fill. Bitmap padding is symmetric: `|offset| + 2*blur + 1` per axis, so the text keeps its place; the shadow is in the cache key because `TextStyle` is `Hashable`.
- Shapes: Core Graphics to premultiplied BGRA, one bitmap per (shape, fill, stroke colour, stroke width in hundredths of a pixel, pixel size). The stroke is drawn by clipping to the shape path and stroking at twice the width, so it lies inside the frame edge. Rounded radius is a fraction of the shorter side, clamped to 0...0.5. Cache: at most 48 bitmaps and 128 MB, least recently used out, never one used by the current frame. A shape bitmap over 64 MB is not drawn (frame far off the slide).
- Draw order implemented as specified: colour, background media/video, theme background image, foreground media, object layers back to front, lyric text, overlay images. Opacity and scissor are now set on every object and lyric draw (previously lyric text inherited the opacity buffer last set by the background image; that latent quirk is gone, no behaviour change for opacity 1).
- Image objects use the existing image cache and `imageDraw` (fit/fill, loading mode as for props).
- Store: `v5` adds nullable `slide.objects`. `appendSlide` and `updateSlide` write it only when there are objects or the column exists, so plain slides still work on `v1` to `v4` stores (tested for each). Objects on a pre-v5 store fail with SQLite's "no such column" rather than being dropped (no new `StoreError` case, to avoid breaking exhaustive switches in the other agent's code). `SlideRecord` got a custom `encode` that writes `objects` only when set.
- An unreadable `objects` value reads as no objects (so one bad row cannot stop a service's slide list loading). Consequence: saving that slide again overwrites the bad value. Judgement call.
- Search: `reindex` appends text-object words (not shapes or images) to each slide's text; the column check is a `PRAGMA table_info` per reindex.

## Commands and results

- `swift test --package-path Packages/WorshipFlowKit --filter 'SlideObjectTests|RenderEngineTests|CompositionTests|DomainTests|PersistenceTests|SettingsStoreTests|StageTests|StageStoreTests|MediaRulesTests'`: `Test run with 278 tests in 47 suites passed`.
- `swift test` (full, run inside the package directory): `Test run with 481 tests in 73 suites passed`.
- `./scripts/check.sh`: first run exit 1, caused by `VideoPlayerSourceTests.aClipThatDoesNotLoopReportsItsEnd` (MediaEngine, AVFoundation timing: "ended count 0", 2 issues). Second run (no code change in between): `Test run with 481 tests in 73 suites passed`, `== OK`, exit 0. The failing test is in the other agent's area and passed in the full `swift test` run before and the second check run after; I treat it as a timing flake but did not investigate it.
- Earlier attempts to run `swift test` failed because of the other agent's unfinished `OperatorCoreTests` (compile errors in `MediaModelTests.swift`); a few minutes later it compiled. No scratch copy was needed.

## Build note (stale objects)

After my change to `SceneDescription.init` (a defaulted parameter changes the mangled symbol), an incremental `swift test` failed to link `OutputEngineTests` ("Undefined symbols ... SceneDescription.init"): SwiftPM had not recompiled that unchanged test module. I removed `.build/debug.yaml`, `.build/arm64-apple-macosx/debug/description.json` and `.build/arm64-apple-macosx/debug/OutputEngineTests.build` (build products only) to force it. The same applies to any other module that calls `SceneDescription(...)`, `TextLayer(...)` or `TextStyle(...)` and has a stale build directory (including the app, in Xcode, if its derived data is stale): a clean or a touch rebuilds it. Source compatibility holds; binary compatibility between old object files and the new Domain does not.

## Not verified

- No editor interface exists, so nothing was seen in the app; no output window or real display rendered an object. Verified only through offscreen `Compositor.renderImage` pixels on this machine's Metal device.
- Image objects were tested with an opaque sRGB PNG only (draw order and fill). `fit` mode, a missing file, background (non-synchronous) loading and wide-gamut images for objects were not tested separately; they share the existing `imageDraw` path covered by the earlier image tests.
- Shadow appearance (blur softness, `2*blur` tail estimate) was checked by tests for no clipping and direction only, not by eye. CG's blur-to-sigma relation was assumed (blur is about twice sigma); a very large blur next to a bitmap clamped at `maxWidth` can still clip at that limit, like outlines.
- Performance with many shapes or large full-frame shapes at 1080p/4K was not measured; shape bitmaps are frame-sized, so full-frame shapes cost 8 MB (1080p) each in the cache.
- Pre-existing `v1` store behaviour: `replaceContent` inserts `groupID`; a v1-only store was not tested for it, and `SlideRecord.encode` keeps writing `groupID` as before.
- Migration `v5` on a populated real library file was exercised only with temp databases created by the tests.
- Data dictionary and this report are the only docs edited; `docs/14-current-status.md`, change log and known-issues were not.

## Tests believed wrong

None. The coordinator's assertions are consistent with the spec as implemented. One note: `layersDrawBackToFrontUnderLyricText` draws a 111 px glyph in a 40 px frame and relies on the glyph being clipped to its frame while the frame centre stays solid; it passes, but it depends on the existing text placement (the bitmap is clamped to `maxWidth` = frame width), not on anything in this slice.
