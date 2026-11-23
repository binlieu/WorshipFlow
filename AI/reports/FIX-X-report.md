# FIX-X report: REVIEW-5 lows L3, L9, L13

Feature IDs: SLIDE (video objects), MEDIA, CUE-33. Model: Sonnet. No migration, no git state change.

## L3 Blackout closes the video-object players: fixed (Unit Tested; hands-on pending)
- Confirmed in code: `AppModel.publish()` -> `syncObjectVideos` -> `apply([])`, because `SceneComposer.themed` returns an empty scene under Blackout or Stop.
- Rule matched: under Blackout the slide's own background player keeps running and only its sound is silenced (`LiveMedia.playing` doc comment). Video objects now do the same: clips keep playing, silenced, and are heard again when Blackout lifts.
- Change: new `ObjectVideoPlayers.apply(_:blackedOut:)` (MediaEngine/UI007c_ObjectVideoPlayers.swift). Under Blackout it only sets `isMuted = true` on the open sources: nothing is opened, closed or waited for. Off Blackout it calls the old `apply` and restores each clip's own muted flag. `EditObjectVideos.syncObjectVideos` passes `show.isBlackedOut` and skips `ObjectVideoAccess.keepOnly` under Blackout (file access is kept with the players). Two internal test hooks `sourceIdentity(for:)` and `isMuted(_:)` were added.
- Limit of 4 unchanged. A publish under Blackout never opens a clip. A slide change under Blackout leaves the old (silenced, invisible, bounded) players until Blackout lifts, then the normal apply swaps them.
- Stop: unchanged, closes everything (no liveDeck, so no objects). Clear: unchanged and left as is: `liveSlide` is nil while cleared, so the composed scene has no objects and the players close; clearing off reopens them from the first frame. (The slide's own background keeps playing under Clear words; the objects do not. Reported, not changed.)
- Tests: `FIXX_ObjectVideoBlackoutTests` (6), real tiny movies, no wall-clock: same player identity across Blackout and lift; sound silenced then restored; muted stays muted; Blackout opens nothing; non-Blackout empty scene still closes; limit still 4. The brief's "fake players with an injected clock" was not needed: identity and mute state are checked, not position.

## L9 and L13 marker delete without confirmation: fixed (Unit Tested; view wiring hands-on pending)
- L13 is the same control as L9: there is one marker delete button, in `MediaMarksPopover.swift` (`MarkerRow`). The Cues "Playback markers" section (`CuesMarkers.swift`) has no delete control, so there is no second site to fix. The media-item delete confirmation (the bin's "Remove from the media bin?") was not checked for naming lost markers; not in scope.
- Change: pure decision `MarkerDeleteConfirmation.prompt(name:time:actionCount:actionsAreUnreadable:)` (OperatorCore/MarkerDeleteConfirmation.swift): nil for a marker with no actions; otherwise title naming the marker (its name, or "the marker at <time>"), message with the action count and "This cannot be undone.", button "Delete marker". Stored actions that cannot be read also ask (they are lost too).
- View: `MarkerRow` uses an `.alert` with Cancel (`role: .cancel`, `.keyboardShortcut(.defaultAction)`) and a plain "Delete marker" button (no destructive role: red only for on air, as FIX-V). The trash button's role was removed; its accessibility label and help are kept. No undo built.
- Tests: `FIXX_MarkerDeleteConfirmationTests` (5).

## Files changed
- Packages/WorshipFlowKit/Sources/MediaEngine/UI007c_ObjectVideoPlayers.swift
- Packages/WorshipFlowKit/Sources/OperatorCore/MarkerDeleteConfirmation.swift (new)
- App/Sources/EditObjectVideos.swift, App/Sources/MediaMarksPopover.swift
- Packages/WorshipFlowKit/Tests/MediaEngineTests/FIXX_ObjectVideoBlackoutTests.swift (new), Packages/WorshipFlowKit/Tests/OperatorCoreTests/FIXX_MarkerDeleteConfirmationTests.swift (new)

## For the coordinator
Change log text: "FIX-X: Blackout no longer closes the video objects' players, so lifting it shows the clips where they would be (they play on, silenced); deleting a marker that has actions asks first, naming the marker and its action count."
Known issue (unnumbered): Clear still closes video-object players and restarts them from the first frame when un-cleared.
Hands-on: (a) video object on the live slide, Blackout, wait, lift: the clip is mid-play, not at frame 0, and an unmuted clip is silent during Blackout; (b) Blackout, then Stop: players close; (c) marker with actions, press trash: alert names it and the count, Return cancels, Escape cancels, "Delete marker" deletes; marker without actions deletes at once; check Return really lands on Cancel in the popover alert and the alert is not drawn red.
Decision for you: whether Clear should also keep video objects playing (not done, brief said leave it).

## Verification
`./scripts/check.sh` exit 0 (Debug and Release app builds, package tests: 3591 tests in 570 suites passed, including the 11 FIXX tests). No timing re-run was needed. The script's own DerivedData folders (WORSHIPFLOW-check, WORSHIPFLOW-check-release) were left in place; no other scratch build was made. Not verified: the app views by hand (alert default button, no red).
