# UI-004 report: name, version and About, rounded borders, editor drag

Model: Sonnet. Brief: `AI/specs/UI-004-about-borders-editor-drag.md`. Order followed: the rename first, `./scripts/check.sh` (exit 0, 2343 tests), then items 1 to 3, then the final check.

## Final check

`./scripts/check.sh` exit status 0. Package tests: `Test run with 2364 tests in 364 suites passed`. The app build and `== OK` followed. After the rename alone: exit 0, 2343 tests. Not run: the UI tests (none exist), a Release build through `check.sh` (the package script built a Release app: exit 0, `codesign --verify --deep --strict` ok).

## The rename ("WorshipFlow")

Done. Changed: `PRODUCT_NAME` (so the bundle is `WorshipFlow.app`, executable and `CFBundleName` `WorshipFlow`), document type names, the operator window title and everything the operator or tester reads (labels, messages, notices, help text, Hardware Test window and report, `summary.txt` MACHINE line, zip and folder names, remote control page, soak report line, stderr log prefix, wait-reason string, cue-run MIDI client names), `scripts/package-test-build.sh`, `scripts/soak.sh`, `docs/hardware-test-guide.md`, `docs/hands-on-checklist.md`. `README.md` had no capitalised name.

Everything that derives a path or identifier from the product name, checked one by one:
- Library path: it was a literal, not derived from the bundle name. It is now `LibraryLocation` (Persistence; `folderName = "WORSHIPFLOW"`), used by `AppModel.libraryURL`. Test `UI004_LibraryLocationTests` pins `.../Application Support/WORSHIPFLOW/Library.sqlite`. I never opened the real library folder.
- Bundle identifier `org.worshipflow.app`: unchanged (read from the built plist: `CFBundleIdentifier => org.worshipflow.app`).
- No `UserDefaults`, `@AppStorage`, autosave names or `CFBundleName`-built paths exist in the app (searched). Window lookup uses the identifier `wf-operator-window`, then the title; `AppModel.operatorWindowTitle` was changed together with the scene title.
- Scheme, project and DerivedData folder names, `check.sh` commands, the `--ui-snapshots` / `UI_SNAPSHOT_DIR` hook: unchanged. `check.sh` only builds, so it needs no change. `soak.sh` ran `.../WORSHIPFLOW.app/Contents/MacOS/WORSHIPFLOW`: changed to the new spelling.
- DerivedData product: Xcode itself removed the stale `WORSHIPFLOW.app` in the `WORSHIPFLOW-check` folder and made `WorshipFlow.app` (seen on disk). The package and soak scripts now delete any `*.app` in their own Release products folder before building, and the package script fails if `WorshipFlow.app` is not listed with exactly that spelling. Run for real: `dist/WorshipFlow-hardware-test-<date>-<commit>/WorshipFlow.app` and `.zip`, the executable `WorshipFlow`.
- Older reports: `HardwareTestUnfinished.find` matches the folder suffix ignoring case, and `zipName` splits ignoring case, so a `...-WORSHIPFLOW-hardware-test-unfinished` folder is found and its zip is named in the new spelling (test `anUnfinishedFolderFromAnOlderBuildIsStillFoundAndNamedInTheNewSpelling`). Nothing else reads its files by that name.
- Test `UI004_NoOldSpellingTests` scans `App/Sources` and `Packages/WorshipFlowKit/Sources` (not the vendored SDK) and fails on any `WORSHIPFLOW` except the library constant.
- Decision and unchanged list: `docs/16-known-issues.md` KI-110 and `docs/17-change-log.md`.

### Existing tests whose expected strings I changed (only the expected string)
- `OperatorCoreTests/FIXE_RevokeTests.swift` line 54: `connect again after WORSHIPFLOW restarts` to `WorshipFlow`.
- `OutputEngineTests/FIXD_S6_UnfinishedTests.swift` lines 40, 41 (folder name, zip name), 71 (folder suffix), 131 (suggested zip name).
- `OutputEngineTests/HWTEST_BundleTests.swift` lines 223, 224 (real and simulated zip names).
- `OutputEngineTests/HWTEST_LaunchTests.swift` lines 78, 154, 170 (zip name expectations).
- `ProgramPackageTests/LIB005_SafetyTests.swift` line 87 (`Update WORSHIPFLOW` to `Update WorshipFlow`).
Left alone on purpose: inputs that merely hold the word as data (`HWTEST_LaunchTests` argv[0], `FIXD_S15_KeyGateTests` window titles, `ToolLibraryGuardTests` / `ToolCLITests` lsof command names, `FIXD_HeadlessInjectionTests`); they assert nothing a person sees.

