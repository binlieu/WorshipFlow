# FIX-Z report: the capture sample and tests use public-domain hymn lines

Feature ID: SYS (repository hygiene). Sample text only; no behaviour change.

## What changed

- The chorus of the design-capture sample song (a copyrighted 2006 addition) is replaced everywhere by lines 3 to 6 of John Newton's 1779 hymn (public domain), with the same number of lines, and the Vietnamese rendering written for this project. Verse 1, verse 2 and the ending of the sample song are public-domain hymn text and stay.
- Sample titles "10,000 Reasons" became "Holy, Holy, Holy" and "How Great Thou Art" became "It Is Well".
- Files: `App/Sources/UISnapshotDesign.swift`, `UISnapshotRun.swift`, `ComponentsBoard.swift`, `EditDesignCapture.swift` (the text object is now "'Tis grace has brought me\nsafe thus far", same slide and frame), `Packages/WorshipFlowKit/Sources/LooksProbe/main.swift`, and `AI/reports/UI-005-audit-show.md` (only the quotation).

## Tests edited (data only)

Every edit swaps a quoted sample string for its replacement, or renames a sample title. No assertion, count, or expected structure changed beyond the swapped text; the new lines have the same line counts as the old ones.

- `DomainTests/ReflowTests.swift`: hymn fixture and two expectations compare the same text that the fixture contains.
- `OperatorCoreTests/FIXH_LanguageLabelTests.swift`, `UI005b_SmallRowsTests.swift`: fixtures feed language detection; both languages keep the same shape.
- `OperatorCoreTests/UI001_ShellTests.swift`: the headline summary join and the filter title list (library filter by case and accents; the title is only an item in the list).
- `OperatorCoreTests/WorkspaceModelTests.swift`: fixture and the expected live slide text.
- `OutputEngineTests/UI005h_SDIReadbackTests.swift`, `UI005hTests/UI005h_Fixtures.swift`, `UI005h_RenderTests.swift`, `UI005h_SceneCompositionTests.swift`, `FIXJ_StageAttachedRuntimeTests.swift`: the slide text fed to the compositor and the same strings expected back.
- `UI005hTests/UI006e_StageAutoFitRenderTests.swift`: one long line of sample text for the auto-fit case, written with about the same length.

## Other lyrics check

`git grep` of the sample song list in capture code and tests found only: invented placeholder lines ("Line one of ...", "Invented Song One"), a public-domain hymn (Be Thou My Vision), "Great Is Thy Faithfulness" (a title only), and verses 1 and 2 of Amazing Grace (public domain). No other lyric of a song under copyright was found. No Bible text was added. Two older reports (`REVIEW-3.md`, `FIX-T-report.md`) match the search only on the words "flood" in other senses.

## Not done on purpose

The design comparison (`scripts/compare-rects.py`) rectangle counts need re-measuring: line lengths changed, so some text rectangles may move by a point or two. No capture was run and the app was not launched; the coordinator decides when to re-measure. `./scripts/check.sh` was not run (the coordinator runs it after merging).

## Re-recorded expectations (coordinator decision, 2026-11-26)

Rendering code is unchanged: `git diff main --stat -- App Packages/WorshipFlowKit/Sources` lists only `UISnapshotDesign.swift`, `UISnapshotRun.swift`, `EditDesignCapture.swift`, `ComponentsBoard.swift` and `LooksProbe/main.swift` (sample text). The old values passed on the same code with the old text; the new values are what the same code now computes from the new text, so they are data.

Golden digests (`UI005h_Golden.swift`, used by `FIXJ_GoldenDigestTests` and `UI005h_MigrationV13Tests`):

| Digest | Old | New |
|---|---|---|
| Sunday blue (audience) | 4b4c3a53290c2341 | 9e3bcc63af339e8 |
| Loop with shadow | 6bcb221942b17552 | a7a2c2380d372bb4 |
| Keyed plain | c8ced4111be51bda | d1b59a5f17665f6 |
| Missing picture | a3840e37db4abbb1 | ec347864d30cdb0b |
| oldFullScreenAudience | 1faed9c1e1957c85 | 52aacad6b54cf85c |
| oldLowerThirdBroadcast | a98ec309ef8a1e43 | 4f6644d5b62a49e5 |

Text boxes (`UI005h_RenderTests`): only numbers that follow the text's own width changed; every y, height, margin, plate, bar, centre and font number stayed and passes.

| Test | Number | Old | New |
|---|---|---|---|
| theAudienceTextBoxesMatchTheDesign | primary x / width | 391.9 / 1136.2 | 284.9 / 1350.2 |
| theAudienceTextBoxesMatchTheDesign | secondary x / width | 631.9 / 656.1 | 591.8 / 736.5 |
| theLowerThirdPlateBarAndTextMatchTheDesign | primary width | 1239.8 | 1315.9 |
| theStageBoxesMatchTheDesign | next width | 1222.0 | 1293.3 |

Full `swift test` afterwards: 3591 tests in 570 suites, exit 0.
