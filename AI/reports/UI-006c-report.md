# UI-006c report: Edit mode features the design draws

Feature ID UI-006c. Brief `AI/specs/UI-006-mode-features.md`, design `docs/UI/screens/02-editor.png` / `mockups/02-editor.html`. Branch `worktree-agent-abc12defbe1168dda`. Levels: **Unit Tested** for the logic, **Implemented** for the views (looked at in debug captures at 1440 x 900, not driven by hand: the Mac screen may be locked, so clicks were not used; the states below were reached through a debug notification hook). Not Hardware Verified, not Live-Service Verified.

## Ranked list (operator value over size)

| # | Feature (audit row) | Gain | Needs | Size | Decision |
|---|---|---|---|---|---|
| 1 | Align to slide (E13/E14) | place a box exactly: edges, centres | pure function + two methods on `SlideEditorModel` (uses the public `edit`) | S | built |
| 2 | Audience / Stage / Broadcast preview (E16) | see how the slide composes on each screen before going live | existing `PublishedScenes`; view state only | M | built |
| 3 | "Saved ... ago" (E19) | know that typing has reached the library | `hasUnsavedDrafts` and `draftSaveProblem`, read once a second | S | built |
| 4 | Zoom (E17) | inspect and place at 25 to 100 % | view state only | M | built |
| 5 | Fit text to box, background fill for text (E35, E38) | stored mode / field on `TextObject` and a compositor change | new stored fields | M-L | not built, migration list |
| 6 | Video object (E12) | video on a slide | new `SlideObject.Content` case, decoding, compositor | L | not built |
| 7 | Layers list (E40) | name, hide, lock, list objects, props, background | object names, hidden flag, roles | L | not built, migration list |

## Built features

- **Align** (`ObjectAlignment`, `SlideEditorModel.align/alignSelected` in `UI006c_EditFeatures.swift`): Left, Horizontal centres, Right, Top, Vertical middles, Bottom, Centre on slide; the menu sits at the design's Align rectangle. One undo step, saved with the slide by the normal debounce, no write when already there, live show untouched. Disabled with nothing selected or off Audience. Tests: `UI006cAlignTests` (5). Unit Tested; the menu Implemented.
- **Preview as screen** (`EditPreviewRole`, `EditPreviewScene`, `AppModel.editPreviewScene` in `EditCanvasChrome.swift`): a segmented control at the design's rectangle. Audience is the editing view; Stage and Broadcast draw the composer's scene for the first enabled screen of that role (with its Look and theme), read-only: no boxes, no guide, Text / Shape / Image / Align / Arrange disabled, selection cleared, caption says "Stage screen, read-only". No notes parameter exists, so no speaker notes can reach any preview. Tests: `UI006cPreviewTests` (4). Stage and Broadcast looked at in a capture (the stage composition shows the words only). Unit Tested + Simulated look; not tried with a real stage layout other than the built-in.
- **Saved text** (`EditSaveStatus`, `EditSaveText`): "All changes saved" until it has itself seen text leave the waiting state, then "Saved just now / N s ago / N min ago / N h ago" timed from the look that saw the save (about 1 s resolution); "Saving..." while waiting; "Not saved" in the warning colour while the workspace reports a draft save problem. At the right of the live strip. Tests: `UI006cSaveStatusTests` (4). Unit Tested; view Implemented.
- **Zoom** (`EditZoom`): pop-up at the design's rectangle: Fit, 25, 50, 75, 100 % of the 1920 x 1080 output. The field always shows the real percentage (Fit shows 42 % at the design's 800 pt canvas; the design's "62 %" is its own scale and is not copied). A fixed zoom that does not fit scrolls both ways; the picture is drawn at up to 1920 px wide so it stays sharp. Tests: `UI006cZoomTests` (2). Looked at at 100 % (scrolls, sharp) and 50 %.
- **Moved**: Undo, Redo, Duplicate, Delete went from the bar (room now used by the switch and zoom) to small icons at the right of the live strip, before the saved words. Same actions, same help and accessibility labels.

## Not built

E12 Video (no video object), E35 Fit and E38 text Background fill (stored fields), E40 Layers (names, hidden, roles); the design's second lyric box is the theme's words, not an object (unchanged). The Video button keeps its 76.1 pt of room.

