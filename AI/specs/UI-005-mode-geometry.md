# UI-005c/d/e/g: Edit, Media, Stage and Cues matched to their mockups' rectangles

Feature IDs: UI-005c (Edit), UI-005d (Media), UI-005e (Stage), UI-005g (Cues). Model: Sonnet. One agent per mode, each in its own git worktree, working at the same time. This brief is the same for all four; the table says what differs.

The owner, 2026-11-21, after testing build 105: "can you work on the edit now? pixel to pixel match", "also matching stage as well", "and matching media, cues too".

| Slice | Mode | Design picture and mockup | Audit (your rows) | Your files |
|---|---|---|---|---|
| UI-005c | Edit | `02-editor.png`, `02-editor.html` | "Edit" in `AI/reports/UI-005-audit-edit-media-stage.md` | `EditModeView` (move it out of `ModeViews.swift` into `App/Sources/EditMode.swift`), `SlideObjectsEditor.swift`, `ThemeEditorSheet.swift`, `SectionOrderSheet.swift`, new files named `Edit*.swift` |
| UI-005d | Media | `05-media-audio.png`, `05-media-audio.html` | "Media" in the same file | `MediaModeView` (move it into `App/Sources/MediaMode.swift`), `MediaBinPanel.swift`, `BinPlayerPanel.swift`, `BinPlayerSupport.swift`, `HotFolderSupport.swift`, `AudioPanel.swift`, `MediaDockView.swift`, `MediaTransportStrip.swift`, new files named `Media*.swift` |
| UI-005e | Stage | `04-stage.png`, `04-stage.html` | "Stage" in the same file | `StageModeView` (move it into `App/Sources/StageMode.swift`), `StageEditorView.swift`, `TimersPanel.swift`, `StageMessageView.swift`, new files named `Stage*.swift` |
| UI-005g | Cues | `06-cues.png`, `06-cues.html` | "Cues" in `AI/reports/UI-005-audit-screens-cues-looks.md` | `CuesMode.swift`, `CuesActionList.swift`, `CuesControlInputs.swift`, `CuesEditors.swift`, `CuesTab.swift`, `CueSupport.swift`, new files named `Cues*.swift` |

## Read first

