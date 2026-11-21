# ADR-0003: Where CLAUDE.md overrides the master spec

Status: Accepted, 2026-11-20

`CLAUDE.md` was added after `docs/MASTER-SPEC.md` version 0.2. Where they differ, `CLAUDE.md` wins.

| Topic | Master spec | Now |
|---|---|---|
| Storage (ARCH-11) | "Local documents plus a search index" | SQLite through GRDB with versioned migrations |
| Who writes code (section 7 note) | "Automated coding agents" | Claude subagents on Haiku and Sonnet. No Codex, no advisor. |
| Ordering | NDI and Syphon ahead of DeckLink in Phase 2 | DeckLink path follows the stage and broadcast variants; NDI is a later milestone. Syphon stays in Phase 2 because it needs no licence. |
| Verification wording (ARCH-33) | "written, unverified" | The five levels in `CLAUDE.md`: Implemented, Unit Tested, Simulated, Hardware Verified, Live-Service Verified |
| Development authorised | No | Yes. The owner gave standing permission to build on 2026-11-20. |

The phase numbers and the placement of the 64 features are unchanged.
