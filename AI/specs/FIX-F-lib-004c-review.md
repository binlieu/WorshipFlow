# FIX-F: fixes from the independent review of LIB-004c

Feature ID: LIB-004c. Model: Sonnet. Owner of files: this task alone.

The independent review of LIB-004c (2026-11-21) found no critical or high defect and nothing that changes Live without an explicit Go Live or Next. It found three medium and several low ones. Work test-first: for every item marked **Fix**, write the failing test, see it fail for the right reason, then change the code. New tests go in new files `FIXF_*.swift` in the test target LIB-004c used. Do not edit existing tests.

## Items

1. **Fix (medium): the centre pane is empty while a scripture passage is live.** The Scripture view shows only when `ui.scriptureOpen` is true, and only the sidebar row and Command-J set it. When Next, MIDI or the remote steps from a song into a scripture playlist item, or one is restored at launch, the centre shows the "no presentation" state while the passage is live. The centre pane must show the passage whenever the workspace has an open scripture passage, however it was opened. Put the decision in a model-level value that can be tested (not only in a view), and test: stepping from a song into a scripture item, and relaunch restore, both report the passage as what the centre shows.
2. **Fix (medium): changing a translation or the verses-per-slide count detaches a playlist passage from its playlist item.** `refresh` re-runs the text in the field, which gives the passage a new identity, clears the selected playlist item, and so Go Live followed by Next no longer advances through the playlist; it also shows an edit the operator has typed but not submitted. Refresh from the shown passage's own reference, keep the playlist item's identity and selection, and leave unsubmitted field text alone. Tests: open from a playlist item, change the second translation, Go Live, Next past the last slide advances to the next playlist item; unsubmitted text in the field is not shown by a refresh.
3. **Fix (medium): the shown passage keeps the text of a translation that was removed or replaced.** After Remove, or an import that replaces a translation, re-show the passage from the library; if its primary translation is gone, show the plain "translation not installed" state and do not let Add to playlist store the missing code. A second translation that is gone is dropped with a notice. The Live deck is never changed by this. Tests for remove, replace, and Live untouched.
4. **Fix (low): an older preview request can land after a newer one.** `show`, `openScriptureItem` and opening a song are not tied together. Use one shared request counter checked after every await, so only the newest request reaches Preview. Test with a store whose lookup can be held and released in a chosen order.
5. **No code change: an older build shows a scripture playlist item as a header named "Unknown item".** Record it as a known issue, including that renaming that header in the older build overwrites the reference.
6. **Fix (low): no limit on the size of a passage.** A reference that would make more than 300 slides is not built; the operator is told how many it would be and asked to narrow it. Test.
7. **Fix (low): Import can be started twice.** Ignore a second import while one is running or waiting for the replace answer, and disable the button in that state. Refuse a file larger than 64 MB before reading it, in plain words. Tests at model level.
8. **Fix (low): a scripture item whose translation is missing blocks Next for the rest of the service.** Keep the stop and the message the first time. A second Next on the same item within the same stay skips to the next playable item, and the message says so. Test for keyboard path; it is the same command path for MIDI and remote.
9. **Check, then fix if real:** `referenceText(of:)` formats stored ranges with the default versification and the text is parsed again against the primary translation's table. With a translation on VI1925 numbering, check a whole-chapter range and a psalm with a title verse for a round trip that changes the bounds. Item 2 removes the round trip for refresh; make sure no other path depends on it. Report what you found either way.
10. **No code change:** the slide count of a stored passage depends on the audience theme and the verses-per-slide setting at the time it is opened. Record it as a known issue and add a line to the hands-on checklist.

## Rules

- No git state changes. No advisor tool. Do not request full computer control.
- Do not edit `docs/UI`, `docs/adr`, `AI/specs`, the vendored `sdk/` folder, or existing test files.
- No migration is expected. If you think one is needed, stop and say why in the report.
- Never open the owner's real library under Application Support or the local MySQL server. If you launch the app: your own uniquely named scratch folder, a temporary `--library`, `--silent-audio`, stop only processes you started, nothing left in the home folder.
- No real Bible text added; invented fixture text only. No assertions on wall-clock time.
- The repository is public: no user names, home paths, computer names or e-mail addresses in any file.
- Docs: `docs/16-known-issues.md` (new entries after the last one), `docs/17-change-log.md`, `docs/hands-on-checklist.md`, and the feature spec `docs/features/LIB-004c-scripture-interface.md` where behaviour changed.
- Finish with `./scripts/check.sh`; report its exit status and test count truthfully. Run the new tests three times.
- Report to `AI/reports/FIX-F-report.md`: per item what changed, the tests added, whether each test was seen failing first, what is not verified.
