# UI-002 report: Screens signal map, remaining modes to the design, light appearance, playlist headers and countdowns

Result: `./scripts/check.sh` exit 0. `✔ Test run with 1641 tests in 249 suites passed after 41.271 seconds.` Verification level: Implemented and Unit Tested; interface checked in a Debug build through the `--ui-snapshots` hook only (pictures drawn from the layer tree). Nothing here is Hardware Verified. No advisor consulted; no git state changed.

## Parts

| Part | State |
|---|---|
| 1 Fixes left by UI-001 (KI-068) | Done, test first |
| 2 Screens mode with signal map | Done (see left-out list) |
| 3 Edit, Media, Stage to the design | Done, partly: layout and components follow the design; features that do not exist were left out |
| 4 Light appearance | Done, with the contrast test |
| 5 Playlist headers and countdowns | Done, test first, schema v8 |

## What was built

### Part 1
Decisions in `OperatorCore/HeaderChrome.swift` (`HeaderChrome`, `ClearControl`, `ThumbnailPolicy`), tests in `UI002_ChromeTests`.
- Header buttons in Show and Edit carry words ("Add slide", "Reflow…", "Quick edit ⌘E", Edit also "Themes…", "Section orders…") and become icons below a measured width (`AdaptiveHeader`, `HeaderChrome.showsLabels`), with tooltip and accessibility label either way. Edit gained Add slide and Quick edit in its header.
- Duplicate title: the real cause of the empty right pane was hiding the title (`toolbar(removing: .title)` makes the right pane draw empty in the capture). Fixed by using the window's own title and subtitle (`navigationTitle` service name, `navigationSubtitle` "WORSHIPFLOW · library") and dropping the custom toolbar item. The operator window is now found by an identifier set by the guard (`AppModel.operatorWindow`), not by its title.
- Clear: one split control, click clears words, the attached menu offers Clear all.
- Thumbnails: scenes now include the background media (not the foreground clip), drawn as one still frame (`ThumbnailPolicy`, `MediaLayers.withoutForeground`), redrawn twice shortly after so a player that is still starting appears.

### Part 2
- `OutputEngine/SignalMapPresenter.swift`: pure map from profiles, `SDIDeviceStatus` (order and key route the device reports), the planner's connector map and per-slot run state. Tiles: unused, output, fill, key, display, window; mirrors are their own paths; faults in words on the tile; Simulated badge on the map, the device block and every tile of a simulated device. 12 tests, including the reversed-route card (SDI 1 Key, SDI 2 Fill).
- "Connected to": `ScreenProfile.connectedTo` (primary and each mirror), shown only where typed; stored in the profile's existing `extra` JSON (no schema change). Writing the store test first showed the notes would have been lost on save; fixed. Removing a mirror removes its note.
- Presets (`SDIPresets`): "Independent outputs" and "Fill + Key broadcast" propose, list `before → after` per screen using the reported route, warn about mirrors that would lose a connector, Apply goes through the ordinary profile update (existing planner and the existing question before a card profile change).
- Keyed screen: three pictures (composite over checkerboard, fill, key) rendered by the same compositor and `FillKeySplitter` from the live scene, captions with the reported connectors, and the "black is not transparency" sentence.
- Verification card (`ScreensPresentation.verification`): Simulated, or Implemented and not hardware verified, or No SDI card. "Run signal test…" opens the Hardware Test window. "Export log bundle…" (`DiagnosticBundle`, a save panel) writes the hardware test's own bundle with only the environment and devices steps (test: two steps, no output started).
- Settings shown: name, role, destination, video mode, fill and key, fill alpha, Look (theme in the current Look), layers, mirrors, stage layout, "If output fails" as fixed text. The old Looks and props panels and the Developer section stay below, so nothing was lost.
- Left out (no feature, or the app cannot know): Thunderbolt enclosure, converter, ATEM and projector tiles; Add screen, Remove screen, Identify screens; pixel format, colour range, embedded audio; schedule lead time counter.

