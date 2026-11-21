# UI-005 audit: Edit, Media and Stage modes against docs/UI

Read-only audit. Nothing was built or run. App values come from the SwiftUI source (file:line) and from the screenshots
`AI/reports/UI-003-edit.png`, `UI-003-media.png`, `UI-003-stage.png`, `MEDIA-010-bin-player.png`, `MEDIA-010-slide-background.png`
(the newest ones showing these modes). Design values come from `docs/UI/mockups/*.html`, `ui.css`, `ui.js`,
`design-tokens.json`, `README.md` and the three PNGs. Already being fixed elsewhere and NOT listed: product name
"WorshipFlow", pill borders, responsive drags in the slide editor.

Class: **S** = a constant or style change. **M** = layout rework of one view (or small data/model addition). **L** = missing feature needing model work.
Present? = yes / partly / no. Design units are CSS px of the 1440 x 900 mock window = points.

## 0. Things that apply to all three modes

| ID | Design | App | Present | Class |
|---|---|---|---|---|
| X1 | Edit and Stage have **no transport bar** (mockup `win nobar`; README: "preparation modes drop it"). Media keeps it. | Transport bar in every mode: `ContentView.swift` ("The transport bar is in every mode"); visible in UI-003-edit.png and UI-003-stage.png. | differs (deliberate) | S (hide) - see Q1 |
| X2 | Window regions: sidebar 256 (240-380), inspector 372 (320-440) (README, tokens). Mockups use 200/220/230 left and 320/340/300 right. | Edit filmstrip 208 (`ModeViews.swift:24`), Media sidebar 220 / right 380 (`:180`, `:197`), Stage 240 / 320 (`StageEditorView.swift:27,44`). | partly | S |
| X3 | Section structure in side panels: `.sec` = padding 10 x 12 with a 1 px `border` line between sections; `.h` header 11/600 uppercase tracking .06em muted. | `SectionLabel` matches (`Components.swift:130`); but Media right column and Stage right column use padding 14 (`Space.s5`) and mixed separators; Edit has none. | partly | S |
| X4 | Control look: 26 pt height, radius 6, `border-strong` outline, 12/500 label, `surface-2` fill. Fields: `bg` fill, `border-strong`, 12 px. | `HeaderButtonStyle` matches (`Components.swift:160`). Inspectors use native `.roundedBorder` text fields, native Stepper, native Picker menus, native `ColorPicker` (SlideObjectsEditor.swift:300-345; StageEditorView.swift:224-238): they do not follow the token look. | partly | M (a shared `WFField`, `WFPopup`, `WFSwatchField` set) |
| X5 | Scrubber: 6 pt track `surface-3`, `cyan` fill, 14 pt white round knob, mono times either side. | System `Slider` with `.tint(Tok.cyan)` (`BinPlayerPanel.swift:75`, `MediaTransportStrip.swift:25`). | partly | S/M (custom slider) |
| X6 | Toggle = 30 x 18 pill, on = `cyan`. Checkbox 14 x 14 radius 3, on = `blue` fill. | System `.checkbox` and switch styles. | partly | S |

## 1. EDIT mode (design: 02-editor)

Design layout: toolbar 52 / body grid `200 | 1fr | 320` / no transport. Centre = object bar, status strip, canvas, caption. Right = tabs + inspector.

### 1.1 Left filmstrip

| ID | Element | Design | App (file:line) | Present | Class |
|---|---|---|---|---|---|
| E1 | Header "AMAZING GRACE" + plus | `.sec row`: `.h` label + 12 px plus | `ModeViews.swift:40-48` `SectionLabel` + plus, padding 12 | yes | - |
| E2 | Column width | 200 | 208 (`:24`) | partly | S |
| E3 | Section label | `.h` coloured by section (verse blue, chorus cyan, ending/bridge warning) | `:55` uppercase 11/600 tracking .66, tone colour | yes | - |
| E4 | Slide number | 11/600 `text` caption (`.cap b`), above thumb, margin 0 0 4 | 12 bold monospaced digit (`:75`) | partly | S |
| E5 | Thumbnail | 16:9, radius 4, outline 1 `border`; selected = 2 px `sel` ring, 2 px offset; live = 3 px `live-fill` ring, 2 px offset; ring outside the image | Selected: padding 3 + 2 pt `Tok.blue` stroke radius 6. Live: extra padding 4 + 3 pt stroke radius 8 (`:78-84`). Effect is close; radii 6/8 vs design 4 (ring follows thumb radius). | partly | S |
| E6 | Gap between cells | 10 | `Space.s3` = 8 (`:57`) | partly | S |
| E7 | LIVE / PREVIEW tag on thumbnail | `.thumb .tag` 9/800 top-left (defined in CSS, not used in the Edit mock) | none in Edit (ring only); Show has it | n/a | - |

