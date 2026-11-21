# UI-005 audit: Screens mode, Cues mode, output Looks picture

Read-only audit. Nothing was built, run or edited; the app was judged from its code and the newest screenshots (`AI/reports/UI-002-screens*.png`, `UI-003-screens.png`, `CUE-002b-cues*.png`). `UI-003-cues.png` is stale (shows the old "arrive in a later version" placeholder); `CUE-002b-cues.png` is the current Cues mode. The app screenshots are a shorter window than the design's 1440 x 900, so the lower half of Screens is judged from code.

Design sources: `docs/UI/screens/03`, `11`, `06`, `07`; `docs/UI/mockups/03-screens-outputs.html`, `06-cues.html`, `07-output-looks.html`, `ui.css`, `ui.js`; `README.md`, `design-tokens.json`. All design sizes below are CSS px = points at 1x (the mockups are 1440 x 900 pt). Gap sizes: **S** = constant or style change; **M** = layout rework of one view; **L** = missing feature needing model or engine work.

"Out of the other agent's scope" (not reported): the product-name rename, pill borders, the toolbar (title/subtitle text, mode switcher, timers, chips) and the transport bar's own styling.

Colour tokens are in the asset catalog and match `design-tokens.json` (a test guards it), so no colour gap is listed unless a view uses the wrong token.

---

## A. Cross-screen findings (apply to Screens and Cues)

| ID | Element | Present | Design | App | Gap |
|---|---|---|---|---|---|
| X-01 | Segmented controls (Role, Fill alpha) | partly | `.seg`: track `surface-2`, 1 px `border`, radius 7, padding 2; selected segment `surface-3` with 1 px `border-strong` inset, text stays `text`, 12/500, segment padding 4x11 (ui.css `.seg`) | native `Picker(.segmented)`: selected segment is filled system-accent blue with white text (visible in `UI-002-screens.png`, "Broadcast" and "Premultiplied"). `ScreensMode.swift:428`, `ControlPanels.swift:416` | M (one reusable component, used in Screens, Cues, Show) |
| X-02 | Pop-up menus and text fields | partly | `.field`: 26 high, fill `bg`, 1 px `border-strong`, radius 6, padding 0 8, 12 pt, chevron `muted` at right | native `.roundedBorder` `TextField` (white fill in light) and native `Picker` menus (`ScreensMode.swift:426, 432, 451, 476`). Visible in light screenshot: name field is white, pop-ups grey capsule | M (a shared `WFField`/`WFMenu` style) |
| X-03 | Checkbox | partly | 14 x 14, radius 3, 1 px `border-strong`; checked = fill `blue`, check in `on-brand` | native `.checkbox` toggle (`ScreensMode.swift:496`), system blue (`#0A84FF`-ish, not the `blue` token `#70B8FA`) | S |
| X-04 | Badge (SIMULATED, role, MACRO) | partly | `.badge`: 10/700, tracking .06em, **radius 4**, padding 1x6, 1 px currentColor (ui.css `.badge`) | `Badge` 10 bold, tracking 0.6, padding 2x6, **radius 3** (`Components.swift:46-49`) | S (radius 4, padding 1) |
| X-05 | `.pill` (action-row screen tags AUD/BRD/STG, "Macro . 5 actions") | no (a Badge is used instead) | capsule 20 high, 11/600, mixed case allowed, 1 px `border-strong` outline text in role colour (ui.css `.pill`) | `ScreenTags` draws `Badge` (rounded rect radius 3, 10 bold) (`CueSupport.swift:60`); the macro chip is a `Badge` in capitals "MACRO . 3 ACTIONS" (`CuesEditors.swift:46`) | S |
| X-06 | Transport bar in Screens mode | differs | README "Window anatomy": Edit, Stage, Screens drop the transport bar; `03-screens-outputs.html` uses `.win.nobar` (52 + 1fr, no bar) | transport bar shown in every mode ("an operator in Screens can still advance the service", `ContentView.swift:89-94`; visible in `UI-002-screens.png`) | S to hide, but it is a decision (Q4) |
| X-07 | Window ground / panes | yes | sidebar `surface`, centre `bg` | matches (`ScreensMode.swift:42, 91`, `CuesMode.swift:90`) | n/a |
| X-08 | Font family | partly | README: SF; mockups use Inter as stand-in, so widths differ slightly | system font | n/a (note only) |
| X-09 | Buttons (`HeaderButtonStyle`) | yes | `.btn` 26 high, radius 6, 12/500, `surface-2`, `border-strong` | `Components.swift:160-171` matches | n/a |
| X-10 | Key hint | yes | `.kbd` 10/500 mono, radius 3, padding 0 4, line height 14 | `KeyHint` 10 semibold mono (weight 600 vs 500), radius 3 (`Components.swift:122-124`) | S |

---

## B. Screens mode (design 03 and 11)

### B1. Left column (design 300 wide, `surface`)