### Part 3
- Edit: slide list grouped by section (coloured labels), a Text / Shape / Image row calling the Insert menu actions, header as above, status strip kept. Left out: Align and Arrange menus, Audience/Stage/Broadcast preview switch, zoom, Object/Slide/Theme tabs, "Saved 2 s ago" (no such features).
- Media: left list "Media bin" and "Audio" with counts (the old kind filter, now a list), title of the selected kind, Import…, larger tiles, blue/red rings (red only while on screen). Left out: Background/Foreground layer switch, routing matrix, levels bars, offline-file card, per-clip transport strip (no such features).
- Stage: layout cards with a drawn preview on the left, layout name and STAGE chip with element buttons on top, larger canvas, right column with element settings, an Elements list, "Assigned to" (stage screens that use the layout) and the timers panel. Left out: Stage message send box (no stage message feature).

### Part 4
`AppearanceChoice` (System, Dark, Light, default Dark) stored in the library's state (`settings.appearance`), View > Appearance menu, applied with `preferredColorScheme` to the operator window only; outputs are drawn by the engine and do not follow it. Contrast test `UI002_ContrastTests` computes ratios from `docs/UI/design-tokens.json` for both appearances: text tokens at least 4.5:1 on `bg`, `surface`, `surface-2` (except the README's own light cyan on `surface-2`), and the README's named pairs. A light-mode defect found and fixed: selected list rows in the library and playlist were unreadable in Light (native sidebar selection); they now use an explicit `surface-3` row.

### Part 5
- Domain (`PlaylistKinds.swift`): `PlaylistItemKind` (presentation, header, countdown), `CountdownSpec`, `PlaylistStepping` (next/previous skip headers, landing for a stored place on a header), `CountdownRun` (duration or time today, clamps at zero, never above the start value), `CountdownText`.
- Schema v8 (rebuild of `playlistItem`: `presentationID` nullable, `kind`, `payload`; existing rows become presentation items); store `addPlaylistHeader`, `addPlaylistCountdown`, `updatePlaylistItem`; `PlaylistItem.kind` has a default, so existing callers compile unchanged. `addPresentation` and `playlistItems` still work on a store opened at an older schema.
- Workspace: headers cannot be selected or taken live; Next and Previous skip them; a countdown goes live as a one-slide deck whose words are the time left (theme primary style on audience, current slide on stage); `countdownTick` rewrites it; at zero it stays at 0:00 and never advances; a countdown as last item ends stepping; deleting the live countdown clears the screens; relaunch on a header lands on the nearest playable item, on a countdown selects it without starting it. 12 workspace tests.
- Interface: playlist "+" menu (Add header…, Add countdown… with a sheet: length or time today), header rows (uppercase label and rule, not numbered), countdown rows (icon, label, 5:00 and LIVE), context menus for rename and edit. Reorder uses the existing `onMove` over all kinds (not exercised by hand).

## Control table (UI-001 table updated; changes only)

| Control | Now |
|---|---|
| Header buttons Add slide, Reflow…, Quick edit | Show and Edit headers, with words, icons when narrow |
| Edit: Themes…, Section orders…, Re-flow, Add slide, Quick edit | Edit header |
| Insert menu items | Insert menu and the Edit row (Text, Shape menu, Image) |
| Clear and Clear all | Transport bar, one split control |
| Screens panel rows (name, role, destination, mirrors, keying, alpha, video mode, layers, theme, stage layout, Start/Stop) | Screens mode: list on the left, detail under the signal map |
| Connector map (text rows) | Signal map; `ConnectorMapView` remains only in the soak view |
| Open/Close screens | Screens list header and the transport bar icon |
| Rescan devices | Signal map header |
| Looks, props panels | Screens mode, bottom section |
| Developer (simulated card, unplug and replug) | Screens mode, bottom section |
| Run signal test… | Screens list, Verification card (and Help menu) |
| Export log bundle… (new) | Screens list, Verification card |
| Presets (new) | Signal map, under the map |
| Connected to notes (new) | Screens detail (primary and each mirror) |
| Media kind filter (All, Videos, Pictures, Sound) | Media mode left list |
| Media Add… | Media header "Import…" |
| Stage layout list, New, Duplicate, Delete, Add element buttons | Stage mode left list and header; element settings right column |
| Timers panel | Stage mode right column (and Show inspector) |
| Appearance (new) | View > Appearance |
| Playlist "+" (new): Add header…, Add countdown… | Playlist header; rows have rename and edit in the context menu |
| Everything else in the UI-001 table | Unchanged |