### 1.2 Centre: toolbars and strip

| ID | Element | Design | App | Present | Class |
|---|---|---|---|---|---|
| E8 | Object bar container | `.bar`: `surface` fill, padding 8 x 14, bottom border; buttons 26 pt | `insertBar` (`ModeViews.swift:99-119`): no fill, padding 14 x 4, `Divider`s around | partly | S |
| E9 | Text button | icon `text` + "Text" | present, `textformat` icon (`:102`) | yes | - |
| E10 | Shape button | plain button with `shape` icon | `Menu` of Rectangle / Ellipse / Rounded rectangle, hand-styled (`:104-113`) | partly | S |
| E11 | Image button | icon + "Image" | present | yes | - |
| E12 | **Video** button | "Video" inserts a video object on the slide | absent. `SlideObject.content` has text / image / shape only (`SlideObject.swift`) | no | **L** |
| E13 | Vertical divider 1 x 20 | after Video | none | no | S |
| E14 | **Align** menu | "Align v": align object(s) to slide / to each other | absent | no | **M** (model ops on `SlideEditorModel`; UI is a menu) |
| E15 | **Arrange** menu | "Arrange v": order | Four icon buttons in the object inspector header (`SlideObjectsEditor.swift:282-294`) | partly | M (move into a menu in the bar) |
| E16 | **Audience / Stage / Broadcast** preview switch | Segmented (`seg`), previews the slide under each screen's theme (README: "previews the same slide under each screen's theme") | absent; the canvas always draws one scene (`SlideCanvas`, `:86`) | no | **M** (`SceneComposer.scene(for:)` already exists per role) |
| E17 | **Zoom** field "62%" | pop-up, 26 pt | absent; canvas width computed `min(860, 58% of width, (h-90)*16/9)` (`:19`) | no | M |
| E18 | Live strip | `surface-2`, padding 6 x 14, 12 px, lock icon, "**Slide 3 is live.** You are editing slide 4. Nothing on the screens changes until it is triggered again." | `status` (`ModeViews.swift:150-169`) same words, 12 px, height 30, `surface-2` | yes | - |
| E19 | "Saved 2 s ago" at right of strip | muted 12 px | absent (autosave exists, no indicator) | no | M (a `lastSavedAt` on the editor model) |

### 1.3 Canvas

| ID | Element | Design | App | Present | Class |
|---|---|---|---|---|---|
| E20 | Placement | Canvas 800 pt wide, centred in a `bg` area that fills the column | Left-aligned in an `HStack` with the inspector to its right (`SlideObjectsEditor.swift:20-25`); width max 860 and 58% of the column | partly | **M** (re-compose: canvas centred, inspector becomes the right column) |
| E21 | Canvas frame | radius 2, `shadow-sheet` (0 12 40 rgba(0,0,0,.5)); tokens: "only sheets, popovers and the editor canvas cast a shadow" | radius 4 + `.quaternary` stroke, no shadow (`:102-103`) | partly | S |
| E22 | **Title-safe guide** | dashed inset 5% (`rgba(255,255,255,.28)`) + label "Title-safe 90%" (10 px, muted) above it | absent | no | S |
| E23 | Selection box | 1.5 px `sel` (blue) line, no fill; 8 handles 8 x 8 white, 1.5 px blue border, radius 1 (corners + edge midpoints) | 2 pt **system accent** colour + 10% accent fill; ONE 12 x 12 corner handle bottom-right (`:143-197`) | partly | S for colour/fill, **M** for 8 handles (model `resize` only takes bottom-right deltas) |
| E24 | Unselected object | solid/dashed box: the second-language box is dashed `rgba(255,255,255,.25)` | dashed white .35, 1 pt [4,3] (`:146-147`) | yes | S (alpha .25) |
| E25 | Footer caption | bottom-left, mono 11 muted: "1920 x 1080 - theme "Worship - full" - slide 4 of 9" | Above the editor: "Slide 4 of 5" headline + "Editing here changes the preview only..." (`CentrePane.swift:373-376`); under the canvas: "Drag to move, drag the corner square..." (`:39`) | partly | S |
| E26 | Alignment guides / snapping | Not drawn; "Align" menu implies it. Guides are not in the model (no snap code in `SlideEditorModel`) | absent | no | M (optional, see Q4) |

