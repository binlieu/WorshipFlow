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
