# OUT-003 and SLIDE-002 — Themes, Looks and props

Satisfies: PRES-06 (themes), SCRN-08 (Looks), SCRN-09 (alternate themes), MEDIA-08 (props); groundwork for PRES-01 (image objects). Phase 1.

## Behaviour

1. **Theme.** A theme sets the background (the media layer, a colour, an image, or transparent) and a text block for the first language and optionally the second: font, size, colour, outline, frame and alignment. Two built-in themes ship: full screen and lower third. UI-005h: they draw the design's looks (type weight and size, a gradient under the loop, a plate and accent bar behind the lower third) and a theme may carry a plate, a gradient background and a gradient under its loop; see `UI-005h-output-looks.md`. The earlier looks are the Classic themes.
2. **Resolution.** For an audience screen: the screen's Look theme, else the presentation's theme, else full screen. For a broadcast screen: the screen's Look theme, else lower third. An unknown id falls back. The stage screen uses its stage layout and ignores themes.
3. **Look.** A Look gives each screen a set of visible layers (background, slide, props) and an optional theme. A screen the Look does not mention shows everything. Switching Look changes every screen in one action.
4. **Props.** A prop is an image with a frame and opacity that stays above the slide across slide changes and Clear, until switched off or Stop. A Look can exclude it per screen. Never on the stage screen.
5. **Images in the compositor.** A scene may carry one background image (under text) and overlay images (over text), each with fit or fill and opacity. Images are decoded once and cached. A missing file never stops a frame; its path is reported for the operator.

## Acceptance

| Check | Level |
|---|---|
| `CompositionTests` and `ImageLayerTests` pass | Unit Tested |
| Operator can pick a Look and a theme per screen, add a logo prop and toggle it | Implemented; seen running when the interface pass happens (KI-011) |
| Themes, Looks and props persist in SQLite | Follow-up after schema v2 lands |
