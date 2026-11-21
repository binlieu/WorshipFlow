# UI-005b report: the features Show's design draws that the app lacked

Feature ID UI-005b (LIB, SLIDE, OUT). Brief: `AI/specs/UI-005b-show-features.md`. Level: **Implemented, Unit Tested, Simulated** (pictures from a Debug build). Not Hardware Verified, not Live-Service Verified. One agent, no Codex, no advisor. Nothing committed (the tree is left for review).

## Items

All seven items are done. Each was built test first for its model logic; the order of work and the failing runs are listed per item below. Pictures are the evidence for appearance.

| # | Item | Done | Notes |
|---|---|---|---|
| 1 | Small open rows | yes | Toolbar timers `00:10:32` / `25:00`; Quick edit field labels are the languages of the words (detected with `NaturalLanguage`, nothing stored; "First/Second language" when it cannot tell: KI-118); "Saved 2 s ago · live at next trigger" from the real write time and the injected save clock; the Arrangement control is always on a song (from the library it previews an order, not stored); "other" section colour is the design's `--tag` colour (broadcast purple; the picture does not draw an "other" section, so CSS decides); the playlist keeps the system List (selection, arrow keys, type-select, drag-reorder) and only its square selection highlight is turned off; the media transport strip and the Audio tab use the shared components (no red: the strip's red wash and the audio meter's red went; meters end in the warning colour). |
| 2 | Service date and title | yes | `playlist.serviceAt`; title "Sunday 9:00 — 22 Nov" from locale, calendar and date (en_GB exact text, en_US, vi_VN, a Tokyo time zone tested); set from the playlist menu; carried by program export and import; a program that differs only by date is not "already present". |
| 3 | Library kinds | yes | `library.kind`; icon, sidebar order (songs, Bible entry, scripture, sermons, announcements), create and change kind from the menus. The count shown is the presentation count for every kind; sermons and announcements libraries hold ordinary presentations for now (KI-119). |
| 4 | Playlist item kinds | yes | Media file, announcements loop, sermon: select (preview only, Live never changes), Go Live, Next, Previous, relaunch restore, export and import, remove and Clear all and Stop end them, Remote state and every switch handled. The app plays them through the bin's own models (`MediaItemPlayer`). Unknown kinds read as "Unknown item" as before. Not tried in a running app with a real file (KI-120). |
| 5 | Props | yes | Per-prop targets (AUD/STG/BRD pills click to stop, "Show on" menu); text props (name, words, size, colour, position, screens) drawn by the same `TextLayer` path as lyrics (pixel-identical to a hand-built layer in `UI005b_TextPropRenderTests`); a prop never appears on a role it is not targeted to, including on the ready-made stage scenes. The design's "Giving reminder" needs nothing more than a text prop: only its icon differs (KI-121). |
| 6 | Four design Looks | yes | Seeded on a new library only (the app decides "new" before the first library exists). Notes: audience shows words and background without props; broadcast words only; stage unchanged. Speaker notes: a Look has no notes layer, so no Look can carry notes to an audience or broadcast screen; notes stay the stage layouts' (KI-122). |
| 7 | Error card actions | yes | One card per enabled faulted output (screen or mirror) with "Retry output" (the coordinator's `restart`, once; a second failure says so plainly with the new recorded text) and "Details" (recorded text, Copy). A covered window, a stopped or disabled screen and render warnings get none. |

## Migration v12 and how it was tested

Additive only (`Schema.swift`; v1 to v11 untouched): `library.kind` default `songs`, `playlist.serviceAt`, `prop.targets` default `["audience","broadcast"]`, `prop.kind` default `image`, `prop.text`. `UI005b_MigrationV12Tests` opens a library at v11 (`open(at:migratingUpTo: "v11")`), writes a library, presentation, slide, playlist with a song, header, countdown and scripture item, two props, a Look and an appState entry with raw SQL in the v11 shape, closes it, reopens at v12 and checks every row is still there, the library is songs, the playlist has no date, props keep audience and broadcast (the stage never drew props, so a new default of all three would have put logos on stage monitors after the upgrade), pictures stay pictures, items read back with the same titles; and that a second open changes nothing. A third test round-trips the v12 values through the store. Records write the new columns only when set, so a store opened at an older schema (existing tests use `migratingUpTo`) still works.

## Tests (test first, seen failing at runtime, then implemented)

Failing output recorded per item (first run before the implementation, stubs returning empty values; counts from the run):
1. `UI005b_SmallRowsTests`: 7 tests, 19 issues (e.g. `toolbarText → "10:32"` expected `"00:10:32"`; `savedNote → ""`; library language names `"First language"`; `previewArrangementID → nil`).
2. `UI005b_ServiceDateTests`: 5 tests, 10 issues (`serviceTitle → ""`, `serviceAt → nil`). `UI005b_ServiceDateProgramTests`: 2 of 3 failed (date lost in the package; a different date reported "already present"). `UI005b_MigrationV12Tests`: 9 issues before the migration (last migration "v11"; missing columns; kind and date not stored).
3. `UI005b_LibraryKindTests`: 6 issues (`kinds → [songs, songs, songs]`; sidebar order unchanged).
4. `UI005b_PlaylistKindsTests`: 10 of 12 failed (only 3 playlist items stored where 6 expected). The program-package part (`UI005b_ItemKindsProgramTests`) was written after its implementation (an order slip, said plainly); it was checked by temporarily removing the importer's `media` and `sermon` cases, which failed 4 expectations, then restoring them.
5. `UI005b_PropTargetTests`: 9 of 10 failed (stage-only prop on audience and broadcast, text props drawn as pictures). `UI005b_PropsModelTests`: 7 issues. `UI005b_TextPropRenderTests` (compositor): 3 tests.
6. `UI005b_DesignLooksTests` / `UI005b_SeedLooksTests`: 5 and 11 issues before seeding.
7. `UI005b_FaultCardTests`: 5 tests failing before (`reopened → []`, no cards).

Each "recorded failure" above is the first runtime run printed in this session; the full text is not copied into the repository.

**Existing tests changed (two, both forced):** `FIXG_SlideBackgroundStoreTests` line 53, the exact-count migration assertion, now uses `prefix(11)`; `LIB005_Fixtures.swift` `describe(...)` gained three `case` lines because its `switch` over playlist item kinds must be exhaustive (existing lines unchanged).

**Checks run:** `./scripts/check.sh` run twice after the last code change: exit 0 both times; 2522 tests in 393 suites passed each time (2451 before this slice, +71).

## Before and after (share of pixels more than 24 of 255 apart; before = `UI-005a-report.md` after-figures at commit dc7c531, same tool and tolerance)

Pictures: `AI/reports/UI-005b-show-dark.png`, `-show-quick-edit.png`, `-show-light.png`, each with `-side.png` (design left, app right) and `-diff.png`. The seed now uses the new kinds: libraries with kinds, the design's playlist order (Countdown, Announcements loop, three songs, scripture, a sermon, a media file, a response song), a service date, four props and the four seeded Looks.

| `01-operator-show` | before | after |
|---|---|---|
| overall | 20.2 | 20.0 |
| toolbar | 16.7 | 16.7 |
| sidebar | 13.3 | 13.1 |
| playlist | 17.3 | 13.3 |
| centre | 20.5 | 20.5 |
| dock | 26.1 | 26.1 |
| inspector | 21.9 | 22.8 |
| transport bar | 16.5 | 16.5 |

| `01b-operator-show-quick-edit` | before | after |
|---|---|---|
| overall | 21.2 | 20.6 |
| toolbar | 16.7 | 16.6 |
| sidebar | 13.3 | 13.1 |
| playlist | 17.3 | 13.3 |
| centre | 20.3 | 20.3 |
| dock | 26.2 | 26.3 |
| inspector | 26.2 | 25.7 |
| transport bar | 16.5 | 16.5 |

| `09-operator-show-light` | before | after |
|---|---|---|
| overall | 21.4 | 21.2 |
| toolbar | 15.3 | 15.1 |
| sidebar | 13.0 | 12.8 |
| playlist | 17.2 | 12.9 |
| centre | 23.9 | 23.9 |
| dock | 26.2 | 26.2 |
| inspector | 22.0 | 22.9 |
| transport bar | 16.5 | 16.5 |

The components pictures (`08`, `10`) are unchanged (12.7 and 13.3 overall).

What remains above tolerance and why: the font (SF against Inter) differs on every line; the toolbar title reads "Sunday 9:00 AM — Nov 22" because the capture runs in a US locale (the design's text is a UK-style date: the brief asks for the user's locale); the sidebar counts are the seed's (5, 1, 0) and the Scripture row has no count; the playlist differs in the "not installed" tag the app honestly draws on the scripture row (no translation is installed in the throw-away library) and in the live row; the inspector got slightly worse because the design's props rows are now all drawn and the Look row, props rows and Add text prop link sit at different heights than the design's (the extra "Add text prop…" row is the app's, not the design's); the header's arrangement field is truncated ("Arrangement: Na…") and the title is full: the header is wider than the 812 pt centre column with the app's extra "Add to playlist" icon button (not in the design), so the field loses width.

## What is not verified

No pointer, Tab/full keyboard access or VoiceOver run on any new control (pills as buttons, the sheets, the loop chooser, the playlist's table highlight shim); no real media file played through a playlist item (the model's commands were recorded; the app player was only built); no real output unplugged for the error card; the Notes and other Looks were not seen on a second screen; language detection on very short or mixed text is a guess (KI-118); the light-mode pictures of the new sheets were not taken; the minimum window size with the new header; the picture-loop timer was not watched for a full cycle.

## Open and decisions to look at

- Language names are read, not stored (KI-118): say if the operator should be able to set them.
- "Notes" Look: the definition above is the coordinator's reading of a design that names it without defining it.
- Old props keep audience and broadcast, not the stage: a deliberate reading of "previous targets".
- The Scripture row has no count; the design shows one.

## What the owner should look at first

1. Show beside `01-operator-show.png`: the playlist (all item kinds), the Props tab (four props, pills), the Look row (Full selected), the title.
2. Add a bin file to the playlist (right-click > Add to playlist), select it, Go Live, Next; and an announcements loop (playlist menu).
3. Playlist menu > Set service date and time…; New library > Sermons.
4. Props > Add text prop… with Vietnamese words on Broadcast, then switch it on.
5. Unplug or disable a screen: the card with Retry output and Details.
