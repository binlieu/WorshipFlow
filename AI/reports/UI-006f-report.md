# UI-006f report: Screens mode features the design draws and the app lacked

Feature IDs SC-03 (Add screen), SC-40 (Remove screen), SC-21 (Identify screens). Brief `AI/specs/UI-006-mode-features.md`, Screens row. Levels: **Implemented** and **Unit Tested** (pure rules and the settings model, with a real in-memory store). Nothing here touches a card or sends video: **not** Hardware Verified, not Live-Service Verified. The overlay windows and the buttons were built and compiled; they were not exercised hands-on (see "Not verified").

## Ranked list

| # | Candidate | Operator gain | Needs | Size | Decision |
|---|---|---|---|---|---|
| 1 | Add screen (SC-03) | a fourth screen (lobby, overflow) without editing the library file | an additive method on `SettingsModel`; profiles are already stored as a replace-all set | small | built |
| 2 | Remove screen (SC-40) | drop a screen that is no longer used | same, plus keeping Looks consistent | small | built |
| 3 | Identify screens (SC-21) | see which physical display is which before choosing a destination | AppKit overlay windows, a pure label function | small | built |
| 4 | Per-destination "Connected to" label (key tile has its own) | the key tile no longer repeats the fill tile's label | new stored field | small | not built: migration |
| 5 | Enclosure and converter chain labels (SC-25, SC-31) | draws the Thunderbolt and SDI-to-HDMI nodes | new stored field | medium | not built: migration |
| 6 | Per-screen Look pop-up (SC-51) | pick a Look for one screen | Look model change (Looks switch every screen) | large | not built: model change |
| 7 | Pixel format, colour, embedded audio, failure choice (SC-45, 46, 47, 53) | | engine and DeckLink conversion work; the app cannot truthfully offer them | large | not built |
| 8 | Schedule-lead statistic (SC-63) | | a new measurement in the scheduler, which FIX-T is changing | medium | not built |
| 9 | Notes layer (SC-52) | | must never exist on audience or broadcast screens | n/a | never |

## Built

