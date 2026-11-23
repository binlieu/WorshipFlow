# UI-007c report: Edit mode features that needed migration v15

Feature IDs UI-007c (SLIDE, MEDIA, OUT). Briefs `AI/specs/UI-006-mode-features.md`, `AI/specs/UI-007-features-on-v15.md` (row UI-007c). Base 0f89ce3. Levels: **Unit Tested** for the logic and the rendering (Metal, offscreen), **Simulated** for playback and the views (the real debug app, a throw-away library, the model's calls standing in for the operator's hands because the Mac screen may be locked: no click, drag or key was made by hand). Not Hardware Verified (no SDI path was run), not Live-Service Verified.

## Built

| Feature | What it does | Verification |
|---|---|---|
| Layers list | Object tab, last section, "top first": the slide's own words (select their box), then each object with name, eye (hide), lock, forward/backward arrows on the chosen row, and a Name field. Hidden objects are struck through and muted. Rows are values (KI-193). | Unit Tested (`UI007c_EditObjectsTests`), view Simulated (picture) |
| Lock | A locked object cannot be moved, resized, dragged, nudged, aligned, typed into Position, or deleted (Delete key included: the key is taken, never falls through). It says why in the usual dismissable bar; has no handles, a lock badge; can still be selected, edited otherwise, reordered, duplicated. | Unit Tested; the message seen in the real app |
| Hide | One undo step; hidden object is not drawn on any screen, has no canvas box unless selected. | Unit Tested; live scene checked in the real app (hidden ellipse absent) |
| Text Fit | Inspector "Fit: None / Shrink to fit box". Own factor per text box, the same measure and the same floor (`Theme.fitFloor`, 56 pt) as lyric Fit; words that cannot fit even at the floor are cut at the box's frame. | Unit Tested (pixels), Simulated (live picture) |
| Text Background fill | Checkbox, swatch, hex in Effects. A box behind the words in the same frame and opacity (one extra shape layer before the text; no renderer change). | Unit Tested |
| Video object | Video button (menu of the bin's clips) places a clip, looped and muted. Edit and every thumbnail show one still poster frame (JPEG in the caches folder, made on a background task). On Live the clip plays inside its frame (aspect-fill, clipped, opacity) through a new `ObjectVideoPlayers` in `MediaRegistry`, the output resolver and `Compositor.encode(objectMedia:)`; nothing is opened or decoded on a render thread. At most 4 clips open at once. Inspector: clip name (or a warning when it left the bin), Loop, Play its sound. | Unit Tested (players with real movies, resolver, compositor pixels); Simulated in the real app: clip opened, frame delivered, audience picture shows it in its frame, closed on Stop |

Every edit is one undo step, never touches Live, is saved with the slide.

## Not built / limits (what is missing)

- Layers rows for the background and props (the design's mock shows them): not stored as layers; only objects and the slide's words.
- Fit does not tell the operator when words still do not fit at the floor (the measure lives in the compositor; no view reads it for objects).
- A video object is not drawn on a Stage screen (stage scenes never carry objects) and not on a keyed broadcast screen (existing rule for all objects).
- A clip's own audio uses the programme device; there is no per-object volume.
- Nothing is missing in storage: all fields used were v15's.

## Tests (54 new, test-first where risky)

- Render digest `UI007c_RenderDigestTests`: recorded on unchanged code before any edit (`d75f33c1...411c`), unchanged after; the existing `SYS015_ScenesDigestTests` and `FIXQ` digests pass unchanged.
- `UI007c_ObjectSceneTests` (Domain), `UI007c_EditObjectsTests` (editor: lock, layers, fit, fill, video, live untouched), `UI007c_ObjectRenderTests`, `UI007c_ObjectVideoPlayersTests`, `UI007c_ObjectFramesTests`.
- One existing test edited, on purpose: `SYS015_FieldsTests.aVideoObjectDrawsNothingYetAndDoesNotStopTheOthers` (renamed `aVideoObjectIsALayerInItsPlaceAndDoesNotStopTheOthers`): its premise, "video draws nothing yet", is what this slice delivers.

## Shared-file lines

- `AppModel.swift`: one call `syncObjectVideos(snapshot)` in `publish()`; `thumbnailScene` returns through `stillScene(...)` (poster instead of video).
- `Thumbnails.swift`: the preview renderer takes the live frames of a scene's video objects (monitors); `hasMedia` counts them so the monitor redraws.
- `UISnapshotDesign.swift`: one hook line `UI_SNAPSHOT_UI007C`.
- Package, additive: `MediaRegistry` (`objectVideos`, `currentObjectPixelBuffer`, three one-line calls in `unregister`, `closeAll`, `setAudioOutputDevice`); `MediaFrameSource` gets `currentObjectPixelBuffer` with a default of nil; `OutputRenderer`/`SDIOutput` pass `objectMedia`; `Compositor.encode`/`renderImage` gain `objectMedia:` (default empty); `SceneObjectLayer.video(VideoLayer)`; `SlideObject.drawableLayers`; `NewSlideObject.video`; lock guards in `SlideEditorModel` and `align`.
- `WORSHIPFLOW.xcodeproj/project.pbxproj` regenerated by the check and NOT committed; regenerate after merge.

## Rectangle table (`scripts/compare-rects.py`, `design-map-edit.json`, 121 entries, not extended)

Dark 101 of 121 within 1 pt (was 99), light 102 (was 100); no entry got worse. New unmapped ids: `ed.bar.video`, `ed.insp.fitrow`, `ed.insp.fit.field`, `ed.insp.fillrow`, `ed.insp.layers` and the layer rows (the Layers rows differ from the design's `.ly`: extra eye/lock/arrows buttons).

## Docs entries (for the coordinator)

Change log: `UI-007c: Edit gained the Layers list (name, hide, lock, reorder, select), lock rules, text Fit and Background fill, and video objects (poster in Edit, playing on Live). Tests UI007c_*.`
Known issues: `Video objects: opened on publish, so a clip starts when its slide goes live and restarts if the slide is triggered again; a missing clip draws nothing and is reported only in the inspector; at most 4 clips play at once. Fit gives no warning when words do not fit at the floor. Poster cache is never cleaned. The live monitors redraw about four times a second while a video object is on screen.`
Hands-on: `Edit: Video menu, add a clip, see the still; go live and see it play in its box on a window screen and the monitor; Stop it; lock a box and try to drag, arrow, Delete; hide a box; Fit a long text box; Background fill; undo each once.`
Feature spec updates: SLIDE objects (name, hide, lock, fit, fill, video), MEDIA (object video players).

## Check

`WF_DERIVED_DATA=<scratch> ./scripts/check.sh`: exit 0, 3312 tests in 525 suites (base 3258), Debug and Release builds pass, no hook strings in Release. Run once, no timing failures. Real-app run: `scripts/ui007c-run.sh` (needs the test clip by path).

## Not verified

Any hand-driven click, drag, key or VoiceOver use; a real second screen or SDI output playing the clip; sound from an unmuted clip; many clips at once; long-running playback and memory; light-mode pictures other than one; narrow windows.
