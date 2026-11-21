# SLIDE-003 / SLIDE-004 report: song sections, arrangements, reflow

## Files
Created (Domain): `Packages/WorshipFlowKit/Sources/Domain/Reflow.swift`, `.../SlideGroups.swift` (SlideGroup, Arrangement, ArrangementResolver).
Created (Persistence): `.../Sources/Persistence/LibraryStore+Structure.swift`.
Created (tests): `Tests/DomainTests/ReflowEdgeTests.swift`, `Tests/PersistenceTests/SongStructureExtraTests.swift`.
Changed: `Domain/LibraryModels.swift` (Slide.groupID, PlaylistItem.arrangementID), `Persistence/Schema.swift` (migration v2 added; v1 untouched), `Records.swift` (SlideRecord.groupID), `StoreError.swift` (new case `invalidReference`), `LibraryStore+Content.swift`, `LibraryStore+Playlists.swift`, `docs/19-data-dictionary.md`.
Coordinator tests were not modified.

## Decisions
- Labels: stem (word list, trailing ASCII digits and colon stripped, lowercased) must be in a fixed set: verse, chorus, pre-chorus (also "pre chorus", "prechorus"), bridge, tag, intro, outro, ending, refrain, interlude, câu, điệp khúc, đoạn, kết. `interlude` is my addition beyond the tests. Only the first line of a block can be a label. A label alone in its block names the next unlabelled block.
- One group per distinct section name, in order of first appearance (brief wording). Two separate "Chorus" blocks share one group. Matching to existing groups is by exact name (case-sensitive).
- `appendSlide` now uses a raw INSERT without `groupID`, because the coordinator test appends slides on a store opened at v1. As a result `playlistItems(of:)` also needs v2 (it selects `arrangementID`); fine for the shipped app, not usable on a store opened with `migratingUpTo: "v1"`.
- `arrangementItem` uses primary key (arrangementID, position); positions are renumbered after a group vanishes.
- New `StoreError.invalidReference` for groups/arrangements that belong to another presentation (tests only require some StoreError).
- `replaceContent` discards speaker notes of replaced slides.
- `Reflow.text(from:language:)` merges consecutive slides with the same name into one section, so two adjacent sections with the same (or both nil) name cannot be told apart on round trip.

## Commands run
- Isolated scratch package (Domain + Persistence + DomainTests + PersistenceTests only, copied to the scratchpad) while another agent's files did not compile: `swift test`, 104 tests passed.
- `swift test --package-path Packages/WorshipFlowKit`: `Test run with 168 tests in 27 suites passed` (exit 0 per output; run before the other agent's last edits).
- `./scripts/check.sh`: first run exit 65 (App/Sources/AppModel.swift label error in the other agent's area), rerun exit 0; its package test step reported `Test run with 180 tests in 29 suites passed`.

## Not verified
- No migration test against a v1 file containing grouped data (impossible by construction) beyond the coordinator's v1-survives test.
- Concurrency of two stores on one file; large-song performance; the other agent's tests are counted in the totals but were not reviewed by me.
- No UI uses these APIs yet.
