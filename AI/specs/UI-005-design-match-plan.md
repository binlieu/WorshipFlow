# UI-005: match the design in `docs/UI` exactly, screen by screen

The owner, 2026-11-21: "after reviewing docs/UI I see the current built is missing a lot of features and not exactly same as UI. Review the design once more time and change the UI to exactly pixel to pixel with the design. Ask me questions if you are not sure or need to make decision."

This changes ADR-0007's working rule for appearance: the design is now the target for how the app looks and what it offers, not a guide. Behaviour that protects a live service or the truth about hardware still wins (below).

## The audits

Three read-only audits list every difference, with the design value and the app's value and code location:

- `AI/reports/UI-005-audit-show.md` (Show and the shared components: about 78 small, 12 layout, 6 features)
- `AI/reports/UI-005-audit-edit-media-stage.md` (Edit 18/11/5, Media 17/5/4, Stage 11/8/3)
- `AI/reports/UI-005-audit-screens-cues-looks.md` (Screens 26/7/10, Cues 21/2/5, output Looks 16/9/3)

Each slice's brief is its audit file plus this plan. A slice is done when every row of its audit is closed (matched, or listed in the report with the reason it cannot be).

## The owner's decisions (asked 2026-11-21)

1. **Order: everything, screen by screen.** Finish one screen completely, appearance and the features the design draws for it, before the next.
2. **Things the owner asked for that the design does not show** (the bin player, hot folders, the live-override row, the four layer clears, scripture, Quick edit and Edit live slide under the monitors): **keep, fitted to the design**: restyled with the design's components and placed where they do not disturb the designed layout.
3. **Transport bar: hidden in Edit, Stage and Screens, as designed.** Keyboard transport keeps working in every mode.
4. **Where the design sources disagree, the screen pictures (PNG) win.** The HTML and CSS mockups give the exact numbers where they agree with the picture; tokens and README apply only where the picture is silent.

## The coordinator's defaults for the audits' other questions

Taken from each audit's recommendation unless a decision above overrides it. The owner may overrule any of them; each slice report repeats the ones it used.

- Custom controls (toggle, checkbox, slider, segmented control, pop-ups) are built once to the design and used app-wide.
- Because the order is "everything": the missing features of a screen are built in that screen's slice or a follow-up slice directly after it, each with its own tests; none is drawn as a dead control. A control whose feature is not built yet is left out until it works, and the slice report lists it as open.
- Show: libraries get a kind (songs, scripture, sermons, announcements) that picks the icon; playlist items gain media file, then announcements loop and sermon; props gain per-prop targets, then text props; the four design Looks are seeded on a new library only; the extras go in one slim row under the monitors; Clear keeps `esc` and shows it; meters stay free of red; timers follow the picture; a sidebar toggle and a service date on the playlist give the design's title.
- Edit: words fields move to the inspector's Slide tab; the header row's theme control moves to the Theme tab and the rest to Show; inspector tabs Object, Slide, Theme with effects, layers and pixel position.
- Media: named collections and audio playlists, offline files with Locate, in and out points and markers, a grid and list toggle with a real list; the bin player sits in the clip strip position.
- Stage: Band, Speaker and Clock layouts added beside Standard (existing screens do not change); eight handles as on the slide canvas; Timers move to a sheet from the toolbar chip.
- Screens: Looks become a per-screen pop-up, props live in the Show inspector, Developer moves to Settings.
- Cues: disabled "later" rows are drawn only as the design draws them and say "later"; keyboard trigger and Test in Preview are built; the on-screen note about order states what the executor really does.

## What the design may not override

These come from `CLAUDE.md` and stand whatever the picture shows:

- **Nothing the app has not observed is drawn as fact.** The signal chain's enclosure, converter and destination are labels the operator types, marked as such. Pixel format, colour and audio rows show what the app really does. The SIMULATED mark stays wherever a device is simulated, restyled to the design.
- **Speaker notes never reach an audience or broadcast screen**, so the design's Notes layer on a Broadcast screen is not built.
- **Red means on air** and nothing else.
- **Editing never changes Live**, and Preview, Live, Clear, Blackout and Stop keep their meanings.
- Accessibility labels, keyboard operation and Vietnamese text rendering are kept through every restyle.
- No verification level is raised by a restyle: a screen that matches the picture is Implemented, not verified on hardware.

## Order of slices

One agent at a time owns the app's view files; each slice is reviewed, checked and committed before the next starts.

0. In flight first: UI-004 (rename to WorshipFlow, version and About, pill borders, editor drag), then FIX-G (review fixes for MEDIA-010 and LIB-005, migration v11).
1. **UI-005a Shared components and Show appearance** (audit-show, the S and M rows, and the cross-screen component rows of the other two audits). Pixel comparison against `01`, `01b`, `09`, `08`, `10`.
2. **UI-005b Show features**: library kinds, media-file playlist item, per-prop targets, error actions, sidebar toggle and service date; then announcements loop, sermon item and text props.
3. **UI-005c Edit**, appearance then features.
4. **UI-005d Media**, appearance then features.
5. **UI-005e Stage**, appearance then features.
6. **UI-005f Screens**, appearance then features.
7. **UI-005g Cues**, appearance then features (markers last).
8. **UI-005h Output Looks**: type sizes and weights, the audience background, the stage composition, the lower-third plate and accent bar in the theme model and the key matte.

## How "pixel for pixel" is checked

Each slice adds to the debug snapshot hook so the app can be captured at the design's window size (1440 by 900 points, 2x) in the same state as each design picture, in dark and light. The slice report includes, per design picture: the app capture, a side-by-side, and a difference image with the share of pixels that differ by more than a small tolerance, with every remaining region explained (real content such as song text differs from the design's sample text; say so). The comparison tool lives in `scripts/` and is run by hand, not by the check. A slice is not called matched from code reading alone.

## Added 2026-11-21: the interface font is Inter

The design's pictures were rendered in Inter while its README says San Francisco. Asked, the owner answered: "Font inter". So the operator interface is set in Inter (SIL Open Font License 1.1), bundled with the app, with the same OpenType features the mockup CSS turns on (`tnum`, `cv11`); monospaced figures stay SF Mono as the mockups have them. San Francisco remains the fallback for any script or glyph Inter lacks, so Vietnamese and other library text never shows a missing glyph. This is about the operator interface only: what is projected on audience, stage and broadcast screens follows each theme's own font and is not changed by this. The font files go in the app's resources with the licence text, are listed in `NOTICE`, the README's third-party section and the About window, and are registered at launch for the process only (nothing is installed on the Mac). Done as its own slice (UI-005i) after UI-005b, before Edit, with the comparison re-run for every picture.

## Added 2026-11-21: the match is measured by rectangles, and the order changes

After the Show slices and the Inter font, the pixel difference against `01-operator-show.png` was still about 20%, and Inter did not move it. The coordinator looked at the difference image: the cause is geometry (rows drifting, controls at other x positions, monitors larger, the extras row pushing the inspector down), not font or sample art as the slice reports had said. From here on a screen is matched when every design element's rectangle, font size, weight and radius agree with the app's within 1 point, measured by the tools UI-005j builds (rectangles dumped from the mockup HTML and from the app, joined by a mapping file). The pixel percentage is kept for reference only.

New order: FIX-H (review fixes), then UI-005j (Show geometry, builds the tools), then UI-005h (output looks: type sizes, backgrounds, lower-third plate, because slide artwork shows in every thumbnail and monitor), then Edit, Media, Stage, Screens and Cues, each with a mapping file for its mockup and the same 1-point rule.
