# FIX-AB report: the Show grid follows Live and Preview, and a video clicked in the media bin is heard

Feature IDs: UI (Show grid), MEDIA-010. Model: Sonnet. Main folder, no git state changed. No migration.

Verification levels: Implemented, Unit Tested (decision rule, sound state, wiring by source). Simulated: the grid's scroll offset in a debug build with
200 slides (below). Hardware Verified and Live-Service Verified: Not Verified. The sound on real speakers and the real-library behaviour: Not Verified
(nothing was played; every run used `--silent-audio` and a temporary library).

## Items 1 to 4: the grid follows Live and Preview

Cause, with evidence. The selection scroll already existed (`ScrollToSelection`, selectedIndex only) and nothing followed the live index. Measured with
the new debug hook (`UI_SNAPSHOT_FIXAB=1`, `App/Sources/UISnapshotFixAB.swift`): 200 slides, the keyboard's model path (`moveSelection(.down)`) and Next,
reading the grid's NSScrollView offset.
- A song with no section names (one run): the old code followed (offset 3858 of max 3872 at slide 199). So the first guess in the brief (a plain
  selectedIndex fault) was not the whole story.
- A song with 100 named sections (one lazy grid per section inside one lazy stack, as a real song): the OLD code did not follow. Offset stayed at 94 of
  max 12743 for Preview at slides 16 to 78 and for Live at slides 40 to 199 (selected and live both 199).
- Cause: a cell's `.id` sits inside a LazyVGrid inside a per-section VStack inside a LazyVStack. A section never on screen has no cells yet, so the
  outer stack knows no target for `scrollTo(cellKey)` and the call does nothing. The section itself (the ForEach identity, `run.id`) is a known target.
- Live was not followed at all in the code (only selectedIndex was watched). In the app the selection moves with Next, so the missing Live follow only
  showed through the section fault; it is still covered by the new rule, and Scripture and the list had no live follow either.

Tests first (all in `FIXAB_ShowGridFollowTests.swift`, run on a stub that returns nil; 7 of 9 failed with `nil == <index>`, the other two assert "nothing"
and pass on the stub by design): live move, last slide of 200, selection move, both change (Live wins), first Go Live, live leaving the open
presentation, out-of-range index and count 0, live out of range falls back to the selection.
`FIXAB_ViewSourceTests.theGridAndTheListFollow...` was written after the code; its patterns were checked against `git show HEAD:` and are absent there
(0 hits for `ShowGridFollow.target(`, `proxy.scrollTo(run)`).

Change:
- `Packages/WorshipFlowKit/Sources/OperatorCore/ShowGridFollow.swift` (new): `ShowGridFollow.target(from:to:count:)`, the one pure rule. Live wins when
  both moved; an index outside `0..<count` is never named; unchanged place gives nil.
- `App/Sources/CentrePane.swift`: `ScrollToSelection` (name kept, FIXQ's test pins it) now reads the live place (`liveIndex(app, workspace)`, so only for
  the open presentation) and the selection, in the small view itself; on a change it scrolls to the cell's section first, then the cell, in one
  `withAnimation`, no anchor (smallest scroll: a visible cell does not jump). No timer, no retry, no deferral was needed (measured). The grid body gained
  `runs` (computed once, reused by its ForEach) and `runIDs`; it still reads no selection, live place or mode (FIXQ source test green).
  `SlideList` had no follow at all: it now uses the same view (its rows are flat in one lazy stack, so no section step).
- `App/Sources/ScriptureView.swift`: the passage grid followed the selection only; it now uses the same rule, so it follows Live too.

