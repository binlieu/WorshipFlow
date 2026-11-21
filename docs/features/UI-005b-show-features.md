# UI-005b: the features Show's design draws

Catalogue: LIB, SLIDE, OUT (Show). Source: the owner's request of 2026-11-21 that the app match `docs/UI` exactly, features included. Verification: Implemented; Unit Tested (`UI005b_*` in `OperatorCoreTests`, `PersistenceTests`, `ProgramPackageTests`, `DomainTests`, `RenderEngineTests`, `OutputEngineTests`); Simulated for the pictures (Debug build, `scripts/design-capture.sh`). Not Hardware Verified, not Live-Service Verified. Brief: `AI/specs/UI-005b-show-features.md`; report: `AI/reports/UI-005b-report.md`.

## Data (migration v12, additive)

| Table.column | Meaning | Existing rows |
|---|---|---|
| `library.kind` TEXT NOT NULL | `songs`, `scripture`, `sermons`, `announcements` | `songs` |
| `playlist.serviceAt` DATETIME | service date and time (UTC instant) | NULL (the title falls back to the name) |
| `prop.targets` TEXT NOT NULL | JSON array of roles the prop may appear on | `["audience","broadcast"]`: where props were drawn before; the stage never drew them |
| `prop.kind` TEXT NOT NULL | `image` or `text` | `image` |
| `prop.text` TEXT | JSON `TextPropSpec` (words, size in points on a 1080 line, colour, anchor) | NULL |

Playlist item kinds (stored in `playlistItem.kind` and `payload`, no schema change): `sermon` (presentation id as for a presentation), `media` (`MediaItemSpec`: bin id, name, kind), `announcements` (`AnnouncementsSpec`: label, items, seconds per picture). A build without these kinds reads them as the header "Unknown item" (its existing rule for unknown kinds), skips them with Next and Previous, and does not crash.

## Behaviour

- **Toolbar timers** read `00:10:32` (elapsed) and `25:00` (countdown; hours only from an hour). **Quick edit** labels are the languages of the words (`NaturalLanguage`; "First language"/"Second language" when it cannot tell; nothing stored) and the note counts from the last real write ("Saved 2 s ago · live at next trigger").
- **Arrangement** is always on a song: with a playlist item it sets that item's order; from the library it previews one (not stored).
- **Service title**: "Sunday 9:00 — 22 Nov" in the user's locale from the playlist's date; set from the playlist's menu; carried by program export and import.
- **Library kinds**: icon by kind; sidebar order songs, the Bible entry, scripture, sermons, announcements. Sermons and announcements libraries hold ordinary presentations for now.
- **Media-file item**: selecting previews it in the bin player and never changes Live; Go Live plays a video or picture over the screens (with nothing live, the screens start on an empty slide) or a sound as audio; Next or Previous ends it and moves on; nothing moves on by itself. **Announcements loop**: pictures cycle every N seconds, or one video repeats, until Next. **Sermon item**: a presentation from a sermons library, listed as "Sermon — title".
- **Props**: per-prop targets (AUD, STG, BRD pills; click to stop, "Show on" in the context menu); text props with a small editor; a prop never appears on a role it is not targeted to; speaker notes are not affected.
- **Looks** seeded on a NEW library only: Full (all layers everywhere), Notes (audience: words and background, no props; broadcast: words only; stage unchanged, notes remain the stage layouts' alone), Lower 3rd (broadcast: slide and props, no background), BG only (audience and broadcast: background).
- **Error card**: an enabled output that is faulted gets "Retry output" (the coordinator's restart, once; a second failure is said plainly) and "Details" (the recorded fault text, Copy).
