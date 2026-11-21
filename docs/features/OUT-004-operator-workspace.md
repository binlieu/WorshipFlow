# OUT-004 — Operator workspace

Satisfies: LIVE-05, LIVE-06, PRES-02, PRES-03, PRES-05 (interface), PRES-07, PRES-08, LIVE-07, NFR-06, NFR-07. Built together with LIB-001, LIB-002, LIB-003, SLIDE-005. Phase 1.

## Behaviour

1. **One window, everything in view** on a 1920 × 1080 display: libraries and playlists on the left; the open presentation's slides in the centre with search above; on the right, a live thumbnail of every screen, the screens panel, Looks and props; a transport bar along the bottom.
2. **Libraries and playlists.** Create, rename and delete libraries; create and delete presentations; add to a playlist, reorder by drag, remove. First run creates a "Songs" library and one playlist.
3. **Import lyrics.** Paste the first language and, optionally, the second; choose lines per slide; see the split as you type; adjust a break; save as a presentation.
4. **Preview and live.** Selecting a slide changes preview only. Go Live, Next, Previous, Clear and Stop behave as in OUT-002. In a playlist, Next continues into the next item and Previous returns to the previous item's last slide.
5. **Editing.** Editing the open presentation is saved and shown in preview; the live output does not change until that content is triggered again. Quick edit is the one action that changes the live slide, and it also saves.
6. **Search.** Typing finds titles and lyrics, ignoring diacritics; opening a result loads it into preview.
7. **Autosave.** Structural changes are written at once. Text being typed is written within two seconds, never later than five, and at once when the app loses focus or quits.
8. **Relaunch.** The open playlist, item and selected slide come back in preview. Nothing is live until the operator triggers it.
9. **Errors** appear in a bar in the operator window and never on an output.

## Acceptance

| Check | Level |
|---|---|
| `WorkspaceModelTests` and `DebouncedSaverTests` pass | Unit Tested |
| The app launches, the workspace window appears, and a screenshot shows the three areas and the transport bar | Seen running |
| Import a bilingual song, go live in a window output, step with the keyboard, quick-edit a word | Seen running (closes KI-011 for these paths) |
| Force-quit during typing loses at most five seconds | Kill test (KI-010) |
