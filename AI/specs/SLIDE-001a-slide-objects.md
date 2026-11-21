# Brief: SLIDE-001a — slide objects: shapes, images and text boxes with fills and effects (no editor interface)

Read first: `CLAUDE.md`, `AGENTS.md`, `docs/adr/0004-persistence.md`, `docs/19-data-dictionary.md`, `AI/reports/OUT-003-report.md`, `AI/reports/MEDIA-002-report.md`, `Sources/Domain/SlideContent.swift`, `Scene.swift`, `SceneComposer.swift`, `StageLayout.swift`, all of `Sources/RenderEngine`, `Sources/Persistence`, and the coordinator test `Tests/SlideObjectTests/SlideObjectTests.swift`.

Catalogue: PRES-01 (slide editor: text, shapes, images), MEDIA-07 (fills and effects). The editor interface is a later slice.

## Goal

Make the coordinator test pass: a slide can carry ordered objects, the compositor draws them, the store keeps them, and search finds text-box words.

## Do not modify

- Coordinator-owned tests, including every earlier one (they must keep passing unchanged). Migrations `v1` to `v4`. `Package.swift`, `project.yml`, `CLAUDE.md`, `docs/MASTER-SPEC.md`, `docs/adr/`.
- `App/`, `Sources/OperatorCore`, `Tests/OperatorCoreTests`, `Sources/MediaEngine`, `Sources/OutputEngine`: another agent is working there now. Every change must be source-compatible for it: add defaulted parameters, new members and new types only. In particular `SlideContent(primary:secondary:)` must keep compiling, existing JSON and database rows must keep decoding, and a slide with no objects must produce exactly the scenes it produces today.

## What to build

**`Domain`** (Foundation only; API fixed by the tests):
- `SlideObject` (`id`, `frame`, `opacity` clamped to 0…1, `content`; `move(dx:dy:)`, `resize(width:height:)`, `minimumSize`), `SlideObject.Content` (`.text(TextObject)`, `.shape(ShapeObject)`, `.image(ImageObject)`), `TextObject`, `ShapeObject` with `Shape` (`.rectangle`, `.ellipse`, `.roundedRectangle(cornerRadius:)` where the radius is a fraction of the shorter side), `ImageObject`.
- `SlideContent.objects` (default empty, decoding tolerant of its absence) with `bringToFront`, `sendToBack`, `moveForward`, `moveBackward`, `removeObject`; `isBlank` is false when there are objects.
- `TextShadow` and `TextStyle.shadow` (optional, decoding tolerant of its absence; offsets and blur in points at a 1080-line reference).
- `ShapeLayer`, `SceneObjectLayer` (`.shape`, `.text`, `.image`), `SceneDescription.objectLayers` (default empty).
- `SceneComposer`: objects belong to the slide layer; they appear on audience screens, on broadcast screens only when the resolved theme's background is not transparent, never on the stage; hidden by Clear and by a Look that hides the slide layer; hidden while a foreground media clip plays, like lyric text.

**`RenderEngine`**:
- Draw order: background colour, background media, theme background image, foreground media, object layers back to front, lyric text layers, overlay images.
- Shapes drawn with correct antialiasing and premultiplied alpha; stroke inside the frame edge; stroke width in points at a 1080-line reference. Rasterising shapes with Core Graphics into cached textures is acceptable; a shader is fine too. Bound every cache.
- Text shadow in `TextRasterizer` for both lyric text and text objects, with the bitmap padded so nothing is clipped; cache keys must include the shadow.
- Image objects reuse the existing image cache.

**`Persistence`** (migration `v5`): a nullable JSON text column on `slide` for the objects (null when empty, so plain lyric slides stay small); `appendSlide`, `updateSlide`, `slides(of:)`, `resolvedSlides`, `slides(forPlaylistItem:)` round-trip objects; text-object words are folded into the search index; `replaceContent` produces slides without objects. All queries keep working on stores opened with `migratingUpTo:` an earlier version.

**Docs**: add the v5 column to `docs/19-data-dictionary.md`.

## Constraints

Swift 6 language mode, strict concurrency, no force unwraps in the live path, justified `@unchecked Sendable` only. Do not commit or change git state. Do not consult any advisor tool.

## Done means

1. `swift test --package-path Packages/WorshipFlowKit --filter 'SlideObjectTests|RenderEngineTests|CompositionTests|DomainTests|PersistenceTests|SettingsStoreTests|StageTests|StageStoreTests|MediaRulesTests'` passes; the full suite and `./scripts/check.sh` exit 0, or you state exactly which step could not run because of the other agent's unfinished work.
2. `AI/reports/SLIDE-001a-report.md` records files, decisions, commands run with exit status, and everything not verified.
