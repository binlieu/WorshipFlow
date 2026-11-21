# Agent handoff

Updated: 2026-11-20

## In flight

- **OUT-001** render spike. Brief: `AI/specs/OUT-001-render-spike.md`. Report lands in `AI/reports/OUT-001-report.md`. The coordinator reviews, runs `./scripts/check.sh`, runs the 60-minute soak, then commits.

## Next safe task

- **SYS-001** SQLite store through GRDB. Test-first: the coordinator writes migration and autosave tests before delegating. Do not start until OUT-001 is committed, because it adds the `Persistence` target to `Package.swift`.

## Standing rules from the owner

- Build without stopping for go-aheads. Decide by common sense and research, record the decision, continue.
- Real stops only: buying hardware, paid services or accounts, licence approval, credentials, destructive operations on user data.

## Blocked on the owner

- Purchase of DeckLink Duo 2, Thunderbolt enclosure and ATEM (KI-001). Not needed until Phase 2.
