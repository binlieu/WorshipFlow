# UI-005h: what the screens show, matched to `07-output-looks`

Feature IDs: UI-005h (OUT, KEY, STAGE). Model: Sonnet, followed by an independent review pass because it touches the render path and the key matte. One agent owns the render, theme and stage files and migration v13. Starts after UI-005j is committed.

## Read first

`CLAUDE.md` (the hardware and video-output rules and the verification levels bind this task); `AI/specs/UI-005-design-match-plan.md`; the section for picture 07 in `AI/reports/UI-005-audit-screens-cues-looks.md` (the work list: every row); `docs/UI/screens/07-output-looks.png` and `docs/UI/mockups/07-output-looks.html` with `ui.css`; `docs/UI/README.md` on the three role compositions; the feature specs for themes, stage and broadcast keying in `docs/features/`; `App/Sources/LiveScenes.swift`, the `RenderEngine` text and compositor sources, `Domain` themes and `SceneComposer`.

## What to build

1. **Type on the outputs as designed.** The theme's text style gains a weight (and anything else the picture needs that the model lacks: letter spacing, line height, a soft shadow as an alternative to the outline). The built-in themes take the design's sizes, weights, colours and shadow for audience (first and second language), stage and lower third. Vietnamese stacked diacritics must still render without clipping at the new sizes and weights: test with the existing diacritic cases.
2. **Audience background.** The built-in audience theme has the design's gradient background (a gradient is a theme background kind if it is not one yet). Motion and picture backgrounds behave as today.
3. **Lower third as a real plate.** The theme model gains a plate (rounded rectangle with its own fill, opacity, padding and radius) and an accent bar (gradient) behind lower-third text; "Lower third" becomes a built-in theme with the design's geometry. The broadcast fill carries plate and text; the **key matte** carries the plate's shape and opacity, not only the letters, with premultiplied and straight alpha both correct. Add pure tests on the matte: plate interior alpha, plate edge antialiasing, text over plate, outside is zero, and fill and key stay the same size and position frame for frame. This is Implemented and Unit Tested only: say plainly in the docs that no keyer has seen this signal.
4. **Stage composition as designed.** Current line, "NEXT" label and next line in the design's sizes, weights and colours (the green goes), second language in its own style, the clock and timer where the picture has them, and the stage message as the warning band. The section and repeat label ("CHORUS ×2") is built if the arrangement data already gives it without a model change beyond this task; otherwise it is listed as open. Existing stage layouts the operator made are not altered; the built-in layout is.
5. **Existing libraries.** Migration v13 is additive. A user's own themes keep exactly how they look today (new fields default to the old appearance: regular weight, outline, no plate). Only built-in themes change. Presentations using a built-in theme therefore change appearance on upgrade: say so in the change log and the hands-on checklist, and offer the previous built-in looks as "Classic" themes so a church can go back.
6. **Everywhere the slide is drawn.** Thumbnails, Preview and Live monitors, the keyed previews in Screens, and the real outputs all come from the same render path, so check each shows the new look, and that the snapshot hook's captures for Show now carry the design's artwork.

## Measuring

Render the three role compositions at 1920 by 1080 with the design's sample words and compare with the three panels of `07-output-looks.png` using the rectangle method where the mockup HTML gives rectangles (text boxes, plate, bar, margins) and the pixel comparison for reference. Report text box position and size, font size and weight per line, plate and bar geometry, and colours, design against app.

## Tests

Test-first, order checked, failing output recorded. New files `UI005h_*.swift`; do not edit existing tests except exact pixel or metric expectations that the new built-in looks change (list each, with before and after) and exact-count migration assertions (to `prefix(n)`). Cover: migration v13 on a v12 library keeps every row and every user theme renders pixel-identical before and after; the matte tests above; weight reaches the rasteriser; the gradient background; stage composition content per element; speaker notes still never reach audience or broadcast; a performance check that a full-HD three-role frame is not slower than before beyond a stated margin (measure, do not assert on wall-clock time in the test suite; put the numbers in the report).

## Rules

- Rendering stays off the main thread; no new per-frame allocation in the live path without saying so; no force unwraps.
- Do not claim keying, alpha or hardware behaviour beyond what the tests show.
- Do not edit `docs/UI`, `docs/adr`, `AI/specs`, `Vendor/`, the vendored `sdk/` folder.
- No git state changes. No advisor tool. No full computer control. Never open the owner's real library; if you launch the app use your own scratch folder, a temporary `--library` and `--silent-audio`, stop only what you started, leave nothing in the home folder or in `dist/`.
- The repository is public: no personal strings; sample words are the design's or invented, no Bible text.
- If you are running out of room, stop at an item boundary with the check passing and say what is done.
- Finish with `./scripts/check.sh` twice. Report to `AI/reports/UI-005h-report.md` with pictures `AI/reports/UI-005h-*.png` (each under 1 MB); update the feature specs, data dictionary (v13), change log, known issues and hands-on checklist.
