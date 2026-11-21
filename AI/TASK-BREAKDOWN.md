# Task breakdown

Implementation IDs are three-digit (ADR-0002). "Catalogue" lists the `docs/MASTER-SPEC.md` rows a slice satisfies. Status values: Todo, In progress, Implemented, Unit Tested, Simulated, Hardware Verified.

## Phase 0 — render spike

| ID | Slice | Catalogue | Depends on | Model | Why this model | Status |
|---|---|---|---|---|---|---|
| OUT-001 | Metal compositor, text rasteriser, looping video background, native display and window outputs, frame statistics, soak mode | ARCH-03, ARCH-20–23, NFR-01, NFR-02, G-6 | — | Sonnet | Render and output integration | Unit Tested; timing Not Verified (KI-007) |

## Phase 1 — service MVP (26 catalogue features)

| ID | Slice | Catalogue | Depends on | Model | Why this model | Status |
|---|---|---|---|---|---|---|
| SYS-001 | SQLite store through GRDB: schema v1, migrations, autosave, crash recovery | NFR-06, NFR-07 | OUT-001 | Sonnet | Persistence with test-first migrations | Unit Tested. Follow-ups: observation streams, debounced autosave (with OUT-004), tables for groups, arrangements, themes, media |
| SLIDE-001 | Slide and presentation model, text and shape and image objects, fills and effects | PRES-01, MEDIA-07 | SYS-001 | Sonnet | Domain plus render integration | Todo |
| SLIDE-002 | Themes and templates, bilingual text areas | PRES-06, PRES-10 | OUT-002 | Sonnet | Feature work | Unit Tested (themes with OUT-003; second-language pairing with SLIDE-004) |
| LIB-001 | Libraries and presentations: create, rename, delete, move | PRES-02 | SYS-001 | Sonnet | Repository plus UI | Unit Tested; interface partly seen running (KI-011) |
| LIB-002 | Service playlists and keyboard stepping | PRES-03 | LIB-001 | Sonnet | Feature work | Unit Tested; interface partly seen running (KI-011) |
| LIB-003 | Quick search, diacritic-insensitive | PRES-08 | LIB-001 | Sonnet | SQLite full-text search | Unit Tested; interface partly seen running (KI-011) |
| SLIDE-003 | Song sections and arrangements | PRES-04 | SLIDE-001 | Sonnet | Domain rules, test-first | Unit Tested (no UI) |
| SLIDE-004 | Reflow editor | PRES-05 | SYS-001 | Sonnet | Pure rules, test-first | Unit Tested (no UI) |
| OUT-002 | Screens with roles, single-display mapping, preview and live and clear and stop semantics | SCRN-01, SCRN-02, SCRN-03, SCRN-04, NFR-03–05, NFR-08, NFR-10 | OUT-001 | Sonnet + review pass | Screen routing and failover are risky logic | Unit Tested, Simulated |
| OUT-003 | Looks, alternate themes per screen, props layer | SCRN-08, SCRN-09, MEDIA-08 | OUT-002 | Sonnet | Feature work | Unit Tested (built with SLIDE-002) |
| MEDIA-001 | Media bin with thumbnails, security-scoped bookmarks | MEDIA-01 | SYS-001 | Sonnet | Feature work | Todo |
| MEDIA-002 | Motion backgrounds and foreground video with transport | MEDIA-02, MEDIA-03 | MEDIA-001, OUT-002 | Sonnet + review pass | Media timing | Todo |
| STAGE-001 | Stage layout editor, current and next, clocks and countdowns | LIVE-01, LIVE-02, LIVE-04 | OUT-002 | Sonnet | Feature work | Todo |
| OUT-004 | Operator workspace with live previews | LIVE-05, LIVE-06 | OUT-002, LIB-002 | Sonnet | SwiftUI and AppKit | Unit Tested; interface partly seen running (KI-011) |
| SLIDE-005 | Quick edit on the live slide; editing queued content never alters live output | PRES-07, LIVE-07 | OUT-002, SLIDE-001 | Sonnet + review pass | Edit and live isolation is risky logic | Unit Tested; interface partly seen running (KI-011) |

Phase 1 covers 26 catalogue rows: PRES-01–08 and 10; MEDIA-01, 02, 03, 07, 08; SCRN-01–04, 08, 09; LIVE-01, 02, 04–07.

### Added during Phase 1

| ID | Slice | Catalogue | Depends on | Model | Why this model | Status |
|---|---|---|---|---|---|---|
| SYS-002 | Schema v3: themes, Looks, props, screen profiles, media assets | PRES-06, SCRN-08, MEDIA-08, MEDIA-01 | SLIDE-003 | Sonnet | Persistence, test-first | Unit Tested |
| APP-001 | Integration pass: settings from SQLite, focus fix, section-order editor, theme editor | PRES-04, PRES-06, KI-021, KI-023, KI-025 | OUT-004, SYS-002 | Sonnet | SwiftUI plus wiring | Unit Tested; editors seen running; keys not pressed (KI-026) |
| STAGE-001a | Stage layouts, timers, time formatting, stage composer, schema v4 | LIVE-01, LIVE-02, LIVE-04 | OUT-003 | Sonnet | Pure rules, test-first | Unit Tested |

## Later phases

Broken down when the phase before them reaches its exit criterion. Placement of the remaining 38 catalogue rows is fixed in `docs/MASTER-SPEC.md` section 3.

| Phase | Planned slices |
|---|---|
| 2 | OUT-005 mirrored outputs, OUT-006 Syphon, HW-001 DeckLink discovery and SDI output, KEY-001 Fill and Key, MEDIA-004 live inputs, MEDIA-005 audio library, MEDIA-006 audio routing, OUT-007 NDI |
| 3 | CUE-001 slide actions and macros, CUE-002 MIDI, CUE-003 remote API and web control, CUE-004 scheduling, CUE-005 playback markers, CUE-006 Stream Deck, OUT-008 messages, announcements and masks, STAGE-002 stage messages |
| 4 | LIB-004 Bible, LIB-005 lyric service, LIB-006 planning integration, MEDIA-007 network streams, OUT-009 recording, OUT-010 RTMP |
| 5 | Per feature, each justified separately |
