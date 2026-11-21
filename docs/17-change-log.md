# Change log

## 2026-11-20

- Repository initialised. Master spec 0.3, ADR-0001 to ADR-0003, project scaffolding.
- OUT-001: Metal compositor, Core Text rasteriser with Vietnamese-safe padding and fallback, looping video source, display and window outputs with frame statistics, operator spike UI, soak mode. 21 package tests pass. Timing not verified (KI-007).
- SYS-001: GRDB store with schema v1 (library, presentation, slide, playlist, playlistItem, appState), dense reordering, cascades, Vietnamese-folding search on FTS5 with a LIKE fallback. 2,000-song search about 1 ms. Observation streams, debounced autosave and the remaining tables are not built yet.
