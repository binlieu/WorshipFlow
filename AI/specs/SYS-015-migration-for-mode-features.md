# SYS-015: one migration (v15) for the stored fields the mode features need

Feature IDs: SYS, SLIDE, MEDIA, STAGE, OUT, CUE. Model: Sonnet. One agent in the main folder; this task alone owns the migration and the public persistence and domain types it touches. The features that use the fields are built afterwards by other agents (UI-007), so this slice ends with the storage, the domain types, the rendering defaults and the store methods in place, tested, and **no change in behaviour or rendering for any existing library**.

Source: the "Needs a migration" lists in `AI/reports/UI-006c-report.md`, `UI-006d`, `UI-006e`, `UI-006f`, `UI-006g` (collected in `docs/15-agent-handoff.md`). Read all five and the data dictionary `docs/19-data-dictionary.md` first.

## What v15 adds (all additive; nothing dropped, renamed or rewritten)

1. **Edit, in the `SlideObject` JSON** (no column): `TextObject.fit` (none or shrinkToFit, default none), `TextObject.backgroundFill` (optional colour), `SlideObject.name` (optional), `SlideObject.isHidden` (default false), `SlideObject.isLocked` (default false), and a new content case `video(VideoObject { mediaID, loops, muted })`. Decoding old JSON gives the defaults; a build that does not know `video` must not lose the object when it re-saves (say how you guarantee that, or state plainly that older builds cannot open a library holding one and add the guard that refuses to downgrade).
2. **Media:** `mediaAsset.markIn REAL NULL`, `mediaAsset.markOut REAL NULL`; table `mediaMarker(id TEXT PK, assetID TEXT NOT NULL REFERENCES mediaAsset(id) ON DELETE CASCADE, time REAL NOT NULL, name TEXT, actions TEXT NOT NULL, sortOrder INTEGER NOT NULL, createdAt, updatedAt)` with an index on `assetID`. This one table serves both Media's markers and Cues' playback markers (`actions` is the versioned JSON `{version, actions}` the Cues report asks for; do not create a second table). Collections stay in app state (no table).
3. **Stage:** a stored section name so a Section element has something true to show: decide between carrying it on the slide content at compose time from the existing section data (preferred if the slide's group already gives a name: then **no stored field** is needed and you only extend what the show state carries to the stage composer) and a stored `sectionName`. Say which and why.
4. **Screens:** on `ScreenProfile`: a separate key-destination label (`connectedToKey` or a per-destination note with fill and key), a per-destination operator-typed signal chain (`[ChainNode { kind: enclosure | converter | other, label }]`), and `screenLookID: UUID?` for a per-screen Look. Where the profile is stored as JSON these are optional keys with defaults; where a column is needed add it.

## Tests first (write them, see them fail for the right reason, then implement; do not weaken them)

- Migration: a v14 library fixture (built by `prefix(14)` as earlier migration tests do) migrates to v15; every existing row is unchanged by value; running the migrator twice is a no-op; a fresh library reaches v15 by the same path; `PRAGMA foreign_key_check` is clean; deleting a media asset removes its markers.
- Rendering: for a library with no new values, scene digests for audience, stage and broadcast (Fill and Key) are byte-identical before and after (use the existing digest test pattern, `FIXQ_PublishedScenesDigestTests`).
- Round trips: each new field stores, reloads, survives duplicate, re-flow where the existing fields do, undo where the existing fields do, and program export and import (the package reader validates each new numeric and string field: finite, in range, bounded length, per FIX-T's rules in `ProgramReader.validate`; hostile-input tests).
- Decoding: old JSON without the keys decodes to the defaults; unknown future keys are preserved or refused as item 1 decides.
- Store methods the feature agents will need, each tested: set and clear mark in and out (in <= out, both within the clip's length, nil allowed); add, move, rename, delete and list markers in time order; set a slide object's name, hidden and locked flags; set a screen's key label, chain and Look.

## Rules

- New tests in `SYS015_*.swift`. Do not edit existing tests. No wall-clock assertions.
- Hidden objects and a `video` object are **decoded and stored only** in this slice: the compositor skips a hidden object (that is the one rendering rule you add, with a test) and draws nothing for `video` yet (it is the feature agent's work); say so in the report.
- A backup is taken before the migration runs on an existing library if the app already does that for earlier versions; if it does not, add it for v15 (copy of the database file set beside it, named with the old version and date, once) and test it. Never touch the owner's real library: use scratch libraries only.
- Update `docs/19-data-dictionary.md`, `docs/17-change-log.md`, `docs/16-known-issues.md` (continue from the highest KI number) and write an ADR in `docs/adr/` only if item 1's downgrade decision or item 3's choice is architectural (number it after the highest existing ADR; this is the one exception to "do not edit docs/adr": add, never change an accepted one).
- Do not edit `docs/UI`, `AI/specs`, `Vendor/`, `dist/`, `.claude/`. No git state changes. No advisor tool. No full computer control. The repository is public: no personal strings.
- Keep one scratch build folder and delete it when done. Delete any build `.app` you leave in Xcode's DerivedData so only `/Applications/WorshipFlow.app` is found by `mdfind "kMDItemCFBundleIdentifier == 'org.worshipflow.app'"`; never touch `/Applications/WorshipFlow.app`.
- Run each check in the foreground; send one final message. Finish with `./scripts/check.sh` twice. Report to `AI/reports/SYS-015-report.md`, including the exact public API the feature agents should call for each field.
