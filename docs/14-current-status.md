# Current status

Updated: 2026-11-22 (night)

## Summary

On 2026-11-22 (night) `main` passes `./scripts/check.sh` with 3,476 package tests and Debug and Release builds; the schema is v15. The whole operator workflow (library, edit, playlist, preview, live to audience, stage and broadcast compositions, media, cues, macros, MIDI, remote control, scripture, program packages) is Implemented and Unit Tested, and the modes are measured against the design by rectangles (UI-008). Keyboard control has been run with real key events through the debug hook (FIX-N, FIX-V); almost none of the 2026-11-22 features has been operated by a person. SDI output is Simulated only: no video hardware is owned, so nothing is Hardware Verified or Live-Service Verified. The Phase 0 timing criterion (KI-007) depends on the soak result recorded in `docs/15-agent-handoff.md`. The table below is per slice and was last filled in on 2026-11-21: its test counts are the counts when each slice landed, and slices after UI-005h (FIX-K to FIX-V, UI-005c to g, UI-006, SYS-015, UI-007, UI-008, TESTDATA-001) have no row; see `docs/17-change-log.md` and `docs/15-agent-handoff.md` for those.

REVIEW-5 (0 high, 6 medium, 23 low) and FIX-W (M1 to M5 and the migration-backup low fixed; M6 open until after the idle soak); FIX-X then fixed lows L3, L9 and L13 (Blackout keeps video objects playing; marker delete asks first); not yet in an installed build (build 197 has neither FIX-W nor FIX-X).

## Verification by slice

| Slice | Implemented | Unit Tested | Simulated | Hardware Verified | Live-Service Verified |
|---|---|---|---|---|---|
| OUT-001 render spike | Yes | Yes (21 tests) | n/a | Not Verified | Not Verified |
| SYS-001 SQLite store | Yes | Yes | n/a | n/a | Not Verified |
| OUT-002 screens and live control | Yes | Yes | Yes (fake outputs and displays) | Not Verified | Not Verified |
| OUT-003/SLIDE-002 themes, Looks, props, image layers | Yes | Yes | n/a | Not Verified | Not Verified |
| OUT-004 operator workspace (with LIB-001, LIB-002, LIB-003, SLIDE-005) | Yes | Yes (logic) | n/a | Not Verified | Not Verified |
| APP-001 integration pass (settings in SQLite, focus, section orders, theme editor) | Yes | Yes (logic) | n/a | Not Verified | Not Verified |
| HW-004 real bridge wired into the app and the test kit | Yes | Yes | Yes (simulated; driver-absent state run for real) | **Not Verified** | Not Verified |
| HWTEST-001 hardware test kit and log bundle | Yes | Yes | Yes (simulated card, with injected faults) | Not Verified | Not Verified |
| CUE-002b cues, macros, schedule, MIDI and remote control wired into the app (schema v10), with FIX-E review fixes | Yes | Yes (2126 tests) | Debug snapshot hook; MIDI through a virtual port and the remote server on loopback only | Not Verified | Not Verified |
| UI-003 Show mode to design revision 2 (dock, controller, toolbar timers, tabs, Quick edit tab, stage message) | Yes | Yes (logic, 2010 tests at the end of Part 1) | Debug snapshot hook with real key events only | Not Verified | Not Verified |
| UI-002 Screens signal map, Edit/Media/Stage to the design, light appearance, playlist headers and countdowns (schema v8) | Yes | Yes (logic) | Simulated card only | Not Verified | Not Verified |
| UI-005h output looks (type weights and sizes, audience gradient, lower-third plate and accent bar in the key matte, stage composition, Classic themes; schema v13) | Yes | Yes (UI005hTests, 2645 tests at the end) | Simulated (SDI readback, simulated card) | **Not Verified** (no keyer has seen the matte) | Not Verified |
| UI-001 six-mode shell, design tokens, app icon, Show mode, Blackout | Yes | Yes (logic) | n/a | Not Verified | Not Verified |
| LIB-004c scripture interface (Scripture view, passages in Show, playlist items, Translations screen; no migration) | Yes | Yes (logic) | Debug snapshot hook with invented text and real key events | Not Verified | Not Verified |
| LIB-004b scripture store and import tool | Yes (no interface) | Yes | Tool run against the owner's real database | n/a | Not Verified |
| LIB-004 scripture engine rules (Phase 4) | Yes (rules only) | Yes (109 tests) | n/a | n/a | Not Verified |
| CUE-001 cue engine rules (Phase 3) | Yes (rules only) | Yes (191 tests) | n/a | n/a | Not Verified |
| HW-003 real DeckLink bridge (SDK 16.0) | Yes | Yes (mapping and driver-absent only) | n/a | **Not Verified** | Not Verified |
| HW-002, OUT-005 SDI and mirrored outputs in the app | Yes | Yes | Yes (simulated card, real-time driver) | Not Verified | Not Verified |
| HW-001, KEY-001 SDI engine with simulated device | Yes | Yes | Yes (simulated Duo 2, manual clock) | Not Verified | Not Verified |
| MEDIA-005, MEDIA-006 audio library and routing | Yes | Yes | Silent render path only | Not Verified | Not Verified |
| SLIDE-001b slide objects editor and reflow fixes | Yes | Yes (logic) | n/a | Not Verified | Not Verified |
| MEDIA-001 media bin, backgrounds, foreground video in the workspace | Yes | Yes (logic) | n/a | Not Verified | Not Verified |
| SLIDE-001a slide objects: model, rendering, storage (no editor) | Yes | Yes | n/a | Not Verified | Not Verified |
| MEDIA-002 media transport, probing, thumbnails, player, media layers (engine only) | Yes (not wired into the app) | Yes | n/a | Not Verified | Not Verified |
| STAGE-001b stage layout editor, timers panel, clock setting | Yes | Yes (logic) | n/a | Not Verified | Not Verified |
| STAGE-001a stage layouts, timers, time formatting (rules and storage) | Yes | Yes | n/a | n/a | Not Verified |
| SYS-002 settings and media references in SQLite (schema v3) | Yes (store only; app still reads JSON) | Yes | n/a | n/a | Not Verified |
| SLIDE-003/004 sections, arrangements, reflow | Yes (rules and storage; no editor UI yet) | Yes | n/a | n/a | Not Verified |

Every other slice in `AI/TASK-BREAKDOWN.md` is Todo.

## Environment

- Development Mac: Mac mini M4, 16 GB, macOS 27.2, Xcode 26.6, Swift 6.3.3. Two 1920 × 1080 displays at 100 Hz.
- Tools added: XcodeGen 2.48.0 (Homebrew).
- No DeckLink, enclosure or ATEM. Desktop Video is not installed.

FIX-J (review fixes of UI-005h: fit to block, text cache, clamped decoding, tolerant loading, stage parts, font check, scripture limits, opaque-key and plate opacity, fill and key tests): Implemented, Unit Tested (see `AI/reports/FIX-J-report.md` for the count); Simulated only for the SDI readback test; Hardware Verified: Not Verified; Live-Service Verified: Not Verified.