### 1.4 Right inspector (design 320 wide, full height, `surface`, left border)

| ID | Element | Design | App | Present | Class |
|---|---|---|---|---|---|
| E27 | Container | Full-height column, 320 pt fixed | Inside the centre: `SlideInspector` takes the remainder after the canvas, width varies (about 42% of centre) (`SlideObjectsEditor.swift:23`) | partly | M (with E20) |
| E28 | **Tabs Object / Slide / Theme** | Segmented, full width | absent. Theme is a pop-up + "Themes..." sheet in the header (`ModeViews.swift:128-150`, `ThemeEditorSheet`). Slide-level settings are not an inspector | no | **L** (Slide tab content is undefined in the design; Theme tab = embed the theme editor, M) |
| E29 | Section "TEXT - FIRST LANGUAGE" | `.h` heading names the object's language | heading is the object title "Text box" 17 bold (`:228`) | partly | S |
| E30 | Font | pop-up "SF Pro Display" | free-text field + orange warning (`:304-313`) | partly | M (installed-family pop-up) |
| E31 | Style (weight) | pop-up "Semibold" | absent (`TextStyle` has only `fontName`) | no | **M** (style picker mapping to font face; or L if a real weight field is added to `TextStyle` and the renderer) |
| E32 | Size | mono field "72 pt", 64 wide | Stepper, step 4 (`:306`) | partly | S |
| E33 | Align | 3-icon segmented (left / centre / right) + Top / Mid / Bot segmented | two pop-up menus (`:315-326`) | partly | S |
| E34 | Colour | 22 pt swatch + mono hex field "#FFFFFF" | six preset swatch buttons 18 pt + system `ColorPicker`, no hex (`:400-418`) | partly | M |
| E35 | **Fit** | pop-up "Shrink to fit box" | absent (no fit mode on `TextObject`) | no | **L** (compositor change) |
| E36 | Effects: Shadow | checkbox + colour swatch + one mono field "0 - 4 - 16" (x, y, blur) | checkbox + three number fields + `ColorPicker` (`:336-348`); default shadow 4/4/8 vs design 0/4/16 | partly | S |
| E37 | Effects: Outline | checkbox + colour + "2 px" | stepper + `ColorPicker`, no checkbox (`:327-335`) | partly | S |
| E38 | Effects: **Background fill** | checkbox + field "None" | absent for text (shapes have fill) | no | **L** |
| E39 | Position X Y W H | 2 x 2 mono fields in **pixels** of 1920 x 1080 (230, 292, 1460, 302), labels X Y W H inside the field | percent, labels Left / Top / Width / Height beside (`:244-248`, `:428-438`) | partly | S |
| E40 | **Layers list** | "LAYERS - top first": rows with icon, name, lock/eye/loop icon, selected row `surface-3`. Rows: Prop, Lyrics - English, Lyrics - Tieng Viet, Background (video loop). Prop locked | absent. The objects have no list, no names, no visibility flag. Prop and background layers are not shown | no | **L** (object names/roles, hidden flag, read-only rows for props and background) |
| E41 | Empty state | (not drawn) | "No object selected" + five insert buttons (`:256-262`) | n/a | not in design |

### 1.5 Edit: things the app has that the design does not show ("not in design")

- Header row: Theme pop-up, **Themes...** sheet, **Section order** pop-up and **Section orders...** sheet, **Add slide**, **Reflow...**, **Edit live slide...** (`ModeViews.swift:123-162`). Design has none of these in Edit (README puts arrangements and reflow in Show).
- **Words fields** (first language, second language, notes) above the canvas (`CentrePane.swift:378`). In the design the only way to enter words is on the canvas.
- Canvas toolbar: Insert menu, Undo, Redo, Duplicate, Delete (`SlideObjectsEditor.swift:45-72`).
- Object inspector extras: Opacity slider, shape controls (fill, outline, corner radius), image controls (fit/fill), "Add another" buttons, z-order buttons.
- Slide's own background: the drop target on each filmstrip cell, the media/photo mark in its corner (`Thumbnails.swift:230`), the "Use the presentation's background" context item (`ModeViews.swift:88-94`).
- Double-click on a text box to type in it (inline editor).

