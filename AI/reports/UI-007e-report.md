# UI-007e report: Stage Section elements

Feature ID UI-007e. Model: Sonnet, no advisor, no Codex. Levels: **Implemented** and **Unit Tested**; also exercised through the debug scenario (model path, no window input). Not Simulated hardware, not Hardware Verified, not Live-Service Verified.

## Built

**Section element and Next section element.** Two new `StageElement.Kind` cases, `.sectionName` (the live slide's section, from `ShowState.liveSectionName`) and `.nextSectionName` (`nextSectionName`, drawn with a "NEXT" caption only when it differs from the live section, so it appears as a heads-up and is quiet while the song stays in one section). Both are drawn only by `StageComposer`, so a section name cannot reach an audience or broadcast scene (the audience and broadcast composers never read them; tested for both roles, and the built-in Standard layout has neither element). Nothing is drawn when stopped, when the slide is in no section, or when the element is hidden (the UI-006e eye works on them). The section is kept while the words are cleared, like the place itself. Neither ticks (`needsPerSecondRefresh` false). Because the compositor is shared, Edit's Stage preview (`StageEditing.sampleScene`, which now carries sample section names "Verse 1" and "Chorus") shows them without further work.
- Preset position: the design's Section element place (right edge, 60% down, 22% wide): section name 74/60/22/7 in the design's blue, next section 74/68/22/12 muted with its caption. `FreeSpace` still moves a new element off existing boxes.
- Add: a "Section" menu in the Stage bar, left of Notes (Section, Next section). The design's own buttons to its right keep their places. Both appear in the element list with the eye, canvas box, inspector heading ("The live slide's section", "The next slide's section, when it changes") and a symbol.
- `NewStageElement.allCases` is deliberately still the six plain-button elements (an existing test enumerates it); the two new cases are in `NewStageElement.sectionElements`.
- Tests: `UI007e_StageSectionTests` (11): live section, no section, no section list, stopped, cleared, next only when different, hidden, never on audience or broadcast, preset positions and no tick, codable round trip and an old layout unchanged, persisted in the operator's layout and refused for the built-in one, sample scene.
- Debug scenario (`UI_SNAPSHOT_STAGE_FEATURES`) logged: stage layers `... "Verse 1", "NEXT", "Chorus"`; audience `["One"]`; broadcast `["One"]`.

## Stage rectangle table (UI-007e run, dark, 1440 x 900, `scripts/compare-rects.py` with `design-map-stage.json`)

| Region | Mapped | Within 1 pt |
|---|---|---|
| toolbar | 23 | 16 |
| sidebar | 17 | 15 |
| centre | 20 | 18 |
| inspector | 32 | 7 |
| total | 92 | 56 |

Map extended by 10 entries (UI-006e's rows): `st.insp.second.label/.swatch/.hex` (all exactly on the design, 0.0), `st.insp.autofit` (right edge skipped: the app's rectangle is the whole checkbox control, the design's the 14 pt box; font 12 vs 13 is open), `st.insp.el.0..5.eye` (skip T, R, B: the app's is the 26 pt hit target, the design's the 12 pt icon). My Section menu is not in the design and is left of the mapped buttons, so none moved.

**Found and partly fixed:** the inspector was 22 of 22 at UI-005e and is now 7 of 32. The rows Shows, Size, Weight, the headings and the element list sit 4 pt left of the design (content 8 pt wider than the column). UI-006e did not re-run the rectangles. One cause found and fixed in my file: the hex fields (Colour, 2nd lang.) had a 175 pt ideal width against the design's 167 (`StageInspector.swift`, `HexField` width 167); the Colour and 2nd lang. rows are now exact. The rest of the 8 pt is not found (something in the Size, Shows or Weight rows or a section is wider than the 275 pt content). Open, for the next Stage pass.

## Not built

- Resize cursors, Video element: not in this slice's list. The "then Verse 2" second line of the design's Section is the Next section element (two elements instead of one two-line element, so each can be hidden, moved and styled).
- KI-237 stays: the section name is as old as the preview deck (a section renamed or moved while a song is live shows the old name until the deck is rebuilt).
- Layout JSON: a layout holding a Section element cannot be read by a build older than this one; v15 already refuses older builds, so no new guard (ADR-0009 rule: new cases ship with a migration; here the stored layout is a JSON `definition`, and an unreadable layout falls back as any unreadable layout does).

## Shared-file lines

- `Packages/WorshipFlowKit/Sources/Domain/StageLayout.swift` (shared domain type, additive): two `Kind` cases, their `ticks` entry, and two composer cases (about 14 lines).
- No change to `ShowState`, `WorkspaceModel`, `ShowDeck`, the key monitor, the Edit preview, or any Show view.

Files: `Domain/StageLayout.swift`, `OperatorCore/StageEditing.swift` (new template cases, presets, sample lines), `App/Sources/StageEditorView.swift` (names, symbol, Section menu), `StageInspector.swift` (heading text, hex width), `StageFeaturesSnapshot.swift` (scenario), `scripts/design-map-stage.json`, test file above.

## Docs entries for the coordinator

Change log: "UI-007e: Stage: Section and Next section elements (the live slide's section, and the next slide's when it changes), added from a Section menu in the Stage bar, shown on stage screens only; the Stage rectangle map covers UI-006e's rows; hex fields 167 pt wide."
Known issues (unnumbered): "Stage inspector rows Shows, Size, Weight sit 4 pt left of the design since UI-006e (cause not found, 8 pt too wide); Auto-fit label 12 pt against the design's 13; a Section element's name is as old as the deck (KI-237); Next section draws nothing while the next slide is in the same section (by design)."
Hands-on checklist: "Stage: your own layout, Section menu, add Section and Next section; with a song live (sections set), the stage screen shows the section name, and NEXT plus the following section on the last slide before a change; hide with the eye; audience and broadcast screens never show them."
Feature spec updates: STAGE layout element kinds `sectionName`, `nextSectionName`.

## Checks

`WF_DERIVED_DATA=<scratch> ./scripts/check.sh` exit 0: 3269 tests in 520 suites passed (base about 3258, +11), Debug and Release builds pass. An earlier full run failed only on timing tests under load (`MIDIRouterTests`, `ToolProcessRunnerTests`, `ScriptureLibraryTests`, `ImageCacheTests`); re-run, then those four suites alone (41 tests): passed. The run before that also failed one existing test (`StageModelTests.addingAndRemovingElementsOfEveryKind`, enumerates `NewStageElement.allCases`), fixed by keeping `allCases` at the six.

## Not verified

Real mouse or keyboard use of the Section menu (the screen may be locked; only the scenario and model tests ran); VoiceOver; a real stage screen or a live service; light mode of the new menu; the cause of the inspector 4 pt shift.