Seen running (debug build, temporary library, `--silent-audio`, the hook above; offset of the grid's scroll view, max 12743 with 100 sections):
Preview by keyboard path, slide 16 offset 626, 32 offset 1690, 48 offset 2754, 64 offset 3818, 78 offset 4749. Live by Next, slide 40 offset 2189, 80
4856, 120 7518, 160 10176, 199 12729 (the last cell in view; 14 pt is the bottom padding). Flat song (no sections), same hook: identical to before the
change (199: 3858 of 3872).

Not verified: the Preview selection moved on its own while Live stays elsewhere (the model moves both together under Next; the keyboard path was
measured with Live stopped); a hand-scrolled grid with the live cell off screen; a slide list (`SlideList`) and a Scripture grid running (no capture
tool; the list uses the same view, the Scripture grid scrolls straight to a flat lazy grid as before); a very tall section (the section step may
move slightly more than the cell step needs, then the cell step corrects it); dragging the scroll bar while Live moves (not required).

## Items 5 and 6: a video clicked in the bin is heard

Cause: `MediaModel.isBackgroundMuted` starts true and only the mute button changed it, so a video clicked in the bin as background started muted, while
a clip over the words (foreground) is heard. The registry takes one mute flag for the background slot, shared by a bin background and a slide's own.

Rule implemented (`MediaModel.setBackgroundFromBin`): a VIDEO clicked in the bin as background turns the background sound on before the layer starts
(`onBackgroundAudioChange` false first, so the player never opens muted). A picture changes no sound state. The sound is remembered as "on because of a
bin click": when that background ends (dropped, cleared, its file gone) the sound goes back to muted, so a slide's own loop that goes live afterwards
stays silent as MEDIA-010 says. Pressing the mute button (either way) makes the sound the operator's own choice: it then stays as it is when the bin
background ends. The operator can still mute a bin background (button label "Mute background" while heard, "Unmute background" after, unchanged);
the NEXT bin click is heard again (chosen: the click is the owner's request for sound; it also needs no extra state). Blackout still silences and
lifting restores; Clear and Stop unchanged (the model does not touch them); `--silent-audio` unchanged (the registry and audio model are not touched);
cues, folders and `setBackground` keep the old muted start; a sound file in the bin is untouched.
Wired in: `AppModel.performDockAction(.setBackground)` (a tile click in the Show dock, the strip's "Live background"), the Show dock tile's context menu
"Set as background", and the Media tab bin's "Set as background" (context menu and VoiceOver action; they set a live background too). The Media tab's own
preview player is untouched.

Tests first (`FIXAB_BinSoundTests.swift`, run on a stub `setBackgroundFromBin` = `setBackground`): failed on the stub as stated
(`isBackgroundMuted` still true; `onBackgroundAudioChange` never called with false; after Blackout lifted the value was not false; after the operator's
mute and the next click it was not heard). Guard tests that pass on the old behaviour by design: a slide's own background stays muted when its slide
goes live (no call told the player to be heard), the bin choice ending re-mutes (on the stub nothing unmuted), the operator's own unmute survives,
a picture changes nothing, the cue path stays muted. `FIXAB_ViewSourceTests.aBinClick...` pins the four call sites (absent at HEAD).

Existing tests that conflicted: none. `MEDIA010_BackgroundSoundTests.aBackgroundVideoIsMutedByDefault...` calls `setBackground` (assertion
`#expect(rig.model.isBackgroundMuted)`), which is unchanged, so the rule for the cue path stays pinned.

Not verified: sound on real output (silent runs only); the hot-folder run and a cue's Set background while a bin choice is live (the sound stays on until
the layer is empty; a folder video that replaces a bin background would be heard); an unmute followed, in the same session, by a slide's own loop with
no bin background (unchanged MEDIA-010 behaviour).

## Gate

`./scripts/check.sh; echo CHECK_EXIT=$?` printed `CHECK_EXIT=0`, `Test run with 3690 tests in 587 suites passed`, `release build took 120 s`, `== OK`.
No timing-flaky test failed, so no re-run. The Debug and Release builds ran (Release without the measuring hooks; the new hook is `DEBUG || WF_MEASURE`
only). `xcodegen generate` added `UISnapshotFixAB.swift` to the project. The scratch build folder and copy of the app were deleted; the gate's own
check folders (`DerivedData/WORSHIPFLOW-check*`) are the script's usual ones.

## Change-log text

FIX-AB: the Show grid scrolls to the live slide and to the selected slide (Space, Next, Previous, a click, a cue, the arrow keys), also for a section far
below that had never been on screen, in the grid, the list and a Scripture passage. A video clicked in the media bin as background is now heard; a slide's
own background stays muted until unmuted.

## Known-issues text (unnumbered)

- The section step of the grid's scroll can move a very tall section more than the cell needs before the cell step corrects it; not seen with songs.
- A bin background turns the sound on until the layer is empty; a hot-folder video that replaces it, or a cue's background video, is heard until then.

## Hands-on entries

1. Open a long song with sections (20 or more slides). Press Space repeatedly through to the last slide: the grid scrolls so the live slide stays in view.
2. Click the first slide, then use the arrow keys (Down, Right) past the bottom of the window: the grid scrolls to keep the Preview slide in view.
3. Click a slide already in view: the grid does not jump. Go Live on a slide far above the window: it scrolls up to it.
4. Switch to the list view and repeat 1 and 2. Open a Scripture passage with many slides and repeat 1.
5. In the Show media bin, click a video (Background chosen): picture and sound together. Press the speaker button: muted; click the video again: heard again.
   Press Blackout: silent; lift it: the sound returns. Set a slide's own background video and go to that slide with no bin background: it stays muted.
6. Drop the bin background ("Use the slide's own background"), then go to a slide with its own video: no sound until you unmute.
