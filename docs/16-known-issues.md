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
| KI-011 | The operator interface has never been clicked through: Go Live, Next, Previous, Clear, Stop, keys and the screens panel are covered by unit tests of the logic only. | Open. UI test pass comes with OUT-004. |
| KI-012 | Decision: a screen whose display is missing when screens are opened, or disappears later, resumes on that same display when it returns. It is never moved to another display. A screen the operator stopped stays stopped. | Accepted. |
| KI-013 | Decision: Stop empties every screen and leaves outputs open; "Close screens" stops the outputs. | Accepted. |
| KI-014 | Dragging the operator window onto a display where a full-screen output is running is not detected. | Open. |
| KI-015 | Whether display ids stay the same across an unplug and replug is unchecked; auto-resume depends on it. | Open. Needs a physical test. |
