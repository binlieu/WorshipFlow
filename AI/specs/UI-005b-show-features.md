# UI-005b: the features Show's design draws that the app lacks

Feature ID: UI-005b (touches LIB, SLIDE, OUT). Model: Sonnet. One agent owns all files and migration v12.

## Read first

`CLAUDE.md`; `AI/specs/UI-005-design-match-plan.md` (binding); `AI/reports/UI-005-audit-show.md` (the L rows and the rows UI-005a left open); `AI/reports/UI-005a-report.md` (the open list, the components in `App/Sources/WFControls.swift`, the capture and comparison tools); the design pictures `docs/UI/screens/01-operator-show.png`, `01b-…`, `09-…` and `docs/UI/mockups/01-operator-show.html`. The pictures win.

## Items, in this order (each is finished, tested and compared before the next)

1. **Small open rows from UI-005a.** The timer format in the toolbar as the picture shows it; language names as Quick edit field labels (from the presentation's languages); "Saved N s ago" in Quick edit, from a real save time with an injected clock; the centre header's Arrangement control always present for a song; the "other" section colour as the picture; the faint square selection block behind playlist rows (replace the system List only if drag-reorder, arrow keys, type-select and VoiceOver are kept and tested; otherwise fix the row background and say what remains); `MediaTransportStrip` and the Audio tab drawn with the shared components.
2. **Service date and title.** A playlist carries an optional service date and time; the toolbar title reads as the design ("Sunday 9:00 — 22 Nov") in the user's locale, falling back to the playlist name. Set from the playlist's menu. Carried by program export and import.
3. **Library kinds.** A library has a kind: songs, scripture, sermons, announcements; the kind picks the icon and the count shown. Existing libraries are songs. The Scripture row stays the entry to the scripture view. Sermons and announcements libraries hold ordinary presentations for now; say so in the report.
4. **Playlist item kinds the design shows.** A media file as a playlist item (a video, picture or audio file from the bin: selecting it previews it, Go Live plays it to the foreground or as audio, Next moves on when the operator presses Next, never by itself unless a later task adds that); an announcements loop item (a set of pictures or a video that loops until Next); a sermon item (a presentation from a sermons library, shown with its icon and title as the design does). Each with its icon and row as drawn, each carried by program export and import, each handled by every switch over item kinds (transport, restore at launch, remote state, cues). An older build must not crash on them (it shows "Unknown item", as recorded for scripture).
5. **Props as the design draws them.** Per-prop targets (which of audience, stage, broadcast show this prop) with the pills as toggles; then text props (service title strap, speaker name) with text, font size, colour and position from a small editor, rendered by the existing compositor on the chosen roles; then the announcement prop if the design's row needs more than a text or image prop (say what you found). A prop never appears on a role it is not targeted to; notes rules are unchanged.
6. **The four design Looks** (Full, Notes, Lower 3rd, BG only) seeded on a new library only. An existing library is not changed. "Notes" must respect the rule that speaker notes never reach audience or broadcast: say exactly what the Notes Look shows on each role.
7. **Error card actions.** "Retry output" and "Details" on output errors: Retry re-opens the failed output through the existing output lifecycle; Details shows the recorded fault text with a Copy button. Only for errors where a retry means something.

## Tests

Test-first, and the order is checked: write the test, run it, see it fail at runtime (or fail to compile only for a symbol the item introduces), then implement; record the failing output per item. New files `UI005b_*.swift`; do not edit existing tests except an exact-count migration assertion (change it to `prefix(n)` and list it). Cover at least: migration v12 on a v11 library keeps every row and gives old libraries kind songs and old props all their previous targets (so nothing disappears from a screen after upgrade); each new playlist item kind through select, Go Live, Next, Previous, relaunch restore, export and import; a media item never changes Live on selection; a prop targeted to stage only is absent from the audience and broadcast scenes; text prop content with Vietnamese diacritics renders through the same text path as lyrics; the seeded Looks exist only on a new library; the Notes Look's per-role content; Retry calls the output's reopen once and reports failure plainly; the service title formatting with an injected locale and date. No wall-clock assertions.

## Rules

- You own migration v12: additive only, earlier migrations untouched.
- Editing never changes Live. Red only for on air. Nothing the app has not observed is drawn as fact.
- Do not edit `docs/UI`, `docs/adr`, `AI/specs`, the vendored `sdk/` folder.
- No git state changes. No advisor tool. No full computer control.
- Never open the owner's real library. If you launch the app: your own uniquely named scratch folder, a temporary `--library`, `--silent-audio`, stop only what you started, nothing left in the home folder, no packaged builds left in `dist/`.
- The repository is public: no user names, home paths, computer names or e-mail addresses in any file or picture; no Bible text.
- If you are running out of room, stop at an item boundary with the check passing and say exactly which items are done and which remain.

## Done means

- Each item done or listed as open with the reason.
- The comparison re-run for `01`, `01b` and `09` with the seed updated to use the new item kinds, props and Looks; before and after numbers per region and the pictures in `AI/reports/UI-005b-*.png` (each under 1 MB).
- `./scripts/check.sh` exits 0, run twice.
- `docs/features/` spec for the new data, `docs/19-data-dictionary.md` (v12), `docs/17-change-log.md`, `docs/16-known-issues.md`, `docs/hands-on-checklist.md` updated.
- `AI/reports/UI-005b-report.md`.
