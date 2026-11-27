# FIX-Z: the capture sample and tests must not quote a copyrighted song

Feature ID: SYS (repository hygiene). Model: Sonnet. One agent in its own worktree; commit on the worktree's branch when done (the coordinator merges). Another agent is fixing other things in the main folder: stay inside the files this brief names.

The repository is public and its rule is that sample songs are synthetic or public domain. The design-capture sample song is "Amazing Grace" with a chorus ("My chains are gone / I've been set free / My God, my Savior / has ransomed me / And like a flood / His mercy reigns / Unending love / Amazing grace") that is a 2006 addition under copyright, with a Vietnamese rendering of it. `git grep -l "My chains are gone"` lists the files: `App/Sources/UISnapshotDesign.swift`, `UISnapshotRun.swift`, `ComponentsBoard.swift`, `EditDesignCapture.swift` ("My God, my Savior\nhas ransomed me"), `Packages/WorshipFlowKit/Sources/LooksProbe/main.swift`, tests (`ReflowTests`, `FIXH_LanguageLabelTests`, `UI001_ShellTests`, `UI005b_SmallRowsTests`, `WorkspaceModelTests`) and `AI/reports/UI-005-audit-show.md`. Search also for the other chorus lines and their Vietnamese lines on their own, and for sample titles "10,000 Reasons" and "How Great Thou Art" (titles of songs under copyright; a title is not the problem a lyric is, but replace them in samples anyway).

## What to do

1. Replace the chorus everywhere with these public-domain lines of the same hymn (John Newton, 1779), same number of lines so slide counts and layouts stay as they are:

   ```
   Through many dangers
   toils and snares
   'Tis grace has brought me
   safe thus far
   The Lord has promised
   good to me
   And grace will lead
   me home
   ```
   Vietnamese (a plain rendering written for this project):
   ```
   Qua bao hiểm nguy
   gian khó thử thách
   Ân điển đưa tôi
   bình an đến nay
   Chúa đã hứa ban
   phước lành cho tôi
   Và ân điển sẽ
   dẫn tôi về nhà
   ```
   Where a file has the chorus as four long lines, join the pairs with a comma in the same way the file does today. The text object in `EditDesignCapture.swift` becomes "'Tis grace has brought me\nsafe thus far" (same slide, same frame: the design comparison depends on its place).
2. Replace sample titles "10,000 Reasons" with "Holy, Holy, Holy" and "How Great Thou Art" with "It Is Well" in sample and capture code and in tests that only use them as sample data.
3. Tests that quote the old lines are sample data, not behaviour: update the quoted text and any count or width that follows from it, and nothing else. List every test edited and why the edit is only data. If a test's meaning depends on the old words in a way a swap would weaken, stop and list it instead.
4. In `AI/reports/UI-005-audit-show.md` replace the quoted lyric lines with the new ones (a report keeps its findings; only the quotation changes).
5. Check that nothing else in the repository quotes lyrics of a song under copyright: `git grep` for the sample song list in the capture code and tests and say what you found (titles only is acceptable; lyric lines are not). No Bible text may be added.
6. The design comparison (`scripts/compare-rects.py` with the design maps) measures rectangles: line lengths change a little, so some text rectangles may move by a point or two. Do not run captures on the owner's displays; say in the report that the rectangle counts need re-measuring (the coordinator decides when).

## Rules

- Do not change behaviour: this is sample text only. No edits outside the files found by the searches above.
- Do not edit `docs/` (except nothing: put change-log text in the report), `docs/UI`, `docs/adr`, `AI/specs`, `Vendor/`, `dist/`. Write `AI/reports/FIX-Z-report.md`.
- No advisor tool. No full computer control. Never open the owner's real library, never touch `/Applications/WorshipFlow.app`; do not launch the app at all. No soak. No display or system settings. Never `pkill` by name.
- No personal strings in any file.
- Run the package tests (`swift test` in `Packages/WorshipFlowKit`; if a test shows garbage values run `swift package clean` first, KI-271) and report the count and exit status actually observed. Do not run `./scripts/check.sh`: the other agent is using the shared build folders; the coordinator runs it after merging.
- Commit on your worktree branch with message `fix(FIX-Z): the capture sample and tests use public-domain hymn lines`, ending with the line `Co-Authored-By: Claude Fable 5.2 <noreply@anthropic.com>`. Do not push. Do not leave monitors or wait loops running when you report.
