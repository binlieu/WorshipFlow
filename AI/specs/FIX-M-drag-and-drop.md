# FIX-M: drag and drop that feels immediate

Feature IDs: UI (Show, Edit, Media), LIB. Model: Sonnet. One agent in the main folder.

The owner, testing build 115 by hand: "drag and drop feels janky and laggy also sometime sluggish". FIX-K measured every drag and fixed the column resize strips, but left two things open (see `AI/reports/FIX-K-report.md`, item 7): each drop handler stalls the main thread for 7 to 29 ms once at the drop, and a reorder redraws every cell of the slide grid. It also could not measure the system drag session (drag image, hover feedback, the `isTargeted` highlight), because synthetic events do not start AppKit's drag loop. That unmeasured part is the most likely source of what the owner felt.

## What to do

1. **Measure the real drag session.** Find a way to exercise real drag sessions without a hand: for example start an `NSDraggingSession` programmatically from the debug hook and drive it, or instrument the drag source and destination callbacks (`draggingEntered`, `draggingUpdated`, `performDragOperation`, SwiftUI `onDrag`, `onDrop`, `dropDestination`, `isTargeted` changes) with signposts and counters and replay them. Say plainly which parts remain measurable only by a person, and give the owner a two-minute procedure with Instruments or the app's own debug overlay to capture numbers themselves (add a debug-only "drag timing" overlay if that is the practical way).
2. **For every drag kind** (slide reorder in grid, list and Edit filmstrip; playlist reorder; song into playlist; bin tile onto a slide, into the playlist, onto the dock's layer; files from Finder into the bin, the grid and the playlist; hot-folder items): per hover update and per drop, what runs on the main thread. Fix the causes:
   - The drag image is a small pre-rendered bitmap, made once at drag start, never a live view hierarchy or a full-size render.
   - Hover feedback changes one view's state (the target's highlight or an insertion line), never the whole grid's layout, identity or data source. No `id` changes, no re-sorting, no thumbnail work during hover.
   - A reorder moves rows by stable identity so only the affected cells update; the grid is not rebuilt.
   - A drop applies an optimistic change to the visible model at once, then does the database write, file probing, bookmark creation, thumbnail generation and import off the main thread; failure rolls the visible change back with a plain message. Order is preserved if several drops arrive quickly.
   - Nothing during a drag or a drop publishes to an output unless the drop's meaning is to change Live (it never is today: a drop edits, it does not go live).
   - File drops from Finder never read file contents on the main thread.
3. **Target:** no main-thread work over 8 ms per hover update, and under 8 ms at the drop before control returns to the user, with 200 slides and 100 bin items in a debug build. Report before and after per drag kind.

## Tests

Test-first for the logic: optimistic apply and rollback, ordering of quick successive drops, stable identity across a reorder (the set of cell identities is unchanged and only the moved range is marked dirty), zero database writes and zero output publications during hover, exactly one write per drop, a failed write restoring the previous order. New files `FIXM_*.swift`. Do not edit existing tests. No wall-clock assertions in the suite: timings go in the report.

## Rules

- Behaviour is unchanged apart from speed and the optimistic update: the same drops are accepted and refused as today, with the same results once settled. Editing never changes Live.
- Do not edit `docs/UI`, `docs/adr`, `AI/specs`, `Vendor/`, the vendored `sdk/` folder, `dist/`, or anything under `.claude/`.
- No git state changes. No advisor tool. No full computer control. Never open the owner's real library; use your own scratch folder, a temporary `--library` and `--silent-audio`, and stop only what you started.
- The repository is public: no personal strings in any file or picture. Known issues continue from the highest number in `docs/16-known-issues.md`.
- If you are running out of room, stop at a drag-kind boundary with the check passing and say what is done.
- Finish with `./scripts/check.sh` twice. Report to `AI/reports/FIX-M-report.md`; update the change log, known issues and hands-on checklist, including the owner's two-minute measuring procedure.
