# Brief: UI-001 — design tokens, app icon, six-mode shell, Show mode, Blackout

Read first: `CLAUDE.md`, `AGENTS.md`, `docs/adr/0007-ui-design-adoption.md`, all of `docs/UI/README.md`, `docs/UI/design-tokens.json`, the pictures `docs/UI/screens/01-operator-show.png`, `08-components.png`, `09-operator-show-light.png` (look at them), `docs/16-known-issues.md`, `docs/hands-on-checklist.md`, all of `App/Sources`, `Sources/OperatorCore` (especially `KeyRouting`, `WorkspaceModel*`, `QuitPolicy`, `LivePublication`), and `Sources/Domain/ShowState.swift`, `SceneComposer.swift`.

Catalogue: LIVE-06 (operator workspace), LIVE-05 (preview surfaces). This is a restructuring of the interface, not new engine features, except Blackout.

## Part 1 — Blackout (test first, before any interface work)

- `ShowCommand.blackout` (toggle) in `Domain/ShowState.swift`, with `isBlackedOut`. While blacked out: audience scenes are opaque black with no video, media, text, objects or props; broadcast scenes are fully transparent with nothing drawn; stage scenes are unchanged (the band still needs its words and clock) but show the word "BLACKOUT" in the layout's warning colour as an extra element; the live deck, index and media transports are kept. `trigger`, `next`, `previous` and a second `blackout` restore the picture; `clear` and `clearAll` keep it blacked out and take effect when it lifts; `stop` ends it.
- Write the failing tests first in new files (for example `Tests/DomainTests/UI001_BlackoutTests.swift` and a composer test), record their output, then implement. Every existing coordinator-owned test must pass unchanged.
- `KeyRouting`: the B key toggles Blackout when the grid has focus, never while typing, never on key repeat. Model method on `WorkspaceModel`. Tests.

## Part 2 — tokens and icon

- An asset catalog in the app target (`App/Resources/Assets.xcassets`; add it to `project.yml` if the sources entry does not already pick it up) with: the `AppIcon` set built from `docs/UI/icon/AppIcon.iconset` (copy the PNGs; set `ASSETCATALOG_COMPILER_APPICON_NAME`), and one named colour set per colour token in `design-tokens.json` with dark and light appearances, using the token names.
- A small Swift file of typed accessors for colours, spacing, radius and type styles so views never use literals. A unit test (in `OperatorCore` or a script run by `scripts/check.sh`) that reads `docs/UI/design-tokens.json` and fails if a colour token has no colour set or a colour set has no token, so design and app cannot drift silently.
- Output colours stay engine constants (ADR-0007 decision 6).

## Part 3 — the six-mode shell

- One window. A segmented mode switcher in the toolbar's principal position: Show, Edit, Media, Stage, Cues, Screens, with Command-1 to Command-6. The selected mode is restored on relaunch. Toolbar also carries the playlist name, the three role status pills (AUD, STG, BRD: on, off or fault, with text for VoiceOver) and search.
- Re-home what exists; do not rewrite working logic:
  - **Show:** library and playlist sidebar; the slide grid; on the right, Preview and Live panes side by side, the Screens summary (one preview per screen, with role chip, destination text, and the Simulated badge where true), Look buttons, props and messages toggles, timers. Below the grid, the compact words editor for the selected slide.
  - **Edit:** the slide editor at full size: words, notes, and the objects canvas with its inspector; theme picker; re-flow and section orders entry points.
  - **Media:** the media bin at full size, the foreground transport, and Audio.
  - **Stage:** the stage layout editor as a full mode (retire the sheet), timers and clock settings.
  - **Screens:** the existing screens configuration, connector map and Looks editing at full size, the developer setting, and buttons that open the hardware test window if it exists (check for the type at build time; leave them out if it does not). The signal-map drawing itself is the next slice: keep the existing connector map for now.
  - **Cues:** a centred note: "Macros, slide actions and control surfaces arrive in a later version." No controls.
- The transport bar stays visible in **every** mode, restyled to the design: LIVE or STOPPED badge, live text and its position ("Amazing Grace · Chorus · slide 3 of 9"), Previous, Go Live (prominent, red fill), Next, Clear (with Clear all in its menu), Blackout, Stop, and the output health readout (frame rate, dropped, late, and the audio meter if present). Key hints on the buttons as in the design. The clip transport strip still appears above it while a clip is loaded.
- Transport keys work in every mode unless a text input has focus (the existing routing rule), so an operator in the Screens mode can still advance the service.
- Sheets that remain sheets: import and re-flow lyrics, section orders, themes, quick edit.
- Everything that worked before still works: every model call, every setting, soak mode, `--library`, `--silent-audio`, `--open-screens`, `--hardware-test` if present.

## Part 4 — Show mode to the design

Match `01-operator-show.png` for layout, spacing, type sizes, colours and component shapes as closely as native controls allow: sidebar rows with counts, the "EN · VI" marker on bilingual songs, section headers with coloured dots and repeat counts, thumbnails with number and first line beneath, LIVE (red) and PREVIEW (blue) rings drawn outside the image, the arrangement menu and Quick edit in the header, grid and list toggle. Do not invent data the app does not have (if there is no song count, show none).

## Do not modify

Coordinator-owned tests. `Package.swift`, `CLAUDE.md`, `docs/MASTER-SPEC.md`, `docs/adr/`, `docs/UI/` (the design is the reference; do not edit it), existing migrations. Do not load or embed anything from `docs/UI/mockups` in the app.

## Seeing it run

Launch the Debug app with a temporary `--library` and `--silent-audio`, import a bilingual song, go live in window outputs, and save one screenshot per mode as `AI/reports/UI-001-<mode>.png` (six files) plus `AI/reports/UI-001-blackout.png` with Blackout on. Put each beside the matching design picture and list, per mode, what matches and what differs and why. Keep runs under two minutes, never cover a display, never switch display modes, do not request full computer control, quit the app, leave nothing behind in the home folder.

## Constraints

Swift 6 language mode, strict concurrency, justified `@unchecked Sendable` only. Views stay thin: any new decision goes in `OperatorCore` or `Domain` with a test written first. No force unwraps in the live path. Do not commit or change git state. Do not consult any advisor tool. You are the only agent in the tree this round.

## Done means

1. `./scripts/check.sh` exits 0. Paste the test summary line.
2. The seven screenshots exist, and your comparison against the design is in the report.
3. `docs/hands-on-checklist.md` is updated for the new layout (mode switching, Command-1 to 6, Blackout, transport keys working from every mode) without dropping any existing check.
4. `AI/reports/UI-001-report.md` records, per part, what was built, what from the design was left out and why, which paths you exercised in the running app, commands run with exit status, and everything not verified.
