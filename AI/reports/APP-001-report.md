# APP-001 report: integration pass on the operator workspace

## Parts
1. Settings from SQLite (KI-025): DONE. `SettingsModel` (OperatorCore) holds screen profiles, Looks, selected Look, props and custom themes; writes are queued in order; a failed write sets `lastError`. `LegacySettingsFiles` imports `screen-profiles.json` and `looks.json` once (marker `settings.legacyImport`) when the tables are empty; files are never changed. Legacy paths derive from the library file's folder. App `LookStore.swift`/`ScreenProfileStore.swift` deleted; `PublishedScenes` moved to OperatorCore.
2. Keyboard focus (KI-021): DONE in code, keys NOT exercised in the running app. `KeyRouting.decision` (pure, tested). Key monitor uses it; slide-grid container takes focus at launch, after any sheet closes and on Escape in search (search is cleared too). Up/Down arrows also map to previous/next.
3. Section order editor (KI-023): DONE. Sheet from toolbar/playlist context menu; create (starts as natural order), rename, delete, palette add, remove, up/down and drag reorder; picker for the open playlist item. Model methods in `WorkspaceModel+SectionOrders.swift`.
4. Theme editor (KI-023): DONE. Create, duplicate, rename, delete; background (video, colour, image, transparent); per language font, size, colour, outline, frame, alignment; live thumbnail via the compositor; per-song theme picker; custom themes in the per-screen picker. `WorkspaceModel.liveThemeID` feeds `PublishedScenes` so the song theme reaches audience scenes only.
5. Live preview with video (KI-022): NOT DONE, left open. Needs a video-frame layer behind a transparent preview render; not cheap.

## Tests (new files in Tests/OperatorCoreTests)
SettingsModelTests, KeyRoutingTests, SectionOrderTests, ThemeEditingTests. Model-level test `aPresentationThemeChangesTheAudienceSceneAndNotTheBroadcastOne` included.
- `swift test --filter OperatorCoreTests`: 72 tests in 10 suites passed.
- `./scripts/check.sh`: exit 0; package step "Test run with 304 tests in 47 suites passed"; app build ok.

## Run in the app (Debug, `--library` in scratchpad, window outputs only, background accessibility control)
Exercised: first-launch import of old JSON into SQLite (2 profiles imported, json untouched); import lyrics sheet; Section orders sheet (new order, add Chorus, move entry earlier, summary line); Themes sheet (new theme, Colour and Transparent background, preview redraw); "Use for song" and header theme picker showing "My theme"; Go Live: audience live preview showed the song theme (grey, large text) while Broadcast kept the lower third; thumbnails followed the theme. Quit via AppleScript; SQLite rows verified (2 profiles, 1 look, 1 theme, 1 arrangement).
Not exercised: any key press (Return, Space, arrows, Escape, Cmd-F) or the focus ring at launch, because background control cannot send keys to a local monitor; typing numeric/name fields in the theme and section order sheets (AX refused); colour picker, image chooser, drag reorder, playlist item section order picker and context menu, delete confirmations, rename in UI, error bar for a failed save, relaunch restore of theme, prop add/bookmark restore.
Screenshots: `AI/reports/APP-001-section-order.png`, `AI/reports/APP-001-theme-editor.png`.

## Decisions and deviations
- Library file path used for the run is temporary; nothing created under `~/Library/Application Support/WORSHIPFLOW` (none existed before, none now).
- A theme created moments ago must reach the store before a song can use it; the app waits (`settings.flush()`) first.
- Editing a custom theme in use changes the live audience screen at once.
- Imported legacy Look/prop only when both Look and prop tables empty; unreadable old files are reported in `notices` and not imported.
- Edited `docs/16-known-issues.md` status text for KI-021/023/025.
- `xcodegen generate` regenerated `WORSHIPFLOW.xcodeproj` (check.sh does this).
- Unverified: bookmark resolution of props after relaunch, wide displays, multiple displays.