`CLAUDE.md`; `AI/specs/UI-005-design-match-plan.md` (every section binds you: the owner's decisions, the defaults, what the design may not override, the font, and the rectangle rule); your audit rows; `AI/reports/UI-005j-report.md` (how Show was matched, and the tools: `scripts/design-rects`, `App/Sources/DesignProbe.swift`, `scripts/compare-rects.py`, `scripts/design-map-show.json`, `scripts/design-capture.sh`); `App/Sources/WFControls.swift`, `Components.swift` and `DesignTokens.swift` (the shared controls, components and type styles you must use); your design picture and mockup with `docs/UI/mockups/ui.css`. The picture wins where sources disagree.

## What to do

1. **Measure first.** Run `scripts/design-rects` on your mockup. Extend the debug capture so the app opens in your mode at 1440 by 900, in a seeded state that reproduces your design picture as far as today's data allows, and tag your views for the probe. Write `scripts/design-map-<mode>.json`. Produce the "before" table (elements mapped, elements within 1 point, the worst).
2. **Close the geometry.** Every S and M row of your audit: panel widths, the centred canvas or grid, headers, rows, tiles, inspectors and their sections, tabs, fields, pills and buttons, at the mockup's rectangles, type sizes, weights and radii, using the shared controls and type styles, in dark and light. Fix causes, never compensate with offsets. Target: every mapped element within 1 point; report honestly what is not.
3. **Only what works is drawn.** This pass changes appearance and layout, not the model. A control the design draws whose feature does not exist (your audit's L rows) is **left out**, and its place in the layout is kept so the rest still lines up; list each as "open, needs a feature slice". Do not draw dead controls and do not fake data.
4. **The owner's extras stay,** restyled and placed where they do not disturb the designed layout; list where each went. For Edit: the word fields go to the inspector's Slide tab and the theme control to its Theme tab (tabs Object, Slide, Theme may be built as layout over existing features). For Media: the bin player sits in the clip strip position; hot folders are a group in the collections sidebar. For Stage: Timers move to a sheet opened from the toolbar's timer chip. For Cues: Schedule stays below Slide actions.
5. **UI-005d only, the owner's request of 2026-11-21:** "have all clear buttons as icon buttons on top menu of media bin next after audio". In the Show dock's header row (`MediaDockView.swift`), directly after the Audio tab, add icon buttons for Clear lyric, Clear background, Clear foreground, Clear music and Clear all, in that order, separated from the tabs by the design's divider; each uses the existing command through the one command path, has a tooltip with its name and key, an accessibility label, a disabled look when there is nothing of that kind to clear, and never uses red. The Clear menu in the transport bar keeps working. Put the same row in Media mode's bin header if it fits the mockup without moving designed elements; say what you did. The Show mapping (`scripts/design-map-show.json`) must still pass for every other dock element.

## Working in a worktree beside three other agents

- You are in your own git worktree on your own branch. Other agents are changing other modes at the same time, and the coordinator will merge all four. **Touch only your files** (the table) plus new files with your prefix. `ModeViews.swift`: only cut your own mode's view out of it into your new file; do not reformat or reorder anything else in it.
- Do not edit shared files: `WFControls.swift`, `Components.swift`, `DesignTokens.swift`, `DesignProbe.swift`, `ContentView.swift`, `AppModel*.swift`, `WorkspaceUIState.swift`, `UISnapshotRun.swift`, `UISnapshotDesign.swift`, the scripts other than your own map file, anything under `Packages/`, `project.yml`, `Package.swift`. If you need a new shared component or token, define it in your own file (`<Mode>Components.swift`) and list it under "wanted in the shared files" in your report. If one line in a shared file is truly unavoidable (for example registering your capture state), make it one clearly commented line and list it.
- Do not edit `docs/` (not the change log, not known issues, not the checklist): put the entries you would add in your report under headings "Change log", "Known issues" and "Hands-on checklist", and the coordinator will merge them. Write only `AI/reports/UI-005<letter>-report.md` and `AI/reports/UI-005<letter>-*.png`.
- Builds: other agents are building too. Use your own build folders: run the check as `WF_DERIVED_DATA="<a scratch folder of your own>" ./scripts/check.sh`. Timing-sensitive tests can fail when four builds run at once: re-run once, and report a failure that repeats.
- Git: when finished, commit everything in your worktree to your own branch with a message starting `feat(UI-005<letter>):` and ending with the line `Co-Authored-By: Claude Fable 5.2 <noreply@anthropic.com>`. Do not push, do not touch `main`, do not merge, do not rebase.

## Rules

- No model, schema or behaviour change. Existing tests are not edited; add tests only for pure layout logic you introduce.
- Editing never changes Live; red only for on air; nothing the app has not observed is drawn as fact; accessibility labels and keyboard behaviour are kept; probe identifiers never replace accessibility labels.
- Do not edit `docs/UI`, `docs/adr`, `AI/specs`, `Vendor/`, the vendored `sdk/` folder.
- No advisor tool. No full computer control. Never open the owner's real library under Application Support; if you launch the app use your own scratch folder, a temporary `--library` and `--silent-audio`, stop only what you started, leave nothing in the home folder or in `dist/`.
- The repository is public: no user names, home paths, computer names or e-mail addresses in any file or picture. No assertions on wall-clock time.
- If you are running out of room, stop at a region boundary with the app building and the check passing, commit, and say exactly which regions are within 1 point and which are not.

## Done means

Your report has: the before and after rectangle table per region (mapped, within 1 point, the worst five with numbers); unmapped elements on both sides with a reason each; the L rows left out; where each extra went; side-by-side and difference pictures in dark and light (each under 1 MB); the shared-file wants; the docs entries; the check's exit status and test count; what is not verified. Do not call a region matched unless the rectangle comparison says so.
