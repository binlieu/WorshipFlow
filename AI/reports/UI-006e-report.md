# UI-006e report: Stage mode features the design draws and the app lacked

Feature ID UI-006e. Levels: **Implemented** and **Unit Tested** for every built feature; Auto-fit also measured through the real compositor (text layout, no hardware). Nothing here is Simulated hardware, Hardware Verified or Live-Service Verified. Model: Sonnet, no advisor, no Codex (project CLAUDE.md).

## Ranked list (operator value over size)

| # | Candidate (from the UI-005e "left out" list) | Operator gain | Needs | Size | Decision |
|---|---|---|---|---|---|
| 1 | Per-element eye (hide) | Switch the timer, notes or next line off for one service without deleting and re-placing it | one new optional field in the layout's JSON definition | S | built |
| 2 | Band / Speaker / Clock only presets | One click to a sensible layout instead of editing a copy of Standard | nothing (new layouts made through the existing model) | S | built |
| 3 | Auto-fit | A long lyric is no longer clipped or overflowing on the confidence monitor | one new optional field in the layout's JSON definition; the compositor's existing fit floor | M | built |
| 4 | Second-language colour row | Bilingual churches colour the second line apart from the first | nothing (existing `secondLanguage.style`) | S | built |
| 5 | Minimum lyric size note (the design's caption names 64 px) | Warns before a lyric is set too small to read | nothing (pure function) | S | built, as a warning that appears only when true; the design's fixed caption text is not drawn as fact |
| 6 | Resize cursors | Feedback on the handles | pointer-layer change on a canvas fixed three times | S | not built (see below) |
| 7 | Section element | Current section and what comes next on the stage | section name per slide in the show deck (shared `ShowState` / `SlideContent`) | M | not built |
| 8 | Video element and Video button | Live video on the confidence monitor | render and output path (`showsVideo` is false for stage scenes) | L | not built |

## Built

**Per-element eye (Implemented, Unit Tested).** `StageElement.isHidden` (default false, absent in old layouts). `StageComposer` skips a hidden element. A hidden message element does not suppress the banner, so a message that is sent is never lost. The eye is at the right end of each row of the element list (the design's place); hidden rows are dimmed, the canvas box is drawn fainter and labelled "hidden", VoiceOver says "hidden". The eye is disabled on the built-in layout. Tests: hidden draws nothing and the others stay; hidden message still arrives as the banner; hidden notes draw nothing; old JSON decodes visible; round trip through the library; the built-in layout refuses; setting the same value writes nothing.

**Presets (Implemented, Unit Tested).** `StagePreset` (`.band` current + next, `.speaker` notes + timer, `.clockOnly`) and `StageModel.addPreset(_:named:)`, in `UI006e_StageModelExtras.swift`. The plus in the layout list's header is now a menu: "New layout (a copy of Standard)" (its old action), then the three presets. A preset is the operator's own layout (editable, saved, deletable), named uniquely ("Band", "Band 2"). Tests: kinds, names, persistence, frames on screen and already clamped, notes shown only on the stage scene, a name is required, a Clock only layout still gets a sent message.

**Auto-fit (Implemented, Unit Tested, compositor-measured).** `StageElement.autoFit` and `StageAutoFit.floor(for:)`. The composer sets the compositor's existing `fitFloor` on the element's text layer (and, for a current slide with its own second-language line, on that line with the same ratio, so the two keep their proportion). Floor: the lyric never goes below 64 px at 1080p (the design's minimum) and never above its own size; other elements go to half their size, not below 24. The checkbox is in the Size row beside the field (the design's place); the font-size stepper moved inside the field. Compositor tests (`UI006e_StageAutoFitRenderTests`, real Inter): long words in a small box get a factor under 1 and not below the floor; off gives `.unchanged`; a lyric already below 64 is left as set; short words are not shrunk. Limit, stated in the control's help: elements with Auto-fit shrink together by one factor (the compositor's rule), governed by the first one's floor.

**Second-language colour (Implemented, Unit Tested).** The "2nd lang." row: swatch and hex field for a current-slide element that has its own second-language line (Band and anything copied from Standard). For a current slide without one the row says "Same colour as the first language" (true: it is appended in the first colour). No new model; `setSecondLanguageColor` changes only that line's style.

**Minimum lyric size warning (Implemented, Unit Tested).** Under the Size row, only when a current-slide element is set under 64 px: "Below the 64 px minimum for lyrics at 1080p: hard to read from the back of the room." The design's fixed caption ("1920 x 1080 · minimum lyric size 64 px at 1080p · readable at 10 m") is not drawn: the app does not enforce a minimum, and "readable at 10 m" is not something it observes.

## Not built, and why

- **Section element**: the show deck carries no section name per slide (`SlideContent` has none), so the stage has nothing true to show. Needs a field on a shared type (see below).
- **Video element and Video button**: stage scenes never carry video (`showsVideo: false`); needs a render and output decision, not a control.
- **Resize cursors**: a cursor change touches the Stage canvas's pointer layer, changed three times for key and pointer bugs; not worth the regression risk for polish. Nothing in the canvas's key or pointer code was edited except one stroke opacity for a hidden box.

## Needs a migration

No SQL schema change. Two optional keys were added inside the existing `stageLayout.definition` JSON (`isHidden`, `autoFit` on an element); old rows decode as false, and old app versions ignore the keys. If the coordinator prefers these as columns, say so; they are not.
For features not built: Section element needs on `SlideContent` (or `ShowDeck`) a stored `sectionName: String?` and the arrangement order of the presentation's items (`nextSectionName: String?`) carried to `ShowState`; Video element needs no stored field but a render path.

## Rectangle table

The mapped rectangles were **not re-run** (see "Not verified"): the capture script needs `design-rects` and a window session. Changes against the mapped layout: the Size row's field keeps its 120.5 pt width (the stepper now sits inside it); the Auto-fit checkbox, the 2nd lang. row, the eye buttons and the presets menu (the plus keeps its 12 pt label) are the designed rectangles. The map file `scripts/design-map-stage.json` was not extended.

## Shared-file lines

- `Packages/WorshipFlowKit/Sources/Domain/StageLayout.swift` (shared domain type, additive): two defaulted fields on `StageElement` (`isHidden`, `autoFit`, in the initialiser, coding keys and tolerant decoder), the composer skipping hidden elements, setting `fitFloor`, and one condition for the message banner. New file `Domain/StageAutoFit.swift`.
- `App/Sources/UISnapshotStage.swift` (Stage scenario): one line calling `runStageFeaturesScenario` when `UI_SNAPSHOT_STAGE_FEATURES` is set.
- `WORSHIPFLOW.xcodeproj/project.pbxproj` is regenerated by `check.sh` (new files); it is not committed from this branch, run `xcodegen generate` after merging.

New files: `UI006e_StageModelExtras.swift`, `StageAutoFit.swift` (Domain), `StageFeaturesSnapshot.swift`, tests `UI006e_StageFeaturesTests.swift` (16) and `UI006e_StageAutoFitRenderTests.swift` (3).

## Docs entries for the coordinator

Change log: "UI-006e: Stage: hide an element with the eye in the element list; Auto-fit on the Size row; second-language colour row; presets Band, Speaker and Clock only from the plus menu; a warning under Size when a lyric is set under 64 px. Two optional keys in the layout definition JSON (`isHidden`, `autoFit`), no schema change."
Known issues (unnumbered): "Stage: Section and Video elements not built (need a section name on the show deck; a stage video path); no resize cursors on the canvas handles; Auto-fit shrinks all auto-fitted elements by one factor; hide and Auto-fit are not undoable (like the other inspector settings)."
Hands-on checklist: "Stage: on your own layout click the eye of Notes, the canvas box fades and the stage screen drops it; click again. Tick Auto-fit on the lyric and send a long verse: it shrinks, never under 64 px. Change the 2nd lang. colour. Plus menu: make Band, Speaker, Clock only. Tab to an eye button with keyboard access: Space acts on it; click elsewhere and Space, Return, B, Escape act on the show again."
Feature spec updates: STAGE layout element gains `isHidden` and `autoFit`; presets; Auto-fit floors.

## Checks

`./scripts/check.sh` exit 0 (package tests 3059 in 483 suites passed, debug and release app builds pass). `scripts/fixn-keys.sh` on the final build: Stage after click and after drag, Return, Space, B, B, Escape all acted on the show and Right nudged the box 1 pt, as in FIX-N (synthetic input).

## Not verified

Operating the new controls with a real mouse (the screen may be locked); VoiceOver; the key behaviour with an eye button focused beyond the shared `wfFocusReport` rule; Auto-fit on a real stage screen or with the owner's fonts; light-mode appearance of the new rows beyond the shared tokens; rectangle comparison for the new rows.
