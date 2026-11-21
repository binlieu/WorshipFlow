# WORSHIPFLOW — agent startup contract

Read `CLAUDE.md` first. It is the authority for this repository. This file is the short version every agent must hold in mind.

## Non-negotiable rules

1. Native macOS only: Swift 6, SwiftUI, AppKit, AVFoundation, Metal. No WebView, HTML or server rendering for core functions.
2. Local-first. Nothing in the live path may need the network.
3. Module boundaries (see `CLAUDE.md`, "Architecture boundaries"). `Domain` imports no UI, media or hardware framework.
4. The live path never blocks the main thread and never uses unbounded queues.
5. Do not weaken or delete an acceptance test to make it pass. Tests listed as do-not-modify in a brief are owned by the coordinator.
6. Do not claim a verification level without evidence. Levels: Implemented, Unit Tested, Simulated, Hardware Verified, Live-Service Verified.
7. Do not say a command passed unless you ran it and checked its exit status.
8. No third-party code, branding or assets copied from other presentation products.
9. Feature IDs go in briefs, tests and commits. See `docs/adr/0002-feature-ids.md`.

## Where things are

| Path | Purpose |
|---|---|
| `docs/MASTER-SPEC.md` | Feature baseline and acceptance criteria |
| `docs/14-current-status.md` | What exists and its verification level |
| `docs/15-agent-handoff.md` | Next safe task |
| `docs/16-known-issues.md` | Known issues and spec conflicts |
| `docs/17-change-log.md` | Change log |
| `docs/19-data-dictionary.md` | Persisted data |
| `docs/adr/` | Accepted decisions |
| `docs/features/` | Per-feature specs |
| `AI/TASK-BREAKDOWN.md` | Tasks, dependencies, model assignments |
| `AI/specs/`, `AI/reports/` | Delegation briefs and results |

## Build and check

```bash
./scripts/check.sh
```

The Xcode project is generated from `project.yml` by XcodeGen. Edit `project.yml`, never the `.xcodeproj` by hand, then run `xcodegen generate`.
