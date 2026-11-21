# LIB-004c: scripture in the app

Feature ID: LIB-004c (catalogue feature: Scripture). Model: Sonnet. One agent owns all files named here.

## Read first

`CLAUDE.md`, `AGENTS.md`, `docs/adr/0007-*.md` (design adoption: behaviour beats picture), `docs/adr/0008-*.md` (Bible translations: nothing bundled yet, import per church), `docs/features/LIB-004-scripture-engine.md`, `docs/features/LIB-004b-scripture-store-and-importer.md`, `AI/reports/LIB-004-report.md`, `AI/reports/LIB-004b-report.md`, `docs/UI/README.md` and `docs/UI/design-tokens.json`. Look at how CUE-002b wired a package module into the app (`AI/reports/CUE-002b-report.md`) and follow the same shape.

## Goal

An operator can type a reference, see the verses, and put them on the screens, without leaving Show. The engine (`ScriptureEngine`) and the store (`ScriptureStore`) exist and are tested; this slice gives them an interface and a model in `OperatorCore`. There is no design picture for scripture, so use the existing design language (tokens, the sidebar, the centre pane, the inspector tabs) and keep it plain.

## What to build

1. **Model.** A `ScriptureModel` in `OperatorCore` (main actor, injected store, no SwiftUI import) holding: installed translations, the chosen primary and optional second translation, the typed reference and its parse result or a plain-words problem, the verses found, and the slides they would make. All reads off the main thread.
2. **Entry.** A "Scripture" item in the Show sidebar under Libraries, and a keyboard shortcut (choose one that does not clash with the table in `CuesMode`; record it there). The reference field accepts what `ReferenceParser` accepts, English and Vietnamese book names, with suggestions as you type. Return shows the passage.
3. **Passage view in the centre pane.** The verses split into slides by `VerseSlides`/`TextSplitter` using the current theme's limits, drawn as the same slide thumbnails songs use, with the reference on each slide. Selecting a slide puts it in Preview; Go Live, Next and Previous work exactly as for a song, through the same command path. Next past the last slide of a passage does nothing surprising (stays, as at the end of a song).
4. **Two translations.** If a second translation is chosen, each slide carries both, in the same two-language layout bilingual songs use. Where the two translations number verses differently, use the `Versification` mapping; where a verse is missing in one, show the other alone and never invent text.
5. **Keep it.** "Add to playlist" adds the passage as a playlist item that survives relaunch (it stores the reference and translation ids, not a copy of the text, unless the store's existing design says otherwise; if a schema change is needed it is migration v11, additive only, and you are the only task that owns a migration). "Save as presentation" makes an ordinary editable presentation.
6. **Search.** A second field or mode that searches verse text with `ScriptureSearch` (diacritic-insensitive for Vietnamese), results listed with their reference; choosing one opens its passage.
7. **Translations screen.** Lists installed translations with name, language, verse count and the copyright line the file carried; Import… takes a translation file (`TranslationFile` JSON or USFM folder, whatever the store's importer already accepts) through an open panel, shows progress and a plain result; Remove asks first. With none installed the Scripture view says so and offers Import. The app bundles no Bible text and the repository must contain none: tests use the tiny synthetic fixtures already in the test targets, or new invented ones.
8. **Per-screen behaviour.** Audience shows the verse text and reference; Stage shows current and next as for lyrics; Broadcast uses the lower-third composition. No new composition code unless something is truly missing; say so in the report if it is.

## Tests (write them first, see them fail, then implement)

New test target or new files `LIB004c_*.swift`; do not edit existing tests. At least: reference typed in English and Vietnamese resolves to the same passage; an unknown book or out-of-range verse gives a plain problem and no slides; a long passage splits into several slides and every verse appears exactly once in order; two translations with a versification difference pair correctly and a missing verse shows one side only; selecting a scripture slide changes Preview only, never Live; Go Live then Next walks the passage through the shared command path; a passage added to a playlist is there after reopening the library; removing a translation that a playlist item uses leaves the item present with a plain "translation not installed" state and does not crash; search finds a Vietnamese word typed without diacritics; migration (if any) keeps existing rows, asserted with `prefix(n)` on the migration list. No assertions on wall-clock time.

## Rules

- No git state changes. No advisor tool. Do not request full computer control.
- Do not edit `docs/UI`, `docs/adr`, `AI/specs`, the vendored `sdk/` folder, or existing test files.
- Never open or touch the owner's real library under Application Support, and never the local MySQL database. If you launch the app: your own uniquely named scratch folder, a temporary `--library`, `--silent-audio`, stop only processes you started, leave nothing in the home folder.
- The repository is public: no user names, home paths, computer names, e-mail addresses, and no real Bible text beyond a handful of invented or clearly public-domain fixture verses already present.
- Screenshots through the existing debug snapshot hook into `AI/reports/LIB-004c-*.png` (the reference view with a passage, two translations, the translations screen, the empty state).
- Docs change with the code: a feature spec `docs/features/LIB-004c-scripture-interface.md`, `docs/17-change-log.md`, `docs/19-data-dictionary.md` if data changed, `docs/16-known-issues.md` (new entries after KI-089), `docs/hands-on-checklist.md`.
- Finish with `./scripts/check.sh`; report its exit status and test count truthfully.
- Report to `AI/reports/LIB-004c-report.md`: per numbered item done or not, what was exercised in the running app and how, what is not verified, every deviation from this brief.