## Needs a migration (stored fields; JSON of `SlideObject` / `TextObject` and the renderer, no column)

- `TextObject.fit: enum { none, shrinkToFit }` and `TextObject.backgroundFill: ColorRGBA?` (plus compositor support in `TextLayer`).
- `SlideObject.name: String?`, `SlideObject.isHidden: Bool` (default false), `SlideObject.isLocked: Bool` (default false); the scene must skip hidden objects.
- `SlideObject.Content.video(VideoObject { mediaID, loops, muted })`.

## Rectangle table (`scripts/compare-rects.py`, `scripts/design-map-edit.json`, 121 entries, 8 added)

Dark: 99 of 121 within 1 pt; light: 100 of 121 (the 22 and 21 outside are the 16 shared-toolbar ones from UI-005c and the text-width ones listed there). New entries (L/R edge difference, points): Align +1.0 / +0.7, divider +1.0, switch +1.1 / 0.0 (segments up to +1.3), strip "Saved" left edge -6.5 (its words are "Saved just now" in the app against the design's "Saved 2 s ago": content, the right edge matches), zoom field -1.8 left (the app's field is 64 pt wide, the design's 62.2). Zoom's text reads "42%" where the design reads "62%".

## Shared-file lines

None edited. `WORSHIPFLOW.xcodeproj/project.pbxproj` regenerated by xcodegen (one new app file); regenerate after merge. `scripts/design-map-edit.json` extended (my own map). New files: `App/Sources/EditCanvasChrome.swift`, package `UI006c_EditFeatures.swift` and its tests. `EditMode.swift` line with `workspace.slides.indices.contains(i)` kept untouched. Debug-only hook `wf.debug.editPreview` (inside `#if DEBUG || WF_MEASURE`) and capture steps in `EditDesignCapture.swift`.

## Docs entries for the coordinator

Change log: `UI-006c: Edit gained Align (to slide, 7 commands), the Audience / Stage / Broadcast preview (read-only off Audience), Zoom (Fit, 25 to 100 %) and "Saved ... ago" in the live strip; Undo / Redo / Duplicate / Delete moved to the strip. Tests UI006c_EditFeaturesTests.`

Known issues (unnumbered): `Edit: not built: Video object, text Fit and Background fill, Layers list (need stored fields, see UI-006c report). Stage and Broadcast previews are read-only compositions of the built-in stage layout and the Look, not the operator's custom stage layouts. Zoom field is 1.8 pt wider than the design. Saved time has about 1 s resolution and exists only after the first save seen this session.`

Hands-on checklist: `Edit: select a box, use Align > each of the 7 and press Command-Z once after each (one step); switch Audience / Stage / Broadcast and check the boxes disappear and Text / Shape / Image are disabled; pick 100 % and scroll the canvas, drag a box while zoomed; type in a words field and watch "Saving..." then "Saved just now" then counting up; cut the library file's write permission and check "Not saved".`

Feature spec updates: SLIDE editor spec: align, preview role, zoom, save status.

## Check

`WF_DERIVED_DATA=<scratch> ./scripts/check.sh` exited 1 twice with 3055 tests in 485 suites (3040 before plus 15 new, all 15 pass). Failures both times only timing-sensitive tests in code this slice does not touch: run 1 `ToolProcessRunnerTests.aClientThatHangsIsStopped`, `MIDIRouterTests` (2); run 2 the same plus `ScriptureLibraryTests.onlyTheNeededVersesAreReadFromTheLibrary` (2.2 s against 2 s). The check stops at the package tests, so the app Debug build was run by `scripts/design-capture-edit.sh` (build succeeded, used for all captures); a Release build was not run.

## Not verified

No mouse or keyboard driving (screen may be locked): menus, the pop-up, dragging while zoomed and the Saved states "Not saved" were not exercised; Saved text was seen in captures only as "Saved just now / N s ago". VoiceOver and Tab order of the new controls. Light-mode captures of the new states other than the main Edit picture. Narrow windows. The capture needed `UI_SNAPSHOT_CLIP` pointing at the main checkout's untracked `TestMedia/loop-1080p5994.mov` (absent from a worktree); nothing was copied into the repository.
