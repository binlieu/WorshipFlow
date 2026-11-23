# ADR-0009: Migration v15, new slide-object content, and what an older build does

Status: Accepted, 2026-11-22 (SYS-015).

## Context

The mode features (Edit, Media, Stage, Screens, Cues) need stored fields: object names, hidden and locked flags, text fit and fill, a video object, a clip's marks and markers, a screen's key note, chain and Look, and a stage Section name. They are built by other slices after this one.

## Decisions

1. **One additive migration, v15.** Two nullable columns on `mediaAsset`, one table `mediaMarker` that serves both Media's markers and Cues' playback markers, and optional keys inside JSON that is already stored. It is written against literal column names, so later changes to the Swift types cannot change what it does (migrations v11 and v13 depend on the types of their day; see `AI/reports/REVIEW-3.md`).
2. **A `video` slide-object content case is a one-way step.** An older build cannot decode it, and `SlideObjectsJSON` reads an undecodable column as no objects, so an older build that opened such a library and saved a slide would lose every object on it. The guarantee is therefore not "older builds keep it": **older builds cannot open the library.** The existing newer-library guard (FIX-H item 14) refuses any library whose migration history holds a step the build does not know, and v15 is such a step for every earlier build. No separate downgrade guard was added. **Rule for the future: a new `SlideObject.Content` case ships with a migration**, so the guard fires. Test: `SYS015_MigrationTests.aLibraryAtAStepThisBuildDoesNotKnowIsRefusedAndLeftAsItWas`.
3. **No stored section name.** A slide already points at its section (`slide.groupID`, `slideGroup.name`), so a stored copy could only disagree with it. The name is composed when the preview deck is built (`ArrangementResolver.sectionNames`) and carried in `ShowDeck.sectionNames`; `ShowState.liveSectionName` and `nextSectionName` give the stage composer the live and next section. A song whose slides have no group has no section name, which is true. Cost: the name is as old as the deck (KI-237).
4. **A copy before a migration.** The app took a backup only before an import. A library that already holds data is now copied aside, once, before any migration runs (SQLite backup API, `Backups/Library before migration to <step> (was <step>) <UTC date>.sqlite`). If the copy cannot be written the library is not opened: a worship service that cannot open a library fails visibly and early, which is better than a migration with no way back. A fixture built one step at a time in a test is not copied.
5. **Defaults write no key.** A value at its default is not stored, so a library that uses none of the new fields stores the same bytes as before and the rendered scenes are unchanged (digests pinned).

## Consequences

Rolling back to an older build needs the pre-migration copy (KI-235). The marker `actions` text is the cue engine's versioned JSON, kept as text in Domain so Domain stays independent of the cue engine.