## 2. MEDIA mode (design: 05-media-audio)

Design layout: toolbar / body grid `220 | 1fr | 340` / transport bar. Centre = header bar, 5-column grid, bottom clip strip.

### 2.1 Left sidebar (220)

| ID | Element | Design | App | Present | Class |
|---|---|---|---|---|---|
| M1 | Width | 220 | 220 (`ModeViews.swift:180`) | yes | - |
| M2 | Row | `.li`: 26 high, padding 0 x 8, radius 6, 13 px, icon 15, count 11 muted, selected `surface-3` | 30 high, 14 px, icon frame 18, count 12 (`:222-226`) | partly | S |
| M3 | **Bin entries** | MEDIA BIN: Motion backgrounds 24, Videos 7, Images 41, Announcement loop 9, Live inputs 0. AUDIO: Walk-in music 12, Sound cues 5 (named collections, with their own counts) | Fixed kinds: All media, Videos, Pictures; Audio: Sound (`MediaBinCategories`, `ModeViews.swift:208-212`). Filter is `kindFilter` only (`MediaModel.swift:60`) | partly | **L** (named bin collections/tags and audio playlists need a model + migration) |
| M4 | Live inputs row | row with 0 (README: "Live video inputs (row only)", later milestone) | absent | no | S (placeholder row) |
| M5 | **Offline callout** | Warning icon, "1 file is offline", file name + reason, **Locate...** button, at the bottom of the sidebar | absent in the bin (no offline state on assets; only a missing hot folder shows a warning) | no | **L** (missing-file detection on assets + relink flow) |
| M6 | Section header gap | `.sec` padding 10 x 12, line between sections | `Space.s4` padding, no lines, sections 8 apart (`:204-216`) | partly | S |

### 2.2 Centre header and grid

| ID | Element | Design | App | Present | Class |
|---|---|---|---|---|---|
| M7 | Header bar | Full-width bar, bottom border, padding 8 x 14, title 17/700 (`title-2`) | Title 20 bold inside the scroll content, no bar, scrolls away (`MediaBinPanel.swift:20-21`) | partly | M (pin the header outside the ScrollView) |
| M8 | Header controls order | Import... then "Background layer / Foreground" segmented then grid/list segmented | Segmented then Import (`:24-39`); segment labels "Background / Foreground", 12 px, 22 high | partly | S |
| M9 | **Grid / list toggle** | Two-icon segmented (grid selected) | absent; no list view | no | **M** |
| M10 | Grid columns | 5 equal columns, gaps 14 (row) / 12 (col), padding 14 | Adaptive min 150 max 220 gap 14 (`:16,49`): 4 columns at the screenshot width | partly | S |
| M11 | Tile kind icon | Top-left chip: `rgba(0,0,0,.55)`, radius 4, padding 2, film/image icon 12 | absent. Top-left carries BACKGROUND / PLAYING capsule badges instead (`:203-208`) | no | S |
| M12 | Tile duration | Bottom-right: mono 10/600, `rgba(0,0,0,.6)`, radius 3, padding 0 x 4, inset 5 | `wfMonoData` 11/500, inset 3, no radius (`:198-201`) | partly | S |
| M13 | Tile corner radius | 4 | 3 (`:196`) | partly | S |
| M14 | Tile caption | 11 / 600 `text`, margin-top 5 | 12 / 500, spacing 3 (`:209`) | partly | S |
| M15 | Selected / live ring | Selected: 2 px blue, offset 2. Live: 3 px `live-fill`, offset 2 (same as slides). No text tag | Both 2 pt, padding 3, radius 8 (`:51-54`); live is red 2 pt (not 3) | partly | S |
| M16 | Placeholder fill | Gradient poster | `Color(white: 0.16)` literal (`:184`) | partly | S |

### 2.3 Bottom clip strip (design: above the transport bar, inside the centre column)