**Add screen.** A button at the right of the list header (the design's place). The new screen is named "Screen N" (smallest free number), role Audience, destination Window, and **off**: adding a screen cannot put a picture on a projector, a confidence monitor or an SDI output by itself; the operator picks the destination and turns it on. It is selected after adding. It is written like every other profile change (`persistProfiles`, retried and reported by the write chain) and the outputs are re-planned through `onProfilesChange`. A screen with no Look entry follows the Look entry of its role (existing rule), so it looks like its role's screens. Tests: `UI006f_ScreenListEditingTests` (name, off, window, free-number rule), `UI006f_SettingsModelScreenTests.anAddedScreenIsKeptAndSurvivesARelaunch`.

**Remove screen.** A ghost button at the right of the selected screen's header, with a confirmation ("Its output stops and its destination, mirrors and notes are forgotten. This cannot be undone. Your slides and media are not touched."). The last screen cannot be removed (the button is disabled and says why). The output coordinator already stops a removed screen's outputs and drops its faults. Looks: a screen with no Look entry of its own follows the first screen of its role that has one, so deleting that entry would have changed a surviving screen; the entry moves to the first surviving screen of the role when none has one (`ScreenListEditing.look(_:afterRemoving:before:)`), and the changed Looks are written. The selection moves to the neighbour. Tests: removing keeps order, last screen kept, selection, Look hand-over (three cases), and after a relaunch the screen is gone and the surviving screen still has the same Look. The design colours this button red; the plan reserves red for on air, so it is muted. Not undoable (screen settings are not undoable anywhere in the app); hence the confirmation.

**Identify screens.** A button in the signal map's header (the design's place). For three seconds a label window per connected **display** says: the screen name(s) set to that display (primary or mirror destination, with the role), or "Operator display" (plus the screens set to it, if any), or "No screen is set to this display". It is offered **only while the screens are closed**: the labels would cover what the outputs show, and a label must never appear over a live projector. When the screens are open the button is disabled and its help and accessibility hint give the reason. Only displays are labelled: an SDI connector has no display, and nothing sends video to a card (the button's help says so). The labels ignore the mouse, hide by one scheduled call (no timer exists while no labels are shown; KI-190 respected), and are closed by the next press. Tests: the label rules and the allowed-only-when-closed rule (`UI006f_ScreenListEditingTests`). The overlay windows themselves are AppKit and were not run (see below).

## Not built and why

Rows 4 to 9 above. Row 4 and 5 are migrations (below); row 6 needs the Look model to hold a Look per screen; row 7 and 8 are engine features and 8 is in code FIX-T is changing; row 9 is forbidden.

## Needs a migration (fields I would add)

- `ScreenProfile.connectedTo` is indexed per destination (0 primary, n+1 mirror n); an SDI screen with Fill + Key has one destination for two connectors. To label the key tile separately: add `connectedToKey: String?` per destination (or change the array to `[DestinationNote]` with `fill`, `key`).
- Enclosure and converter nodes (SC-25, SC-31): per destination `chain: [ChainNode]` where `ChainNode` is `{kind: enclosure | converter | other, label: String}`, typed by the operator, labelled "typed by you".
- Per-screen Look (SC-51): `Look` keyed per screen (`screenLookID: UUID?` on `ScreenProfile`, or a per-screen selected-Look table).

No schema change was made: profiles are one JSON set in the existing table.

## Shared-file lines

- `Packages/WorshipFlowKit/Sources/OperatorCore/SettingsModel.swift`: two additive public methods, `addProfile()` and `removeProfile(_:)` (about 25 lines, next to `updateProfile`, commented "UI-006f"). They need the private `persistProfiles` and `persistLook`, which is why they are in that file; the rules are in the new `UI006f_ScreenListEditing.swift`. No existing method changed.
- No other shared file edited. `SDIProviders.swift`, the adapters, renderer and scheduler were not touched.

New files: `Packages/WorshipFlowKit/Sources/OperatorCore/UI006f_ScreenListEditing.swift`, `Packages/WorshipFlowKit/Tests/OperatorCoreTests/UI006f_ScreenListTests.swift` (15 tests), `App/Sources/ScreensIdentify.swift`. Edited own files: `ScreensMode.swift`, `ScreensMap.swift`, `ScreensDetail.swift`.

## Rectangle table

Not re-measured: `scripts/compare-rects-screens.py` needs a capture of the app (`scripts/design-capture-screens.sh`) and the Mac's screen may be locked; and the design-map still lists the three buttons as "room kept" (`design-map-screens.json` was not extended). The three buttons were put at the design's places (list header right, map header right of Rescan, detail header right of Stop output), but the widths are not matched: "Add screen" has an icon and the 22 pt height of the design is not applied (the shared button is 26 pt). Remove screen and Identify screens use the shared button style whose text is 1 to 2 % narrower than the mockup, as for every other button. The kept room widths (114.8 and 110.2 pt) were replaced by the real buttons, so the header text and Stop button positions can move by a few points. **Rectangle status: not verified.**

## Docs entries for the coordinator (verbatim)

Change log:
> UI-006f: Screens mode: Add screen (new screen starts off, in a window), Remove screen (asked first, last screen kept, Looks keep their entries), Identify screens (labels on every connected display for 3 s, only while the screens are closed; displays only, no SDI). Unit Tested; not hands-on tested.

Known issues:
> KI (UI-006f): Identify screens labels displays only; an SDI output cannot be identified without sending video to the card, which the app does not do for a label.
> KI (UI-006f): Remove screen is not undoable (it is confirmed first). A removed screen's stage layout choice stays in the stage settings as an unused entry.
> KI (UI-006f): the design's red Remove screen is muted (red is only for on air); the new buttons' widths and the list header's 22 pt button height are not matched to the mockup.
> KI (UI-006f): a per-destination label (key tile), enclosure and converter nodes and a per-screen Look need a migration (fields above).

Hands-on checklist:
> Screens: press Add screen (a "Screen N" appears, off, in a window; select it and choose a destination, turn it on). With the screens closed press Identify screens: every display shows a label for three seconds (operator display, a screen's name, or "No screen is set to this display"). Open the screens: the button is disabled and says why. Select a screen and press Remove screen: Cancel keeps it; Remove deletes it and selects its neighbour; with one screen left the button is disabled. Relaunch: the list is as left. Dark and light. VoiceOver reads the three buttons.

Feature spec updates (`docs/features`, Screens/OUT): add SC-03, SC-21, SC-40 as built (Unit Tested), SC-25/31 and per-screen Look as needing a migration.

## Checks

`WF_DERIVED_DATA=<own folder> ./scripts/check.sh` ran the package tests: 3055 tests in 483 suites; the failures were only the known timing tests under load (`ToolProcessRunnerTests.aClientThatHangsIsStopped`, `MIDIRouterTests` ordering and polling). A first run also failed `UI005i_InterFontTests` because my overlay used `.system(size:)`; fixed (the shared `.wf` styles). Those suites alone, with the new ones: 56 tests in 6 suites passed. The check stopped at the package tests (exit 1) before the app builds, which were then built by hand (Debug and Release); results are in the final message.

## Not verified

The overlay windows (placement on each display, the three-second hide, the labels on a second display, behaviour with a fullscreen operator window); the confirmation dialog and the three buttons on screen (look, dark and light, focus order, VoiceOver); adding and removing with the simulated card and with mirrors; the rectangle table (above). Untracked dependencies (`Vendor/DeckLinkSDK/`, `Bibles/`, `TestData/`, `TestMedia/`) are absent in a worktree, so tests that need them are skipped or not run.