| ID | Element | Present | Design value | App value (file:line) | Gap |
|---|---|---|---|---|---|
| SC-01 | Column width | yes | 300 (`.body` grid-template-columns) | 330 (`ScreensMode.swift:27, 86`) | S |
| SC-02 | Header row | partly | `.sec row`: padding 10x12, "SCREENS" `.h` + button "+ Add screen" 22 high with plus icon, `border-top` none, hairline below | header 48 high, padding 14 (`:79`), hairline below; button is "Close screens"/"Open screens" (`:73-77`) | S for size |
| SC-03 | **Add screen** button/feature | **no** | creates a new screen profile | the app has no way to add a screen (no `addProfile` anywhere; three default profiles from `DefaultScreenProfiles.swift:15-17`) | L (model API, default naming, persistence, coordinator starts it) |
| SC-04 | Open/Close screens | not in the design | (design has no global start/stop here; per-screen toggle plus "Stop output" only) | button at `:73-77` | not in the design |
| SC-05 | Row layout | partly | `.scr`: padding 10, radius 8, grid 96 (thumb) + 1fr, gap 10, **vertically centred**; selected = `surface-3` fill, no border | `HStack(alignment: .top)`, thumb 88 (`:98`), spacing 12 (`:97`), padding 8 (`:110`), selected also has a 1 px `border-strong` outline (`:112`) | S |
| SC-06 | Row text | partly | name `<b>` 13 bold with the **toggle on the same line**; role badge below; destination line 11 muted `SDI 3 . 1080p59.94` | name 14 semibold (`:100`); toggle sits at far right, vertically centred top of the card (`:106`); destination text = device display name + mode, e.g. "Simulated SDI card (4 connectors), connect..." wrapped and truncated to 2 lines (`:103, 120-123`) | S (font), M (destination text should be `SDI <n> . <mode>`, with `SDI 1 + 2 . Fill + Key` for a pair) |
| SC-07 | SIMULATED badge in each row | not in the design | design shows no per-row badge; only the "Simulated" badge in the Signal map header and the verification card | extra badge in every row (`:102`) | not in the design (it is the honest status rule in README principle 5; keep or move to a dot) |
| SC-08 | Toggle | yes | 30 x 18 pill, on = `cyan` | native switch tinted cyan (`:107`), 38 x 22 | S (accept native) |
| SC-09 | Thumbnail | partly | live tile in `.thumb` 16:9, radius 4, 1 px `border`; Broadcast tile on checkerboard with plate | `LiveScreenPreview` radius 3, `.quaternary` stroke (`Thumbnails.swift:224-225`); broadcast shows text only on checker (no plate, see LK-12) | S |
| SC-10 | Sample screen set | n/a | Sanctuary / Confidence / Livestream graphics / Lobby | Audience / Stage / Broadcast (defaults) | n/a (sample data only) |
| SC-11 | Verification card | partly | `.card`: **`surface`** fill, 1 px `border`, **radius 10**, padding 10, 12/16; head: warning-triangle icon 15 + "Verification" bold 13; body 12 `muted` with "Hardware Verified" in `text` bold; buttons "Run signal test..." (`.btn`) and "Export log bundle" (`.btn.ghost`, no border, no ellipsis); pinned to the bottom with a flexible gap above | fill `surface2`, radius 8 (`:152`), padding 12 (`:151`); icon `checkmark.shield`, plus a verification-level Badge at right (`:137-140`); body not bold-emphasised (`:142`); both buttons bordered and with ellipsis (`:144-146`); optional export message line (`:149`) | S |
| SC-12 | Verification wording | differs | "...simulated card. It becomes **Hardware Verified** after a signal test on the real enclosure, card, converters and ATEM." | "...It can become Hardware Verified only after a signal test on the real card and the equipment after it." (`ScreensPresentation.swift`) | S (copy). The app's wording is the more cautious one |

### B2. Centre: Signal map header and diagram

| ID | Element | Present | Design value | App value (file:line) | Gap |
|---|---|---|---|---|---|
| SC-20 | Header bar | partly | `.bar`: padding 8x14, hairline below; title 17/700; Simulated badge; note 12 `muted`; buttons "Rescan devices" (loop icon) and **"Identify screens"** | title 18 bold (`:171`), note 11 caption (`:174`), only "Rescan devices" (`:176`); no hairline under the bar | S |
| SC-21 | **Identify screens** | **no** | button | none (no identify function in the app) | M (put a large labelled card on every output for 3 s; needs an overlay layer in the coordinator, honours "never expose" rules) |
| SC-22 | Diagram structure | **partly / differs** | 9-column grid: Mac node 150 -> wire 28 -> **Thunderbolt PCIe enclosure node 150** ("carries PCIe, not video") -> wire 28 -> **connector tile (1fr)** -> wire 28 -> **converter node 150** ("SDI -> HDMI, active 3G converter") -> wire 28 -> **destination node 170** ("ATEM input 5 . key fill source"). Four rows, one per SDI connector, in connector order. The Mac and enclosure nodes span all four rows. | Mac tile (190 wide, `:205`) -> one 28 x 1 wire (`:181`) -> a column of device blocks and tiles, each with at most **one** "Connected to <typed note>" box (`:256-265`). No enclosure node, no converter node, no multi-hop wire chain. | L (see Q1) |
| SC-23 | Wires | partly | 2 px high `border-strong` lines, 28 wide, joining every node | 1 px high, 28 wide between Mac and tiles (`:181`), 22 wide to the note (`:257`); no wire between Mac and the individual tiles | S |
| SC-24 | Mac node | partly | `.node`: 1 px `border-strong`, radius 8, padding 8x10, `surface-2`; icon 20, **"Mac mini M4"**, sub "WORSHIPFLOW render engine", mono "4 compositions . 0.64 ms" (composition count and render time) | border `border` not `border-strong` (`:207`), padding 12 (`:205`), width 190 vs 150; title = host model without chip (`map.hostTitle`), sub text 12 (`:202`), mono line = "N of M screens running" (`:203`) | S; the render-time readout is L (a mean render time is not measured, see SC-45) |
| SC-25 | Thunderbolt enclosure node | **no** | node with cable icon | none. The app cannot know about an enclosure (see ambiguity A-3) | L, or drop (Q1) |
| SC-26 | Connector tile | partly | `.conn`: **1.5 px border in the role colour always**, radius 8, padding 6x10, `surface-2`; 20 px **BNC ring icon** (3 px ring + dot) in role colour; **title 12 bold "SDI 1 . Fill"**, sub 11 `muted`; role icon right-aligned (layers for fill, key for key, monitor for audience, stage house for stage) | width **fixed 300** (`:251`), padding 12 x 7 (`:250`), border 1 px `border`, 2 px role colour only for the selected screen (`:253`); SF symbols `circle.circle`/`square.fill.on.square`/`key`/`circle.dashed` at 14 on the left (`:235, 271-280`); title 13 semibold (`:238`), sub 12 (`:241`); no trailing role icon | M (restyle plus BNC glyph) |
| SC-27 | Tile titles | differs | `SDI 3 . Sanctuary` / sub "Audience"; `SDI 1 . Fill` sub "Livestream graphics"; `SDI 2 . Key` sub "paired with SDI 1" | `SDI 3 . Output` / "Audience"; fill sub "Livestream graphics . paired with SDI 2"; key sub "... paired with SDI 1" (`SignalMapPresenter`) | S |
| SC-28 | SIMULATED badge on every tile | not in the design | design: one badge in the header | a badge per tile plus one per device block (`:215, 239`) | not in the design (visual noise: owner decides) |
| SC-29 | Fill/key pairing display | partly | both tiles in the Broadcast colour with a layers icon (fill) and key icon (key), adjacent rows, subtitle "paired with SDI 1" | both outlined in `roleBroadcast` only when selected; icons differ; pairing text is present | S |
| SC-30 | Unused connector | not in the design | design shows four connectors, all used (SDI 4 = Stage) | "SDI 4 . Unused / Not used . key position of its pair" tile with dashed circle (`:273`) | not in the design (keep; the design has no empty-connector case) |
| SC-31 | Converter and destination node content | **no** | converter "SDI -> HDMI active 3G converter" and destination "ATEM input 5 key fill source", "Projector sanctuary", "Stage monitor floor TV" | one typed free-text note per destination ("Connected to", `ScreenProfile.connectedTo`), shown as a single box | L for the chain; S if the single note box is simply restyled (see Q1) |
| SC-32 | Route lines and device header | not in the design | none | device header "Simulated SDI card (4 connectors) . 4 connectors" (`:214`), route lines "Connectors 1 and 2: fill on 1, key on 2 (reported by the card's simulator)" (`:218`), group "Displays and windows" with Window/Display tiles and their paths (`:222-227`) | not in the design (these are real, useful, and honest; owner decides where they go) |
| SC-33 | Footer row under the map | partly | left: "DeckLink Duo 2 . four 3G-SDI connectors . HD only, no 4K." 12 `muted`; right: a **two-option segmented control** "4 independent outputs" / "Fill + Key broadcast" (selected shown) | left: "Plan for <device name>" (`:296`); right: two bordered buttons "Independent outputs" / "Fill + Key broadcast" that toggle an inline proposal with Apply/Cancel (`:298-306, 311-332`) | M (segmented look, selected state from the current profile layout; keep proposal/Apply because it interrupts outputs) |
| SC-34 | Static spec text "HD only, no 4K" | no | stated as a fact | not shown | S (only if the device reports Duo 2; see ambiguity A-4) |