## Pictures (`AI/reports/`, 2880 x 1720)
Dark: `UI-002-show.png`, `-edit.png`, `-media.png`, `-stage.png`, `-cues.png`, `-screens.png`, `-blackout.png`, `-countdown.png`. Light: `UI-002-show-light.png`, `-screens-light.png`, `-edit-light.png`. Taken with a temporary library, `--silent-audio`, windows only, the simulated card with a keyed "Livestream graphics" screen plus a window mirror and the audience screen on SDI 3. Note: the test loop video is a rainbow, which is why backgrounds look loud.
- Show: single title with subtitle, labelled header buttons, thumbnails with the video behind the words, LIVE and PREVIEW rings, playlist now with PRE-SERVICE and WORSHIP headers and a countdown row, inspector with three screen cards (audience and broadcast marked SIMULATED).
- Edit: sections named in the slide list, an object row under the header, slide 3 live and 4 in preview strip, three words fields, objects canvas and inspector.
- Media: left list with counts, "All media" title, one tile with BACKGROUND badge and red ring while live, Import…, audio panel on the right.
- Stage: layout card, STAGE chip and element buttons, large canvas with dashed boxes, Elements list, Assigned to "Stage · Window", timers.
- Screens: three screens in the list, signal map with four connector tiles (SDI 1 Fill and SDI 2 Key outlined, both with the typed note, SDI 3 Output for the audience, SDI 4 unused), route lines "reported by the card's simulator", two window paths (one mirror with note), the two preset buttons, then the selected screen's settings. Light versions show the same with light tokens.
- Countdown: transport bar says LIVE 4:55 · Starting soon; audience and stage cards show 4:55.
- Cues and blackout as in UI-001.

## Against the design pictures
- `03-screens-outputs`: matches the list with picture, name, role chip, destination, switch; the map as data; Verification card with both buttons; preset buttons; settings form; counters; the three keyed pictures with the black-is-not-transparency text. Differs: tiles are stacked in one column instead of a left-to-right flow with converters and switchers (cannot be known), no Add/Remove/Identify, no pixel format, colour or audio fields (not features), counters are fps, presented, dropped, late (and repeated) without a schedule lead.
- `02-editor`: matches grouped slide list, object row, status strip, large canvas. Differs: inspector is the existing objects inspector, not Object/Slide/Theme tabs; no align, arrange, preview-screen switch, zoom or saved time.
- `05-media-audio`: matches the two-group left list, title, Import, tile grid. Differs: no layer switch, routing matrix, level bars, offline warning, clip transport strip, categories are kinds, not "Motion backgrounds".
- `04-stage`: matches layout list with previews, header with chip and element buttons, big canvas, elements and assigned-to. Differs: no stage message box, element settings are the app's (font size, colour, alignment, frame percentages), no section/arrangement element.
- `09`/`11` light: tokens and rows readable; not compared pixel by pixel.

## Paths exercised in the running app
Debug hook only: import of a bilingual song, headers and a countdown added to the playlist, simulated card on, profile updates (keyed broadcast with mirror and notes, audience on SDI 3), Go Live, Command-1 to 6 through the real menu, B and Right arrow through the key monitor, light appearance set through the setting, countdown go-live and its tick, pictures of each mode, quit by `exit(0)`. The persisted setting and everything in `swift test` were exercised by tests.
Not exercised: any mouse click or typing in the real window (so no preset Apply, no Edit/Media/Stage control, no countdown sheet, no drag reorder across kinds, no save panel for Export log bundle), VoiceOver, minimum window size (1100 x 640), a real second display or card, the View > Appearance menu itself, colour accuracy of window chrome in captures.