| ID | Element | Design | App | Present | Class |
|---|---|---|---|---|---|
| M17 | Strip | `surface`, top border, padding 10 x 14. Row 1: bold file name, "Live - background" red badge, mono meta "1920x1080 - 59.94 - ProRes 422 - 0:30", Loop pill (cyan). Row 2: prev / play / stop (26 pt buttons), mono 00:11.4, scrubber, mono -00:18.6, **Mark in**, **Mark out**, **Add marker** | `MediaTransportStrip` appears only while a foreground clip is loaded (`ContentView.swift` strip condition), red-tinted (`Color.red.opacity(0.10)`, `.foregroundStyle(.red)` film icon), one row: name, play, times, slider, mute, volume, Stop (`MediaTransportStrip.swift:15-45`). Never shown for a live background | partly | **M** (re-layout, show for the live background too, meta line, Loop pill) |
| M18 | Mark in / Mark out / Add marker | Buttons; README: "a transport strip with in/out and markers" | absent (no in/out or marker in `MediaModel`; CUE design 06 has "playback markers" too) | no | **L** |
| M19 | Prev (restart) button | rewind icon | absent | no | S |
| M20 | Use of red | Only the LIVE badge | Red tint of the whole strip and the film icon: against the "red = on-air only" principle where the clip is not on air | partly | S |

### 2.4 Right column (design 340: Audio cue, Routing, Levels)

| ID | Element | Design | App | Present | Class |
|---|---|---|---|---|---|
| M21 | Width | 340 | 380 (`ModeViews.swift:197`) | partly | S |
| M22 | **Audio cue** card | Title row "AUDIO CUE" + source name (muted). One cue: 26 pt play button, bold track name, mono "02:14 / 04:31", scrubber, speaker icon + blue volume scrubber + "-6 dB" | "Audio" headline; device pop-up; mute + volume slider with percent (80%); list of ALL sound files each with play, name, length, loop, overlap (`AudioPanel.swift:12-46,98-150`) | partly | M (restructure: one current-cue card + list below) |
| M23 | Volume readout | dB ("-6 dB") | percent (`AudioPanel.swift:31`) | partly | S (needs dB mapping in `AudioModel`: M if the model stores linear gain only) |
| M24 | **Routing matrix** | 4 rows (Media audio L/R, Audio cues L/R) x 4 columns (Mixer L, Mixer R, SDI 3 emb., SDI 1 emb.), 22 high cells radius 5, on = `cyan`; hint about not embedding the same audio twice | absent. One programme device only ("Sound files and video sound both go to this output, once", `AudioPanel.swift:77`) | no | **L** (per-bus routing in `AudioModel` + output engine embedded audio) |
| M25 | Device | "Device" label + full-width pop-up "QU-32 USB - 2 ch" | "Output" label + pop-up + refresh button (`AudioPanel.swift:57-73`), "name - N ch" text matches | partly | S |
| M26 | **Levels** | Four vertical meters 14 wide x 150 high (L, R, Cue L, Cue R), cyan to warning (88%) to live gradient, dB scale 0 / -12 / -24 / -48 | Two horizontal 7 pt bars, `.green/.yellow/.red` system colours, scale -60..0 hidden (`AudioPanel.swift:153-196`) | partly | **M** vertical meters + scale + token colours; separate Cue meters = **L** (no cue bus) |
| M27 | Section spacing | `.sec` 10 x 12 with lines | padding 6 + 14 | partly | S |

### 2.5 Media: things the app has that the design does not show ("not in design")

- **Bin player** at the top of the right column (video/sound preview with play, scrub, Loop, Muted, "Send to live background / foreground", note "preview on this Mac only") (`BinPlayerPanel.swift`; `MEDIA-010-bin-player.png`).
- **Folders** (hot folders) section in the sidebar with add, missing state, per-folder count (`ModeViews.swift:228-263`) and the folder header with "Play folder", "Stop folder", "Stop following", "Point to the folder again..." (`MediaBinPanel.swift:122-151`).
- Selected-item action row "Live background / Live foreground" (`:71-81`) and the live-override row "Use the slide's own background" (`:83-92`).
- BACKGROUND / PLAYING capsule badges on tiles; drag a tile onto a slide (per-slide background); context menu (Set as background, Play in foreground, Rename, Remove).
- Audio: per-file **overlap** toggle, "Stop sound" button, refresh devices, mute button, long explanatory paragraphs.
- Double-click-to-send-live semantics tied to the layer choice.

## 3. STAGE mode (design: 04-stage)

Design layout: toolbar / body grid `230 | 1fr | 300` / no transport.

