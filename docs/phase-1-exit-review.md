# Phase 1 exit review

Date: 2026-11-20. Reviewer: coordinator. Code at commit "feat(SLIDE-001b)". 550 package tests pass; `./scripts/check.sh` exits 0.

## Exit criterion (master spec, section 7)

> A full service is run from a playlist with the audience output on the second display and the stage output in an output window.

**Not met.** Every Phase 1 feature has code and unit tests, and most have been seen working in the operator window through accessibility automation. No full service has been run, nothing has been shown full-screen on the second display, and the keyboard has never been pressed in the running app. Those need a person at this Mac with the second display free.

Phase 0's criterion (60 minutes at 60 Hz with zero dropped frames) is also **not met**: not yet measured (KI-007).

## The 26 Phase 1 catalogue features

Levels: **T** unit tested · **S** seen working in the running app (operator window, automation) · **H** hands-on by a person · **—** not done.

| ID | Feature | T | S | H | Slice | Notes |
|---|---|---|---|---|---|---|
| PRES-01 | Slide editor | Yes | Partly | — | SLIDE-001a, SLIDE-001b | Rectangle and text box added and coloured; drag, resize, image insert not exercised (KI-040) |
| PRES-02 | Presentation libraries | Yes | Partly | — | SYS-001, OUT-004 | Rename, delete and move not exercised in the app |
| PRES-03 | Service playlists | Yes | Partly | — | SYS-001, OUT-004 | Add to playlist seen; keyboard stepping not pressed (KI-026) |
| PRES-04 | Song arrangements | Yes | Yes | — | SLIDE-003, APP-001 | Called "section orders" in the interface |
| PRES-05 | Reflow editor | Yes | Yes | — | SLIDE-004, OUT-004, SLIDE-001b | Moving a break in the sheet not exercised |
| PRES-06 | Themes & templates | Yes | Yes | — | OUT-003, APP-001 | Typing in numeric fields and the colour panel not exercised |
| PRES-07 | Quick edit | Yes | Partly | — | OUT-002, OUT-004 | Popover opened; changed text applied only in unit tests |
| PRES-08 | Quick search | Yes | — | — | SYS-001, OUT-004 | About 1 ms on 2,000 songs; results list never seen in the app |
| PRES-10 | Multiple translations | Yes | Yes | — | OUT-001, SLIDE-004 | English with Vietnamese seen on audience and stage previews |
| MEDIA-01 | Media bin | Yes | Partly | — | SYS-002, MEDIA-002, MEDIA-001 | Real add path (panel, drop, probe) never run in the app (KI-037) |
| MEDIA-02 | Motion backgrounds | Yes | Yes | — | OUT-001, MEDIA-001 | 30-minute seamless-loop check not done |
| MEDIA-03 | Foreground videos | Yes | Yes | — | MEDIA-002, MEDIA-001 | Words returned after the clip; pause, seek, sound not exercised |
| MEDIA-07 | Object fills & effects | Yes | Partly | — | SLIDE-001a, SLIDE-001b | Fill seen; stroke, shadow, opacity by pixel tests only |
| MEDIA-08 | Persistent props | Yes | — | — | OUT-003, APP-001 | Never added through the interface |
| SCRN-01 | Independent outputs | Yes | Partly | — | OUT-001, OUT-002 | Different audience and stage compositions seen in previews and window outputs; never on two displays |
| SCRN-02 | Audience screens | Yes | Yes | — | OUT-002 | |
| SCRN-03 | Stage screens | Yes | Yes | — | OUT-002, STAGE-001b | |
| SCRN-04 | Single display | Yes | — | — | OUT-001 | A short full-screen run on the main display presented frames in OUT-001; never on the second display |
| SCRN-08 | Screen Looks | Yes | — | — | OUT-003, APP-001 | Look switching never exercised in the app |
| SCRN-09 | Alternate themes | Yes | Yes | — | OUT-003, APP-001 | Song theme reached audience and not broadcast |
| LIVE-01 | Stage layout editor | Yes | Partly | — | STAGE-001a, STAGE-001b | Drag and resize on the canvas not exercised (KI-029) |
| LIVE-02 | Current & next slide | Yes | Yes | — | OUT-002, STAGE-001b | |
| LIVE-04 | Countdowns and clocks | Yes | Yes | — | STAGE-001a, STAGE-001b | Countdown seen ticking, pausing and surviving a relaunch; one-hour accuracy not measured |
| LIVE-05 | Preview surfaces | Yes | Yes | — | OUT-004, MEDIA-001 | |
| LIVE-06 | Operator workspace | Yes | Yes | — | OUT-004 | Not checked at exactly 1920 × 1080 full screen |
| LIVE-07 | Live editing | Yes | Yes | — | OUT-002, OUT-004 | Edit isolation seen for words and for objects |

Totals: 26 of 26 unit tested. 14 seen working, 9 partly, 3 not seen. 0 hands-on.

## Non-functional requirements

| ID | State |
|---|---|
| NFR-01 zero drops for 60 minutes | Not measured (KI-007). Short windowed runs on a 100 Hz display dropped 3 to 9 frames in 20 to 30 seconds. |
| NFR-02 drop counters visible | Built. |
| NFR-03 trigger to output within 100 ms | Not measured. |
| NFR-04 all outputs on the same frame | One snapshot is published for all outputs; not measured on hardware. |
| NFR-05 device loss | Unit tested with fake displays. No physical unplug test (KI-015). |
| NFR-06 restore after crash | Restore to preview seen after a normal relaunch. No crash test. |
| NFR-07 lose at most five seconds | Debounce logic tested; a save was seen landing in about three seconds. No kill test (KI-010). |
| NFR-08 nothing modal on outputs | By design; under independent review. |
| NFR-09 remote control off by default | Not applicable until Phase 3. |
| NFR-10 no sleep while live | Seen: both sleep assertions held during a run and released after. |
| NFR-11 memory budget | 96 to 112 MB with one output and a looping video. Not measured with four outputs. |
| NFR-12 works offline | Nothing in Phase 1 uses the network. |

## What a person needs to do to close Phase 1

1. Run through `docs/hands-on-checklist.md` (about 30 minutes).
2. Free the second display, set it to 60 Hz, and run `scripts/soak.sh 3600 1`.

## Decision

Phase 2 work that needs no hardware and no hands-on input starts now, in parallel with the items above, because the owner asked for building to continue without stopping. Phase 1 stays open until the two items above are done and any defects they find are fixed.