### How the coordinator replaces the installed copy so the name changes on disk
Finder treats `WORSHIPFLOW.app` and `WorshipFlow.app` as the same name, so copying over it keeps the old capitals. Quit the app, then delete the old bundle first and copy the new one in: `rm -rf /Applications/WORSHIPFLOW.app && ditto "<DerivedData or dist>/WorshipFlow.app" /Applications/WorshipFlow.app`, then check with `ls /Applications | grep -i worshipflow` (it must print `WorshipFlow.app`). The library is untouched by this. (Never `ditto` over the existing bundle, and do not use Finder's replace.)

## Item 1: version and About: done

- `BuildInfo` (Domain): reads `CFBundleShortVersionString`, `CFBundleVersion` (the build number), and `WFBuildCommit` and `WFBuildDate`, which a build phase ("Stamp build info" in `project.yml`, a post-build script) writes into the BUILT Info.plist only. Line: `WorshipFlow 0.0.1 (build 87), commit 4d9431b-dirty, built 2026-11-21`; with no git: `WorshipFlow 0.0.1 (build 1), development build`. Junk in either value (a path, an unexpanded `$(...)`, text) is ignored, never shown. The build number is the git commit count (the script rewrites `CFBundleVersion` in the built plist). Nothing is written to a tracked file; the script exits 0 and writes nothing when git is missing. The phase is in the Xcode target, so the package script and `check.sh` both get it; I set `ENABLE_USER_SCRIPT_SANDBOXING: NO` for it. Signing still verifies (Debug and Release).
- About window (`AboutView`, `AboutInfo`): icon, name, one paragraph, the version line with Copy, "Developed by Simon Lieu", `me@simonlieu.com` (mail link), Apache 2.0, the project link, the third-party notices from NOTICE and the README. Menu items: app menu "About WorshipFlow" and Help "About and version...". It follows the appearance choice (my first picture showed it stuck in dark; fixed). Added beyond the brief: Space, Return and the arrows are not transport keys in the About window (`KeyRouting.isAboutWindow`), otherwise they would have moved the live show.
- Hardware Test: `HardwareEnvironmentInfo.appBuildDetail` (optional, so an older `report.json` still decodes), shown in the environment step and in the `summary.txt` MACHINE line. Tests `UI004_ReportBuildLineTests`.
- Tests: `UI004_BuildInfoTests` (format, fallback, junk, unexpanded settings), `UI004_AboutInfoTests` (the name and address are the only personal details, one `@`, no path), `UI004_AboutKeyGateTests`.

## Item 2: rounded borders: done. Causes found

Reproduced first with the ui-snapshots hook (new `UI_SNAPSHOT_UI004=1` scenario, whole window at 2x, dark and light), before any change.
1. Mode switcher, AUD/STG/BRD pills, toolbar timers: the outline was `.overlay(shape.stroke(...))`, which is centred on the edge, so half the 1 pt line lies outside the view's frame and the toolbar item clips to its bounds: the ends and the top and bottom were flattened, and the last pill lost its right end. Fix: one `wfOutline(shape, stroke:, fill:)` in `Components.swift` (fill and stroke from the same shape; stroke drawn with `strokeBorder`, inset by half its width) plus 1 pt of room inside the toolbar items.
2. Media controller pill (not clipped by anything): a `Capsule()` with the default `.continuous` style, stroked at 1 pt, drew a short straight stub at each end on this macOS (seen at 6x). Switching to `Capsule(style: .circular)` removed it (tried alone, picture checked). Also its `frame(maxWidth:)` came before `.fixedSize()`, which cancelled the cap. It is now `PillTag`, the shared text pill.
3. Fill and outline were two separate shapes (`.background(in:)` and `.overlay`) in every component: same radius in code, but nothing forced it. Now one shape.
Changed to the shared helper: `Badge`, `RolePillView`, `KeyHint`, `TransportButtonStyle`, `HeaderButtonStyle`, the mode switcher, the media dock layer switch and its button style, the toolbar timers (box and button), the Clear control and its popup, the transport state badge, the Screens status pill, the inspector's AUD/BRD pills and Preview chip, the transport chrome. Cards, thumbnails, selection rings and text fields (many `RoundedRectangle().stroke` uses in container views that do not clip) were left as they are.
Pictures (rows: before dark, after dark, before light, after light; 2x): `AI/reports/UI-004-mode-switch.png`, `UI-004-role-pills.png`, `UI-004-media-controller.png`. In the "before" rows the ends are flat or notched; in the "after" rows every outline is a complete round shape. The media controller crops differ a little in layout between rows because the clip was at a different time and layout.

## Item 3: slide editor drag: done in the model, not tried with a real pointer. Causes found

Measured in the running Debug build (hook scenario, no real pointer) and by the new tests:
1. Every drag event was a full slide write: 60 events caused 61 show changes (`onShowChange`, i.e. publish and preview restore) and a save schedule (new test failing first: `r.showChanges.n → 61 == 1`, stored slide moved mid-drag).
2. The canvas picture is drawn by `ScenePreview`, which restarts a 100 ms wait on every change. During a 1 s drag of 60 events it asked the renderer only 2 times: the picture did not move until the pointer stopped, while the outline moved. That is the lag the owner saw. (The model write itself is cheap: 0.05 ms per event.)
3. Press, click, double click and drag were four gestures on one view (two tap gestures plus the drag), so the drag competed with them and started late or not at all.
Changes: during an open interaction `move` and `resize` only set `SlideEditorModel.dragFrames`; `objects` and `selectedObject` show them (so the canvas box and the inspector follow); `endInteraction` writes once through the existing path and records the single undo step; outside an interaction nothing changed. The canvas is drawn from those frames with `ScenePreview(follow: true)`: no 100 ms wait, and `PreviewRenderer` keeps only the newest request per picture (an older one not started yet is dropped), so there is no growing queue. Result in the hook: 60 canvas renders asked during the 1 s drag (against 2 on the old path), the stored slide unchanged mid-drag, the grid thumbnail unchanged mid-drag, one write and one undo step on release, `show.liveDeck` and `liveIndex` unchanged throughout. One gesture (`DragGesture(minimumDistance: 0)`) now selects on press, starts the drag after `SlideEditing.dragThreshold` (3 pt), and a press without movement is a click; the double click is a simultaneous gesture. The resize square's grab area is 28 pt (`SlideEditing.handleHitSize`). Live is never touched: the dragged object is only in the editor, the presentation changes once on release and Live changes only when the slide is triggered again (existing rule).
Tests (`UI004_DragTests`, 7): nothing written while down (no show change, no stored change, no save after the clock passes), one write and one undo step on release, resize likewise, inactive-slide drag leaves Live unchanged, a move without an interaction still writes at once, a drag that returns to its start writes nothing, threshold and hit size. The existing drag tests in `SlideEditorModelTests` pass unchanged.
Pictures: `UI-004-editor-drag-mid.png` (mid-drag: the rectangle is drawn by the compositor at the dragged place, the inspector reads Left 24, the thumbnail of slide 4 still shows the old place), `UI-004-editor-drag-after.png`.
Not verified: no real mouse or trackpad was used (see KI-111): the 3 pt threshold feel, press-to-select, double click next to the new gesture, the 28 pt grab area and how smooth it is at the hand's speed.

## Other pictures
`UI-004-about-dark.png`, `UI-004-about-light.png`: the About window opened through the real Help menu item. Contents: the icon, name, paragraph, the version line of that Debug build (`commit ...-dirty` because the tree had my changes), Copy, the developer line and address, the project link, the licence, the notices. No other name, address or path.

## Order of work and honesty about tests-first
- Seen failing first: the rename tests (names, remote page, the old-spelling scan, unfinished folder), the drag tests (the 61 show changes and the unchanged-slide expectations).
- Not seen failing individually: `UI004_BuildInfoTests`, `UI004_AboutInfoTests`, `UI004_AboutKeyGateTests` and `UI004_LibraryLocationTests` (a characterisation of an existing path), because I wrote the small pure type with its test in one step. They assert the format, fallbacks and gates and pass.
- No wall-clock assertions in any test. The millisecond figures above are logged by the hook, not asserted.

## Deviations and things to know
- Build number is the git commit count, written into the built plist (brief: "a build number"). The tracked `project.yml` still has `CURRENT_PROJECT_VERSION: "1"` for builds without git.
- Added beyond the brief: the About window's key gate, the appearance following, `PillTag`, `LibraryLocation`, the follow mode in `PreviewRenderer`, `requestCount` (Debug only) for the hook's render count.
- The check, my pictures and the package run happened while other commits landed (HEAD moved from 11ef7d6 to ae4b89d and 4d9431b); I changed no git state. The stamped commits in my pictures and in the packaged app say `-dirty`.
- Leftovers outside the repository's tracked files: `dist/WorshipFlow-hardware-test-20261121-4d9431b/` and `.zip` (git-ignored; the old `dist/WORSHIPFLOW-...zip` is still there), `~/Library/Developer/Xcode/DerivedData/WORSHIPFLOW-package` (rebuilt by the package script) and a stale `WORSHIPFLOW.app.dSYM` in it. My scratch app, library and pictures are in the session scratchpad. No process of mine is running and no timer is left.
- `wf-bible-import --help` shows the library path as `.../Application Support/WorshipFlow/Library.sqlite` (it works because of case-insensitivity): not changed.
- Not changed although the brief lists "every label": CLAUDE.md, AGENTS.md, `CONTRIBUTING.md`, `docs/MASTER-SPEC.md`, feature specs and the research guide still write the capitalised name (not in the brief's list of prose to change; `docs/UI`, `docs/adr` and `AI/` history must not change).
