# UI-004: version and About, rounded borders, dragging in the slide editor

Feature ID: UI-004. Model: Sonnet. Starts after MEDIA-010 is committed, because it touches the media controller and toolbar files that task owns.

Source: the owner's hands-on feedback of 2026-11-21, items 1, 2 and 4 of ten. The owner's words are quoted.

## Items

1. **"add built version number to easy manage at help popup. also in the help setup have something to introduce the application and the developer Simon Lieu me@simonlieu.com".**
   - Every build carries a version the owner can read out: the marketing version, a build number, the short git commit and the build date, set at build time by `scripts/package-test-build.sh` and by the Xcode build (a build phase or generated file that falls back to "development build" when git is not available; the check must still pass in a clean clone and never write the commit into a tracked file).
   - A native About window (the app menu's "About WORSHIPFLOW" and Help, "About and version…"): the app icon and name, one short paragraph saying what the app is, the version line above with a Copy button, "Developed by Simon Lieu" with `me@simonlieu.com` as a mail link, the licence (Apache 2.0) and a link to the project page `https://github.com/binlieu/WorshipFlow`, and the third-party notices already in `NOTICE` and the README. No other name, address or path appears.
   - The same version line appears in the Hardware Test report's environment section and in `summary.txt`, so a tester's report says which build made it.
2. **"fix the rounded border of these attach images".** Three pictures are beside this brief: `UI-004-feedback-mode-switch.png` (the mode switcher in the toolbar), `UI-004-feedback-role-pills.png` (the AUD, STG, BRD pills), `UI-004-feedback-media-controller.png` (the AUD pill at the right end of the media controller). In each the rounded outline is drawn wrongly: the outer container's border is clipped or flattened at its ends, the corner radius of the outline and of the fill behind it do not match, and the last pill is cut off by its container. Find the cause in each (a stroke drawn on the bounds and then clipped, a background and overlay with different radii, a frame too small for the stroke) and fix it in the shared component where one exists, so every pill and segmented control drawn from the tokens is right: the stroke inset by half its width, one radius for fill and stroke, nothing clipped at 1x and 2x, in dark and light appearance. Check the other places that use the same components and list what you changed.
3. **"Click and drag in the slide edit tab not really responsive".** In the slide editor, dragging a text box or object lags behind the pointer or does not start reliably. Measure before changing: find what runs per drag event (a save, a full re-render, a thumbnail rebuild, a re-layout of the whole deck). Required: the object follows the pointer within the same frame, the drag starts on the first movement past a small threshold, selection handles are easy to grab, the model is written once at the end of the drag as one undo step, expensive work (thumbnails, saving) waits until the drag ends, and Live is never touched by a drag in the editor. Say in the report what the cause was.

## Tests

Test-first where there is logic: the version line's format and its fallback; the drag producing exactly one model write and one undo step at the end and none during; a drag on an inactive slide leaving Live unchanged. New test files `UI004_*.swift`; do not edit existing tests. Rounded borders are checked by pictures: before and after crops of the three controls at 2x in dark and light, saved to `AI/reports/UI-004-*.png`. The drag is to be exercised in the running app as far as the debug hook allows; say plainly what was not done with a real pointer.

## Rules

- No git state changes. No advisor tool. Do not request full computer control.
- Do not edit `docs/UI`, `docs/adr`, `AI/specs`, the vendored `sdk/` folder, or existing test files. No migration.
- Never open the owner's real library under Application Support. If you launch the app: your own uniquely named scratch folder, a temporary `--library`, `--silent-audio`, stop only processes you started, nothing left in the home folder.
- The repository is public: apart from the developer's name and e-mail address given in item 1, no user names, home paths, computer names or e-mail addresses in any file or picture.
- Docs: `docs/17-change-log.md`, `docs/16-known-issues.md`, `docs/hands-on-checklist.md`, `docs/hardware-test-guide.md` (where the version appears in the report).
- Finish with `./scripts/check.sh`; report its exit status and test count truthfully. Leave no wait timers or background work running.
- Report to `AI/reports/UI-004-report.md`.

## Added 2026-11-21: the name is written "WorshipFlow"

The owner asked: "can you rename the WORSHIPFLOW to WorshipFlow?" Do this as the first item of this task, on its own, and run the check before going on.

- **What the operator and a tester see becomes "WorshipFlow":** the app bundle (`WorshipFlow.app`), the name in the menu bar, Dock and About window, window titles, every label, message, notice and help text in the app, the Hardware Test window and its report (`summary.txt`, the zip and folder names: `WorshipFlow-hardware-test.zip`, `-unfinished`), the remote control page, the default MIDI port names, the package script's output names (`dist/WorshipFlow-hardware-test-<date>-<commit>.zip`) and its tester guide, and the prose in `README.md`, `docs/hardware-test-guide.md` and `docs/hands-on-checklist.md`.
- **What must not change, because data or tooling depends on it:** the bundle identifier `org.worshipflow.app`; the library's location `~/Library/Application Support/WORSHIPFLOW/` (an existing library must open after the rename with no move; add a test that the library path is unchanged); preference keys and any stored identifier; the Xcode project and scheme names (`WORSHIPFLOW.xcodeproj`, scheme `WORSHIPFLOW`), the DerivedData folder names the scripts use, `scripts/check.sh` commands, the package name `WorshipFlowKit`; `docs/UI`, `docs/adr`, `AI/` history and older change-log entries.
- A report written by an older build must still be recognised: wherever the app looks for an unfinished hardware-test folder or reads its own files by name, accept both spellings.
- The file system is case-insensitive: `WORSHIPFLOW.app` and `WorshipFlow.app` are the same name to Finder. The package script must produce the new spelling in a fresh folder; say in the report how the coordinator should replace the installed copy so its name changes on disk.
- Tests that assert the old spelling in user-visible text are the one exception to "do not edit existing tests": change only the expected string, list each one in the report.
- Record the decision and the list of things left unchanged in `docs/16-known-issues.md` or the change log.
