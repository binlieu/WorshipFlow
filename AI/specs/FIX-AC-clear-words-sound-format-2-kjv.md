# FIX-AC: a video object is heard under Clear words, the package format is version 2, and the test build carries the KJV

Feature IDs: MEDIA (KI-286), LIB (KI-285), LIB-004d (bundled translation). Model: Sonnet. One agent in the main folder; nothing else is in flight. No migration: if an item seems to need a schema change, stop that item and report.

Decided by the owner on 2026-11-27:

1. "should a video object's sound keep playing under Clear words?" Answer: "yes, keep it playing".
2. "should the package format version go to 2?" Answer: "yes".
3. "Which English Bible to bundle." Answer: "KJV".

Read `AI/reports/FIX-Y-report.md` (items 2 and 7: what Clear does with video-object players today, and what an older build does with a package that carries a video object), `AI/reports/FIX-X-report.md`, and the LIB-004b and LIB-004c briefs and reports for the translation file format, the store's import and the translations view. Confirm what the code does before changing it.

## Required behaviour, each test-first (write the test, run it on the old code, record that it fails for the stated reason, then change the code)

### A. KI-286: Clear words does not silence a video object

- Under Clear words a video object's player keeps playing and is heard, exactly as the slide's own background layer is under the same Clear. Its picture follows today's rule for Clear words (do not change what is drawn).
- Clear all, Blackout and Stop keep today's behaviour (silent; Stop closes). A muted object stays muted. `--silent-audio` still silences everything. Un-clearing does not restart the player or jump its position.
- Tests at the model level with the existing fakes: the audible state of a video object after Clear words, after Clear all, after Blackout, after un-clear. No wall-clock assertions.
- If an existing FIX-Y test pins "silenced under Clear words", do not edit it: list the test and the exact assertion in the report, and the coordinator decides (the owner asked for this change, so expect the answer to be "replace that one assertion"; still stop and list it, and finish the other items).

### B. KI-285: package format version 2

- An export writes format version 2. Import reads version 1 and version 2. A version above 2 is refused with the existing "made by a newer version" message, not "damaged".
- Find out and state what build 221 and older do with a version 2 package (read the import code at the last commit that wrote version 1): "newer" or "damaged". Do not try to make old builds behave better; just state it.
- A version 1 package still imports exactly as before (keep a version 1 fixture test). Hostile input stays bounded; nothing in the import result's wording about kept and dropped items changes.
- This is file recovery logic: tests first, and do not weaken any existing import test. A test that pins the literal `1` as the written version is data: list it, change the number only, and say so.
- Data-dictionary text for the version goes in the report (do not edit `docs/`).

### C. LIB-004d: the packaged build carries the King James Version

Rule that stays: no Bible text in the repository. `Bibles/` is git-ignored and holds translation files on the owner's Mac only; one of them (NKJV) is under copyright and must never reach a build.

- `scripts/package-test-build.sh`: if `Bibles/KJV.json` exists, copy it into the app at `Contents/Resources/Bibles/KJV.json` before signing. An allow-list by exact file name with one entry, `KJV.json`: nothing else from `Bibles/` is ever copied. After signing, the script lists `Contents/Resources/Bibles/` and fails if it holds anything other than `KJV.json`. If the file is absent the build is made without it and the script prints one line saying so. `scripts/check.sh` and the Debug and Release builds must not depend on `Bibles/`.
- The app: when a bundled translation file is present and the library has no translation with that id, it is imported through the existing store import (the same validation as a file the operator picks), off the main thread, after the window is up. It must not delay launch, block the Show, or show an alert. A failure is shown where translations are listed, with the existing wording style.
- Imported once: if the operator removes the KJV it is not put back at the next launch. Keep the "already offered" fact without a migration (an existing settings place in the library, or a marker file beside the database: choose the smaller and say which). If neither is possible without a migration, stop and report.
- An existing library that already has a translation with id `KJV` is left exactly as it is.
- The translations view shows the file's own copyright and licence text, as it does for any translation (check; do not add text of your own about rights).
- Tests with a small synthetic translation file made in the test (a few invented verses; no Bible text in the repository): first launch imports; second launch does not; removed is not put back; a library that has the id is untouched; a damaged bundled file reports and does not crash; no bundled file does nothing. Test the script's allow-list with a temporary folder holding `KJV.json` and another file if the script can be exercised without a full build; otherwise test the copying function you factor out, or say "not exercised" and why.
- Do not read, print or copy the contents of any file in `Bibles/` into a test, a report, a log or the repository. Do not open `Bibles/NKJV.json` at all.

## Rules

- New tests in `FIXAC_*.swift`. Do not edit or weaken existing tests except as the items above say (stop and list).
- Out of scope, not to be touched: `OutputEngine/`, the SDI adapter, the scheduler, Fill/Key, `RenderEngine/`.
- Smallest change. No new abstraction. No force unwraps. Swift 6 strict concurrency clean in Debug and Release. Nothing ticks while idle. Editing never changes Live. Accessibility labels and keyboard behaviour kept.
- The owner's own copy of the app is running (build 221): do not quit or disturb it; stop only process ids you started; never `pkill` by name. Never open the owner's real library, never touch `/Applications/WorshipFlow.app` or `~/Library/Application Support/WORSHIPFLOW`; temporary `--library` only, with `--silent-audio`. Nothing that makes sound. No soak. No display or system settings. No full computer control. No advisor tool. Do not run `scripts/package-test-build.sh` for real (the coordinator packages); a dry exercise of the copy step in a temporary folder is fine.
- If any test shows garbage values, run `swift package clean` in `Packages/WorshipFlowKit` first (KI-271).
- Do not edit `docs/`, `docs/UI`, `docs/adr`, `AI/specs`, `Vendor/`, `dist/`, `.claude/`, `Bibles/`. Write `AI/reports/FIX-AC-report.md`: per item what the code did, the failing test and why it failed, the change, what is not verified; then change-log text, known-issues text (unnumbered), data-dictionary text, hands-on entries.
- No git state changes: the coordinator commits. The repository is public: no personal strings in any file.
- Keep one scratch build folder and delete it and any DerivedData build `.app` when done. Finish with `./scripts/check.sh` exit 0, reading the exit status itself (timing-flaky `MIDIRouterTests`, `ToolProcessRunnerTests`, `ScriptureLibraryTests`, `MediaAvailabilityTests`: re-run once, report both). Do not leave monitors or wait loops running when you report.
- If the same failure shows twice, stop that item and write down what was tried. If you are running out of room, stop at an item boundary with the check passing and say what is done.
