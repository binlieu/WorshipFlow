# MEDIA-010: live media control

Status: Implemented, Unit Tested, run in a Debug build through the snapshot hook. Simulated and Hardware Verified: not applicable (no output path changed). Live-Service Verified: Not Verified.

From the owner's hands-on feedback of 2026-11-21 (items 3 and 6 to 10).

## Behaviour

1. **Live override.** A choice in the media bin (double click, "Send to live background", the Show dock, a cue) sets the live background (`MediaModel.layers.background`). It is never written to the presentation, its slides or its theme. Preview and slide thumbnails never show it (`LiveMedia.preview`). It stays while slides advance, when another playlist item goes live and across Stop, until it is replaced or dropped (`MediaModel.dropBackgroundOverride`, the Drop button in the Show inspector). Before this change a click in the Show dock set the same layer, but thumbnails drew it (so it looked applied to every slide) and it was remembered across launches.
2. **Four live clears.** Lyric (`CueTransport.clear`, today's Clear), background (`.clearBackground`), foreground (`.clearForeground`), music (`.clearMusic`). All go through `CueModel`'s serial command path and are macro actions. Clear background is `ShowState.isBackgroundCleared`: every background (theme, slide's own, override) is hidden on audience and broadcast screens; words, clip and props stay; Blackout still hides everything; Go Live, Next, Previous, Stop or a new bin choice lifts it. None of them cancels waiting macro steps or bumps the transport epoch. Keys: Control-Option-B, F, M (menu items, so the transport key monitor leaves them alone).
3. **Background sound.** `MediaModel.isBackgroundMuted` (default true), `setBackgroundMuted`, `backgroundHeardMuted` (the choice, or Blackout); `MediaRegistry.setBackgroundAudio` reaches the open player and any opened later. Shared volume with the clip.
4. **Bin player.** `MediaPreviewModel` over `PreviewPlayback` (AVPlayer in the app). Single click selects, double click sends live. Never touches the media layers; `--silent-audio` keeps it muted.
5. **Hot folders.** `HotFolderModel`: list, watch, hold back files whose size changed since the last look, name order, ids derived from folder id and file name, missing state, relocate, bookmark. `MediaModel.setHotAssets`, `playFolder(_, on:)`, `stopFolder`.
6. **Slide's own background.** `SlideContent.background`, `SlideEditorModel.setBackground(_, forSlide:)` (undoable while that slide is selected), drop of a bin tile (`wfmedia:<id>` drag text) or a Finder file. Used by the live composer when the slide is at the live place unless an override is on.

## Rules and decisions

- **FIX-G (review fixes).** A slide's own background is stored with the slide: migration v11 adds the nullable `slide.background` column (JSON of a `MediaSelection`) and moves the old `appState` entries across (KI-100 closed). A re-flow carries it by the same match as notes and objects and its loss list names a background nothing takes; deleting a slide or presentation removes it; undo restores it; the program package carries it (LIB-005). Removing a bin item that slides use as their own background first tells which slides (`MediaModel.removalImpact`); the slides keep their choice and show the missing-media mark. A background hidden by Clear background or Stop is not played at all (`LiveMedia.playing`), so its sound is off too, and returns with the picture; Blackout keeps the player and silences it. Hot folders: bookmarks are resolved without UI and without mounting, off the main actor, and the folder follows the path the bookmark leads to; launch never waits on a folder; one scan at a time per folder; a listing error keeps the last items and shows "not answering"; a clip on air stays registered while it plays; unreadable files are retried with a growing delay (counted in scans); the probe cache is pruned; a folder lists at most 2,000 items with a notice; Play folder skips an unreadable file and says so once. The sidebar preview starts muted every session with a line saying where it would be heard, and is paused when its item is sent live.
- Where a background shows: KI-101.
- Show dock tiles still send on a single click; the Media mode bin selects on a single click.
- Tests: `MEDIA010_*` in `OperatorCoreTests`, `PersistenceTests`, `MediaEngineTests`.

## UI-007d additions (marks and markers)

- Marks: `markIn` and `markOut` on a video clip (set at the playhead or typed, cleared), honoured by the bin preview and by live playback (start at in, stop or loop at out) through `MediaTransport` and the player.
- Markers: add at the playhead, rename, move, delete; kept in time order; stored in table `mediaMarker` (migration v15).
- Playback rule: a marker's actions run when live playback crosses it, once per crossing, through the one command path (source "marker"); never from the preview and never when seeking over it.
- Not verified: the AVFoundation adapter of the bin player (out-mark stop, loop to in); marker timing against real picture and sound.
