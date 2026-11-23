# UI-007f report: Screens features on v15

Feature IDs SC-25, SC-31 (signal chain), SC-51 (per-screen Look), key destination label. Brief `AI/specs/UI-007-features-on-v15.md`, UI-007f row. Model: Sonnet. Base 0f89ce3. Levels: **Implemented** and **Unit Tested**. Nothing touches a card or sends video; nothing is Simulated-verified beyond the unit tests, and nothing is Hardware Verified.

## Built

1. **Key destination label** (Implemented, Unit Tested). `SignalMapPresenter` gives a key tile the key note (`connectedKeyNote`); with none typed it shows the fill's note, exactly as before (an existing test requires that). A "Key goes to" field under the selected keyed screen (primary and each keyed mirror) edits it.
2. **Signal chain** (Implemented, Unit Tested). Per destination, the operator adds, names, retypes the kind of, reorders and removes boxes (enclosure, converter, other; at most 12, 120 characters each; pure rules in `SignalChainEditing`). The map draws up to three boxes between a connector (or display or window) and its "Connected to" node, each saying "Enclosure/Converter/Other · typed by you"; more show as "+N more". A key tile carries no chain (one chain per destination, drawn on the fill/output/display tile). The section is headed "Your notes on the signal path ... none of this is detected or checked". Spoken labels say "typed by you".
3. **Per-screen Look** (Implemented, Unit Tested). A pop-up "Look for this screen" (Follow the show's Look, or any Look). A screen with its own Look composes with it; others follow the global Look; changing the global Look does not move a screen that has its own; deleting a Look clears it (in memory at once, in the store by `deleteLook`); the Screens list row shows "Look: name" only for a screen that has its own, and the section states which Look is in use and why. Choosing is an explicit operator action; nothing is chosen by default. It republishes through `onAppearanceChange` (one call, no output re-plan), exactly as `selectLook` does. A Theme or Layers edit on a screen edits the Look that screen uses.

## Not built / left

- Edit's canvas preview (`EditCanvasChrome` -> `EditPreviewScene`) still draws with the show's Look, not a screen's own: both files belong to UI-007c's area (known issue below).
- Key label and chain edits on a mirror that is not keyed: the key field is offered only where the destination is keyed.
- Still not storable (no new fields were needed): nothing missing in storage.

## Tests (written first, seen failing for the right reason)

`UI007f_ScreenLookTests` (13), `UI007f_ScenesDigestTests` (1), `UI007f_SignalMapNotesTests` (6), `UI007f_SignalChainTests` (5). The first run of the Look and notes tests failed to compile for the missing API (`ScreenLooks`, `screenLooks:`, `screenLookOverrides`, `setScreenLook`, `SignalTile.chain`). The digest was recorded on unchanged code (publications 29, `86933eae...a028`: FIX-Q sequence, global Look with theme, layers and three props, audience, stage and keyed broadcast) and passes after the change, also with an empty override map; the FIX-Q and SYS-015 digests pass unchanged. `SignalChainEditing` (small pure helper) was written before its tests, not after failing ones.

## Shared-file lines (all additive, commented UI-007f)

- `PublishedScenes.swift`: init parameter `screenLooks: [UUID: Look] = [:]`, one line in the loop. `ImageAvailability.swift`: the same parameter on `pathsInUse`.
- `SettingsModel.swift`: `screenLook(for:)` resolves the screen's own Look; new `screenLookOverrides`, `screenLookSummary(for:)`, `setScreenLook(_:forScreen:)`; `deleteLook` clears a chosen Look from `profiles`; `editScreenLook` edits the used Look. None of FIX-V's remove-screen path was touched.
- `OutputEngine/SignalMapPresenter.swift`: `SignalTile.chain` (defaulted), key note, chain.
- `AppModel.swift`: `screenLookOverrides` plus `screenLooks:` at four composition sites and `pathsInUse`; four `currentLook?.screenLook(...)` lines now call `screenLook(for:)`. `AppModel+Program.swift`: the live context counts per-screen Looks and themes. Not touched: SDI adapter, renderer, scheduler, key monitor, `KeyRouting`, `SettingsModel.removeProfile`.
- New: `OperatorCore/UI007f_ScreenLooks.swift`, `UI007f_SignalChainEditing.swift`, `App/Sources/ScreensNotes.swift`. Edited own files: `ScreensDetail.swift` (one line), `ScreensMode.swift` (row tag and label), `ScreensMap.swift`, `ScreensComponents.swift`.

## Rectangle table

Not re-measured (the Mac's screen may be locked; no capture was run). The designed rows are unchanged in structure: the new section is added below the keyed previews, inside the scroll, and the map row adds boxes only when a chain was typed. A library with no chain and no own Look draws the same rectangles as before, except that the list row's role badge row gains nothing unless a screen has its own Look. **Rectangle status: not verified.**

## Docs entries for the coordinator

Change log: UI-007f: Screens: the key connector has its own "connected to" label (blank shows the fill's), a typed signal chain per destination drawn on the signal map as the operator's own note, and a Look per screen (a screen with its own Look keeps it when the show's Look changes; deleting a Look returns the screen to the show's Look). Unit Tested; no hardware; hands-on not tested.

Known issues: (1) Edit's canvas preview of a screen with its own Look follows the show's Look. (2) A note or chain label typed in the new fields is committed on Return or when the field loses focus; switching screen with uncommitted text loses it. (3) The map shows at most three chain boxes per path; the rest are in the settings list. (4) A stage screen with its own Look takes it only for which props show. (5) Screens' Theme and Layers rows still say "in the current Look"; for a screen with its own Look they edit that Look.

Hands-on checklist: Screens, select a keyed broadcast screen: type a key label and press Return (the key tile shows it; blank shows the fill's). Add a chain (enclosure, converter), name and reorder it: the map shows the boxes with "typed by you". Choose a Look for one screen: its row shows "Look: name"; select another Look for the show: that screen does not change, the others do; delete the Look: the screen follows the show's Look again. Relaunch: all kept. Dark and light, VoiceOver.

Feature spec updates (`docs/features`, OUT): SC-25, SC-31, SC-51 and key label built (Unit Tested).

## Checks

`WF_DERIVED_DATA=<own folder> ./scripts/check.sh` three runs. Run 1: 3286 tests, only `MIDIRouterTests` and `SearchTests` (timing, under load) failed. Run 2: all 3286 package tests passed; the app build then failed on my own error (`ScreenLooks.Summary` init not public), fixed. Run 3: 3286 tests, only `MIDIRouterTests` (timing) failed, so the check stopped at exit 1 before the app builds. Those suites alone with `ToolProcessRunnerTests`, `ScriptureLibraryTests` and `SearchTests`: 60 tests passed. Debug build by hand (xcodegen, xcodebuild): exit 0. Release build by hand: exit 0. Test count: 3286 (3,258 at base plus 28 new... counted by the runner as 3286 including parameterised cases).

## Not verified

The Screens screens, the pop-up, the commit-on-Return fields, the map with a chain, the list tag, dark and light, VoiceOver, focus order: built and compiled, not run hands-on. Rectangles not measured. No SDI hardware or signal: the chain and key label are typed text only. Live behaviour of a per-screen Look with real outputs was exercised only through `PublishedScenes` and `SettingsModel` in unit tests.
