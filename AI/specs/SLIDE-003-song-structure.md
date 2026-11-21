# Brief: SLIDE-003 and SLIDE-004 — song sections, arrangements and reflow

Read first: `CLAUDE.md`, `AGENTS.md`, `docs/adr/0004-persistence.md`, `docs/19-data-dictionary.md`, `AI/reports/SYS-001-report.md`, the existing `Sources/Persistence` and `Sources/Domain/LibraryModels.swift`, and the three coordinator test files `DomainTests/ReflowTests.swift`, `DomainTests/ArrangementTests.swift`, `PersistenceTests/SongStructureStoreTests.swift`.

Catalogue: PRES-04 (arrangements), PRES-05 (reflow), PRES-10 (second language pairing).

## Goal

Make those tests pass: a pure reflow rule set, section and arrangement models with a resolver, and schema v2 with the store operations.

## Do not modify

- Coordinator-owned tests. Add your own test files freely.
- Migration `v1` in `Schema.swift`. Schema changes go in a new migration named `v2`.
- `Package.swift`, `project.yml`, `CLAUDE.md`, `docs/MASTER-SPEC.md`, `docs/adr/`, `Sources/OutputEngine`, `Sources/RenderEngine`, `Sources/MediaEngine`, `App/`, and the Domain files `ShowState.swift`, `SceneComposer.swift`, `OutputRouting.swift`, `Scene.swift`.

## What to build

**`Domain`** (Foundation only):
- `Reflow` with `sections(from:)`, `slides(from:maxLines:)`, `moveBreak(in:after:by:)`, `contents(primary:secondary:maxLines:)`, `text(from:language:)`, and the value types `ReflowSection`, `ReflowSlide`, `ReflowResult`, `ReflowLanguage`. Behaviour is fixed by the tests: label recognition is a whole-line match, case-insensitive, with an optional number and optional trailing colon, for the English and Vietnamese words listed in the tests; the stored name drops the colon and keeps the user's spelling.
- `SlideGroup`, `Arrangement`, `ArrangementResolver.order(slides:groups:arrangement:)`.
- `Slide` gains `groupID: UUID?` (default nil, so existing call sites compile). `PlaylistItem` gains `arrangementID: UUID?` (default nil).

**`Persistence`** (migration `v2`):
- Tables `slideGroup`, `arrangement`, `arrangementItem`; `slide.groupID` and `playlistItem.arrangementID` nullable with `ON DELETE SET NULL`.
- `groups(of:)`, `replaceContent(of:with:)` (one transaction: replaces all slides, keeps groups whose name matches an existing group in order of first appearance, creates new ones, deletes groups no longer present, strips deleted groups from arrangements, refreshes the search index), `createArrangement(for:name:groupIDs:)`, `arrangements(of:)`, `updateArrangement(id:name:groupIDs:)`, `deleteArrangement(id:)`, `resolvedSlides(of:arrangementID:)`, `setArrangement(_:forPlaylistItem:)`, `slides(forPlaylistItem:)`.
- Section names are not indexed for search; only titles and lyric text are.

**Docs**: add the v2 tables and columns to `docs/19-data-dictionary.md`.

## Constraints

Swift 6 language mode, strict concurrency, no force unwraps, no `@unchecked Sendable` without a justification. Do not commit or change git state.

## Done means

1. `swift test --package-path Packages/WorshipFlowKit` passes in full. Paste the summary line.
2. `./scripts/check.sh` exits 0.
3. `AI/reports/SLIDE-003-report.md` records files, decisions, commands run with exit status, and everything not verified.
