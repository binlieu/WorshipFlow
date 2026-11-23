# UI-008 report: every mode re-measured against its design

Feature IDs UI (Show, Edit, Media, Stage, Screens, Cues). Brief `AI/specs/UI-008-remeasure-modes.md`. Model: Sonnet. Level: **Implemented**, measured in Debug builds on the seeded design library at 1440 x 900 points, dark and light, on this Mac with the display unlocked. Not Hardware Verified, not Live-Service Verified. No migration, no behaviour change, no test edited.

## 1. Why Show measured 32 of 220 (FIX-U) and not 205 of 242 (UI-005j)

**It was the measurement, not the layout.** Reproduced with UI-005j's method exactly (`UI_PREFIX=UI008 scripts/design-capture.sh`, `scripts/design-rects` on `01-operator-show.html`, `scripts/compare-rects.py` with `scripts/design-map-show.json`) on today's tree: **209 of 242 within 1 pt, dark and light** (toolbar 16 of 23, sidebar 31 of 32, centre 54 of 65, dock 42 of 51, inspector 50 of 52, transport 16 of 19). That is 2 better than UI-005j's 207 and the same elements are out (the list below). Evidence that the layout did not move: the pixel comparison of the same capture reads 13.2 % (light, tolerance 24) against UI-005j's 15.3 %; the per-region counts equal UI-005j's except two more in the dock and one in the centre.

