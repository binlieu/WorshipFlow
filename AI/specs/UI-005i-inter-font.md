# UI-005i: the operator interface is set in Inter

Feature ID: UI-005i. Model: Sonnet. Starts after UI-005b is committed; one agent owns the app's view files.

Read `CLAUDE.md`, then `AI/specs/UI-005-design-match-plan.md` (the section "Added 2026-11-21: the interface font is Inter" is the decision and its limits), `docs/UI/mockups/ui.css` (every `font`, `font-size`, `font-weight`, `letter-spacing`, `line-height` and `font-feature-settings` rule) and `AI/reports/UI-005a-report.md` (the comparison tools).

## What to build

1. **Bundle the font.** `Vendor/Inter/` holds `InterVariable.ttf`, `InterVariable-Italic.ttf`, `LICENSE.txt` and `SOURCE.txt`, unmodified from the official 4.1 release. Add them to the app's resources through `project.yml` (do not copy them to a second place in the repository), register them at launch for this process only (`CTFontManagerRegisterFontsForURL` with process scope; nothing is installed on the Mac), and fail soft: if registration fails the app uses the system font and says so once in the log.
2. **One place for type.** Every text style the interface uses comes from named styles in `DesignTokens.swift` built on Inter at the mockup's size, weight, line height and letter spacing, with the `tnum` and `cv11` features on as the CSS has them; monospaced text stays SF Mono as the mockups have it. Replace every `.font(.system(…))`, `.font(.body)` and similar in `App/Sources` with those styles; AppKit views (`NSFont.systemFont`) too. List what could not be replaced and why (menus, the title bar, open panels and alerts are drawn by the system and stay as they are).
3. **Fallback.** Text in the library is any script. Inter covers Latin with Vietnamese, Cyrillic and Greek; everything else must fall back to the system font with no missing-glyph boxes and no change in line height that clips a row. Test with Vietnamese stacked diacritics, Chinese (both scripts), Hmong, and a few of the minority-language samples already used in tests; use short invented phrases, not Bible text.
4. **Not the outputs.** What is projected on audience, stage and broadcast screens follows each theme's own font. Do not change the render engine's fonts, the themes, or any slide thumbnail's rendered text. Add a test that the output text path does not use the interface font styles.
5. **Credits.** Inter and its licence are named in `NOTICE`, the README's third-party section and the About window's notices. Include the licence text in the app bundle.
6. **Measure.** Re-run the capture and comparison for all five Show and component pictures before and after, per region, and put the numbers and pictures in the report. Look at the captures: check for truncated labels, clipped descenders and rows whose height changed, in dark and light, and fix what the font change broke.

## Rules

- No model, schema or behaviour change. Existing tests may be edited only where they assert a font name or a text measurement; list each.
- Do not edit `docs/UI`, `docs/adr`, `AI/specs`, the vendored `sdk/` folder, or the files in `Vendor/Inter/`.
- No git state changes. No advisor tool. No full computer control. Never open the owner's real library; if you launch the app use your own scratch folder, a temporary `--library` and `--silent-audio`, stop only what you started, and leave nothing in the home folder or in `dist/`.
- The repository is public: no user names, home paths, computer names or e-mail addresses in any file or picture.
- Finish with `./scripts/check.sh` twice. Report to `AI/reports/UI-005i-report.md`; update `docs/17-change-log.md`, `docs/16-known-issues.md`, `docs/hands-on-checklist.md`.
