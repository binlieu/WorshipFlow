# ADR-0007: Adopt the docs/UI design, with six modes

Status: Accepted, 2026-11-20. Layout decision made by the owner ("Adopt six modes").

## Decision

1. The design in `docs/UI` is the visual and layout specification for the operator interface: tokens (`design-tokens.json`), logo and app icon (`docs/UI/logo`, `docs/UI/icon`), and the screens in `docs/UI/screens` with their README.
2. The operator window is reorganised into **six modes**, switched from the toolbar: **Show, Edit, Media, Stage, Cues, Screens**. Stage layouts and Screens become full modes; the stage layout sheet and the long right-hand column are retired.
3. The HTML and CSS in `docs/UI/mockups` exist to draw the pictures. They are never shipped, embedded or loaded by the app (`CLAUDE.md`: native macOS only).
4. Where the design shows something the engine does not do yet, the interface shows it only when it works. No dead controls. Not-yet-built areas (the Cues mode until Phase 3; pixel format, colour range and embedded audio on SDI screens) appear as a short "coming later" note or are left out.
5. Where the design and verified behaviour disagree, behaviour wins. In particular the signal map is drawn from what the device reports: connector order, and which connector carries fill and which key (KI-053), are never hard-coded from the picture.
6. Colours go in the asset catalog as named colour sets with dark and light appearances. Output colours (the slide canvas and lyric inks) are render-engine constants and do not follow the operator's appearance.
7. The mockups use Inter as a stand-in; the app uses the system font.
8. Rules that the restyle must not break: red is reserved for "on screen now"; a simulated device is always labelled; a black background is never presented as transparency; transport buttons stay large and labelled; every existing keyboard command keeps working.

## New behaviour the design introduces

| Item | Decision |
|---|---|
| Blackout | A new command: every audience and broadcast screen goes to black (broadcast: transparent) at once, including background and media; the place is kept; a second press, or any trigger, restores. Distinct from Clear (words only), Clear all (words and clip) and Stop (drops the live deck). Test-first in `Domain`. |
| Separate Preview and Live panes | Both already exist as state (`previewDeck`, live). The Show mode shows them side by side. |
| Playlist section headers and countdown items | New playlist item kinds. Needs a migration; done in the second interface slice. |
| "Run signal test" and "Export log bundle" in Screens | These open the hardware test kit (HWTEST-001). |

## Order of work

1. **UI-001:** tokens and icon in the asset catalog, the six-mode shell with existing panels re-homed, the Show mode to the design, the restyled transport bar with Blackout.
2. **UI-002:** Screens mode with the signal map; Stage, Media and Edit modes to the design; light appearance; playlist headers and countdown items.
3. Cues mode arrives with Phase 3.

Each slice ends with screenshots compared against `docs/UI/screens` and an updated hands-on checklist.
