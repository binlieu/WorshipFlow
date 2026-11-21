# LIB-004c: scripture in the app

Catalogue: PRES-09, PRES-10. Verification: Implemented; Unit Tested; seen once in a Debug build through the `--ui-snapshots` hook with real key events. Not Hardware Verified, not Live-Service Verified. Mouse use of the new views, VoiceOver and the light appearance were not tried.

Code: `OperatorCore` (`ScriptureModel`, `ScriptureModel+Search`, `ScriptureModel+Translations`, `ScriptureRules`, `WorkspaceModel+Scripture`), `Domain/ScriptureItem.swift`, `App/Sources/ScriptureView.swift`, `ScriptureTranslationsView.swift`. Tests: `OperatorCoreTests/LIB004c_*`, `PersistenceTests/LIB004c_ScripturePlaylistItemTests`.

## What the operator sees

- **Entry.** "Scripture" under Libraries in the Show sidebar, or Command-J (Show menu). It takes the centre of Show; opening a song closes it. Command-J is recorded in the keyboard table of `CuesMode`.
- **Reference field.** Accepts what `ReferenceParser` accepts, English and Vietnamese book names. Book suggestions appear as chips while the book name is typed. Return shows the passage in Preview and moves keyboard focus to the slide grid, so Return again is Go Live and Space or the arrows step.
- **Passage.** The slides are the same thumbnails songs use. The reference is the last line of each side's words (so a transparent broadcast screen, which leaves slide objects out, still gets it). Choosing a slide is Preview only. Go Live, Next and Previous are the ones every song uses, through `CueModel`'s command path. Next after the last slide stays; for a passage that came from a playlist item it goes on to the next item, as a song does.
- **Limits.** `ScriptureSlideLimits` turns the audience screen's theme (text box size and type size on a 1920 by 1080 canvas) into a character budget, one line less for the reference; with two translations the smaller of the two boxes. It is an estimate. Verses per slide: 1 to 4 (more than one: superscript verse numbers).
- **Two translations.** The pair is made by `VerseSlides` (by book, chapter and verse number); `ScriptureLibrary` adds a note for every chapter the two tables number differently. A verse one translation lacks leaves that side empty; nothing is made up. A verse only the second translation has is not shown (see KI-090).
- **Keep it.** "Add to playlist" stores a playlist item of kind `scripture` (the existing `kind` and `payload` columns of schema v8): reference ranges, the translation codes and a label, never the words. No migration. "Save as presentation" makes an ordinary presentation (kind scripture) of the slides as they are, in the selected library, and opens it for editing.
- **Search.** The Search tab searches the first translation with `ScriptureStore.search` (case, accents, đ ignored). A result opens its verse.
- **Translations.** Lists name, language, verse count and the copyright line the file carried; Import… (open panel, a translation `.json`), progress, a plain result, a question before replacing a code that is installed; Remove… asks first. USFM goes through `wf-bible-import`. With none installed the view says so and offers Import.
- **Missing translation.** A playlist item whose translation is not installed stays in the playlist with "not installed"; selecting it shows the reason; Next into it stops with a message.
- **Screens.** Audience: verse and reference. Stage: current and next, as for lyrics. Broadcast: the lower-third composition. No new composition code.

## Decisions

- A passage is a preview deck, not a stored presentation: `WorkspaceModel.openScripture` (`openPresentationID` is nil), so nothing writes to the library until Add or Save. The deck id is the playlist item's id when it came from one, so the item is marked LIVE.
- Editing a passage is done after "Save as presentation". Quick edit and the Edit mode do nothing for a passage.
- A reference that is partly bad shows nothing (a plain problem) rather than half a passage.
- The chosen translations and verses per slide are saved in the library's state table (`scripture.choices`).

## FIX-F changes (review of 2026-11-21)

- **Centre pane.** `WorkspaceModel.centreShowsScripture` is true whenever a passage (typed, from a playlist item, stepped into, restored) is open; the Show centre shows the Scripture view when that is true or when the operator asked for it. The view's close button also closes the open passage.
- **Refresh.** A change of translation or verses per slide makes the shown passage again from its own ranges (not from the field text), with the same identity and playlist item, and does not touch the field.
- **Library changes.** After Remove or a replacing Import the shown passage is read again by its own codes: a missing primary gives the "not installed" state and the code is never kept for Add to playlist; a missing second translation is dropped with a notice. Live is never changed.
- **Requests.** One counter on the workspace numbers every request that puts a passage, a playlist item or a song into Preview, and each checks it after every await; the newest wins.
- **Size.** More than 300 slides is refused: the operator is told the count and asked to narrow the reference.
- **Import.** `canStartImport` is false while an import runs or the replace question is open; a second import is ignored and the buttons are disabled. A file over 64 MB is refused before it is read.
- **Missing translation and Next.** The first Next or Previous onto such an item stops with the message; a second one onto it, from the same live item, in the same stay (no other live change), skips it (and any further such item) and says so. The keyboard, MIDI, remote and the buttons all end in `WorkspaceModel.next()`/`previous()`.
- **Reference text.** Stored ranges written with the KJV table and read back by the primary translation's table: whole chapters and partial ranges are unchanged on both built-in tables. Across tables a verse the other table lacks is refused in plain words, never changed silently. Known issues KI-093 to KI-095.
