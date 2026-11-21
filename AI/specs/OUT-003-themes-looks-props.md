# Brief: OUT-003 and SLIDE-002 — themes, Looks and props

Read first: `CLAUDE.md`, `AGENTS.md`, `docs/features/OUT-003-themes-looks-props.md`, `docs/16-known-issues.md`, `AI/reports/OUT-002-report.md`, the coordinator tests `Tests/CompositionTests/ThemeAndLookTests.swift` and `Tests/RenderEngineTests/ImageLayerTests.swift`, and the existing `Sources/Domain/SceneComposer.swift`, `Scene.swift`, `Sources/RenderEngine`, and `App/Sources`.

## Goal

Make those tests pass and let the operator choose a Look, a theme per screen and a logo prop in the existing screens panel.

## Do not modify

- Coordinator-owned tests, including the earlier `SceneComposerTests`, `ShowStateTests`, `OutputRouterTests` and `CompositorTests`, which must keep passing unchanged.
- `Package.swift`, `project.yml`, `CLAUDE.md`, `docs/MASTER-SPEC.md`, `docs/adr/`.
- `Sources/Persistence`, `Sources/Domain/LibraryModels.swift`, and any Domain files for reflow, slide groups or arrangements: another agent is working there now. The `DomainTests` and `PersistenceTests` targets may not compile until it finishes; your tests are in `CompositionTests` and `RenderEngineTests`, which compile independently. Run them with `--filter 'CompositionTests|RenderEngineTests'` until the full suite compiles.

## What to build

**`Domain`** (Foundation only; API fixed by the tests):
- `TextBlock`, `ThemeBackground` (`.media`, `.color`, `.image(path:)`, `.transparent`), `Theme` with `fullScreen`, `lowerThird`, `builtIn` (fixed, hard-coded UUIDs so stored references survive relaunches), `ThemeResolver`.
- `LayerKind`, `ScreenLook` (with `.standard`), `Look` with `screenLook(for:)`, `Prop`.
- `ImageLayer`, `ImageContentMode` (`.fit`, `.fill`); `SceneDescription` gains `backgroundImage` and `overlayImages` with defaults, keeping its existing initialiser source-compatible.
- `SceneComposer.scene(for:state:theme:look:props:clockText:)`. Keep the existing `scene(for:state:clockText:styles:)` entry point working and make it equal to the new one with role defaults (see `legacyEntryPointMatchesDefaults`). If `SceneStyles` and the built-in themes would otherwise disagree, derive one from the other so there is a single source of truth.

**`RenderEngine`**:
- Draw order: background colour, background video, background image, text layers, overlay images.
- An image texture cache keyed by path and file modification date; decode with ImageIO off the render path where practical, never on the main thread in the live path. Expose `imageDecodeCount` and `unavailableImagePaths` as the tests require. Bound the cache (for example 64 images) so a long service cannot grow memory without limit.
- Correct premultiplied alpha and sRGB handling so a 50 % white image reads 128 in the frame.

**App**:
- In the screens panel: a Look picker (create, rename, delete, select), per-screen theme picker and layer toggles for the selected Look, and a props list (add an image through an open panel, on and off toggle, remove). Show unavailable image paths in the operator window.
- Persist Looks and props as JSON beside the screen profiles for now, using security-scoped bookmarks for prop image files chosen by the user; the SQLite tables come in a follow-up.
- Publish one immutable snapshot per change that every output reads, as OUT-002 does.

## Constraints

Swift 6 language mode, strict concurrency, no force unwraps in the live path, justified `@unchecked Sendable` only. Do not commit or change git state. Do not consult any advisor tool.

## Done means

1. `swift test --package-path Packages/WorshipFlowKit --filter 'CompositionTests|RenderEngineTests|OutputEngineTests'` passes; the full suite too once the other agent's work compiles (say which you ran).
2. `./scripts/check.sh` exits 0, or you state exactly which step could not run because of the other agent's unfinished work.
3. `AI/reports/OUT-003-report.md` records files, decisions, commands run with exit status, and everything not verified.
