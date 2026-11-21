# FIX-E: fixes from the independent review of CUE-002b

Feature IDs: CUE-002b, CUE-003, CUE-004. Model: Sonnet. Owner of files: this task alone.

The independent review of CUE-002b (2026-11-21) found no critical defect, two high and several lower ones. This brief lists them with the decision taken for each. Work test-first: for every item marked **Fix**, write the failing test, see it fail for the right reason, then change the code. Put new tests in new files named `FIXE_*.swift` in the existing `OperatorCoreTests` target. Do not weaken or delete any existing test.

## Items

1. **Fix (high): a failed revoke is silent and the device comes back.** `LibraryTokenStore.writeProblem` is never read. Revoke and Revoke all must be written before they are reported as done: await the write (or flush straight after), retry a failed write, and if it still fails tell the operator in plain words that the revoke is not saved and the device may return after a restart. The in-memory cache must still refuse the token at once. A pairing whose write fails must also be reported. Tests: a store whose delete throws produces an operator-visible problem; after `stopRemote`/`startRemote` with a successful delete the token is still refused; a revoke is on disk by the time `revoke` returns.
2. **Fix (high): Blackout, Clear and Clear all do not cancel a macro's waited steps.** Today only Stop does. Decision: Blackout on, Clear, Clear all and Stop, from any source, drop every pending waited step of every running macro or scheduled event, and the activity list says so ("cancelled: N waiting steps"). Blackout off cancels nothing. Test: `[Next, wait 30 s, Next]`, then Blackout, then advance the test clock 30 s: the slide has not moved and Blackout is still on. Same for Clear and Clear all.
3. **Fix (medium): switching the remote server on and off can interleave.** `remoteServer` is assigned only after `await server.start()`. Serialise start, stop and port change through one chain so that the last request wins and the saved setting always matches whether a server is listening. Tests with a fake server whose start suspends: on then on again starts one server; on then off during the start ends with nothing listening and the setting off; a port change during a start ends listening on the new port only.
4. **No change: a Next that crosses into another playlist item runs after the macro's other steps.** Already recorded as KI-087. Leave the behaviour; make sure one existing or new test pins the order so a later change is deliberate.
5. **Fix (medium): MIDI and remote commands still move the show during a Hardware Test.** Decision: while the Hardware Test runs, commands from MIDI, the remote server and the schedule are refused; operator buttons and keys are unaffected. The remote answers 409 with a reason, the activity list records the refusal. Tests for each source.
6. **Fix (small): an event that falls due during a Hardware Test.** Keep the notice, and also list it with the missed events so it is visible after the test ends. Test.
7. **Fix (low): the remote macro endpoint answers 200 when a macro step failed.** Return the same rejection as transport commands do. Test.
8. Covered by item 1.
9. **Fix (low): `refreshRemote()` calls `getifaddrs` every second on the main actor.** Compute the addresses when the server starts and when the network path changes (`NWPathMonitor`), not on the one-second tick. Nothing runs when the server is off.
10. **Fix (low):** remove the wake observer in `shutdown()`.
11. **Fix (low): `CUE002b_SlideActionsTests.swift:111` waits 200 ms of wall-clock time.** Give tests something to await (for example a `reloadSettled()`), and use it there. You may edit that one test only to replace the sleep; the assertions stay.
12. **No change:** no debounce on MIDI input. Record it as a new known issue to be checked with a real pad.

## Rules

- No git state changes (no add, commit, stash, checkout, reset). No advisor tool. Do not request full computer control.
- Do not edit `docs/UI`, `docs/adr`, `AI/specs`, the vendored `sdk/` folder, or any test file other than as item 11 allows.
- No new migration is expected. If you think one is needed, stop and say why in the report instead.
- If you launch the app at all: temporary `--library` in your own uniquely named scratch folder, `--silent-audio`, never the owner's real library under Application Support, leave nothing in the home folder, and stop only processes you started.
- No assertions on wall-clock time.
- The repository is public: no user names, home paths, computer names or e-mail addresses in any file.
- Finish by running `./scripts/check.sh` and report its exit status and test count truthfully.
- Update `docs/16-known-issues.md` (new entries after KI-087), `docs/17-change-log.md` and `docs/hands-on-checklist.md` where behaviour changed.
- Write the report to `AI/reports/FIX-E-report.md`: per item what changed, the tests added, what was not verified.