## Files
Created: `App/Sources/ScreensMode.swift`; `Domain/PlaylistKinds.swift`; `OperatorCore/{HeaderChrome,WorkspaceModel+Countdowns}.swift`; `OutputEngine/{SignalMapPresenter,SDIPresets,ScreensPresentation}.swift`, `OutputEngine/HardwareTest/DiagnosticBundle.swift`; tests `DomainTests/{UI002_ConnectedNoteTests,UI002_MediaLayersTests,UI002_PlaylistKindsTests}`, `OperatorCoreTests/{UI002_AppearanceTests,UI002_ChromeTests,UI002_PlaylistItemsTests}`, `OutputEngineTests/{UI002_DiagnosticBundleTests,UI002_SDIPresetTests,UI002_ScreensPresentationTests,UI002_SignalMapTests}`, `PersistenceTests/UI002_PlaylistKindStoreTests`, `SettingsStoreTests/UI002_ConnectedNoteStoreTests`; eleven pictures and this report.
Changed: `App/Sources/{AppModel,CentrePane,Components,ContentView,ControlPanels,DesignTokens,LibrarySidebar,MediaBinPanel,ModeViews,OperatorWindowGuard,StageEditorView,Thumbnails,TransportBar,UISnapshotRun,WorkspaceUIState,WorshipFlowApp}.swift`; `Domain/{LibraryModels,MediaLayers,OutputRouting}.swift`; `OperatorCore/{ScreenEditing,SettingsModel,WorkspaceModel,WorkspaceModel+Playlists,WorkspaceModel+Transport}.swift`; `Persistence/{LibraryStore+Playlists,LibraryStore+Settings,LibraryStore+Structure,Records,Schema}.swift`; `WORSHIPFLOW.xcodeproj` (regenerated); `docs/{hands-on-checklist,16-known-issues,17-change-log}.md`.
One existing test line edited: `PersistenceTests/ScriptureSchemaTests.swift` asserted the last migration was v7; it now reads `prefix(7).suffix(1)` (the brief asks for `prefix(n)` migration tests). No coordinator-owned file was touched.

## Deviations and everything not verified
- The session was interrupted once and resumed; the earlier work was re-checked by a clean build and the full test run before continuing. The scratch folder of the first session was lost, so all pictures were retaken.
- Failing-first evidence is compile errors (the API did not exist) or, for persistence, real failing assertions: the connected-note store test failed until the profile's extra JSON carried the notes; `v2StoreStillWorksWithoutThemeColumn` and `v6RowsSurviveV7` failed after v8 until the store tolerated older schemas and the suffix assertion was changed.
- One run of `ScriptureStorePerformanceTests` (fetch under one second) failed once under load while the app was also building; it passed on the next full run.
- "Look" in the Screens settings is the per-screen theme inside the current Look (the Look itself is chosen in the Looks panel below).
- Edit, Media and Stage follow the design's layout and components, not its content; the left-out list above is the "differs and why".
- A one-line countdown label sits in the transport bar as "Starting soon · slide 1 of 1" (the existing position line).
- Not verified: contrast of every restyled control (only token pairs are computed), behaviour at the minimum window size, the preset Apply with the real profile-change question, the countdown against a real clock over a long time, headers across a relaunch in the running app, drag reorder across kinds, VoiceOver reading of tiles and rows, hardware of any kind. Dark `muted` on `surface-3` (5.46) and light `muted` on `surface-3` (4.49) fall just short of the README's stated 5.5 and 4.5 (KI-072).
- Commands run: `swift build`, `swift test` (filtered and full, several), `swift package clean` once (stale link after a Domain change), `xcodegen generate`, `xcodebuild … build` into a scratch folder, the app under `timeout 100` with `--library`, `--silent-audio`, `--ui-snapshots` (about a dozen runs, each quit), `./scripts/check.sh` (exit 0).
