# LIB-004c report: scripture in the app

Verification: Implemented; Unit Tested (58 new tests); seen once in a Debug build through the `--ui-snapshots` hook with invented text and real key events. Not Hardware Verified, not Live-Service Verified. No advisor consulted. No git state changed.

## Items

1. Done. `ScriptureModel` (OperatorCore, main actor, injected `ScriptureStore`, no SwiftUI): translations, first and second choice, typed reference, problem or passage, slides. Reads are awaited off the main actor.
2. Done. Sidebar row "Scripture" under Libraries and Command-J (Show menu; recorded in `CuesMode.keys`). Book suggestions as chips; Return shows the passage and moves focus to the grid.
3. Done. Passage in the centre pane as the song thumbnails, reference as the last line of each slide's words; splitting by `VerseSlides` with limits from the audience theme (`ScriptureSlideLimits`). Select = Preview only; Go Live, Next, Previous through `CueModel`'s command path; Next at the end stays.
4. Done. Two translations in the bilingual layout; notes for chapters numbered differently (existing `numberingNotes`); a verse missing on one side shows the other alone.
5. Done. Add to playlist (kind `scripture` in existing `kind`/`payload` columns, reference and codes only, survives reopen; no migration v11 needed) and Save as presentation (kind scripture, opened for editing).
6. Done. Search tab on `ScriptureStore.search`; Vietnamese without diacritics tested; a result opens its verse.
7. Done, with one limit. Translations screen: list (name, language, verse count, copyright line), Import (open panel, progress, plain result, ask before replacing), Remove (asks first), empty state offering Import. Import takes the translation `.json`; a USFM folder still goes through `wf-bible-import` (the store's importer takes `TranslationFile` only).
8. Done, no new composition code. Audience, stage (current and next) and broadcast (lower third) use the existing composers. The reference is part of the words so the lower third gets it (slide objects are left out of keyed screens).

## Tests

Written first; the first build failed to compile for the missing types (`ScriptureItemSpec`, `PlaylistItemKind.scripture`, `addPlaylistScripture`; the OperatorCore ones were not reached yet), as in CUE-002b. New files: `OperatorCoreTests/LIB004c_{Fixtures,RulesTests,PassageTests,ShowTests,KeepTests,SearchAndTranslationsTests}.swift`, `PersistenceTests/LIB004c_ScripturePlaylistItemTests.swift`. All text is invented. Covered: English and Vietnamese reference to the same passage; unknown book, out-of-range verse, partly bad reference, verse the translation lacks: plain problem and no slides; long passage split with every verse once in order and parts re-joining to the verse; two translations and the Exodus 12 numbering difference; Preview-only selection; Go Live then Next/Previous through the cue path; stay at the end; playlist item after reopening a file library; translation removed under a playlist item (item stays, "not installed", Next into it stops with a message); save as presentation; search; import, replace, bad file; migration list `prefix(10)` and count 10 (no v11). No wall-clock assertions.

- `./scripts/check.sh` (with `WF_DERIVED_DATA` in a scratch folder): exit 0, `Test run with 2184 tests in 333 suites passed after 61.293 seconds` (baseline 2126). One earlier filtered run: 58 LIB004c tests passed; one failed first (the field text was overwritten after a search result) and was fixed.

## Seen in the running app

Copy of the Debug app under a throw-away bundle id, temporary `--library`, `--silent-audio`, loopback remote, window outputs, `UI_SNAPSHOT_SCRIPTURE=1`. From the log: Command-J through the real menu opened the view (nothing installed); two invented files imported through the model; "John 3:16-18" typed with real key events and Return gave 5 slides in Preview, nothing live; Return again went live at slide 0; Right arrow went to slide 1 ("slide 2 of 5"); with a second translation 3:18 showed one side only; Add to playlist added the item; search "binh an" found "Giăng 3:16". Pictures (`AI/reports/`): `LIB-004c-empty.png` (empty state with Import and Translations), `-translations.png` (list with name, language, verse count, copyright line, Remove, import result), `-passage.png` (reference view, 5 thumbnails each ending in its reference, Preview monitor showing slide 1), `-two-translations.png` (both languages per slide, note that the second translation lacks 3:18). No personal strings (scanned text and PNG strings). No process left running; the owner's library was not opened.

## Not verified

Mouse clicks, drag, the open panel, the remove and replace dialogs, light appearance, VoiceOver, minimum window size; a scripture playlist item restored at launch (model level only); stage and broadcast screens with a passage (composers unchanged, not looked at); real translations (only invented text used); long-run behaviour.

## Deviations and decisions

- No migration (the existing playlist item columns suffice); the migration test says so.
- Engine changes beyond the brief, additive: `ScriptureLibrary.lookup(ranges:)` (the typed lookup now shares its builder), public initialisers for `ScriptureSlide` and `ParseOutcome`. `OperatorCore` now depends on `ScriptureEngine` and `ScriptureStore` (Package.swift, project.yml). `PlaylistItemKind` gained `.scripture`; `LibraryStore.addPlaylistScripture`.
- "Use the Versification mapping": the engine pairs by number and reports differing chapters; no content alignment. A verse only the second translation has is not shown (KI-090).
- A bad part of a multi-part reference shows nothing rather than the good part.
- Fixed a Preview monitor gap: it read only `workspace.slides`, so a passage showed blank there (`ShowInspector`).
- Docs: feature spec, change log, data dictionary note, KI-090 to KI-092, hands-on checklist, status and handoff lines.
- `WORSHIPFLOW.xcodeproj/project.pbxproj` regenerated by xcodegen.