### 3.1 Left column

| ID | Element | Design | App | Present | Class |
|---|---|---|---|---|---|
| S1 | Width | 230 | 240 (`StageEditorView.swift:27`) | partly | S |
| S2 | Header | "STAGE LAYOUTS" + plus | same (`:67-74`), height 48 | yes | - |
| S3 | **Layouts** | Band (current + next), Speaker (notes + timer), Clock only (time of day) | One built-in "Standard" (`StageLayout.swift:75-84`: current, next, clock) + user copies | partly | **M** (add three built-in layouts as data; needs timer/notes elements wired to default timer) |
| S4 | Row caption | bold name + muted description ("current + next") | name + "built in" / "yours" (`:102-105`) | partly | S |
| S5 | Row selection | `surface-3` fill, radius 8, no outline; padding 8 | same plus a `border-strong` outline (`:108-109`) | partly | S |
| S6 | Thumbnails | 16:9 black, text sample | `ScenePreview` of the layout (`:100`), good | yes | - |
| S7 | **Stage message** composer (bottom of the column) | Field 48 high multi-line, 5 px top pad; "Send" = **brand gradient** primary with message icon; "Clear" button always visible; "Stage only" muted at right | `StageMessageView.swift`: single-line 26 pt field, Send in resting `HeaderButtonStyle`, recent-messages menu, "On stage now: ..." row with Clear only while a message is up; "Stage screens only" at the top right | partly | M |
| S8 | Primary button style | `.btn.primary` gradient `brand-a`->`brand-b`, `on-brand` text | no primary style exists in `Components.swift` | no | S (add `PrimaryButtonStyle`) |

### 3.2 Centre

| ID | Element | Design | App | Present | Class |
|---|---|---|---|---|---|
| S9 | Top bar | `surface`, bottom border, padding 8 x 14: name 15/700, "STAGE" badge (warning, radius 4), element buttons: Current, Next, Clock, Timer, Message, **Video** | Name 18 bold (`:120`), badge radius 3 (`Components.swift:49`), buttons "Current slide / Next slide / Clock / Timer / Message / **Notes**" (`:123-129`), height 48, no bar fill | partly | S |
| S10 | **Video** element button | PiP-style video element on stage | absent (`NewStageElement`) | no | **L** |
| S11 | Canvas size and position | 820 wide, centred in the area, black, `shadow-sheet` | up to 900 wide, left-aligned under a name/banner row (`:32-39`), 4 radius, `.quaternary` stroke, no shadow | partly | M |
| S12 | **Element labels** | Each element has a caption above it: 10/600 uppercase .06em muted ("CLOCK", "TIMER - SERVICE ELAPSED", "NEXT SLIDE"); the selected one in `sel` blue and fuller ("CURRENT SLIDE - BOTH LANGUAGES") | none (`ElementBox`, `:325-357`) | no | S |
| S13 | Element boxes | Unselected: 1 px dashed `rgba(255,255,255,.22)`, padding 8 x 12. Selected: 1.5 px solid `sel`, no fill, **no handles drawn** | Unselected dashed white .45; selected 2 pt system accent + 12% fill + 12 x 12 corner handle (`:329-350`) | partly | S |
| S14 | Sample content | Current: two languages (2nd in `#ffd17b` 600). Next: `#9fb2c7`. Clock "9:14 AM" with small AM. Timer 54 px **cyan**. Section "CHORUS x2 / then Verse 2" (blue / muted). Message: full-width bar filled `warning`, `on-brand` text | Sample current in white; next slide drawn **green** in UI-003-stage.png; clock "7:36 AM" same size; no timer, section or message in the Standard layout | partly | M (sample scene + colours from tokens) |
| S15 | **Section / arrangement** element | "SECTION - ARRANGEMENT": "CHORUS x2" + "then Verse 2" | absent (`StageElement.Kind`: current, next, timeOfDay, message, notes, timer) | no | **L** (needs arrangement progress in the show state) |
| S16 | Footer caption | mono 11 muted, bottom-left: "1920 x 1080 - minimum lyric size 64 px at 1080p - readable at 10 m" | "Sample words, clock, message and notes are shown here. Drag a box..." (`:36`) | partly | S |
| S17 | Layout name / read-only | Name is the title; no rename or banner drawn | Name text field + Rename (`:195-209`); built-in banner "cannot be changed" + Duplicate to edit; Duplicate / Delete in the column | n/a | not in design |