What I could and could not establish about FIX-U's run:
- The design dump is not the variable: dumped at five viewport sizes (1100 x 900 to 1512 x 982) it gives the same 242 mapped and 209 within 1 pt each time.
- FIX-U's own numbers fit a capture whose window was not 1440 x 900: toolbar 16 and transport 16 are the same as today's (those two bars are anchored to the window's edges), the four body regions read 0, and 22 fewer elements were drawn. FIX-U says "the screen is locked". macOS shrinks a 1440 x 900 window to a small or locked display. **I could not lock the screen to reproduce it** (that is a system setting), so this cause is inferred, not shown. Commit `8590d5a` was not needed and was not built.
- **Fix to the tool so the number is true again:** `scripts/compare-rects.py` now reads the `window` size the app dump already records (`DesignProbe.write`) and **exits 3 with a warning** when it is not 1440 x 900 (`--allow-size` overrides). Tested with a dump edited to 1280 x 800: prints the warning, exit 3. A run on a shrunken window can no longer produce a plausible-looking table.
- A second measurement defect found on the way (Cues): the marker action list added by UI-007d reused the macro's rectangle ids (`act.N`, `main.add`), so the last list drawn overwrote the macro's and the table read "act.0 T +505". The marker list now tags `mk.act.N` / `mk.main.add` (`rectPrefix`, debug-only tag names; no layout or behaviour change).

## 2. All six modes, dark and light, final tree (after the fixes in section 3)

"Mapped" counts the map's entries that are drawn. "Previous" is the last recorded count for that mode (report named).

| Mode | Appearance | Mapped | Within 1 pt | Previous count |
|---|---|---|---|---|
| Show | dark | 242 | 209 | 207 of 242 (UI-005j) |
| Show | light | 242 | 209 | 207 of 242 (UI-005j) |
| Edit | dark | 129 | 108 | 101 of 121 (UI-007c) |
| Edit | light | 129 | 109 | 102 of 121 (UI-007c) |
| Media | dark | 178 | 159 | 156 of 175 (UI-005d) |
| Media | light | 178 | 159 | 156 of 175 (UI-005d) |
| Stage | dark | 92 | 73 | 56 of 92 (UI-007e) |
| Stage | light | 92 | 73 | 56 of 92 (UI-007e) |
| Screens | dark | 181 | 149 | 147 of 178 (UI-005f) |
| Screens | light | 181 | 149 | 147 of 178 (UI-005f) |
| Cues | dark | 186 | 159 | 156 of 182 (UI-005g) |
| Cues | light | 186 | 87 | none (no light design picture; UI-005g measured dark only) |

The extra mapped entries are the ones added in section 4. On the entries that existed before, nothing got worse in any mode (diffed against the first measurement of this session): Edit's old 121 are still 101 / 102, Media's old 175 still 156, Screens' old 178 still 147, Cues' old entries are 157 of 183 (dark; UI-005g read 156 of 182, the extra one is the macro's `main.test`/`act` rows now read from the right list after the prefix fix).

The 33 toolbar and transport entries in every table are the shared bars (`toolbar` 16 of 23, `transport` 16 of 19 in every mode): the timers capsule (-2.7), the timer parts, and the transport text block (-0.7 / -1.6) are all SwiftUI's text measure against the browser's, as UI-005j recorded.

### Every element off by more than 1 pt (app minus design, points; L T R B; dark, light is the same except where stated)

**Show** (shared bars excluded, listed above): dock tile names "Soft particles" R -2.1 and "Deep blue drift" R -2.0; PREVIEW tag R -2.0; LIBRARIES R -1.9; stage message field R +1.5; layer switch L +1.5 and its first segment L +1.5 R +0.9; title T +1.0 B -1.0 R +1.4; Arrangement field L +1.4; LIVE tags R -1.3; Loop pill R +1.3; speaker icon L +1.3; wrapped-section grid T +0.9 B +1.2; Backgrounds tab L -0.5 R -1.2; Videos tab L -1.2; Audio tab R +1.1; Reflow R +1.0; Quick edit L +1.0 R +1.0 (its key hint R +1.0); view switch and its two segments L +1.0 R +1.0. Every one is a text width (SwiftUI rounds Inter up 0.5 to 2 pt) or one fractional point from the card-height rounding; none is a padding, size or gap.

**Edit**: strip note L -2.8 R -7.7; "Saved" L -6.5 (dark only: "Saved 2 s ago" content); "Slide 3 is live" R -2.8; Audience / Stage / Broadcast switch L -0.7 R -1.8, Broadcast L -1.0 R -1.8, Stage L -0.5 R -1.0; **zoom field L -1.8** (KI-197, see section 3); Title-safe label R +1.5; Shape L +0.6 R +1.4; Image L +1.4 R +1.0; Video L +1.0 R +0.9; vertical-align switch R +1.7, Mid L +0.8 R +1.5, Bot L +1.5 R +1.7. All text measure or the content of the seed ("Saved 2 s ago" is a sentence).

**Media**: strip scrub R -55.2, remaining L -55.2 R -54.6, badge R -2.7, meta L -2.7 (R is content); the first three are the owner's extra marker-list button after Add marker (not in the design), which takes 55 pt; Import L +2.0 R +1.5; layer switch L +1.5 and segment L +1.5 R +0.9; "Audio cue" label R -1.5; level label "R" L +0.8 R +1.2.

**Stage**: Auto-fit box L -2.5 (the app's rectangle is the whole 71 pt control, the design's the 14 pt box); Size field R -2.5 (its width is now what the 13 pt "Auto-fit" word leaves: 118 against 120.5, because the word is 49 pt in SwiftUI and 46.5 in the browser); the six element eye buttons L -6 T -5 R +8 B +5 (a 26 pt hit target against the design's 12 x 16 glyph; the glyph is within 1 pt of the design's, the hit target is kept); Stage badge R -1.5; "Stage layouts" R -1.4; "Next slide" label R -1.1; Clear L +0.5 R +1.1.

**Screens**: Running (simulated) L -3.2 R -5.9; role tag Broadcast L -1.6 R -3.2; map note L +4.2; Alpha switch R -2.7 and its two segments; SDI titles R -2.1 to -2.4; preset switch L +1.9; Fill title R -1.8; Export log bundle R -1.7; Audience / Broadcast role tags R -1.7 / -1.5; Verification R -1.7; Livestream graphics R -1.6; Stop output L +1.5; Add screen L +1.3. (Text measure; Running (simulated) is also content.)

**Cues** (dark): the order note T +187 B +203 and the Activity section T +116 (Activity R -297 and its lines R -90 are content: the design draws four lines); keyboard section B +116 (13 keys against 9); the left column's Control inputs, its rows and Schedule T -26 (the design lists two presentations under Slide actions, the app one); the Control inputs dot L -4.8; Trigger L -30.8 (the design has no keyboard half in the trigger text); pill L +0.6 R -1.5; **Playback markers axis T -16 B -18** (the app's axis row is 14 tall and sits 16 higher; it has three times, the design five). The new header and track entries are within 1 pt.
**Cues light** is 87 because the inspector column is 7 pt left and 3 pt narrower in the whole right column (see section 5).

### Not in the design (new controls, left as they are)

Show: none new in this pass. Edit: Layers eye, lock and arrow buttons; Stage-preview read-only state. Media: the marker-list button, the drop, mute and send-menu extras, the sixteenth bin tile (the sound). Stage: the Section menu, the element eye buttons (their 26 pt target). Screens: the notes section, the offline and Identify banners. Cues: the Schedule section, keyboard keys 10 to 13, the marker action list under a marker, the Dry run button and its result card.

## 3. Fixes (largest first), before and after

1. **Stage inspector 4 pt left of the design (KI-252): 7 of 32 -> 24 of 32 within 1 pt** (Stage total 56 -> 73 of 92, dark and light). Cause found by bisecting the inspector's parts with a temporary environment switch (not committed): the Size row. `HStack(spacing: 8)` ended in `Spacer(minLength: 0)`, and a spacer after the 8 pt gap made the row's ideal width 8 pt more than the 275 pt column content, so every section was laid out 8 pt wider than the column (centred: 4 left, 4 right: "283 wide at x 1149" against "275 at 1153"). `StageInspector.sizeControl`: the spacer is gone and the size field is `maxWidth: .infinity` (the design's flex row) instead of a fixed 120.5. All twelve rows (Shows, Size, Weight, headings, the element list, Assigned to, the note) moved from L -4 / R +4 to 0. Note, Assigned toggle and screen rows are now exact.
2. **Stage Auto-fit label 12 pt against 13 (KI-253): fixed** (`Font` 13; tag size 13). The font mismatch no longer prints. A consequence: the 13 pt word is 49 pt in SwiftUI (46.5 in the browser), so the field takes 2.5 pt less and the box sits 2.5 pt left; left as a text-measure offset.
3. **Screens "Add screen" button 26 pt against 22 (found by the new map entry): T -2.0 B +2.0 -> 0.0 / 0.0** (`ScreensMode.swift`: `CuesSmallButtonStyle`, the 22 pt style that already exists for Cues' Manage button). L +1.3 remains (the label is 1.3 pt narrower in SwiftUI).
4. **Edit zoom field 1.8 pt wide (KI-197): not fixed, with the cause.** The field hugs its text: 9 + text + 6 + 12 + 9. SwiftUI's "50%" is 28 pt, the browser's 26.2, so the field is 64 and the design's 62.2. Setting the width to 62.2 (tried and rejected) truncates the text to "50..." (seen in the capture), so it is a text-measure offset like the rest of the bar, not a layout drift. Source unchanged (reverted to `minWidth: 62.2` + `fixedSize`).
5. Measurement fixes: the window-size guard and the `mk.` rectangle prefix (section 1).

Nothing in `Show` was touched; `FIXO_ViewSourceTests`, `FIXQ_ViewSourceTests`, `FIXS_CellSlotTests` and `FIXU_ViewSourceTests` are unaffected and FIX-U's three splits are intact. No source-rule test conflicted.

## 4. Maps extended (only where the design has the element)

- `design-map-edit.json` (+8): Video button (L +1.0 R +0.9, the cascade of Image's +1.4), Fit row and its label and field (exact), Background fill row, its checkbox and its field (exact), the Layers heading (left edge only: the app's Layers section sits lower under taller sections). Edit 121 -> 129 mapped; 7 of the 8 are within 1 pt. The design has no Layers rows of its own beyond the heading (its `.ly` rows are not drawn in the app the same way: see "Not in the design").
- `design-map-media.json` (+3): Mark in, Mark out, Add marker (UI-007d built them): top and bottom compared, left and right skipped (the owner's marker-list button after Add marker shifts them 55 pt). Within 1 pt.
- `design-map-screens.json` (+3): Add screen, Identify screens, Remove screen (UI-006f built them): Identify and Remove within 1 pt (L +0.8, R 0), Add screen L +1.3.
- `design-map-cues.json` (+3 entries, +1 ignore rule): Playback markers header and track (within 1 pt; the track's top and bottom skipped: 34 pt against 54 with the names under the lines), the time-axis row (T -16 B -18, listed above); `mk.act` / `mk.main` explained as the marker's own list.
- Not extended: Media's routing matrix, Cue meters, collections and audio collection names (still not built to the design's shape, their LEFT OUT rules stand), Cues' marker lines and labels, Show and Stage (their maps were complete).

## 5. Known-issue text for what was not fixed (unnumbered; the coordinator numbers them)

- **Cues, right column, light capture: content 7 pt left and 3 pt narrower than the design's.** It appears when the Activity list holds a two-line entry (a marker line "marker ... at 00:11.0 in Waves ... : 0 actions" is two lines), and does not appear with Activity hidden or with each entry limited to one line (both tried, in a throw-away build). The dark capture runs before the marker fires, so it has one line and is exact. The cause (the column's vertical overflow changing how the scroll content is laid out, not a visible scroller) was not found; the fixed-width MIDI and keyboard tables (90.5 + 224.6 pt) are the likely reason the content cannot shrink. An operator whose Activity grows past the column sees the same shift. Offset when it shows: L -7, R -10 on every right-column element. A `.frame(maxWidth: .infinity)` on the activity message was tried and did not help (reverted).
- **Edit zoom field 1.8 pt wide**: text measure (28 against 26.2); not fixable without truncating (section 3).
- **Stage Auto-fit**: field 2.5 pt narrow (118 against 120.5) and checkbox box 2.5 pt left; the element eye buttons' 26 pt hit target against the design's 12 x 16 glyph.
- **Cues Playback markers**: the order note is 187 pt lower than the design's (marker list and the marker's action list are added), and the time axis is 14 tall at 447 against 16 at 463 (three times against five).
- **Media strip**: the owner's marker-list button takes 55 pt, so the scrub, the remaining time and the three mark buttons sit 55 pt left of the design.
- **The Show, Edit, Media and Screens residuals** listed in section 2 are text widths (0.5 to 2.7 pt); none is a size, padding or gap.

## 6. Change log and hands-on entries for the coordinator (docs are not edited here)

Change log: `UI-008: Stage inspector rows aligned to the design (the Size row's trailing spacer made every section 8 pt too wide: 7 -> 24 of 32 within 1 pt, KI-252), Auto-fit label at 13 pt (KI-253), Screens Add screen button 22 pt; all six modes re-measured dark and light (one table in AI/reports/UI-008-report.md); compare-rects.py refuses a capture whose window is not 1440 x 900 (the 32 of 220 in FIX-U was such a capture); maps extended for Edit, Media, Screens and Cues; the Cues marker action list tags its rectangles with its own prefix.`

Hands-on checklist (screen unlocked): Stage, select an element, check the right column rows line up with the left edge of the section headings and the Size row shows the field, the stepper and a 13 pt Auto-fit word without clipping at a 1280-wide window; Screens, Add screen button looks the same as Cues' Manage; `scripts/compare-rects.py` with a capture made on a shrunken window prints the warning and exits 3.

## 7. Files changed

`App/Sources/StageInspector.swift`, `App/Sources/ScreensMode.swift`, `App/Sources/CuesActionList.swift`, `App/Sources/CuesMarkers.swift` (tag names, three new debug-only tags), `scripts/compare-rects.py`, `scripts/design-map-cues.json`, `scripts/design-map-edit.json`, `scripts/design-map-media.json`, `scripts/design-map-screens.json`, this report. Scratch build folder and DerivedData `WorshipFlow.app` removed.

## 8. Checks

`./scripts/check.sh`: **exit 0**, 3,476 tests in 548 suites passed (one run; none of the timing-sensitive suites failed), release build 85 s, "the Release app carries none of the measuring hooks" OK. Rectangle tables: six modes in section 2, run on the final tree.

## Not verified

- FIX-U's 32 of 220 cause (a capture window that was not 1440 x 900) is inferred from the pattern of its numbers; I could not lock the screen or reproduce it.
- No hands-on look at Stage's inspector or Screens' Add button by a person; the pictures were read, the rectangles measured.
- The Cues light right-column shift: mechanism not found.
- Behaviour at other window sizes, full screen, VoiceOver, keyboard focus order of the changed rows (no source behaviour changed).
- Pixel differences were measured only for Show; the other modes were compared by rectangles only.
- No Hardware Verified or Live-Service Verified level is claimed for anything here.