### B3. Selected-screen settings

| ID | Element | Present | Design value | App value (file:line) | Gap |
|---|---|---|---|---|---|
| SC-40 | Section header | partly | `.bar` no border, title **15/600** ("title-3"), role badge, status pill "Running (simulated)" (cyan), right: "Stop output" (btn) and **"Remove screen" (ghost, `live` colour)** | title 18 bold (`:373`), role badge, status pill 22 high with 12/500 text (`:385-401`), right: Stop/Start output only | S (size) and L for **Remove screen** (no removeProfile; paired with SC-03) |
| SC-41 | Form grid | partly | 2 columns, column gap 28, row min-height 32, label 96 right-aligned 12 `muted`, field flex | 2 columns with gap 24 (`:357`), label 96 (`:419`) but row spacing 12 and rows have no 32 min-height (`:425`); baseline alignment | S |
| SC-42 | Name | yes | `.field` | native rounded TextField (`:426`) | S (X-02) |
| SC-43 | Role | yes | seg, 3 options | native segmented (X-01) | M (X-01) |
| SC-44 | Destination | yes | field "DeckLink Duo 2 - connectors 1 and 2" | native pop-up listing displays, Window, SDI connectors (`ControlPanels.swift:390-404`): label "Simulated SDI card (4 connectors), connectors 1 and 2" | S |
| SC-45 | Video mode + **pixel format** | partly | two fields: "1080p59.94" and "10-bit YUV 4:2:2" | only the mode picker (`:450-456`). `ScreenProfile` has **no pixel-format property**; the renderer produces BGRA 8-bit (`SDIOutput.swift:2, 119`) | L (model field + DeckLink conversion path + hardware proof). Until then a read-only truthful row (Q3) |
| SC-46 | **Colour** row | **no** | "Rec. 709 . video range" pop-up | none; no colour-space setting in the model or the engine | L (or read-only "Rec. 709 assumed", Q3) |
| SC-47 | **Audio** row | **no** | "No embedded audio" pop-up | none; no SDI embedded audio in the engine | L (embedded audio is a separate feature) |
| SC-48 | "Connected to" row | not in the design | the design has no input for this; it appears as diagram nodes | text field "Connected to" (`:436`) and one per mirror (`:510`) | not in the design (this is the only way the typed destination text enters; see Q1) |
| SC-49 | **Fill and key** | partly (wrong place) | right column, first row: **toggle** (30 x 18) + 12 muted "Uses two connectors and two ATEM inputs" | left column, under Destination: a **checkbox** + caption "Uses connectors 1 and 2: fill on 1, key on 2" (`ControlPanels.swift:407-413`) | M (move into right column, toggle style, design caption; "two ATEM inputs" is an assumption about the switcher, keep the app's connector wording) |
| SC-50 | Fill alpha | partly (wrong place) | right column, below Fill and key; seg Premultiplied / Straight, label column aligned | under Destination in the left column, max width 300 (`ControlPanels.swift:416-421`) | M (with SC-49) |
| SC-51 | Look | differs | right column: **a Look pop-up with the name of a Look** ("Lower third only"); Looks are a named preset of layers+theme | pop-up of **themes** ("Default for this screen") for the selected screen inside the current Look (`:475-480`; noted as a deviation in UI-002 report) | M (design intent: choose a Look per screen. See ambiguity A-5) |
| SC-52 | Layers | partly | four checkboxes: Background, Slide, Props, **Notes** | three: Background, Slide, Props (`:481-485`); `LayerKind` has no `notes` (`Look.swift:5`) | L if Notes becomes a layer; see Q5 (design vs the privacy rule) |
| SC-53 | If output fails | differs | a pop-up with options ("Keep the show running, show a warning here") | static text, not a choice, by design (`ScreensPresentation.outputFailureText`, `:487-489`) | S for the look; L if the owner wants real choices (e.g. "go black", "hold last frame"). Q6 |
| SC-54 | Mirror | partly | one `.btn` "+ Add mirror" in the row | mirror list; each mirror a bordered box (`:499-520`) with Remove, destination editor, note field, status line; "Add mirror" button after the list (`:516`) | S (empty state matches; keep boxes) |
| SC-55 | Stage role settings | not in the design | design shows only a Broadcast screen | stage layout picker + "Edit layouts..." + help text replace Look and Layers (`:460-473`) | not in the design |
| SC-56 | Render problems/messages | not in the design | none | warning lines "Left out of this screen: ..." and fault/hidden message (`:361-362, 403-409`) | not in the design (kept: errors must be visible) |

### B4. Stats row and keyed previews

| ID | Element | Present | Design value | App value (file:line) | Gap |
|---|---|---|---|---|---|
| SC-60 | Stat tiles layout | partly | 5 tiles, grid, gap 8, tile `surface-2`, radius 8, **padding 8x10**, value 17/22 mono **bold**, label 11 `muted` | HStack spacing 8 (`:525`), padding 12 (`:541`), value `wfMonoReadout` 17 semibold (`:538`), label **12** (`:539`) | S |
| SC-61 | Stat tile values | differs | neutral values (59.94, 18 440, 2.1 ms) in `text`; only the zero dropped/late in `cyan` | **all** values `cyan`, `warning` when non-zero (`:538`) | S |
| SC-62 | Number format | differs | "18 440" (thin space grouping) | "18440" (`:527`) | S |
| SC-63 | Fifth tile | differs | "2.1 ms **schedule lead . mean**" | "repeated" frames (SDI only) (`:530`); no schedule-lead mean is measured in `FrameStatistics`/`SDIRenderAhead` | L (a new engine statistic; plus keep "repeated") |
| SC-64 | Counter unit for windows | not in the design | "Hz" for display outputs (`:526`) | | not in the design |
| SC-65 | Keyed preview sizes | differs | three thumbs 270 wide, gap 14, 16:9, radius 4, 1 px `outline`; fourth column text | `ScenePreview(width: 320)` clipped by `.frame(maxWidth: 230)` (`:568, 576`) -> ~230 wide, gap 12 (`:553`) | S |
| SC-66 | Preview captions | partly | 11 `muted`; "Composite" bold + "what the keyer produces"; fill/key captions begin with an 8 px **square in the broadcast colour** | 12 pt, title semibold + detail (`:571-574`), no coloured square | S |
| SC-67 | Preview content | **differs** | the lower third sits on a 86 % dark **plate**; fill shows the plate in `#071321` on black; key shows the plate as `#dbdbdb` matte with the text in grey/white | text only with a black outline; no plate, so the key matte is the outline of the glyphs only (LK-12) | L (plate is a theme feature) |
| SC-68 | Explanatory text | partly | "...Set the ATEM keyer to linear key, premultiplied to match 'Fill alpha', and check key polarity with the **calibration slide**..." | "Set the keyer to linear key ... with a test pattern" (`ScreensPresentation.blackIsNotTransparency`); no ATEM naming, no calibration slide | S. A calibration slide does not exist in the app (L if wanted, see Q7) |
| SC-69 | Visibility of previews | partly | always shown for the selected broadcast pair | shown only when the destination is a fill+key pair (`:364`) | fine |

### B5. Things in the Screens mode that the design does not show

`Looks panel` and `Props panel` (`AdvancedSection`, `:604-605`), `Developer` section (simulated card toggle, unplug/replug) (`:607`), the "Images that cannot be read" warning (`:590`), `SDIEnvironmentLine` (driver not installed / no card) (`:596`), `sdiProfileNotice` (`:599`), mirror status lines, mirror notes, preset proposal block. All are real functions. The design has no home for the Look list or the props; owner decides (Q8).

---

## C. Cues mode (design 06)

### C1. Column geometry

| ID | Element | Present | Design | App (file:line) | Gap |
|---|---|---|---|---|---|
| CU-01 | Left column width | yes | 230 | 260 (`CuesMode.swift:16`) | S |
| CU-02 | Right column width | yes | 380 | 372 (`Space.inspectorWidth`, `:20`) | S |
| CU-03 | Centre header | partly | `.bar`: padding 8x14, hairline below, 17/700 title | no bar; the header is an in-scroll row, padding 24 (`:145`), name field 22 bold (`CuesEditors.swift:41`); no hairline | M (bar + 17 pt title; the name remains editable) |
| CU-04 | Centre padding | differs | 14 | 24 (`:145`) | S |

### C2. Left column

| ID | Element | Present | Design | App | Gap |
|---|---|---|---|---|---|
| CU-10 | Section padding | partly | `.sec` padding 10x12, 1 px `border` between sections; label row `.h` 11/600 +6 gap | padding 14 (`:88`), `Divider()` between sections (native hairline) | S |
| CU-11 | Row | partly | `.li` 26 high, 13 pt, icon 15, radius 6, count `muted` 11, selected `surface-3` | 32 high (`:118`), 14 pt (`:113`), icon 18 (`:112`), count 12 (`:115`) | S |
| CU-12 | Macros header "+" | yes | plus icon 12, no frame | `+` 24 x 24 tappable (`:55`) | S |
| CU-13 | Macros list | yes | five sample macros with counts | live macros with counts (`:59-63`) | n/a |
| CU-14 | Slide actions list | differs | **one row per presentation** ("Amazing Grace 2", "Baptism testimony 3") with its own icon (music, film) | one row "Actions on slides" with count of slides having actions (`:71`) | M (a list per presentation or per slide; actions are stored per slide, `SlideActionsEditor`) |
| CU-15 | Control inputs: MIDI row | partly | "MIDI - nanoPAD2" (device name) + `cyan` dot | "MIDI" + dot or "on"/"off" (`:82, 95-100`), icon `pianokeys` vs design `sliders` glyph | S (show device name from `cue.midi.inputName`) |
| CU-16 | Control inputs: **Stream Deck** "later" | **no** | row with grid icon and "later" muted | deliberately omitted ("a control that does nothing is not shown", `CuesMode.swift:3`) | S (disabled labelled row; Q9) |
| CU-17 | Control inputs: "Remote API" "off" | partly | label **"Remote API"**, status `off` muted | label **"Remote control"**, "on"/"off" (`:83-85`) | S |
| CU-18 | Schedule section | not in the design | none | "Schedule / Scheduled events" (`:75-78`) | not in the design (real feature, CUE-003) |

### C3. Centre: macro editor

| ID | Element | Present | Design | App | Gap |
|---|---|---|---|---|---|
| CU-20 | Title chip | differs | `.pill c-muted` "Macro . 5 actions", mixed case | Badge uppercase "MACRO . 3 ACTIONS" (`CuesEditors.swift:46`) | S (X-05) |
| CU-21 | **Trigger field** | partly | `.field`: "Trigger: **F1** . MIDI note C2" (keyboard key **and** MIDI) | text "Trigger: MIDI Note C4 . ch 1" shown only if a MIDI binding exists, 30 high (`:48-51`); no keyboard trigger exists in the cue model (`Macro`, `CueBinding`) | L (key bindings for macros: model, store, KeyRouting conflicts with `ShowShortcuts`) |
| CU-22 | **Test in Preview** | **no** | button with play icon | none; running a macro always acts on the live show | L (a dry-run that applies the effects to Preview only: needs a preview scene path in `CueExecutor`) |
| CU-23 | Run button | differs | `.btn.primary`: brand gradient 135deg, `on-brand` text, 26 high, bolt icon | `TransportButtonStyle` (36 high, `surface-2` with `border-strong`) with bolt.fill (`:53-55`) | S |
| CU-24 | "..." menu | not in the design | none | ellipsis menu holding "Delete macro..." (`:58`) | not in the design |
| CU-25 | Action row structure | partly | `.act`: grid 22 / 150 / 1fr / auto, gap 10, padding **8x10**, border 1 `border`, radius 8, `surface` fill, margin-bottom 6, so ~37 high; number circle **20** (`surface-3`, 11/700); icon 15 + title **13 bold** in a 150 column; detail 13 `muted`; tags at right | HStack spacing 12, padding horizontal 12, **minHeight 48**, number circle **24** (12 bold) (`CuesActionList.swift:33, 50`), icon 18, title **14 semibold width 190** (`:35`), detail 13 | S |
| CU-26 | Row controls | not in the design | none | move up/down, edit (slider icon), delete icons on every row (`:39-48`); the edit popover form (`ActionEditForm`) | not in the design (needed to edit; consider showing on hover) |
| CU-27 | Action detail text | partly | rich: "Worship - full, on Audience and Broadcast"; "Waves - teal.mov, loop, **1.0 s dissolve**"; "Church logo bug"; "Band"; "Service elapsed, from 00:00" | "Worship"; "Welcome, we are starting"; "Service" (`CueActionEditing.describe`) | S (copy: include which screens the Look touches, timer start value) |
| CU-28 | **Start background with loop and dissolve** | no | action shows `loop` and `1.0 s dissolve` | `CueAction.setBackground(assetID:)` has no loop or transition parameters (`CueAction.swift:54`) | L (loop flag and transition belong to the media/background model and renderer) |
| CU-29 | **Stage layout** action | **no** | action 4 "Stage layout - Band" with STG tag | no such `CueAction` case (list in `CueAction.swift:44-62`) | L (needs a per-screen stage layout command through `CueExecutor`) |
| CU-30 | Action kinds | partly | Set Look, Start background, Prop on, Stage layout, Start timer | Look, prop, message, timer start/pause/reset, background, clip, sound, MIDI out, run macro, wait, transport | n/a |
| CU-31 | Add action | partly | `.btn` 26 high: plus 15 + "Add action" + small chevron | outlined menu label, 30 high, 13 medium (`:84-87`) | S |
| CU-32 | Order note | differs | `.card` (`surface`, radius 10, padding 10x12, 12/17): **bold "Order is fixed and visible."** then muted text: "Actions run top to bottom **on one frame boundary**..." warning icon | `CueNote`: no fill, radius 8, padding 12, all muted, no bold lead (`CueSupport.swift:70-82`); longer text saying order is **not** strictly top to bottom (a step that moves the show comes first, a wait splits the list) (`CuesEditors.swift:20`) | S for the look; **conflict** in meaning (A-6) |
| CU-33 | **Playback markers** | **no** | section "PLAYBACK MARKERS - BAPTISM TESTIMONY.MOV": 54 high timeline (`surface-2`, radius 8) with a gradient played portion, a red (`live`) playhead, three yellow (`warning`) marker lines with labels ("Lower third on", "Lower third off", "Fade to background") and a time axis (00:00..03:02, mono 11) | not drawn. `PlaybackMarker`/`MarkerTracker` exist in `CueEngine/PlaybackMarker.swift` but are not referenced by any app code or by `CueModel` (no store, no UI, no wiring to the media player) | L (store markers per clip, feed positions from the media engine, timeline view, marker editing, execution) |
| CU-34 | Empty state | not in the design | none | "Macros and control inputs are not available." (`:23`); "No macros yet..." (`:65`) | not in the design |

### C4. Right column

| ID | Element | Present | Design | App | Gap |
|---|---|---|---|---|---|
| CU-40 | Pane layout | partly | three `.sec` blocks separated by hairlines; the last grows | one scroll view with `Divider`s, padding 14 (`:158-166`) | S |
| CU-41 | MIDI map header | partly | `.h` "MIDI MAP" + `Learn...` button (22 high) | "MIDI MAP" + `Manage...` (`:176`) | S (label; Learn lives on the MIDI page) |
| CU-42 | MIDI map table | differs | real table: header row **INPUT / COMMAND** (11/600 uppercase `muted`, tracking .04em), rows padding 6x8, 12 pt, input mono 11, hairline between rows, a trailing "..." (dots) icon column | list without headers: pattern mono 11 in a 120 column, command 13 (`:183-184`), `Divider` between rows, a conflict triangle instead of the "..." menu | S (header, font 12) and S/M for a per-row menu |
| CU-43 | Pattern text | partly | "Note C2" | "Note D4 . ch 1" (`MIDIText.pattern`) | n/a (channel shown is more exact) |
| CU-44 | Keyboard table | partly | 2-column table, rows padding 6x8, 12 pt, `.kbd` chips | `KeyHint` 96 wide + command 13 pt, `Divider` rows (`:199-203`); the list comes from `ShowShortcuts.all` | S (13 -> 12, row padding) |
| CU-45 | Keyboard list content | differs | `-> or Space`, `<-`, `Return` "Go live with Preview", `B`, `Cmd K` "Clear slide", `Shift Cmd K` "Clear all layers", `Cmd .` "Stop media", `Cmd E`, `Cmd F` | the app lists "esc" for Clear and "shift esc" for Clear all, "Go live with the selected slide" (see `CUE-002b-cues.png`); no Stop media row | S, and a **conflict** between design and app key assignments (A-7) |
| CU-46 | Activity | partly | `.h` "ACTIVITY"; mono 11, line height 18, **24-hour `09:03:11 macro Start worship set`**, a warning line in `warning` colour | 12-hour locale time "9:11:00 AM" (`:217`), `button macro ...` source word first; problem lines are `warning` (`:218`), `source.activityColor` | S (time format `HH:mm:ss`, line height) |
| CU-47 | Activity cap | not in the design | | last 14 lines (`:215`) | n/a |

### C5. Things in the Cues mode that the design does not show

`ScheduleEditor` (scheduled events and "Not run" list), `RemoteSection` (phone pairing, port, QR/address), `MIDISection` (use MIDI, input/output devices, virtual ports, bindings editor with Learn), `SlideActionsEditor`, macro rename/delete with "used by" alert, MIDI Out and Wait actions, step reorder controls. Design shows only "later/off" placeholders for the remote side. Owner decides where the MIDI/Remote pages sit relative to the design's rows (Q9).

---

## D. 07 Output looks vs what the engine produces (1920 x 1080 reference)

All design sizes derive from the mockup `cqw` units on a 1920 px wide output (1 cqw = 19.2 px) and match `design-tokens.json` type tokens. The app values are in the same pixel space (`SceneStyles`, 1080p points). Source: `Domain/SceneComposer.swift` (SceneStyles :9-36; themed/stage/broadcast composers), `Domain/Theme.swift:54-64`, `Domain/StageLayout.swift`.

### D1. Audience (Sanctuary, full-screen lyrics)

| ID | Element | Design | App | Gap |
|---|---|---|---|---|
| LK-01 | Background | radial gradient `110% 100% at 80% 90%`: `#2d7d6c` -> `#123b52` 50 % -> `#050f1c` | solid `#0A0F24` fallback (`audienceBackground`, `SceneComposer.swift:9`; `Theme.mediaFallbackColor`); real background comes from the shared loop or an image | S (default theme colour / generated gradient), M if gradient is a theme background kind (`ThemeBackground` has only media/color/image/transparent) |
| LK-02 | Primary font size | 6.2 cqw = **119 px** (token `lyric` **120/144**) | **84** (`:10`) | S |
| LK-03 | Primary weight | **600** | no weight field in `TextStyle`; font "Helvetica Neue" regular (`:10`) | M (add weight or name a bold face; migration for stored themes) |
| LK-04 | Primary line height | 1.2 | engine default line spacing (not set) | S/M |
| LK-05 | Secondary size, weight, colour | 4.1 cqw = **79 px** (token 80/104), **500**, `#ffd17b` | **64** (`:12`), regular, `(1, 0.86, 0.4)` = `#FFDB66` (`:13`) | S |
| LK-06 | Text effect | soft drop shadow `0 .3cqw 1.2cqw rgba(0,0,0,.6)`, **no outline** | black **outline** 4 / 3 px (`outlineWidth: 4`/`3`, `:11, 14`); `TextShadow` exists in the model but the default does not use it | S |
| LK-07 | Layout | the two blocks are one vertically-centred group; secondary margin-top 3.4 cqw (65 px) | primary frame (0.06, 0.18, 0.88, 0.32), bottom-aligned; secondary frame (0.06, 0.52, 0.88, 0.28), top-aligned (`:15-16`); gap between the blocks is only ~2 % (22 px) | S |
| LK-08 | Title-safe margin | 90 % (README, caption "Text stays inside the 90 % title-safe area") | frames are 88 % wide (6 % each side) | S |
| LK-09 | **W watermark** | logo mark (`worshipflow-mark-mono-white.svg`), right 3 %, bottom 4 %, width 5 %, opacity .55 | none; no logo asset in the catalog (only AppIcon and colour sets) and no watermark layer/prop. (`Prop` images exist; the mark could be a default prop) | M (asset + default off-by-default prop; **a vendor mark on a church's audience screen is a product decision, Q10**) |
| LK-10 | Layers note | "Layers: background video, slide, props" | the Look layers are exactly Background, Slide, Props | n/a |

### D2. Stage (confidence monitor, layout "Band")

| ID | Element | Design | App | Gap |
|---|---|---|---|---|
| LK-20 | Ground | `#000000` (`canvas`), padding 4 % | `(0.02,0.02,0.02)` = `#050505` (`:19`) | S |
| LK-21 | Current lyric | 6.6 cqw = **127 px**, weight **700** (token `stage-current` 128/148 bold, auto-fit down to 96), line height 1.15, **white**, both English lines; top-left | **96** regular, white (`:20`), frame (0.04, 0.08, 0.92, 0.50) (`:25`); auto-fit minimum/maximum not applied | S (size, weight via LK-03) |
| LK-22 | Second language | own line, 3.6 cqw = **69 px**, `#ffd17b`, weight **600**, languages joined with " . " on one line | appended to the same text layer after a newline, so the **same style as the primary** (96 pt white) (`StageLayout.swift:114-120`, `SceneComposer` stage) | M (separate style for the second language on stage: `StageElement` has only `showsSecondLanguage`) |
| LK-23 | NEXT label | "NEXT" 1.5 cqw = 29 px, tracking .08em, `#9fb2c7`, above the next line | none (next line only) | M (label text layer or a style option on the next-slide element) |
| LK-24 | Next line | 3.8 cqw = **73 px** (token `stage-next-line` 72/88, min 64), weight 700 per token, colour `stage-next` `#9fb2c7` (`muted`), bottom-left at 15 % from the bottom | **56** regular, **green `(0.35,0.85,0.55)` `#59D98C`** (`:21-22`), frame y 0.64..0.94 top-aligned (`:26`) | S (colour, size, frame). Green conflicts with the README's "not green" rule (status-ok is cyan) |
| LK-25 | Clock | time of day 4 cqw = 77 px white, right-aligned top right | 44 pt `#CCCCCC` (`:23`), frame (0.74, 0.01, 0.22, 0.07) (`:27`) | S |
| LK-26 | Timer | 6 cqw = **115 px**, `cyan` `#49d3c3` (token `stage-timer` 116/128 tabular), below the clock | only if the layout has a timer element; style per element; the standard layout has no timer (`StageLayout.swift:75-84`) | M (built-in layout "Band" with clock + timer elements; timer default cyan) |
| LK-27 | **Section label "CHORUS x2"** | 2 cqw = 38 px, `blue` `#70b8fa`, under the timer | none: no stage element kind for the section name or repeat count (`StageElement.Kind`: currentSlide, nextSlide, timeOfDay, timer, message, notes) | L (section name and repeat count are not in `ShowState`; plus a new element kind) |
| LK-28 | **Message band** | full-width bar along the bottom, fill `warning` `#ffd17b`, text `on-brand` `#062138` 2.6 cqw = 50 px, padding 1 cqw 4 % | no band: large warning-**red** `(1,0.25,0.2)` text on black, 64 pt, centred, frame (0.04, 0.84, 0.92, 0.14) (`StageLayout.swift:150-155`) | M (text layer needs a background fill; add `fill` to the stage text layer or a `TextBlock.plate`, shared with LK-41) |
| LK-29 | Built-in layout list | layout named **"Band"** | only the built-in "Standard" (`StageLayout.standard`) and user layouts | M (ship "Band" as the built-in default) |
| LK-30 | Typeface | SF / Inter | "Helvetica Neue" | S |

### D3. Broadcast lower third (Fill and Key)

| ID | Element | Design | App | Gap |
|---|---|---|---|---|
| LK-40 | Transparency / checkerboard | checker on every broadcast preview; background alpha 0 | `.transparent` background, checker in `ScenePreview(keyed:)` | yes (matches) |
| LK-41 | **Plate** | rounded rectangle, fill `plate` `rgba(7,19,33,.86)`, width **88 %**, radius 1 cqw = **19 px**, padding 1.6 cqw x 2.4 cqw (**31 x 46 px**), bottom margin 5 % (54 px); its alpha becomes `#dbdbdb` in the key | **none**. `plate.colorset` exists in the catalog but no code uses it; `TextBlock`/`Theme` have no plate | **L** (theme property for plate colour/alpha/radius/padding; renderer draws a rounded rect before text; key channel inherits it; migration of stored themes; broadcast text placement relative to the plate) |
| LK-42 | **Accent bar** | 0.6 cqw = **11.5 px** wide, full plate height, rounded, brand gradient (`#42d9b8 -> #4d99ed`) in fill; **white** in key | none | L (with LK-41) |
| LK-43 | Primary | 3.5 cqw = **67 px** (token `lower-third` 68/84), weight **600**, line height 1.25, white, **left-aligned** inside the plate | **60** (`:30`), regular, white with black outline 3 (`:31`), **centred**, bottom-aligned in frame (0.08, 0.70, 0.84, 0.14) (`:35`) | S/M (size, weight via LK-03, alignment) |
| LK-44 | Secondary | 2.6 cqw = **50 px** (token `lower-third-2` 50/64), weight **500**, `#ffd17b`, line height 1.3, directly under | **44** (`:32`), regular, `#FFDB66`, outline 2, frame (0.08, 0.85, 0.84, 0.11) (`:36`) | S |
| LK-45 | Geometry | plate spans 6 %..94 % horizontally and sits 5 % above the bottom; height grows with the text (two lines max) | text frames 8 %..92 %, primary 70 %..84 %, secondary 85 %..96 %: fixed frames, no plate, the secondary runs to 96 % (4 % from the bottom) | M (auto-height plate; reflow before shrinking, never below 56 px per token) |
| LK-46 | Text effect | none (plate gives contrast) | black outline | S |
| LK-47 | Look "Lower third only" | slide and props, no background | the layers mechanism exists; **no built-in Look named "Lower third only"** (`Look.swift`; default Looks are created by the app) | S (seed a built-in Look; the README also mentions "Full, Notes, Lower 3rd, BG only" buttons in Show) |
| LK-48 | Key output | white = plate opaque, grey = 86 %, black transparent | key matte is derived from the fill's alpha (glyph + outline shapes only, without a plate) (`ScenePreview` keyed channels) | follows LK-41 |
| LK-49 | Two-line limit and reflow | "Two lines maximum; text reflows rather than shrinking below 56 px" | reflow exists for slides (`Reflow.swift`), but there is no shrink floor on the broadcast text layer | M |

### D4. Caption wording on the design board

Design notes read "Look 'Lower third only'", "Second language in `lyric-secondary`", "Theme 'Worship - full'". These names (Look, theme, token `lyric-secondary`) do not exist in the app: theme names are "Full screen" and "Lower third" (`Theme.swift:55, 61`). Sample naming only (S if the owner wants the built-ins renamed).

---

## E. App icon and logo (docs/UI/icon, docs/UI/logo vs App asset catalog)

| ID | Item | Status | Gap |
|---|---|---|---|
| IC-01 | `AppIcon.appiconset` | present and byte-identical to `docs/UI/icon/AppIcon.iconset` (checked `icon_512x512@2x.png`; all ten sizes are present) | none |
| IC-02 | Optical small variant (16/32 px) | the iconset files for 16/32 are the design's rendering | none |
| IC-03 | Logo SVGs / PNGs in the app | **not in the catalog** (`App/Resources/Assets.xcassets` has colour sets and the icon only). The About window and the audience watermark (LK-09) have no mark/wordmark asset | S to add an image set (mark on dark/light, wordmark); the About view is outside this audit |
| IC-04 | Layered `.icon` | README says not built | not a gap |

---

## F. Behaviour the design implies that the app lacks (summary)

1. Add screen / Remove screen / Identify screens (SC-03, SC-21, SC-40).
2. Full hardware chain: enclosure, converter, destination nodes (SC-22, SC-25, SC-31).
3. Pixel format, colour space and embedded audio per SDI output (SC-45..47).
4. Schedule-lead mean and render-time readouts (SC-24, SC-63).
5. Look selector per screen with named Looks (SC-51); Notes layer (SC-52); selectable output-failure policy (SC-53).
6. Plate and accent bar on lower thirds, hence a real key matte (LK-41, LK-42, SC-67).
7. Stage "Band": second-language style, NEXT label, section/repeat label, timer defaults, message band (LK-22..LK-29).
8. Macro keyboard trigger, Test in Preview, loop and dissolve on background action, Stage layout action (CU-21, CU-22, CU-28, CU-29).
9. Playback markers timeline wired to the media player (CU-33).
10. Per-presentation slide-actions list (CU-14); Stream Deck/Remote API placeholder rows (CU-16, CU-17).

## G. Ambiguities and disagreements between design sources

| ID | Item | Sources | Note |
|---|---|---|---|
| A-1 | Badge radius | `tokens radius-xs 3 (LIVE/PREVIEW tags)` and `radius-sm 4 (badges)` vs `ui.css .badge` 4 | The app uses 3 for all badges; tokens say 4 for badges |
| A-2 | Sidebar width | README: 256; Screens/Cues mockups use 300 and 230 (and a 380 right column); README says inspector 372 | Mockup values per screen differ from the README table; the app uses 330/260/372 |
| A-3 | What the app may claim about hardware | `03` draws "Thunderbolt PCIe enclosure", "active 3G converter", "ATEM input 5/6" as facts. README says the screens "illustrate intended UI, not a verified signal path". The app can only know the DeckLink device list; it cannot detect converters, an enclosure or ATEM inputs | Showing these as detected status would be a false claim (CLAUDE.md hardware rules). They may appear only as operator-typed labels |
| A-4 | "HD only, no 4K" and "four 3G-SDI connectors" | static Duo 2 facts in the design | true of the Duo 2, but only to be shown when the connected device reports a Duo 2 |
| A-5 | "Look" | README: Look = one row of buttons in Show (Full, Notes, Lower 3rd, BG only); `03`: a per-screen pop-up with a Look name; UI-002 report: per-screen theme inside the current Look | The design does not say whether a Look is global (current Look) or per-screen. In the app a Look holds a theme and visible layers **per screen** |
| A-6 | "Order is fixed and visible ... top to bottom on one frame boundary" | `06` vs the app's executor, which orders by kind (moves the show first, then Look/props/messages, media, sound, timers, MIDI; a wait splits the list) | The design's promise is not what the engine does; either the note or the executor must change (Q) |
| A-7 | Clear key | README table: Clear = Cmd K, Clear all = Shift Cmd K, Stop = Cmd . ; app lists esc / shift esc and, in the transport bar, a Clear button with `esc` | Design vs app disagree on the key; the app's bar also shows "esc". Other agents cover the transport bar, but the Keyboard table in Cues is here |
| A-8 | Notes layer on a Broadcast screen | `03` shows a **Notes** layer checkbox on a Broadcast screen (unchecked); README principle and `06` say notes never reach Audience or Broadcast | The checkbox invites exactly the mistake the rules forbid |
| A-9 | Stage next line colour | README token `stage-next` `#9fb2c7` (muted) and the `07` caption "next line in `muted`", vs `07` HTML font weight 700 inherited for the whole stage frame | consistent with tokens; app is green |
| A-10 | Audience type size | HTML 6.2 cqw = 119 px vs token 120 px | trivial |
| A-11 | Stage current size | HTML 6.6 cqw = 127 px vs token 128 px, "auto-fit min 96"; caption says "96 px minimum" | the app uses 96 fixed (= the floor) |
| A-12 | Lower-third corner radius | `07` plate 1 cqw (19 px); `03` mini composites 1.5 cqw and 2.2 cqw padding | small drift between the two mockups |
| A-13 | Transport bar in Cues | `06` has it, README agrees; `03` omits | consistent (A: modes) |
| A-14 | Light theme | `11` shows the segmented selected state as `surface-3` with blue text; app light screenshot shows saturated blue fill | same as X-01 |
| A-15 | Hardware claims in labels | "Running (simulated)", "Simulated" badge, "Hardware Verified" | consistent with the verification levels; the app's per-tile SIMULATED badges are stricter than the design |

---

## H. Tally (counted from the tables above)

See the end of this file, section "Counts", updated after the last edit.

---

## Questions for the owner

1. **Signal map: how much of the chain do you want drawn?** The design shows Mac -> Thunderbolt enclosure -> connector -> SDI-to-HDMI converter -> ATEM input/projector/monitor. The app can detect only the Mac and the DeckLink connectors; the rest is what the operator tells it. Options: (a) draw the full chain, but the enclosure, converter and destination nodes are labels the operator types (a short edit sheet per connector, with sensible starting text like "SDI to HDMI converter"), clearly styled as "typed by you"; (b) keep today's picture (Mac, connectors, one "Connected to" note) and only restyle it; (c) draw the full chain with fixed text exactly like the design. Recommendation: (a). It matches the design's look, keeps it truthful, and (c) would claim equipment the app has never seen.
2. **Lower third plate and accent bar: build them as a real theme feature?** Today the broadcast text has no plate, so the key matte is just the shape of the letters. The design has an 86 % dark plate with a gradient accent bar and a grey key matte. Options: (a) add plate and accent bar to the theme model (colour, opacity, radius, padding, bar on/off), make "Lower third" the built-in theme with the design's values, existing user themes unchanged; (b) hard-code the plate in the broadcast renderer only; (c) keep text with outline. Recommendation: (a): it needs a theme migration but it is the only way the Fill and Key previews can match the picture, and it needs a real signal test before it is called verified.
3. **Pixel format, colour and audio rows in a screen's settings.** The engine sends 8-bit BGRA converted by the card, assumes Rec. 709 and sends no audio. Options: (a) show them now as read-only truthful rows ("8-bit BGRA, converted by the card", "Rec. 709 assumed", "No embedded audio"); (b) build the real choices (10-bit YUV, colour range, embedded audio) as separate tasks; (c) leave the rows out. Recommendation: (a) now, (b) later as hardware tasks once the real card has run.
4. **Transport bar in Screens mode.** The design drops it in Screens (and Edit, Stage); the app keeps it everywhere so you can advance the service from any mode. Options: (a) follow the design: no transport bar in Screens, Edit, Stage; (b) keep it everywhere; (c) keep a slim bar (live line, Next, Clear, Blackout). Recommendation: (a), since you asked for pixel for pixel and the toolbar chips still show what is live; say so if you ever need to advance from Screens.
5. **The "Notes" layer checkbox on a Broadcast screen.** The design shows it, but the project rules say notes must never reach Audience or Broadcast. Options: (a) leave it out (current); (b) show it greyed with a lock and "Stage only"; (c) add it as a working layer. Recommendation: (a); the design contradicts its own privacy rule here.
6. **"If output fails" row.** The design shows a pop-up of choices, the app shows a fixed rule ("show a warning here, restart when it returns"). Options: (a) keep the fixed rule but draw it in the design's field style; (b) a real pop-up with 2 or 3 policies (keep running and warn, hold the last frame, go to black or transparent); (c) leave it as text. Recommendation: (a), because only one policy is implemented and safe.
7. **Calibration slide.** The design's key explanation tells the operator to check key polarity with a "calibration slide". The app has no such slide. Options: (a) change the sentence to "test pattern" as now; (b) build a calibration pattern (bars plus a key polarity card) in the Hardware Test window; (c) build it as a slide in the library. Recommendation: (b), small and useful at the first real ATEM test.
8. **Where do Looks and Props live once Screens matches the design?** The design's Screens page has no Looks list and no Props list; the app has both below the screen settings, plus the Developer section. Options: (a) keep them below, under a divider and a title "Looks and props"; (b) move Looks to a Look pop-up in each screen's settings (as in the design) and Props to the Show inspector only, Developer to Settings; (c) move all three to a sheet. Recommendation: (b), which is closest to the design and removes the long scroll.
9. **Cues: placeholders and extra pages.** The design lists Stream Deck "later" and Remote API "off" as rows and has no Schedule section or MIDI/Remote detail pages. Options: (a) add the two disabled "later/off" rows exactly as drawn, rename "Remote control" to "Remote API" only if it is not a web-based API (it is a phone page, so I would keep "Remote control"), keep Schedule below Slide actions; (b) leave them out; (c) hide Schedule behind the macro list. Recommendation: (a), with the label "Remote control" kept.
10. **WorshipFlow mark on the audience screen.** The design puts a faint W logo bottom right on the audience output. Options: (a) leave it out; (b) add it as an optional, off-by-default prop; (c) always on. Recommendation: (a), a church projecting someone else's logo during worship by default is surprising; the prop in (b) is cheap if you want it.
11. **Cues: "Test in Preview", a keyboard trigger and the playback-marker timeline.** None exists (the marker engine is written but unused). Options: (a) build all three, markers last (about three tasks, new storage for markers); (b) build only the keyboard trigger and Test in Preview now, draw no timeline; (c) none, and drop the pictures from the design. Recommendation: (b) now, (a) for markers when you want clip cues for baptism-style videos.
12. **Macro order promise.** The design says actions run top to bottom on one frame; the engine reorders by kind. Options: (a) change the on-screen note to the real behaviour (current wording, restyled); (b) change the executor to run strictly in the shown order; (c) show the reordered execution order next to each row. Recommendation: (a); the engine's order was chosen so a step that moves the show never lands after the Look.
13. **Stage: add the design's "Band" layout as the default?** It needs a second-language style, a NEXT label, a section/repeat label (a new stage element and data) and a message band. Options: (a) add a built-in "Band" layout with everything including the section label; (b) retune the existing "Standard" (colours, sizes, remove the green) and add the message band, without the section label; (c) only retune colours and sizes. Recommendation: (b) now, section label with the cue/section work later.

---

## Counts

Counted by the first size letter in each row's Gap cell (rows with "S / L" count under the first). Rows marked n/a or "not in the design" are not counted.

| Area | S | M | L |
|---|---|---|---|
| Cross-screen (X) | 5 | 2 | 0 |
| Screens (SC) | 26 | 7 | 10 |
| Cues (CU) | 21 | 2 | 5 |
| Looks picture (LK) | 16 | 9 | 3 |
| Icon and logo (IC) | 1 | 0 | 0 |
