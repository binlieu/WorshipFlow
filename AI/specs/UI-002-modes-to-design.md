# Brief: UI-002 — Screens signal map, remaining modes to the design, light appearance, playlist headers and countdowns

Read first: `CLAUDE.md`, `AGENTS.md`, `docs/adr/0007-ui-design-adoption.md`, `docs/UI/README.md`, `docs/UI/design-tokens.json`, every picture in `docs/UI/screens/` (look at them all), `AI/reports/UI-001-report.md` and its seven pictures, `docs/16-known-issues.md` (KI-053, KI-067 to KI-069), `AI/reports/HW-004-report.md`, all of `App/Sources`, `Sources/OperatorCore`, and the SDI device report types in `Sources/SDIEngine`.

Catalogue: LIVE-06, SCRN-10, SCRN-11 (interface), LIVE-01 (interface), MEDIA-01 (interface), PRES-03 (playlist structure).

## Rules

Test first for every decision; views stay thin; no dead controls; red only for "on screen now"; behaviour beats the picture (ADR-0007 decisions 4 and 5); never load anything from `docs/UI/mockups`; nothing that works today may be lost — keep the before-and-after control table from UI-001 up to date and include it in your report.

## Part 1 — fixes left by UI-001 (KI-068)

- Header buttons in Show and Edit carry labels as in the design ("Add slide", "Reflow…", "Quick edit" with its key hint), collapsing to icons only when the window is too narrow, with tooltips and accessibility labels either way.
- The duplicate "WORSHIPFLOW" window title beside the service name is removed without breaking the right pane (find the real cause of the empty pane when the title is hidden).
- Clear becomes one split control: click clears words, the attached menu offers Clear all.
- Thumbnails and previews show the theme's background colour or image when there is no video frame, so they are not flat black.

## Part 2 — Screens mode with the signal map

Match `03-screens-outputs.png`: a screens list on the left (thumbnail, name, role chip, destination text, enable switch); on the right a **signal map** and, below it, the selected screen's settings and health counters.
- The signal map is drawn entirely from data: the Mac → each output path → its destination. For SDI: the device, each connector tile with what it carries (unused, output, fill, key, and for which screen), in the order and with the fill and key route **the device reports** (`SDIDeviceReport`), never a fixed order. For displays and windows: a tile per destination. Mirrors appear as their own paths. Faults are shown on the tile in words. A simulated device carries the Simulated badge on the map and on every tile.
- Converters, the ATEM and projector names in the design picture are things the app cannot know: show a destination label only where the operator has typed one (add an optional free-text "connected to" note per destination, stored with the screen profile), otherwise nothing.
- The "4 independent outputs / Fill + Key broadcast" switch from the design becomes two preset buttons that propose a plan for the selected SDI device and show what will change before applying; applying uses the existing planner and asks before a profile change (existing rule).
- For a keyed screen: the three small previews from the design (composite over checkerboard, fill, key) rendered by the compositor and `FillKeySplitter` from the live scene, and the sentence explaining that black is not transparency.
- Settings shown are only those that work today: name, role, destination, video mode, fill and key, fill alpha, Look, layers, mirrors, stage layout for stage screens. Pixel format, colour range and embedded audio are left out. "If output fails" is shown as fixed text describing what the app does.
- The Verification card states the true level for the selected device (Simulated, or Implemented and not hardware verified) and has "Run signal test…" (opens the Hardware Test window) and "Export log bundle…" (saves the app's diagnostic bundle: reuse the hardware test bundle's environment and device steps without running video).
- The presentation logic (what tiles, labels, badges and warnings to show for a given plan, device report and status) lives in `OperatorCore` or `OutputEngine` as a pure, tested function; the view only draws it.

## Part 3 — Edit, Media and Stage modes to the design

Match `02-editor.png`, `05-media-audio.png` and `04-stage.png` for layout, spacing, type and component shapes as closely as native controls allow, using only features that exist. List per mode what matches and what differs and why.

## Part 4 — light appearance

A setting (System, Dark, Light; default Dark) stored with the library's settings. Every colour comes from the asset catalog, so both appearances work; check each mode against `09`, `10` and `11` in the design. Output colours do not follow the appearance. Contrast: text at least 4.5:1 against its background in both appearances; add a test that computes contrast for the token pairs the README names and fails below threshold.

## Part 5 — playlist section headers and countdown items

- New playlist item kinds beside presentations: a **header** (a label such as "Pre-service", "Worship"; not selectable for live; Next skips over it) and a **countdown** (a duration, or a target time today; going live on it starts a timer and shows it on the audience screen with the theme's primary text style, and on stage; when it reaches zero it stays at zero until the operator moves on, and never advances by itself).
- Storage: a migration (the next free number after the latest in `Schema.swift`; never edit earlier ones) adding a kind and a small JSON payload to `playlistItem`, with existing rows becoming presentation items; a migration test using `prefix(n)`. Store API additions are source-compatible.
- Rules test-first in `Domain` and `OperatorCore`: stepping across headers and countdowns, an empty playlist, a countdown as the last item, relaunch restore landing on a header, deleting the live countdown item.
- Interface: the playlist "+" menu adds a header or a countdown; headers render as in the design; drag reorder keeps working across kinds.

## Do not modify

Coordinator-owned tests. `Package.swift`, `CLAUDE.md`, `docs/MASTER-SPEC.md`, `docs/adr/`, `docs/UI/`, earlier migrations, vendor files. You may edit `project.yml` only if the asset catalog needs it.

## Seeing it run

Use the existing debug `--ui-snapshots` hook (extend it) or background accessibility control: temporary `--library`, `--silent-audio`, the simulated SDI card switched on with a keyed broadcast screen and a mirror. Save one picture per mode in dark, and Show, Screens and one other in light, as `AI/reports/UI-002-<mode>[-light].png`. Look at each beside its design picture and write the comparison. Keep runs under two minutes, never cover a display, never switch display modes, do not request full computer control, quit the app, leave nothing in the home folder.

## Constraints

Swift 6 language mode, strict concurrency, justified `@unchecked Sendable` only, no force unwraps in the live path. Do not commit or change git state (do not run `git mv`, `git add`, `git reset` or similar). Do not consult any advisor tool. You are the only agent in the tree this round.

## Done means

1. `./scripts/check.sh` exits 0. Paste the test summary line.
2. The pictures exist with your comparisons.
3. `docs/hands-on-checklist.md` is updated for the signal map, presets, light appearance, and playlist headers and countdowns, without dropping any existing check.
4. `AI/reports/UI-002-report.md` records, per part, what was built, what was left out and why, the updated control table, paths exercised in the running app, commands run with exit status, and everything not verified.
