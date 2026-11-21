# Current status

Updated: 2026-11-20

## Summary

Phase 0 (render spike) is implemented and unit tested; its timing exit criterion is not yet measured (KI-007). Phase 1 is under way: SYS-001 and OUT-002 are unit tested. 304 package tests pass. The workspace has been seen running (screenshot in `AI/reports/OUT-004-workspace.png`); keyboard control has not. Offscreen benchmark: four 1080p compositions per frame take about 0.64 ms mean on this Mac (no video layer, debug build). No video hardware is owned, so nothing is Hardware Verified.

## Verification by slice

| Slice | Implemented | Unit Tested | Simulated | Hardware Verified | Live-Service Verified |
|---|---|---|---|---|---|
| OUT-001 render spike | Yes | Yes (21 tests) | n/a | Not Verified | Not Verified |
| SYS-001 SQLite store | Yes | Yes | n/a | n/a | Not Verified |
| OUT-002 screens and live control | Yes | Yes | Yes (fake outputs and displays) | Not Verified | Not Verified |
| OUT-003/SLIDE-002 themes, Looks, props, image layers | Yes | Yes | n/a | Not Verified | Not Verified |
| OUT-004 operator workspace (with LIB-001, LIB-002, LIB-003, SLIDE-005) | Yes | Yes (logic) | n/a | Not Verified | Not Verified |
| APP-001 integration pass (settings in SQLite, focus, section orders, theme editor) | Yes | Yes (logic) | n/a | Not Verified | Not Verified |
| STAGE-001a stage layouts, timers, time formatting (rules and storage) | Yes (no interface) | Yes | n/a | n/a | Not Verified |
| SYS-002 settings and media references in SQLite (schema v3) | Yes (store only; app still reads JSON) | Yes | n/a | n/a | Not Verified |
| SLIDE-003/004 sections, arrangements, reflow | Yes (rules and storage; no editor UI yet) | Yes | n/a | n/a | Not Verified |

Every other slice in `AI/TASK-BREAKDOWN.md` is Todo.

## Environment

- Development Mac: Mac mini M4, 16 GB, macOS 27.2, Xcode 26.6, Swift 6.3.3. Two 1920 × 1080 displays at 100 Hz.
- Tools added: XcodeGen 2.48.0 (Homebrew).
- No DeckLink, enclosure or ATEM. Desktop Video is not installed.
