# UI-005h report: output looks matched to `07-output-looks`

Feature IDs: UI-005h (OUT, KEY, STAGE). Verification: **Implemented, Unit Tested**; the SDI readback is **Simulated** only. Nothing is Hardware Verified or Live-Service Verified: no keyer, ATEM, converter or SDI signal has seen the lower third's matte (KI-138). Brief: `AI/specs/UI-005h-output-looks.md`. Pictures: `AI/reports/UI-005h-*.png`.

## Items

| # | Item | Result |
|---|---|---|
| 1 | Type as designed | Done. `TextStyle` gains `weight`, `letterSpacing`, `lineHeight`, `opticalSize`, `fontFeatures` (all optional, nil = earlier look). Applied by `TextRasterizer` (Inter on its weight and optical-size axes, other fonts by nearest face). Built-in themes carry the design's sizes, weights, colours, shadow. Vietnamese marks tested unclipped at every design size and weight, with and without the shadow. |
| 2 | Audience gradient | Done. Radial gradient as `Theme.mediaFallback` under the shared loop (the loop, slide backgrounds and bin choices behave as before); `ThemeBackground.gradient` is a background kind of its own (editor offers it with the design's colours). |
| 3 | Lower third plate, bar, key matte | Done. `TextPlate` + `AccentBar` in the theme and scene; the compositor stacks the plated lines, sizes the plate to them and draws it before the text; the matte is the frame's alpha. Premultiplied and straight both tested. Not verified on any keyer (KI-138). |
| 4 | Stage composition | Done except the section label. Current, second language (own line, own style), NEXT, next line (muted), clock, first countdown timer, message as a warning band. "CHORUS x2" not built: the show state carries no section name or repeat count (KI-139). Layouts the operator made are untouched. |
| 5 | Existing libraries | Done. Migration v13 additive; user themes byte for byte and pixel for pixel unchanged; Classic themes added to libraries with content. Appearance change on upgrade is in the change log and the hands-on checklist. |
| 6 | Everywhere the slide is drawn | Done by construction and checked: thumbnails, monitors, keyed previews and outputs all draw through `Compositor`. The Show capture (`UI-005h-show-dark.png`) shows the gradient and new type in the thumbnails, the Live monitor (over the loop), the Stage monitor (clock, timer, small second line) and the Broadcast monitor (plate). Not built from the design: the audience watermark (product decision, KI-139). |

Also: the SDI output's readback changed (see Frame time). The theme editor gained a Gradient choice; the stage editor knows the new timer kind.

## Test order and failing output

1. Before any implementation, the baseline: `swift test` 2606 tests passed; frame times recorded (below); digests of four user themes and of the old built-ins rendered with the code of 38ca00d (`UI005h_Golden.swift`).
2. Tests written (`Tests/UI005hTests`: design numbers, scene composition, type, render geometry, matte, migration v13). First run: they did not compile, **283 errors, all for symbols the slice introduces** (`TextStyle.weight`, `TextLayer.inPlate`, `TextPlate`, `GradientBackground`, `SceneDescription.plate`, `Compositor.layoutReport`, `Theme.classic...`, `StageElement.label`, ...) and the types that depended on them.
3. Inert declarations only (fields and types, no behaviour; a placeholder in the two exhaustive switches), then the same tests run: **38 tests, 76 issues, all at runtime** (log kept in the scratch folder as `red-run.log`). Examples: plate interior alpha 0 instead of 219, no plate or bar pixels, matte bounds empty, rasteriser widths identical for weights 300 to 900 (`Set(widths).count == 4` false), `blockHeight` 0 instead of 240, gradient pixels flat, Classic rows missing, `applied.last == "v13"` false, built-in values still the old ones.
4. Implementation, then green: 38 UI005h tests pass (39 with the SDI readback test, written after the fact: the readback change was forced by the existing `HW002_SDIBenchmarkTests`, which failed at 17.2 ms against its 16 ms ceiling, see Frame time).
5. Full suite after the implementation: 12 existing tests failed; the 8 expectations the new looks change were edited (below), the ceiling test was fixed by making the output faster, two wall-clock tests passed alone (flaky under load).

The matte tests were written before the compositor or the matte was touched.

## Design against app

Design numbers are from `scripts/design-rects` on the mockup at 1920 x 1080 per panel with Inter loaded (opsz 14, `cv11`, `tnum` on the clock and timer; see "How the numbers were made"). App numbers are `Compositor.layoutReport`. Sizes in points at 1080 lines = pixels at 1920 x 1080.

`scripts/compare-rects.py` with `scripts/design-map-looks.json`: **17 of 17 mapped rectangles within 1 point** (L, T, R, B; most differ by 0.0 to 0.1), 2 mapped but not drawn (the watermark, the section label), 1 app element unmapped (the band text, its box is checked in `UI005h_RenderTests`).

| Role / element | Design box x, y, w, h (panel) | App box | Size / weight | Colour |
|---|---|---|---|---|
| Audience primary | 391.9, 262.2, 1136.2, 285.7 | same | 119.04 / 600, lh 1.2 | white, shadow 0 / 5.76 / blur 23.04 / 60 % |
| Audience second language | 631.9, 613.1, 656.1, 204.7 | same | 78.72 / 500, lh 1.3 | `#ffd17b`, same shadow |
| Stage current | 76.8, 76.8, (block 1766.4), 268.1 | left, top, height equal | 116.58 / 700, lh 1.15 | white |
| Stage second language | design box 16 px tall at y 525.6 (HTML quirk) | 1.3 box, 12 pt lower: ink 355 to 425 equals the picture | 63.59 / 600 | `#ffd17b`, lines joined " · " |
| NEXT | 76.8, 796, , 34.4 | same | 26.5 / 700, tracking .08 em | `#9fb2c7` |
| Next line | 76.8, 837.5, 1222.0, 80.55 | same | 67.12 / 700 | `#9fb2c7` (was green) |
| Clock | right edge 1843.2, top 64.8 | same | 70.66 / 700 tabular | white |
| Timer | 3518.7-1978 = right edge 1843.2, top 163.7, 302.5 x 121.9 | same | 105.98 / 700 tabular | `#49d3c3` |
| Message band | 0, 985, 1920, 95 | same | text 45.93 / 700, lh 1.3, padding 76.8 x 17.66 | fill `#ffd17b`, text `#062138` |
| Lower third plate | 115.2, 773.8, 1689.6, 210.3, radius 19.2 | same | fill `rgba(7,19,33,.86)` | key: grey 219 (`#dbdbdb`) |
| Accent bar | 161.3, 804.5, 11.5, 148.9, radius 5.76 | same | gradient `#42d9b8` to `#4d99ed` | key: white |
| LT primary | 211.2, 804.5, 1239.8, 84.0 | same | 67.2 / 600, lh 1.25 | white |
| LT second language | 211.2, 888.5, (wrapper 1239.8), 64.9 | left, top, height equal | 49.92 / 500, lh 1.3 | `#ffd17b` |

The key panel's rectangles are the same composition (mapped separately, also within 1 point).

Pixel share against the picture (tolerance 24 of 255, `scripts/compare-looks.py`, panels cut from the 2880-wide picture): audience **2.7 %** of pixels differ (2.6 % without the missing watermark corner), stage **5.4 %**, key **1.3 %**. The fill panel is not compared pixel by pixel: the plate is 86 % opaque, so the checkerboard shows through, and the design's checkerboard is not the preview's (side by side in `UI-005h-compare-broadcast-fill.png`). Remaining differences: the stage text sits up to 3 pt away from the picture's (the picture and the HTML disagree by that much: KI-141), glyph edges, the gradient's dither, and the watermark.

### How the numbers were made (and a tool fix)

`scripts/design-rects` looked for `Vendor/Inter` three folders up from the mockup, which is `docs/`; for the 07 mockup the page then fell back to another font (widths 1015 against Inter's 1074). It now walks up to the folder that holds `Vendor/Inter` and gained `--root`, `--width`, `--height`, `--css`. For 01 the old and new tool gave identical rectangles (372 elements, 0 differences), so the Show measurements are not affected as far as tested. The picture shows Inter's text cut (ink widths 1126 and 644 px at 1920 match optical size 14 with the single-storey a, `cv11`) with tabular figures in the clock and timer (ink 148 and 285 px), so the measuring run set `opsz` 14, `cv11`, and `tnum` only on the clock block. KI-125 (UI-005i) found the double-storey a in the UI pictures; picture 07's large text has the single-storey a.

## Migration v13 and the unchanged-user-theme guarantee

v13 changes no table and rewrites no row; it inserts the two Classic themes (frozen JSON literals in `Schema.swift`, fixed ids, `INSERT OR IGNORE`) when the library has a presentation or a theme. Tests (`UI005h_MigrationV13Tests`, library written with raw SQL at v12 through `LibraryStore.open(migratingUpTo: "v12")`, four user themes with colour, loop with shadow, keyed, and missing-picture backgrounds, one presentation using the first):

- every stored definition equal byte for byte before and after; decoded themes equal; library, presentation (and its theme id), slide and appState rows unchanged;
- each user theme rendered (audience, 1280 x 720, the keyed one also as broadcast) from the v12 library and from the v13 library: **digests equal to each other and to the digests recorded with the code of 38ca00d** before this slice (so also equal to what the old code drew);
- the Classic themes render the old built-in looks (digests recorded with 38ca00d); the church can rename, edit and delete them; a deleted one does not return; opening twice adds nothing; a church theme named "Classic full screen" keeps its own row;
- a library with nothing in it gets none; one with presentations but no themes gets both; a fresh in-memory library gets none.

The digests are machine and OS dependent (an antialiased edge could be drawn differently on another Mac); the byte-for-byte and decoded checks are not.

## Frame time

`wf-looks-probe perf`: three role compositions of the sample slide, 1920 x 1080, each into its own texture, GPU complete per frame, 600 frames after warm-up (3 runs each). Not asserted anywhere. Before = baseline commit; after = this slice.

| | Release warm mean (median) | Debug warm mean (median) | cold first frame (Release / Debug) |
|---|---|---|---|
| before | 0.48 to 0.57 ms (0.46 to 0.47) | 0.48 to 0.62 ms (0.46 to 0.50) | 22.3 to 23.3 / 36.9 to 38.0 ms |
| after | 0.58 to 0.69 ms (0.57 to 0.59) | 0.63 to 0.66 ms (0.62 to 0.62) | 45.5 to 45.9 / 87.3 to 88.6 ms |

About +0.1 ms warm (+25 %), well inside a 16.7 ms frame; the cold frame doubles because the gradient bitmap, the plate bitmap and the larger shadowed text bitmaps are rasterised once (cached afterwards). New per-frame allocations in the live path (said plainly): when a plate is present the compositor builds small arrays (the plated layers, their placement records) each frame; a gradient or plate bitmap is allocated once per size and cached (at most 8 of each per compositor).

**A regression found and fixed outside the render code.** The existing `HW002_SDIBenchmarkTests` (four simulated SDI outputs with readback, Debug) went from 7.2 ms to 17.2 ms per frame, over its 16 ms ceiling, because `MTLTexture.getBytes` of a picture that is not flat (a gradient, and by the same measure any photograph or video) costs about 5.4 ms instead of 0.9 ms for a flat one. `SDIOutput` now copies the frame with a blit into a shared buffer in the frame's own command buffer and one memory copy: 1.4 ms (gradient) and 0.6 ms (flat) for render plus readback (`wf-looks-probe readback`). Same build, same four scenes: classic looks 7.18 ms, design looks with the old readback 17.19 ms, design looks with the new readback **3.4 to 3.8 ms** (baseline 7.2 ms); per output render and readback 1.77 ms before, 0.84 to 0.91 ms after. `UI005h_SDIReadbackTests` checks the bytes the card gets equal `renderImage`'s, for the three roles, twice, with no ring reallocation. No real card or soak (KI-145).

## Existing tests changed (the brief's allowance: expectations the new built-in looks change)

| Test | Before | After |
|---|---|---|
| `SettingsStoreTests.v2RowsSurviveV3` | `themes().isEmpty` after upgrading a v2 library that has a presentation | `themes().map(\.name).sorted() == ["Classic full screen", "Classic lower third"]` (v13 adds them to a library with content) |
| `StageModelTests.addingAndRemovingElementsOfEveryKind` | `elements.count == 3 + 6 - 1` | `4 + 6 - 1` (the built-in layout has four elements) |
| `StageModelTests.theAppOnlyTicksForScreensWhoseLayoutHasAClockOrTimer` | removes elements of kind `.timeOfDay` from the copy | also removes `.firstCountdown` (the built-in layout also has a timer) |
| `ThemeAndLookExtraTests.builtInThemesComeFromTheStyles` | `Theme.fullScreen` / `Theme.lowerThird` equal the `SceneStyles` values | `Theme.classicFullScreen` / `Theme.classicLowerThird` equal them |
| `UI003_StageMessageBannerTests.aLayoutWithoutAMessageElementGetsABannerAlongTheBottom` | uses `StageLayout.standard` | the same with `messageBand = nil` (the built-in now draws a band; a layout without one keeps the banner) |
| `UI005b_MigrationV12Tests` | `prefix(11) == v1...v11 && last == "v12"` | `prefix(12) == v1...v12` |
| `LIB004c_PassageTests.severalVersesCanShareASlideWhenTheyFit` | `L4C.rig()` (default theme) | `L4C.rig(theme: .classicFullScreen)` (119 pt holds about 55 characters, 84 pt what the test was written for; KI-142) |

Kept passing without edits by design: the legacy entry `SceneComposer.scene(for:state:)` with the standard styles now returns the built-in looks (`ThemeAndLookTests.legacyEntryPointMatchesDefaults`, `StageParityTests`, `StagePublishingTests`). Not edited, passed alone, flaky under full-suite load: `ScriptureLibraryTests.onlyTheNeededVersesAreReadFromTheLibrary` (2.23 s against a 2 s wall-clock limit in one parallel run).

## Checks

- `./scripts/check.sh` run twice: **exit 0 both times**, `Test run with 2645 tests in 414 suites passed` both times (baseline 2606; +38 UI005h tests, +1 SDI readback test). The app built.
- Pictures (all under 1 MB): `UI-005h-app-audience.png`, `-app-stage.png`, `-app-broadcast-fill.png` (over a checkerboard), `-app-broadcast-key.png`; `-compare-audience.png`, `-compare-stage.png`, `-compare-broadcast-fill.png`, `-compare-broadcast-key.png` (design | app | difference); `-show-dark.png` (the app's Show at 1440 x 900, scaled).
- The debug capture ran the app only from a copy under a throw-away bundle id with a temporary `--library` and `--silent-audio`, in a scratch folder; it stopped itself. Nothing in `dist/`, nothing in the owner's library.

## What is not verified, and what is open

- **Hardware and keying**: nothing here has seen a keyer, ATEM, SDI-to-HDMI converter or card. The matte is proven as pixels and a splitter only. Fill alpha mode must still match the receiver.
- **Not built**: the audience watermark (product decision), the stage section label (no data), the design's "shrink never below 56 px" (the lower third wraps and the plate grows up instead), editing a plate, bar, gradient, weight or line height in the theme editor (model only; built-in themes read only), a Classic stage layout.
- Scripture slides under the default theme hold about 55 characters (KI-142); Classic or a smaller theme holds more.
- The look depends on the bundled Inter being registered at launch (KI-140); not tried on another Mac.
- The SDI readback change is Simulated only; the Show capture was seen, but no pointer, VoiceOver or real screen output was tried.
- Digests in the migration tests are for this Mac and macOS version.
- Stage text sits up to 3 pt from the picture's where the picture and the HTML disagree (KI-141).

## Files

Domain: `Scene.swift`, `Theme.swift`, `SceneComposer.swift`, `StageLayout.swift`, new `OutputLooks.swift`, `TextPlate.swift`. RenderEngine: `TextRasterizer.swift`, `Compositor.swift`, new `LooksRasterizer.swift`, `LayoutReport.swift`. Persistence: `Schema.swift` (v13). OutputEngine: `SDIOutput.swift`. OperatorCore: `StageEditing.swift`. App: `StageEditorView.swift`, `ThemeEditorSheet.swift`. New package target `LooksProbe` (`wf-looks-probe`) and test target `UI005hTests`; `Tests/OutputEngineTests/UI005h_SDIReadbackTests.swift`. Scripts: `design-rects.swift`, `compare-rects.py` (one line), new `compare-looks.py`, `design-map-looks.json`. Docs: `docs/features/UI-005h-output-looks.md`, `OUT-003`, data dictionary (v13), change log, known issues KI-138 to KI-145, hands-on checklist, current status, handoff.
