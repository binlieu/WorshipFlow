# Known issues and open risks

| ID | Issue | State |
|---|---|---|
| KI-001 | No DeckLink, enclosure or ATEM is owned. Every `HW` and `KEY` slice can reach "Simulated" at most. | Open. Needs purchase by the owner. |
| KI-002 | Desktop Video support for macOS 27 is unconfirmed (spec UNV-01). | Open. |
| KI-003 | The development Mac has two displays. Stage output is checked in an output window. | Accepted. |
| KI-004 | Both displays run at 100 Hz. Timing tests must use a 60 Hz mode or the result does not count toward NFR-01. | Open until Phase 0 measurement. |
| KI-005 | The repository sits on a case-sensitive APFS volume with ownership disabled (spec UNV-07). | Watch. |
| KI-006 | Spec conflicts with `CLAUDE.md` are listed in `docs/adr/0003-spec-overrides.md`. | Recorded. |
| KI-007 | OUT-001 timing (NFR-01) is not verified. Runs so far: 30 s Debug window on a 100 Hz display gave 9 dropped of 2,996; a 120 s Release window run presented nothing because the window was behind a full-screen app. The 60-minute run needs a free display at 60 Hz: `scripts/soak.sh`. | Open. Needs the owner to free a display. |
| KI-008 | Frame statistics come from the drawable's presented time, so an occluded output reports zero presented frames. Correct for a covered window, but the operator readout should say "hidden", not look like a stall. | Closed by OUT-002 for the code path (tested with fakes); a really occluded window was not observed. |
| KI-009 | Not exercised in OUT-001: keyboard shortcuts, the stage window toggle, closing an output mid-run, unplugging a display, the loop seam, GPU load. | Open. Covered by OUT-002 tests and a field checklist. |
| KI-010 | SYS-001 crash survival is tested by dropping the store without closing it, not by killing a process or cutting power. | Open. Kill test belongs with OUT-004 autosave. |
| KI-011 | The operator interface has never been clicked through: Go Live, Next, Previous, Clear, Stop, keys and the screens panel are covered by unit tests of the logic only. | Partly closed by OUT-004: import, go live, Next button, slide edit isolation, relaunch restore and autosave were exercised through accessibility controls. Still open: Return, Space, arrows, Escape and Command shortcuts; quick edit with changed text; break moving; search results; drag reorder; rename and delete; error bar. |
| KI-012 | Decision: a screen whose display is missing when screens are opened, or disappears later, resumes on that same display when it returns. It is never moved to another display. A screen the operator stopped stays stopped. | Accepted. |
| KI-013 | Decision: Stop empties every screen and leaves outputs open; "Close screens" stops the outputs. | Accepted. |
| KI-014 | Dragging the operator window onto a display where a full-screen output is running is not detected. | Open. |
| KI-015 | Whether display ids stay the same across an unplug and replug is unchecked; auto-resume depends on it. | Open. Needs a physical test. |
| KI-016 | Themes, Looks and props are stored as JSON files, not SQLite, and presentations have no theme field yet. | Open. Follow-up slice SYS-002. |
| KI-017 | A newly added prop image appears a few frames late in the live path because decoding is off the render thread. Each screen decodes its own copy. | Accepted for now. |
| KI-018 | Not verified for OUT-003: the Look, theme and prop controls in the interface, bookmark restore after relaunch, wide-gamut, 16-bit and very large images. | Open. Part of the interface pass (KI-011). |
| KI-019 | Re-flowing a presentation discards the speaker notes of the slides it replaces. | Closed by SLIDE-001b: unchanged slides keep notes and objects; what will be lost is listed before saving. |
| KI-020 | Two separate blocks with the same section name (for example two "Chorus" blocks with different words) share one group after reflow. | Closed by SLIDE-001b: different words under a repeated label become "Chorus 2"; identical blocks share one section. |
| KI-021 | At launch the toolbar search field takes keyboard focus, so Space, arrows and Return go to it until the operator clicks elsewhere. | Fixed in APP-001 in code (grid takes focus at launch and after sheets; pure key rule tested). Key presses in the running app not exercised (see APP-001 report). |
| KI-022 | Live previews show the background colour, not the moving video. | Closed by MEDIA-001 for the live previews. |
| KI-023 | No interface yet for creating a section order (arrangement) or a custom theme. | Done in APP-001: section order editor and theme editor, exercised in the running app through accessibility controls. |
| KI-024 | Slides cannot be added, moved or deleted while a playlist item plays a custom section order; the app explains why. | Accepted. |
| KI-025 | The app still stores screen profiles, Looks and props as JSON; the SQLite tables from SYS-002 are unused. | Fixed in APP-001: settings live in SQLite; old JSON files imported once and left in place. |
| KI-026 | Keyboard control (Return, Space, arrows, Escape, Command-F) and launch focus are implemented with a tested routing rule but have never been pressed in the running app: background automation cannot send keys to it. | Open. Needs a person at the keyboard, or a UI test run when the Mac is free. |
| KI-027 | Editing a custom theme that is in use changes the live audience screen immediately. | Accepted (matches PRES-06); revisit if operators want a staged edit. |
| KI-028 | In the theme editor the "Background video" segment label is clipped. | Closed by SLIDE-001b. |
| KI-029 | Stage layout editor: dragging and resizing on the canvas, the layout picker popup, typing in fields and the colour picker have not been exercised in the running app (the helpers they call are unit tested). | Open. Part of the hands-on pass with KI-026. |
| KI-030 | A timer started mid-second can show up to one second behind on stage, because the stage picture refreshes on whole seconds. | Open. Minor. |
| KI-031 | Deleting a timer leaves its element in stage layouts, drawing nothing until re-pointed. | Accepted. |
| KI-032 | MEDIA-002 is engine only: the app does not yet pass the media registry to outputs, and nothing has been seen on a real output. Foreground audio, volume and device choice are unverified or unbuilt. Only small synthetic H.264 files were tried. | Open. MEDIA-001 interface slice wires and exercises it. |
| KI-033 | Decision: a foreground clip shows only on screens whose Look shows the slide layer, and an audio file chosen as a visual layer is ignored. | Accepted. |
| KI-034 | Was a real player stall, not test timing: after a seek the player could sit ready at rate 1.0 with time not advancing, so the end of clip was never reported. Reproduced under CPU load (2 of 20 and 3 of 25 runs failed). Fixed with a watchdog that re-seeks a ready player whose time has stood still for one second; 30 of 30 passes under load afterwards. The lyrics also return by the transport clock if the player never reports. | Closed for clips with a known duration. Open: the watchdog was never observed firing, and a clip with no stored duration depends on the player's report alone. |
| KI-035 | A slide whose stored objects cannot be decoded is shown with no objects, and saving it overwrites the bad value. | Accepted, so one bad row cannot break a slide list mid-service. |
| KI-036 | Slide objects have been checked by offscreen pixel tests only; there is no editor yet and none has been drawn on a real output. Image objects were tested in fill mode with one sRGB PNG. | Partly closed by SLIDE-001b: a rectangle and a text box were added, coloured, and seen on the audience preview after Go Live. Image objects still untested in the app. |
| KI-037 | Media bin paths not exercised in the running app: adding files through the open panel or by drag and drop (rows were inserted directly for the test run), context menu, rename, remove, kind filter, pause, seek, volume, mute, Stop clip, still image as a layer, relaunch restore, error bar. No sound has been played. | Open. Hands-on pass. |
| KI-038 | Decision: a clip can be played only while the show is live; Stop ends it. Foreground volume starts at half. | Accepted. |
| KI-039 | App test runs wrote `~/Library/Preferences/org.worshipflow.app.plist`. | Noted. Harmless; remove with `defaults delete org.worshipflow.app` if wanted. |
| KI-040 | Slide editor paths not exercised in the running app: dragging, corner resize, double-click text editing, typing in inspector fields, colour panel, stacking and shadow controls, inserting an image, Delete key, undo and redo and duplicate shortcuts. | Open. Hands-on pass with KI-026. |
| KI-041 | Undo covers object edits only, not words or notes, and its history is dropped when another presentation is opened. | Open. |
| KI-042 | Image objects and props store plain file paths; a moved or renamed file draws nothing (the inspector warns). | Open. Revisit with project packaging in LIB. |
