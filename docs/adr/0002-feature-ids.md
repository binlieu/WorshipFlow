# ADR-0002: Two sets of IDs, and how they map

Status: Accepted, 2026-11-20

## Context

`docs/MASTER-SPEC.md` catalogues the guide's 64 features as `PRES`, `MEDIA`, `SCRN`, `AUTO` and `LIVE`. `CLAUDE.md` asks for implementation feature specs under `LIB`, `SLIDE`, `MEDIA`, `OUT`, `STAGE`, `HW`, `KEY`, `CUE` and `SYS`.

## Decision

- **Catalogue IDs** (`PRES-01`, `SCRN-11`, ...) stay as the requirement baseline. They are two-digit.
- **Implementation IDs** (`OUT-001`, `SLIDE-003`, ...) name the vertical slices actually built. They are three-digit, so the two sets cannot be confused. `MEDIA-06` is a catalogue row; `MEDIA-006` is an implementation slice.
- Every feature spec in `docs/features/` lists the catalogue IDs it satisfies, in full or in part.
- Briefs, tests and commits use implementation IDs.
- The spec's `HW-nn` signal rules keep their two-digit form; hardware implementation slices are `HW-001` onward.

## Consequences

`AI/TASK-BREAKDOWN.md` carries the mapping table and is the place to check coverage of the 64.
