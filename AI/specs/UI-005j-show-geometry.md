# UI-005j: Show, element by element, to the mockup's rectangles

Feature ID: UI-005j. Model: Sonnet. Starts after FIX-H is committed; one agent owns the app's view files.

## Why this slice exists

After UI-005a, UI-005b and the Inter font, Show still differs from `01-operator-show.png` in about 20% of pixels. The earlier reports put that down to the font and to sample art. The coordinator looked at the difference image (`AI/reports/UI-005i-show-dark-diff.png`) and that explanation is wrong: Inter changed nothing measurable, and the image shows whole regions displaced. What it shows:

- Sidebar and playlist rows drift downward: by the playlist every row is drawn at a different height from the design's (doubled text in the difference image), so row heights or section gaps are off by a point or two each and it accumulates.
- The toolbar's mode switcher, timers and pills sit at different x positions, and the title block differs.
- The centre header's controls are at different x positions and widths (the Arrangement field is truncated; the app has an extra icon button).
- Slide thumbnails are a different size and start at a different y; their captions differ in length and position; section headers sit at different heights.
- The inspector's monitors are larger than the design's, and the slim extras row was put between the monitors and LOOK, which pushes the Look row, tabs, props and stage message down by about 40 points.
- The media bin's header, tiles and controller sit a few points lower than the design; the transport bar's buttons are at different x positions and widths.
- Slides and tiles in the capture have no artwork, where the design shows a teal gradient with large lyric text. Part of that is the seed and part is the output look (type size and background), which UI-005h owns.

So this slice does not judge by a percentage. It measures rectangles.

## Method (build the tool first)

1. **Rectangles from the design.** Write a small tool (`scripts/design-rects`, Swift with `WKWebView`, run by hand) that loads a mockup HTML file from `docs/UI/mockups/` at 1440 by 900 CSS pixels, waits for layout, and writes a JSON list of every visible element: a stable path (tag, classes, index, and the text it contains), its `getBoundingClientRect()`, and its computed font size, weight, line height, colour, background, border width and radius. Check the tool's own render against the design PNG once (they should be the same picture, apart from the font if Inter is not installed for WebKit: load `Vendor/Inter/InterVariable.ttf` through an injected `@font-face` so it is). If the HTML render and the PNG disagree anywhere, the PNG wins and the report lists where.
2. **Rectangles from the app.** In the debug snapshot hook, tag every corresponding view with an identifier that names the design element it stands for, and dump identifier, frame in window coordinates (points, top-left origin), and the resolved font and colours where they apply, as JSON, for the same seeded state and window size as the capture.
3. **Compare.** A script joins the two lists by a mapping file kept in the repository (`scripts/design-map-show.json`: design path to app identifier) and prints, per element, the difference in x, y, width, height, font size, weight and radius; sorted by the largest; and a summary count of elements within 1 point on all four edges. Unmapped elements on either side are listed: every element in the design must be mapped or explained, and every app element with no counterpart is one of the owner's extras or a defect.
4. Work region by region until every mapped element is within 1 point on position and size and exact on font size, weight and radius, in dark and light. Fix causes, not symptoms: if rows drift, find the row height or spacing that is wrong; do not offset things to compensate.

## Layout decisions for this slice

- The extras row ("Edit live slide…", the live-override state with Drop, Configure…) leaves the space between the monitors and LOOK. It goes to the bottom of the inspector, pinned above the transport bar, in the area the design leaves empty, and takes no space when it has nothing to show. "Add text prop…" becomes a "+" in the Props tab's header line, not a row.
- The centre header matches the design's set and order of controls. The extra "Add to playlist" icon button moves into the header's overflow or the song row's context menu; nothing is lost, and say where it went.
- The monitors take the design's sizes and captions (one line: role and destination), with the SIMULATED mark as the small pill the design draws ("SIM").
- The seeded capture library uses a theme whose background and type match the design's sample slides as far as today's theme model allows, so thumbnails can be compared; what cannot be matched until UI-005h (output looks) is listed, not hidden.
- Window controls: capture with the window active so the traffic lights are coloured as in the design.

## Rules

- No model or schema change, no behaviour change. Existing tests may be edited only where they assert a layout number; list each.
- Editing never changes Live; red only for on air; accessibility identifiers added for the dump must not replace or hide accessibility labels.
- Do not edit `docs/UI`, `docs/adr`, `AI/specs`, `Vendor/`, the vendored `sdk/` folder.
- No git state changes. No advisor tool. No full computer control. Never open the owner's real library; if you launch the app use your own scratch folder, a temporary `--library` and `--silent-audio`, stop only what you started, leave nothing in the home folder or in `dist/`.
- The repository is public: no user names, home paths, computer names or e-mail addresses in any file or picture.
- If you are running out of room, stop at a region boundary with the check passing and say exactly which regions are within tolerance and which are not.

## Done means

- The three tools exist and are documented in a short section of `docs/hands-on-checklist.md` or a script header.
- `AI/reports/UI-005j-report.md` has the before and after table of rectangle differences per region (count of elements, count within 1 point, the worst five), the unmapped lists with a reason for each, the pixel comparison numbers for reference, and side-by-side and difference pictures after (`AI/reports/UI-005j-*.png`, each under 1 MB).
- `./scripts/check.sh` exits 0, run twice.
- Change log, known issues and hands-on checklist updated.