### 3.3 Right column (design 300)

| ID | Element | Design | App | Present | Class |
|---|---|---|---|---|---|
| S18 | Width | 300 | 320 (`:44`) | partly | S |
| S19 | Header | "ELEMENT - CURRENT SLIDE" (`.h`) | `.headline` element title; when nothing is selected "Choose an element to see its settings." (`:213-257`) | partly | S |
| S20 | **Shows** | pop-up: Both languages (first only / second only implied) | checkbox "Show second language" (`:235-239`) | partly | M |
| S21 | **Size + Auto-fit** | mono field "96 px" + checkbox Auto-fit (tokens: auto-fit may shrink from 128 to 96, never below) | Stepper "Font size", step 4 (`:224-227`); no auto-fit flag | partly | **L** (auto-fit in the stage compositor; verify what `StageEditing`/renderer already do) |
| S22 | **Weight** | pop-up "Bold" | absent | no | M |
| S23 | Colour + **2nd lang. colour** | two swatch + hex rows | one `ColorPicker`; no second-language colour (output constant `lyric-ink-2`) | partly | M for hex rows, **L** for a per-element second-language colour |
| S24 | Alignment | not in the design inspector | segmented Left/Centre/Right (`:230-234`) | n/a | not in design |
| S25 | Position / delete | not in the design | Left / Top / Width / Height percent grid + "Delete element" (`:240-248`) | n/a | not in design |
| S26 | **Elements** list | Icon + name + eye icon at right; 6 rows incl. Section, Stage message; selected `surface-3` | Text-only rows, height 28 (`:152-163`); no icons, no visibility | partly | S for icons; **L** for per-element hide (eye) |
| S27 | **Assigned to** | Row "Confidence - SDI 4" with role dot and a **toggle** (assign/unassign this layout to that screen) + the privacy note | Dot + "Name - destination" text, read-only; empty-state text "Choose it for a stage screen in Screens" (`:165-179`) | partly | M (toggle writes `stage.layoutID(forScreen:)`) |
| S28 | Privacy note | "Speaker notes and stage messages never appear on Audience or Broadcast screens. Themes, Looks and props do not apply to stage layouts." | identical text (`:177`) | yes | - |

### 3.4 Stage: things the app has that the design does not show ("not in design")

- **Timers and clock** panel in the right column: add timer (countdown / elapsed / to a time), Pause, Reset, Rename, Delete, stage clock 12/24 hour and Seconds (`TimersPanel.swift`, `STAGE-001b-timers.png`). The design only shows Service/Sermon timers in the toolbar.
- Notes element button; Duplicate / Delete layout; rename field; read-only banner; font-size stepper; alignment; position fields; recent stage messages menu; "On stage now" row.
- Transport bar (see X1).

## 4. Where the design sources disagree or are ambiguous

1. **Transport bar**: README "Show, Media and Cues keep it; Edit, Stage, Screens drop it" and the mockups (`win nobar` in 02, 04) agree, but `ContentView.swift` states the opposite as intent ("an operator in Screens can still advance the service"). Needs the owner (Q1).
2. **Side widths**: README/tokens 256 left and 372 right (320-440); mockups 200/220/230 and 320/340/300. The app follows neither fully.
3. **Zoom "62%"** in 02 does not match the drawn canvas: 800 / 1920 = 41.7%.
4. **Inspector "72 pt"** vs canvas text: mockup draws 44 px on an 800 px canvas = 105 px at 1080 (tokens: lyric 120 px). Position fields (230, 292, 1460, 302 px) are consistent with the box (12%, 27%, 76%, 28%).
5. **Layers**: README says "prop and background layers shown but locked"; the mockup locks only Prop (Background row shows a loop icon; text rows show eye icons).
6. **Where words are typed in Edit**: the design shows only canvas editing; the app has three words fields above the canvas (they are also the only way to edit the second language and notes). Not resolved by the design (Q2).
7. **Stage handles**: the design draws no resize handles on the stage canvas (or the slide canvas inspector for stage); the editor needs some way to resize (Q3).
8. **Stage element set**: top bar has no Notes button, yet the "Speaker" layout thumbnail shows notes text; Section and Video have a button/element that the app lacks, Notes has a button that the design lacks.
9. **Shadow tokens**: tokens say only sheets, popovers and the editor canvas cast a shadow; the stage mockup canvas also has `var(--shadow)`.
10. **Badge radius**: CSS `.badge` 4 px; tokens put 3 (`radius-xs`) on LIVE/PREVIEW tags and 4 (`radius-sm`) on "badges"; the app's `Badge` uses 3.
11. **Media clip strip**: the mockup shows it for the live *background* (a looping motion background); README says "transport strip with in/out and markers" but the app's strip is for foreground clips only, and the Show dock has its own controller row.
12. **Fonts**: mockups use Inter; widths differ from SF. Pixel comparison of text will never be exact; compare sizes and weights, not glyph widths.
13. **Audio duplication rule**: design hint says "send playback to the mixer once; embedding on SDI too would double it"; the app text says the same for its single output. A routing matrix must keep that warning.

