# FIX-J report: fixes from the independent review of UI-005h

Feature IDs: UI-005h (OUT, SLIDE, STAGE, KEY). Brief: `AI/specs/FIX-J-ui-005h-review.md`. Verification: **Implemented, Unit Tested**; the SDI readback test is **Simulated** only; **Hardware Verified: Not Verified; Live-Service Verified: Not Verified**. No migration. Model: Sonnet (one agent in the tree). No advisor, no Codex (project rules).

## Items

| # | Item | Result |
|---|---|---|
| 1 | Fit text to its block | **Done.** `Theme.fitsText` (built-in looks on; Classic and every stored theme off, the editor has the switch), `TextLayer.fitFloor`, `TextFit.swift`, `Compositor.fitStatus`. Both languages shrink by one factor in 4 % steps down to a first-language floor of 56 pt (scaled for other sizes); a plated lower-third block may take two lines at its design size first. Beyond the floor the words are drawn at the floor, clipped to the title-safe frame, flagged on the thumbnail (warning triangle) and in the editor ("These words do not fit this theme at its smallest size"). Measured once per slide and theme at the 1080-line reference (so thumbnail, monitor and output agree), cached, rendered on the render thread, never on the main thread. The audience theme's second-language frame now reaches the title-safe bottom (it was a 0.28-high box that held only two lines). |
| 2 | Text cache | **Done.** `LRUCache` (one entry at a time), a 16-entry cache for `TextLayer.ticks` text (clock, timers, countdowns), `TextWarmer` (selected slide, each screen, background queue, into a shared store the outputs read; wired in `AppModel.scheduleImageWarm`). |
| 3 | Clamps on decode | **Done.** `ColorRGBA`, `NormalizedRect`, `TextShadow`, `TextStyle`, `GradientBackground` and `Stop`, `TextPlate`, `AccentBar` decode through their initialisers; sane ranges added; hostile JSON tests, including through a program package import. |
| 4 | One bad row | **Done.** `themesAndSkipped`, `looksAndSkipped`, `stageLayoutsAndSkipped`; the models name the skipped row once in the error bar; the row stays in the table. |
| 5 | Stage parts | **Done.** `StageSecondLanguage` and `StageLabel` store `relativeFrame`; layouts with absolute `frame` are converted on read, in memory; no migration. Editor move, resize, typed numbers and drag-from-start-frame tested through `StageModel`. |
| 6 | Missing Inter | **Done.** `OutputFont.check()`; one launch notice in the error bar; `HardwareEnvironmentInfo.outputFont` and an "Output font" line in the summary and the environment step. The comment in `InterFont.swift` that said outputs never use Inter is corrected. |
| 7 | Scripture limits | **Done.** For a style with its own line height (the design's looks) the capacity uses that line height and the measured average advance of the font and weight (`TextMetrics`); other styles keep the earlier estimate. See below for stored items. |
| 8 | `isOpaque`, plate opacity | **Done.** A gradient with all stops opaque is opaque; the plate takes the highest opacity of the layers on it. |
| 9 | Tests the review asked for | **Done, one part limited.** Scene A then B through the SDI readback (mutation-checked: a ring slot that is never rewritten fails it); multi-verse packing under the default theme; golden digests gated by machine identity in new tests. The earlier digest tests could not be edited (rule) and are still ungated: KI-156. |
| 10 | Fill and key split | **Read, tested, no defect.** See below. |

## Test order and the failing output, per item

Item 1. `FIXJ_FitRuntimeTests` (existing API only) run first: 2 of 4 failed at runtime: `p.y → -23.52 >= pf.y - 0.5 → 53.5` (the first language's block started 23.5 px above the top of the screen), and the same property on the bilingual slide. Then `FIXJ_FitTests` (13 tests: switch and its encoding, floor on layers, shared factor and ratio, ink inside the frame, floor and flag, thumbnail/output agreement, computed once, user theme with the switch, lower third, unfit lower third): compile errors only for the introduced symbols (`fitsText` 16, `fitStatus` 18, `fitFloor` 6, `fitComputationCount` 6). Then the change; all pass. A bug found on the way: 4 existing test files were stale-linked after the init gained a parameter (build cache only; fixed by touching `EngineReviewFixTests.swift`'s modification time, no content change).

Item 2. `FIXJ_TextCacheRuntimeTests` first, runtime failures: `rasterizationCount → 128 == 65` (63 tiles drawn again after the cache emptied itself at 64), and `320 == 304` (16 lyric bitmaps drawn again during 300 clock ticks). `FIXJ_TextCacheTests`: compile errors only for `lyricCacheLimit`, `tickingCacheLimit`, `textCacheCount`, `tickingCacheCount`, `ticks`, `TextWarmer`; then pass (ticking cache never evicts a lyric; one entry per insert; least recently used, not oldest; the first frame of a warmed scene rasterises 0 bitmaps and computes 0 fits; warmed pixels equal cold pixels; a warmed scene at another size is not mistaken for this one).

Item 3. `FIXJ_ClampTests` first, existing API only: the hostile-value tests failed at runtime (the colour, plate, bar, gradient radii, shadow, style and whole-theme tests; e.g. `weight → 5000 == 900`, `paddingY → 1e12 <= 1000`, `radiusX > 0` false, `plate cornerRadius → -5.0 == 0`). Then the change; pass. `FIXJ_ThemeImportTests` (through a program package, read and imported) was written after the change and not run red (it exercises the same decode path).

Item 4. `FIXJ_TolerantLoadingRuntimeTests` first: 3 of 3 failed at runtime with the thrown `DecodingError` (unknown background kind, Look screen key, unknown stage element kind). Then `FIXJ_TolerantLoadingTests` (store, models, notice text); pass.

Item 5. `FIXJ_StageAttachedRuntimeTests` first: most failed (second line stayed behind on move: `after.x - before.x - 0.03` not 0; width not scaled on resize, `0.46` off; NEXT stayed; the layout was not stored with `relativeFrame`). One of my own expectations was wrong (a clamp at the screen edge) and was corrected in my own new test; the legacy-layout test passes before and after, by design. `FIXJ_StageAttachedTests` (through the model; save and reload) pass.

Item 6. `FIXJ_OutputFontTests` and `FIXJ_EnvironmentFontTests`: compile errors only for `OutputFont` and `Theme.outputFontName`; then pass.

Item 7. `FIXJ_ScriptureLimitsTests` first: 2 failed at runtime (`loose → 55 < tight → 55`; weight 900 held as many characters as 300); the earlier-themes test and the fits-at-design-size tests passed before and after (regression guards). One existing test (`LIB004c_PassageTests.versesNumberedDifferentlyArePaired...`) failed with the first version (the second-language frame held two lines, so the bilingual limit fell to 35); the cause was the audience theme's second-language frame (0.28 high, 5 px short of a third line), fixed in the theme (title-safe bottom), not in the test.

Item 8. `FIXJ_OpacityTests` first: 2 failed at runtime (`isOpaque` false for an opaque gradient; the plate alpha did not follow its layers: `abs(b - a/2) → 109.5`). Then pass.

Item 9. `FIXJ_SDIReadbackSceneChangeTests` passes; with a deliberate mutation (ring slot 1 never rewritten) it failed (`Expectation failed: same` on the first frame after a change and on the scene changes), and the mutation was removed. `FIXJ_MultiVerseTests`, `FIXJ_GoldenDigestTests` pass; on this machine the identity matches and the digests are compared; the skip path was run with a wrong identity and printed `FIXJ golden digests skipped: Golden digests were recorded on a machine with identity ...; this one is ...`.

Item 10. `FIXJ_FillKeyTests` (6 tests) pass on the first run.

## Item 10: the fill and key split

`FillKeySplitter` takes one premultiplied BGRA array and returns a fill and a key from that array in one pass, so both always come from the same frame. The key is the alpha as an opaque grey; the fill is opaque. Premultiplied mode passes the colour through; straight mode divides by alpha, rounded, zero where alpha is zero, clamped at 255. Checked, for every alpha and every colour value up to it (all 32 896 premultiplied pixels): key equals alpha; fill alpha 255; premultiplied fill equals the source; straight fill keyed with its key gives the colour back within one level. Checked on a real rendered lower-third frame at 1920 x 1080 (semi-transparent plate, antialiased edges, text over the plate, more than 100 000 partly transparent pixels): every pixel's key equals the frame's alpha, no colour where alpha is 0, premultiplied fill equals the frame, straight fill re-keyed equals the frame within one level; plate interior key 219, premultiplied fill (6, 16, 28), straight fill (7, 19, 33); corner ring pixels keep the plate colour in the straight fill; text over the plate is white and opaque in both modes, and glyph edge pixels blend plate and white in the straight fill; a keyer that adds the premultiplied fill to its background through the key reproduces the compositor's own "over" exactly, and one that scales the straight fill by the key is within one level, over black, over a colour and over white. **No defect found, nothing fixed.** What this does not show: how a keyer or the ATEM treats the signals (KI-138). A finding: the Screens preview draws its Fill and Key panels from two separate renders (KI-155); the SDI output and the hardware test split one frame.

## Frame times (item 2), measured with `wf-looks-probe`, not asserted

`wf-looks-probe perf` and `perf-long` (Release, three role compositions at 1920 x 1080 into private textures, GPU complete per frame, 600 frames after 20 warm-up frames, three runs each, Inter registered, this Mac). Before = the tree at f354752 built in a scratch copy with the same probe; after = this tree. The sample slide fits at its design size; the long slide is the bilingual one in the pictures (fitting is active).

| | cold first frame | warm mean (median) | first frame after the text was prepared ahead |
|---|---|---|---|
| sample, before | 54.8 to 65.3 ms | 0.579 to 0.582 ms (0.565 to 0.570) | n/a |
| sample, after | 58.7 to 59.4 ms | 0.563 to 0.678 ms (0.546 to 0.671) | 18.2 to 20.4 ms (preparing: 32.6 to 35.2 ms on a background thread) |
| long slide, before | 74.3 to 76.2 ms | 0.636 to 0.650 ms (0.618 to 0.621) | n/a |
| long slide, after | 71.8 to 74.0 ms | 0.615 to 0.705 ms (0.597 to 0.678) | 21.2 to 22.2 ms (preparing: 48.9 to 49.2 ms) |

Warm frames are unchanged within the run-to-run spread of this Mac. An earlier version of the cache and fit lookup added up to about 0.1 ms per frame (a second hash per layer and an array allocation per frame); that is why `LRUCache` marks an entry used by writing a field of a class and `fitStatus` compares the layers with the last frame's and allocates nothing when they match. No allocation was added to the live path in steady state; on a frame whose text changed (a clock tick) the fit key is rebuilt, once a second, and is a cache hit. What stays in the cold first frame: the gradient, the plate and the textures' upload (about 19 ms).

## Pictures

`AI/reports/FIX-J-before-audience.png` and `FIX-J-after-audience.png`, `FIX-J-before-lowerthird.png` and `FIX-J-after-lowerthird.png`: a long bilingual slide (invented words, 1280 x 720; the lower third over a checkerboard). Before: the first language runs off the top of the audience screen; after: both languages fit, the same ratio. Made with `wf-looks-probe long-pictures` (the before pictures with the tree at f354752 in a scratch copy).

## Saved scripture items: stored or derived

**Derived.** A scripture playlist item stores `ScriptureItemSpec` (label, ranges, translation codes, verses per slide), not slides; the slides are built every time the item is opened, with `ScriptureSlideLimits.options(theme:...)` from the current theme (`ScriptureModel`). For an existing item: under a Classic or a stored theme the same passage splits as before; under the built-in audience theme the limit now comes from the theme's own line height and the measured advance of Inter at its weight, so the item may split into a different number of slides than under the previous build (KI-154), and every slide fits at the design size. A passage never has to be re-saved.

## Existing tests

None edited. The guarantee that user themes and the Classic themes draw exactly as before still holds: `UI005h_MigrationV13Tests` (digests of four user themes and the two Classic looks, byte-for-byte storage, decoded equality) pass unchanged on this Mac, and `FIXJ_GoldenDigestTests` compares the same digests behind the machine-identity gate (identity matches here). A stored theme and a Classic theme have `fitsText` false, so the compositor never analyses them.

## Checks

`./scripts/check.sh` on the final tree, run twice in a row: **exit 0 and exit 0**; both: `Test run with 2811 tests in 441 suites passed` (baseline 2720; +91 new tests), package tests, the domain boundary check, project generation and the app build all passed. Before the font race in my own SDI scene-change test was fixed (it used the built-in Inter looks, whose rasterisation depends on whether another test in the same process had registered Inter yet) one run failed in that test; after the fix it did not fail again. Seven other runs made while the Mac was heavily loaded by other work (load average 50 to 120; another process was building in this tree and wrote into this session's scratch folder) failed only in wall-clock tests in code this fix does not touch (`ToolProcessRunnerTests.aClientThatHangsIsStopped`, `MIDIRouterTests.orderIsKeptForABurst`, `VideoPlayerSourceTests.pauseHoldsAndSeekMovesTheFrame`, `ScriptureLibraryTests.onlyTheNeededVersesAreReadFromTheLibrary` and a few remote/pad timing tests); the baseline run before any change had two such failures as well. Those tests pass alone and when the Mac is quiet.

## What is not verified

- Nothing was run in the live app: the thumbnail warning mark, the editor line, the theme editor switch, the launch font notice and the text warm-up are compiled (the app builds) but not looked at in a running window; the hands-on checklist has them.
- Hardware, keying, alpha on any keyer or ATEM: Not Verified (KI-138, KI-155).
- The warm-up covers SDI mode sizes and 1920 x 1080 only (KI-151).
- No wall-clock assertion exists anywhere in the new tests; the frame times above are hand measurements on one Mac.
- Fitting for slide-object text boxes and props: not done (not asked).
- The earlier digest tests are not gated by machine identity (KI-156): that needs permission to edit them.

## Files

Domain: `Theme.swift`, `Scene.swift`, `SceneComposer.swift`, `OutputLooks.swift`, `StageLayout.swift`, `TextPlate.swift`. RenderEngine: `TextFit.swift`, `TextStores.swift`, `TextMetrics.swift`, `OutputFont.swift`, `Compositor.swift`, `TextRasterizer.swift`. Persistence: `LibraryStore+Settings.swift`, `LibraryStore+Stage.swift`. OperatorCore: `SettingsModel.swift`, `StageModel.swift`, `ScriptureRules.swift`. OutputEngine: `SDIOutput.swift`, `HardwareTest/*`. App: `Thumbnails.swift`, `CentrePane.swift`, `ThemeEditorSheet.swift`, `AppModel.swift`, `ContentView.swift`, `HardwareTestSupport.swift`, `InterFont.swift`. Probe: `LooksProbe/main.swift` (`perf-long`, `long-pictures`). Package: `Package.swift` (OperatorCore depends on RenderEngine; `UI005hTests` gained dependencies). Tests: `FIXJ_*.swift` in `UI005hTests`, `OutputEngineTests`, `OperatorCoreTests`, `ProgramPackageTests`. Docs: the UI-005h and OUT-003 feature notes, data dictionary, change log, known issues KI-150 to KI-156 (and KI-142 annotated), hands-on checklist, current status, handoff.
