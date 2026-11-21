# Brief: STAGE-001a — stage layouts, timers and time formatting (rules and storage)

Read first: `CLAUDE.md`, `AGENTS.md`, `docs/adr/0004-persistence.md`, `AI/reports/SYS-002-report.md`, `Sources/Domain/SceneComposer.swift`, `Scene.swift`, `ShowState.swift`, `Sources/Persistence`, and the coordinator tests `Tests/StageTests/StageLayoutTests.swift` and `Tests/StageStoreTests/StageStoreTests.swift`.

Catalogue: LIVE-01, LIVE-02, LIVE-04; groundwork for LIVE-03. No interface in this slice.

## Goal

Make those two test files pass with pure Domain rules and a `v4` migration.

## Do not modify

- Coordinator-owned tests. Migrations `v1` to `v3`. `Package.swift`, `project.yml`, `CLAUDE.md`, `docs/MASTER-SPEC.md`, `docs/adr/`.
- `App/`, `Sources/OperatorCore`, `Tests/OperatorCoreTests`, `Sources/OutputEngine`, `Sources/RenderEngine`: another agent is working there now. Do not change the signature or behaviour of any existing public API in `Domain` or `Persistence`; the existing `SceneComposer.scene(for: .stage, ...)` must keep returning exactly what it returns today (its tests are coordinator-owned).

## What to build

**`Domain`** (Foundation only, new files; API fixed by the tests):
- `ShowTimer` and `ShowTimer.Kind` (`.countdown(seconds:)`, `.elapsed`, `.countdownTo(Date)`), with `start(at:)`, `pause(at:)`, `reset()`, `value(at:)`, `isRunning`, `isOverrun(at:)`. Times are `TimeInterval` since the reference date. Store an anchor and an accumulated amount, never a ticking counter, so a relaunch keeps the right time.
- `TimeFormat.clock(seconds:)` and `TimeFormat.timeOfDay(_:calendar:twentyFourHour:showSeconds:)`, built by hand so the result does not depend on the user's locale.
- `StageElement` (`id`, `kind`, `frame`, `style`, `alignment`, `showsSecondLanguage` default true, `move(dx:dy:)`, `resize(width:height:)`, `minimumSize`), `StageElement.Kind` (`.currentSlide`, `.nextSlide`, `.timeOfDay`, `.timer(UUID)`, `.message`, `.notes`), `StageLayout` (`id`, `name`, `background`, `warningColor`, `elements`, `.standard` with a fixed UUID), `StageContext`, `StageComposer.scene(layout:context:)`.
- Make `StageLayout.standard` look like today's built-in stage scene so switching the app over later changes nothing visible.

**`Persistence`** (migration `v4`, new file): tables `stageLayout` and `showTimer`; `stageLayouts()`, `saveStageLayout`, `deleteStageLayout` (the built-in layout is never stored or deleted), `timers()` in creation order, `saveTimer` (upsert), `deleteTimer`. JSON text columns for the definitions.

**Docs**: add the v4 tables to `docs/19-data-dictionary.md`.

## Constraints

Swift 6 language mode, strict concurrency, no force unwraps, justified `@unchecked Sendable` only. Do not commit or change git state. Do not consult any advisor tool.

## Done means

1. `swift test --package-path Packages/WorshipFlowKit --filter 'StageTests|StageStoreTests|PersistenceTests|SettingsStoreTests|DomainTests|CompositionTests'` passes; the full suite and `./scripts/check.sh` too if the other agent's app work compiles at that moment (say which you ran and the result).
2. `AI/reports/STAGE-001a-report.md` records files, decisions, commands run with exit status, and everything not verified.