## 5. Gap counts

| Mode | S | M | L | Total |
|---|---|---|---|---|
| Edit | 18 | 11 | 5 | 34 |
| Media | 17 | 5 | 4 | 26 |
| Stage | 11 | 8 | 3 | 22 |
| Shared (X1-X6) | 5 | 1 | 0 | 6 |

(One count per table row, by its first class where a row lists two; rows marked "-", "n/a" or "not in design" are excluded. Some L rows hide an M part, named in the row.)

## 6. Questions for the owner

**Q1. Transport bar in Edit and Stage.** The design hides it there; the app shows it everywhere.
- (a) Hide it in Edit and Stage, as designed.
- (b) Keep it everywhere (an operator can always advance the service).
- (c) Hide it in Edit only.
Recommendation: (a), since you asked for pixel for pixel; the toolbar chips still show what is live.

**Q2. Where are the words typed in Edit?** The design has only the canvas; the app has three words fields above it.
- (a) Remove the fields; words are edited only on the canvas (and in Quick edit).
- (b) Move the three fields into the inspector "Slide" tab.
- (c) Keep them above the canvas.
Recommendation: (b): matches the design's tab and keeps a way to edit the second language and notes.

**Q3. Header row in Edit** (Theme pop-up, Themes..., Section order, Add slide, Reflow..., Edit live slide...) is not in the design.
- (a) Move Theme into the inspector Theme tab and the rest to the Show header.
- (b) Keep the row but under the object bar.
- (c) Remove from Edit; reach them by menu commands only.
Recommendation: (a).

**Q4. Features implied by the design but not yet in the model.** Which L items do you want now?
- (a) Layers list, Fit, Background fill, Video object, 8-handle resize, Align menu (Edit); media collections, offline/Locate, in/out + markers, routing matrix and Cue meters (Media); Section element, Video element, auto-fit, eye toggles (Stage): all of it.
- (b) Visual match first (all S and M), L items later in this order: layers list, offline/Locate, collections, routing.
- (c) Visual match plus only the Edit L items.
Recommendation: (b); L items each need a spec, migration and tests, and the visual gaps are what you see first.

**Q5. Features you asked for after the design was made.** Where do they go?
- Sidebar bin player, hot folders, per-slide background mark, Timers panel in Stage, Themes sheet, overlap toggle.
- (a) Keep each where it is, restyled to tokens.
- (b) Move the bin player into the bottom clip strip (design position) and keep the right column for audio only.
- (c) Move Timers into a sheet opened from the toolbar timer chip.
Recommendation: (a) for hot folders, slide-background mark and overlap; (b) for the bin player only if you want the strip to match the design exactly; (c) for Timers.

**Q6. Stage canvas editing handles.** The design draws none.
- (a) Keep one corner handle, in the token blue.
- (b) Draw 8 handles as in the Edit mockup.
- (c) No handles; size and position only by the inspector fields.
Recommendation: (b), the same as the slide canvas, so both editors behave alike.

**Q7. Media list view.** The design shows a grid/list toggle but draws only the grid.
- (a) Build the toggle and a simple list (name, kind, duration, size).
- (b) Draw the toggle with the list disabled for now.
- (c) Leave it out.
Recommendation: (a) later, (b) for the first visual pass.

**Q8. Preset stage layouts Band, Speaker, Clock only.**
- (a) Ship all three as built-ins next to Standard.
- (b) Replace Standard by Band.
- (c) Keep Standard only.
Recommendation: (a); Standard stays so existing screens do not change.
