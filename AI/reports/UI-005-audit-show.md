# UI-005 audit: Show mode and shared components

Read-only audit. Nothing was built or run; app values come from the SwiftUI source (file:line) and from the newest screenshots (UI-003-show.png, UI-003-show-light.png, MEDIA-010-show-override.png). Design values come from docs/UI/mockups (01-operator-show.html, 08-components.html, ui.css, ui.js), docs/UI/README.md, design-tokens.json and the PNGs in docs/UI/screens. Screens are 1440 x 900 pt at 2x.

Not reported as gaps (another agent is fixing them): the visible product name "WorshipFlow", and pill borders.

Sizes: S = a constant or style change. M = layout rework of one view. L = a missing feature that needs model work. Each gap has an ID (T = toolbar, SB = sidebar, PL = playlist, H = header, G = slide grid, D = dock, C = media controller, I = inspector, Q = quick edit, ST = stage message, TR = transport, K = shared components).

Abbreviations: ShowInspector.swift = SI, MediaDockView.swift = MD, CentrePane.swift = CP, LibrarySidebar.swift = LS, TransportBar.swift = TB, Components.swift = CO, ContentView.swift = CV, ToolbarTimersView.swift = TT, StageMessageView.swift = SM, ShowMode.swift = SH. All in App/Sources.

## 0. Window-level measurements (from the screenshots)

| Item | Design | App | Size |
|---|---|---|---|
| Sidebar width | 256 pt (255.6 measured in 01-operator-show.png) | about 276 pt measured. SH:21 gives ideal 256 but max 276, and HSplitView lets it settle at the max | S |
| Inspector width | 372 pt (README, tokens: resizable 320-440) | about 381 pt measured. SH:27 sets ideal 372, max 380 | S |
| Centre column at 1440 | 812 pt | about 781 pt (follows from the two rows above) | S |
| Resize ranges | sidebar 240-380, inspector 320-440 (README, tokens) | sidebar 240-276, inspector 320-380 (SH:21, SH:27) | S |
| Toolbar | 52 pt, own chrome: traffic lights, sidebar-toggle button, title block, mode switcher, timers, pills | system toolbar, 52 pt. No sidebar-toggle button | M (T3) |
| Transport bar | 56 pt (grid-template-rows) | 56 pt (Space.transportBarHeight) | matches |
| Window ground | bg | Tok.bg (CV:96) | matches |

## 1. Toolbar

| Element | Present? | Differences (design vs app) | Size |
|---|---|---|---|
| T1 Window title block | partly | Design: "Sunday 9:00 — 22 Nov" 13/600 plus a muted 11 subtitle "WORSHIPFLOW · Lakeshore library" (ui.js toolbar). App: title = the playlist name (CV:160, shows "Service"), subtitle = library name (CV:163, shows "Songs"). Design title is a service name with a date; the model has no service date | M |
| T2 Traffic lights | yes | System-drawn. Fine | none |
| T3 Sidebar toggle button (icon `sidebar`, ghost button) | no | Design has it left of the title. App has no control to hide the sidebar (HSplitView, no collapse) | M |
| T4 Mode switcher | yes | Track: radius 7, 2 pt padding, 1 px `border`, fill surface-2 (ui.css `.seg`). App radius 8 (CV:189), 2 pt padding, same fill. Segment: design 12/500 text, padding 4 x 11 (about 26 pt tall), radius 5, icon 12 pt, selected = surface-3 fill PLUS 1 px border-strong inset ring. App: 24 pt tall, padding 10, radius 6, selected text goes semibold (CV:174) and has NO ring. Icons: design play / edit / film / stage-building / bolt / monitor; app play.fill / pencil / film / music.mic / bolt / display (README suggests `music.mic`, so the app follows the README, the PNG differs) | S |
| T5 Timers capsule | partly | Design (ui.css `.tm`): 28 pt tall, radius 7, 1 px `border`, surface-2; content "clock-icon Service **00:10:32** | timer-icon Sermon 25:00 [play button]". Label 11 muted, value 13 bold mono. A 1 x 16 separator between the two timers. Play button 20 pt tall, padding 6, bordered. App (TT:48-49): radius 10 (Radius.xl), no separator, timer name 12, value 13 semibold; play button 22 x 18 radius 4. Value format: design `00:10:32` (HH:MM:SS), app `0:10` (screenshot) | S |
| T6 Timer colours | partly | Design PNG: running service value is default text colour, idle sermon value is muted. App: running = cyan, idle = text (TT:31). tokens.json says cyan is "timers". See Ambiguities A1 | S |
| T7 Role pills AUD / STG / BRD | yes | Design `.pill`: 20 pt, 11/600, padding 0 8, dot 7. App (CO:104-107): 11/**700**, tracking 0.4, padding 9. Weight and padding differ. Fault and off states exist in the app, which the design only shows in 08 | S |
| T8 Pill position | yes | Right end, after timers. Matches | none |

Behaviour the design implies that the app lacks: a sidebar collapse (T3). The "Sermon 25:00" idle countdown with a play button exists in the app.

## 2. Sidebar (Libraries section)

| Element | Present? | Differences | Size |
|---|---|---|---|
| SB1 "LIBRARIES" label and plus | yes | Label 11/600/.06em muted: matches (CO:134). Plus is a menu (LS:83) | none |
| SB2 Search field | partly | Design: 26 pt, radius 6, fill **bg**, 1 px border-strong, 12 pt text, search icon 12 pt, ⌘F kbd at right, margin 6 below. App: 26 pt, radius 6, stroke border-strong, **no fill** (LS:160-162), icon is the system size (about 13), focus stroke turns cyan (design has no focus style; blue would match `sel`) | S |
| SB3 Key hint (kbd) | partly | Design `.kbd`: mono 10/14, **weight 500**, padding 0 4 (14 pt tall), radius 3, 1 px border in the text colour at 75 % opacity (text also 75 %). App (CO:122-124): weight 600, vertical padding 1 (16 pt tall), border-strong, muted text | S |
| SB4 Library rows | partly | Design: FOUR typed rows, each with its own icon: Songs (music), Scripture (book), Sermons (text), Announcements (megaphone), count at right 11 muted. Row 26 pt, radius 6, 13 pt, selected = surface-3. App (LS:196-214): one row per user library, all with `music.note.list` icon, row 28 pt, count in 12 pt mono. Libraries have no kind, so there are no Sermons / Announcements libraries and no per-kind icons | L (library kind) |
| SB5 Scripture row | yes (different) | Design: a library row with count 38. App (LS:177-194): a special row with a ⌘J key hint and no count; it opens the Scripture view | S |
| SB6 Divider between sections | partly | Design: 1 px `border` line between the Libraries block, the song list and the Playlist (`.sec+.sec`). App: VSplitView divider between Libraries+list and Playlist only; none between the library rows and the song list | S |
| SB7 Song list | partly | Design: plain 26 pt rows, music icon in the TEXT colour, selected row = surface-3 radius 6, "EN · VI" at right 11 muted. App: system `List` (LS:104). In UI-003-show.png the selected row shows the system selection tint as a square-cornered block behind the rounded surface-3 fill (visible artefact). Icon is muted, 16 pt frame, row height is the List default | M |
| SB8 Search-result tags ("Title" / "Lyrics") | extra | Not in the design (design never shows a search state) | not in design |

## 3. Playlist

| Element | Present? | Differences | Size |
|---|---|---|---|
| PL1 Header | partly | Design: "PLAYLIST" label, then a `field` (22 pt, radius 6, border-strong, bg fill) "Sunday 9:00 ⌄", then at far right a dots icon. App (LS:219-243): system popup Picker (`.labelsHidden`, filled system look, up-down chevrons), then a plus menu AND an ellipsis menu | S |
| PL2 Playlist plus menu (add header, add countdown) | extra | Not in the design header (design has only the dots). Keep, but the owner decides where it lives | not in design |
| PL3 Section headers (PRE-SERVICE etc.) | partly | Design `.li.sub`: 22 pt row, 11/600, uppercase, tracking .04em, muted, **no rule line**. App (LS:290-292): same text with a 1 px rule after it, 6 pt top padding. In UI-003-show.png the rule is visible | S |
| PL4 Item rows | partly | Design: no row numbers; every row has a leading icon by kind (timer, megaphone, music, book, text, film); 26 pt, radius 6, 13 pt. App (LS:341-352): a number column (18 pt) first; icon only on countdown and scripture rows, none on songs | S |
| PL5 Item kinds | partly | Design playlist holds: countdown, "Announcements loop" (megaphone), songs, scripture, "Sermon — Saved by Grace" (text), "Baptism testimony.mov" (film clip). App item kinds: presentation, countdown, scripture, header only (LS:288). No media-file item, no announcements-loop item, no sermon-notes item | L |
| PL6 LIVE marker | yes | Design `.n.c-live`: dot 8 + "LIVE" 11 (not mono). App (LS:368-374): dot 6, "LIVE" in mono 11/500 | S |
| PL7 Selected + live row | yes | Both are surface-3 in the design. App uses a listRowBackground rounded fill (LS:315 etc.). Same system-tint artefact as SB7 | S |
| PL8 Scripture / countdown item tags ("not installed", "empty") | extra | Not in the design | not in design |
| PL9 Playlist drag-reorder, Export/Import program | extra | Not in the design | not in design |

## 4. Centre: header

| Element | Present? | Differences | Size |
|---|---|---|---|
| H1 Bar geometry | partly | Design `.bar`: padding 8 x 14, bottom border, so about 43 pt tall. App: AdaptiveHeader fixed at Space.headerHeight 48 (CO:219), 14 horizontal padding | S |
| H2 Title | partly | Design: static text 17/22 bold (title-2 token). App: editable TextField 20 bold (CP:51), so 3 pt bigger and a different style | S |
| H3 Arrangement control | partly | Design: `field` 26 pt, radius 6, fill bg, border-strong, text "Arrangement: Sunday", chevron at right, always shown. App: system `Menu` with `.menuStyle(.button)` (CP:58-67), shown only when a playlist item is selected, no design chip look | S |
| H4 "EN + VI" chip | partly | Design: a pill (capsule, 20 pt, 11/600, border-strong, muted text). App: `Badge` outline, radius 3, uppercase tracked rectangle (CP:71) | S |
| H5 Buttons: Add slide, Reflow…, Quick edit ⌘E | yes | HeaderButtonStyle matches the `.btn` metrics. Quick edit should get a 2 pt `sel` (blue) ring while the Quick edit tab is open (01b PNG, `ED` flag); app has none | S |
| H6 Grid / list toggle | partly | Design: custom `.seg` with icons (surface-2 track, selected = surface-3 + ring). App: system segmented Picker (CP:91-95); the screenshots show it blue-selected in one and grey in another (focus dependent) | S (shared K3) |
| H7 Extra header buttons | extra | "Add to playlist" icon button (CP:86), not in design | not in design |
| H8 Scripture view in the centre (LIB-004c) | extra | Design has no scripture screen. `ScriptureView.swift`, `ScriptureTranslationsView.swift` | not in design |

## 5. Centre: slide grid

| Element | Present? | Differences | Size |
|---|---|---|---|
| G1 Area padding | partly | Design: 10 top, 14 sides. App: 14 all round (CP:184, Space.s5) | S |
| G2 Section label | partly | Design `.sl`: 11/**600**, dot 8, gap 6, "× 2" in weight 400 muted, 5 pt below. App (CP:115-130): 13/600 label, "× 2" 12; 6 pt top padding | S |
| G3 Grid gaps | partly | Design: 5 columns, column gap **10**, no row gap inside a section (rows are labelled by caption), 9 pt before the next section label. App: gap 12 both ways (SlideGridLayout.spacing 12, ShowRevision2.swift:12), LazyVStack spacing 10 | S |
| G4 Thumbnail size | partly | Design at 812 pt: about 149 pt wide. App: each cell is padded 3 pt inside its ring (CP:199) so the picture is about 135 pt at 781 pt column width (measured). Unselected thumbnails carry an invisible 3 pt inset | S |
| G5 Idle outline | no | Design `.thumb`: 1 px `border` outline on every thumbnail (and on the idle state in 08). App: none, so a dark slide fades into the bg | S |
| G6 Preview ring | partly | Design: 2 pt blue outline, **2 pt offset**, radius follows 4. App (CP:199-200): 2 pt, radius 6, 3 pt gap | S |
| G7 Live ring | partly | Design: 3 pt live-fill, 2 pt offset. App (CP:199-202): padding 3 + 4 then a 3 pt stroke at radius 8, about 7 pt gap, and the cell grows by 8 pt while live (neighbours stay smaller). Visible in UI-003-show.png | S |
| G8 LIVE / PREVIEW tag on the thumbnail | partly | Design `.thumb .tag`: 9 pt, weight 800, tracking .08em, padding 1 x 5, radius 3, at 5,5. App Badge: 10/700, tracking .6, padding 6 x 2 (CO:46-47): about 10 % bigger | S |
| G9 Caption | partly | Design `.cap`: 11 pt, bold number in text colour, then muted text with a literal "…", 3 pt below. App (CP:203-209): 12 pt, 4 pt below | S |
| G10 Empty slide caption | no | Design shows "Blank · background only" for the empty ending slide. App shows an empty string | S |
| G11 Own-background mark | extra | White circle bottom-right on slides with their own background (OwnBackgroundMark). Not in the design | not in design |
| G12 Section tone for "other" | partly | tokens.json: bridge, ending and tag labels are warning. ui.css defines `--tag` = broadcast colour. App: `.other` = muted (CO:179) | S (A5) |
| G13 Slide context menu, drag-reorder, drop-a-background | extra | Not in the design | not in design |

## 6. Media dock

| Element | Present? | Differences | Size |
|---|---|---|---|
| D1 Dock frame | yes | Design: border-top 1, fill surface. App: same (MD:28, MD:37) | none |
| D2 Tab strip | partly | Design `.tabs`: label "MEDIA BIN" then tabs 12/500, padding 7 x 9, selected = text colour with a **2 pt blue (`sel`)** underline. App (MD:98-109): 12 pt, selected semibold, underline is **cyan** (MD:107) | S |
| D3 Layer choice | partly | Design: seg "Background layer" / "Foreground", selected = surface-3 + ring. App (MD:114-125): labels "Background" / "Foreground" (MediaLayerChoice.title), no ring, radius 4 | S |
| D4 Add / collapse icons | partly | Design: ghost buttons 22 pt, icons 12. App plain buttons, muted. Fine apart from size | S |
| D5 Tile layout | no | Design: **7 columns filling the width** (grid repeat(7,1fr), gap 10, padding 10 x 14 x 6), about 103 pt wide. App (MD:133): fixed width max(88, min(220, (height-60)*16/9)), measured about 135 pt, horizontal scroll with the last tile cut off (UI-003-show.png) | M |
| D6 Dock height | partly | Design: about 180 pt (tabs 40, tiles about 85, controller 46). App default is taller, about 221 pt measured | S |
| D7 Tile ring and tags | partly | Same pattern as slides (G5-G8) with the same offsets. Design: 2/3 pt at 2 pt offset. App: 3 + 4 padding and radius 6 / 8 (MD:214-217) | S |
| D8 Duration badge | partly | Design `.dur`: mono 9/600, radius 3, bg 60 % black, 4 pt in. App (MD:209-211): mono 11/500 (wfMonoData), square corners (no radius), 3 pt in | S |
| D9 Tile name | partly | Design: 11 pt, weight 500, one line, ellipsis. App (MD:218): 12 pt regular, text colour, middle truncation | S |
| D10 Drag a tile onto a slide (MEDIA-010) | extra | Not in the design | not in design |

## 7. Media controller row

| Element | Present? | Differences | Size |
|---|---|---|---|
| C1 Row frame | partly | Design `.ctl`: padding 6 x 14 x 10, no extra rule, about 40 pt tall. App (MD:340-342): 46 pt, own top rule and own surface fill | S |
| C2 Buttons | partly | Design `.btn.ib`: 28 x 24, radius 6, icons 12; pause shows surface-3 fill when playing. App ControllerButtonStyle: 30 x 28, selected = cyan 1.5 pt stroke (MD:395) | S |
| C3 Name | partly | Design: one line, "Waves — teal.mov" 12 pt **bold**, with file extension. App: two lines, name 13/600 plus a kind caption "Background" / "Clip over the words" / "Sound" (MD:321-324) | S |
| C4 Times | partly | Design: mono 11 with tenths "00:11.4" and "−00:18.6" (true minus sign). App: mono 12, no tenths "0:10", ASCII hyphen "-0:10" (MD:326, 332) | S |
| C5 Scrubber | partly | Design: custom track 5 pt, radius 3, surface-3 track, cyan fill, 13 pt white thumb with a 1 px ring. App: system `Slider` with cyan tint (MD:327) | M (shared K4) |
| C6 Loop control | partly | Design: a pill "⟲ Loop" in cyan (22 pt), on state. App: background shows the plain text "Loops" (MD:353); fg clip shows a repeat icon button; no pill | S |
| C7 Volume | partly | Design: speaker icon, then a 70 pt scrubber with BLUE fill at 60 %. App: 80 pt system slider, cyan | S |
| C8 Screen chip(s) | yes | Design: AUD pill 18 pt. App PillTag 20 pt | S |
| C9 Strip in other modes (MediaTransportStrip) | extra | Shown above the transport bar in every mode but Show (CV:90-93). Not in the design. Uses system `Button`, `Label`, `.red`, `Color.red.opacity(0.10)`; none of it is token styled (MediaTransportStrip.swift:16, 45) | not in design, M restyle |

Behaviour the design implies that the app already has: the controller only appears while a clip or sound is loaded.

## 8. Inspector

### 8a. Monitors

| Element | Present? | Differences | Size |
|---|---|---|---|
| I1 Section padding | partly | Design `.sec`: 10 x 12. App: 14 top and sides, 12 bottom (SI:17) | S |
| I2 Monitor header badges | partly | Design: "Preview" is an OUTLINED blue badge (`badge c-aud`), radius 4, followed by "slide 4" (11 muted); "Live" is the filled red badge. App (SI:40): PREVIEW is a FILLED blue tag (Badge.preview) with radius 3; "slide 4" is 12 pt | S |
| I3 Live caption | partly | Design: "Audience · SDI 3" (role and connector). App: profile name only, "Audience" (SI:59) | S |
| I4 Monitor corner radius | partly | Design `.mon .thumb`: radius 6. App clips at 3 (Thumbnails.swift:211, 224) | S |
| I5 Preview ring | partly | Same as G6 (3 pt padding, radius 6, 2 pt stroke) | S |
| I6 Live ring | partly | Design 3 pt at 2 pt offset. App pads 7 (SI:104), a visibly larger gap in the screenshot | S |
| I7 Two buttons under the monitors ("Quick edit ⌘E" and "Edit live slide…") | extra | Not in the design. They push Stage and Broadcast down by about 40 pt; the design puts them straight under Preview and Live | not in design |
| I8 Stage / Broadcast cards | partly | Design: preview, then ONE caption line: coloured dot + bold role + connector ("SDI 4", "SDI 1+2") and a SIM badge 9 pt. App (SI:140-159): role 12/600, then a destination text of up to 2 lines ("Simulated SDI card (4 connectors), connectors 1 a…"), then the profile name ("Livestream graphics"), 3 lines in all | M |
| I9 Stage monitor content | partly | Design: current line, "NEXT · …" line and clock "10:32" top-right. App stage preview shows all lines of both languages, plus extra small lines and the stage message (UI-003-show.png) | S/M (stage layout default) |
| I10 "Configure…" link | extra | Design README says screen configuration is not on this screen. App has a link (SI:134) | not in design |

### 8b. Look row

| Element | Present? | Differences | Size |
|---|---|---|---|
| I11 Row | partly | Design `.lk`: label "Look" 36 wide, buttons flex 1, **24 pt tall, 11 pt text**, radius 6, gap 4, chevron ghost. App: 26 pt, 12 pt, gap 6, label 38 (SI:177) | S |
| I12 Selected state | partly | Design: surface-3 fill + 1.5 pt `sel` BLUE ring. App: surface-3 + 2 pt **cyan** ring (SI:184) | S |
| I13 Look names | partly | Design: Full, Notes, Lower 3rd, BG only. App seed: "Standard" (SettingsModel.swift:107) and user Looks (screenshots show Standard, Notes, Sermon). The design set is not seeded | S/M (Q4) |

### 8c. Live override row

| Element | Present? | Differences | Size |
|---|---|---|---|
| I14 "Live background override: name" with Drop | extra | Not in the design (SI:202-216). Uses `liveFill` red film icon and a system-weight text | not in design |

### 8d. Tabs

| Element | Present? | Differences | Size |
|---|---|---|---|
| I15 Tab strip | partly | Design `.tabs`: 12/500, padding 7 x 9, gap 2, strip padding 0 10, selected underline 2 pt **blue**. App (SI:220-241): 13 pt (selected semibold), gap 12, 30 pt, underline **cyan** | S |
| I16 Quick edit tab | partly | Design: pencil icon + "Quick edit" + 6 pt blue dot. App: text + dot, no icon (SI:226-227) | S |
| I17 Props tab | partly | See table 8e | |
| I18 Cues tab | extra | The design does not draw its content. App: macro buttons, next scheduled event, slide-action note, "Open the Cues mode" (CuesTab.swift) | not in design |
| I19 Audio tab | extra | Not drawn in the design. App AudioPanel.swift uses system controls: `.headline`, `.caption2`, `.toggleStyle(.button)` (AudioPanel.swift:121, 125), system `Slider`/`Picker`, not the token styles | not in design, M restyle |

### 8e. Props tab

| Element | Present? | Differences | Size |
|---|---|---|---|
| I20 Prop kinds | partly | Design: four props with different icons: "Church logo bug" (image), "Service title strap" (text), "Speaker name" (text), "Giving reminder" (megaphone). App props are image files only (`prop.imagePath`, SI:263-266). No text or announcement props | L |
| I21 Per-prop destinations | no | Design: each prop has its own AUD / BRD pills (logo: AUD+BRD, strap: BRD, speaker: BRD, reminder: AUD). App shows the SAME role pills on every prop, from the active Look's props layer (SI:256, 270). The model has no per-prop target | L |
| I22 Row | partly | Design `.prow`: 28 pt, icon 15, pills 16 pt tall. App: 18 pt icon, pills 20 pt | S |
| I23 Toggle | no | Design `.tgl`: 30 x 18, on = cyan, off = border-strong, white 14 pt knob. App: system switch with cyan tint (SI:275), 38 x 22 | M (shared K2) |
| I24 Empty text | extra | "No props. Add a logo image in Screens…" | not in design |

### 8f. Quick edit tab (01b-operator-show-quick-edit.png)

| Element | Present? | Differences | Size |
|---|---|---|---|
| Q1 Header | partly | Design: "Slide 4 of 9" bold 13, "Chorus" muted 11, pill "Preview only" 18 pt (11/600, blue). App (SI:300-304): 14/600, 12 pt section, pill 22 pt, 12 medium | S |
| Q2 Done (esc) | partly | Design: in the **footer row**, bottom-right, beside the saved note. App: top-right in the header row (SI:305) | S |
| Q3 Field labels | partly | Design: real language names, "ENGLISH" and "TIẾNG VIỆT", then "SPEAKER NOTES · STAGE ONLY". App: "FIRST LANGUAGE", "SECOND LANGUAGE", "SPEAKER NOTES — STAGE SCREENS ONLY" (SI:309-311). Language names are not in the model | M (L if languages need storing) |
| Q4 Field style | partly | Design: 46 pt (two lines) with a 2 pt glow ring (sel at 35 %) on the focused field; notes field 30 pt with placeholder "None". App TextEditor min 50 / 34, focus ring is the system one, no "None" placeholder (CP:342-360) | S |
| Q5 Footer note | partly | Design: "Saved 2 s ago · live at next trigger". App: "Saved · <previewNote>" (SI:312), no elapsed time | S |
| Q6 Stage message while open | differs | In the 01b mockup the stage-message section disappears while Quick edit is open (the `editTab` replaces `propsTab`, which contained it). App keeps it pinned. See A3 | S (A3) |

### 8g. Stage message

| Element | Present? | Differences | Size |
|---|---|---|---|
| ST1 Position | partly | Design: a section directly under the tab content, border-top, grows to fill, label at its top. App: pinned to the bottom of the column under a rule (SI:25-26) | S |
| ST2 Field + Send | partly | Design: field 26 pt fill bg + "Send" `.btn` with message icon, always looks enabled. App: same field, Send is dimmed at 40 % while empty (SM:60) | S |
| ST3 Extras | extra | "Stage screens only" caption, recent-messages clock menu, "On stage now: …" row with Clear (SM:16, 47-55, 25-34). Not in the design; the privacy caption is arguably needed | not in design |

## 9. Transport bar

| Element | Present? | Differences | Size |
|---|---|---|---|
| TR1 Bar | yes | 56 pt, surface, top border. Design padding 0 14 gap 10; app padding 14, gap **8** (Space.s3, TB:11) | S |
| TR2 State badge | partly | Design: `badge fill` 11 pt, padding 3 x 8, radius 4, text "LIVE". App (TB:111-112): 12/bold, padding 10 x 28 pt tall, radius 3 | S |
| TR3 Headline | partly | Design: first-language line only, lines joined with ", ", "My chains are gone, I’ve been set free"; sub "Amazing Grace · Chorus · slide 3 of 9". App headline in UI-003-show.png joins lines with a space and appends the second language and so ends in "…" (LiveSummary.line). Sub line matches | S |
| TR4 Buttons | partly | Design `.btn.lg`: 36 pt, **padding 0 16**, radius 8, 13/600, icon 15. App padding **12** (CO:148). Previous / Go Live / Next with ← ↩ → hints: present | S |
| TR5 Clear | partly | Design: ONE button "Clear ⌄" (no key hint) with a menu. App: split control: "Clear esc" + separate chevron cell (TB:71-97) | S |
| TR6 Blackout / Stop | yes | Design: Blackout with B, Stop with no hint. Matches | none |
| TR7 Screens button | extra | Display icon that opens/closes screens (TB:138-145). Not in the design | not in design |
| TR8 Health | partly | Design: mono 11, left-aligned two lines: cyan "●" + "59.94 fps" and "dropped 0 · late 0". App: right-aligned, no cyan dot, text colour (TB:150-153). When screens are closed it prints "screens closed" (TB:160) | S |
| TR9 Meters | partly | Design `.meter`: 2 bars 6 pt wide, gap 3, 34 pt tall, gradient cyan to warning to **live (red)**. App (TB:200): 5 pt x 30, cyan only, comment says red means on screen. See A4 | S |
| TR10 Layer clears (Clear menu: background, foreground, music, words) | extra | Design Clear menu is not drawn. App menu has Clear all plus four layer entries | not in design |
| TR11 Other states (STOPPED, CLEARED, BLACKOUT badges) | extra | Design shows only live | not in design |

## 10. Shared components (08-components.png, 10-components-light.png)

| Component | In app? | Differences | Size |
|---|---|---|---|
| K1 Buttons | partly | `.btn` = HeaderButtonStyle: matches. `.btn.primary` (brand gradient, on-brand text, "Run"): **no style exists** (Tok.brandGradient is declared at DesignTokens.swift:35 but unused). `.btn.ghost` ("Configure…"): done ad hoc with `.plain` + muted in 6 places. `.btn.off`: 45 % opacity, app 40 % (CO:154, 169) | S |
| K2 Toggle and checkbox | no | `.tgl` 30 x 18 (on = cyan, off = border-strong, white knob) and `.chk` 14 x 14 radius 3 (on = blue fill + on-brand check; check is white in light). App uses system `.switch` and `.checkbox` (ControlPanels.swift:125, 149, 259, 408, 521; CuesEditors.swift:191; CuesControlInputs.swift:25, 79) | M |
| K3 Segmented control | partly | Design `.seg` (surface-2 track, 1 px border, surface-3 selected with ring, 3 labels or 2 icons). Only the mode switcher is drawn this way; everywhere else the system segmented Picker is used (CP:91, LS:447, others) | M |
| K4 Slider / scrubber | no | Design `.scrub`: 5 pt track, 13 pt white thumb with ring. System `Slider` everywhere | M |
| K5 Field and dropdown field | partly | `.field`: 26 pt, radius 6, fill bg, border-strong; dropdown shows a chevron at right ("1080p59.94 ⌄"). App: search field and stage field are hand-drawn; dropdowns are system Picker/Menu | S/M |
| K6 Role badges (Audience / Stage / Broadcast) | yes | RoleChip, Badge outline. Matches | none |
| K7 Pills: AUD / STG / BRD, Running, Signal lost, Off | partly | AUD / STG / BRD (RolePillView) are done. "Running" (cyan dot), "Signal lost" (warning icon), "Off" (muted) exist only inside RolePillView's status. The generic `PillTag` has no dot or icon variants, and weight is 700 against the design's 600 | S |
| K8 State badges | partly | Live (filled) and Simulated / Hardware Verified / Not Verified (outline) work with Badge. "Preview" in the design is **outline** blue; app Badge.preview is filled (CO:55-67) and the radius is 3 vs the design's 4 (`.badge`). The thumbnail TAG is the one that stays filled. Needs two styles | S |
| K9 Slide thumbnail states | partly | Idle with 1 px border, preview 2 pt blue, live 3 pt red, all at 2 pt offset, transparent on the checker. App has no idle outline and bigger offsets (G5-G7) | S |
| K10 Messages (error card) | partly | Design: padding 8 x 12, radius 8, 1 px warning border, fill surface-2, 15 pt icon, bold first sentence + plain second; below it "Retry output" button and ghost "Details". App ErrorBar (CV:229-245): full-width strip, warning fill at 16 %, no border or radius, whole message plain, only a "Dismiss" button | M (look) |
| K11 Error actions ("Retry output", "Details") | no | Needs a per-error action in the model | L |
| K12 Colour swatches | yes | Token list matches the asset catalog (UI-001 test). Not compared value by value here | none |
| K13 Light theme | partly | Checked on UI-003-show-light.png vs 09. Looks and tag colours follow tokens. Differences: the dock tab underline, Look ring and monitor badges are cyan/filled in light too (same S items). On the PREVIEW tag the design uses white text in light, `on-brand` in dark; app uses Tok.bg in both (CO:57) | S |

## 11. Not in the design (the owner decides where these go)

- Sidebar: Scripture row with ⌘J and the whole Scripture view; search-result match tags; playlist "+" menu; program export / import; "not installed" and "empty" tags; playlist drag-reorder.
- The bin player (BinPlayerPanel) and hot folders live in Media mode (ModeViews.swift:193 and MediaBinPanel), not in the Show sidebar.
- Header: "Add to playlist" icon.
- Grid: own-background mark; context menu; drop a media tile onto a slide.
- Dock: tile drag source, resize handle.
- Inspector: "Quick edit" button under Preview, "Edit live slide…" button under Live (with popover), "Configure…" link, live background override row with Drop, Cues tab content, Audio tab content.
- Stage message: "Stage screens only", recents, "On stage now" with Clear.
- Transport: screens open/close button, layer-clear entries, STOPPED / CLEARED / BLACKOUT states.
- Other modes: MediaTransportStrip above the transport bar.

## 12. Ambiguities and disagreements between design sources

- A1 Timers colour: tokens.json says cyan is for "timers"; the mockup and PNG draw the service value in the text colour and the idle sermon value muted. App uses cyan for a running timer.
- A2 Clear key: README semantics table says Clear = ⌘K (slide) and ⇧⌘K (all), and "every transport action has a visible key hint" (principle 4); the mockup draws Clear and Stop with no hint; the app shows "esc" on Clear and nothing on Stop.
- A3 Quick edit: the mockup removes the stage message while Quick edit is open, which looks like a mockup artefact; README does not say it.
- A4 Meters: mockup meter ends in red (`--live`); README principle 1 says nothing else may use red; app comment says cyan only.
- A5 Tag/ending colour: tokens.json says bridge, ending and tag labels are warning; ui.css defines `--tag` as the broadcast colour.
- A6 Badge radius: tokens say radius-xs 3 for LIVE/PREVIEW tags and radius-sm 4 for badges; ui.css has `.badge` 4 and `.thumb .tag` 3. The monitor "Preview"/"Live" are `.badge`, so 4.
- A7 Radii: tokens say segmented controls 6; ui.css `.seg` is 7 with 5 inside; `.tm` is 7; app uses 8 / 6 / 10.
- A8 Section padding: tokens say sidebar section padding 12, pane padding 14; ui.css `.sec` is 10 x 12; app uses 14 and 8.
- A9 Timer type: tokens define mono-readout as 17/22 for timer readouts; the toolbar timers are drawn at 13.
- A10 README says Configure lives only in the Screens tab; 08 lists a "Configure…" ghost button as an example, and the app shows it in Show.
- A11 README says the Show window has "Stage and Screens may become sheets" (open decision); the app has them as modes, so the design drawn here is the modes version.
- A12 Quick edit placement: README says the Quick edit tab is "absent when nothing is being edited"; the app also shows two Quick edit buttons in the monitors that the design does not have.

## 13. Count

By size, with the number of ID'd rows: S about 78, M 12, L 6.

- L: SB4 library kinds (Sermons, Announcements); PL5 media-file and announcements-loop playlist items; I20 text/announcement props; I21 per-prop destination routing; K11 error actions (Retry / Details); and Q3 if language names need storing (counted as M).
- M: T1 service date title, T3 sidebar toggle, SB7 song list (selection artefact), D5 dock tile layout, C5/K4 custom scrubber, I8 Stage/Broadcast captions, I23/K2 toggle and checkbox, K3 segmented control, K10 error card, C9 MediaTransportStrip restyle, I19 Audio tab restyle, Q3 field labels.

## Questions for the owner

1. **Library kinds.** The design shows four libraries (Songs, Scripture, Sermons, Announcements), each with its own icon; the app has user-made libraries that are all songs, plus a separate Scripture row. Options: (a) keep user libraries, give each library an optional kind that picks the icon (small model change); (b) build the four fixed kinds as the design shows, with a sermon-notes and an announcements item type; (c) keep today's behaviour and only change icons and counts. Recommendation: (a) now, (b) as a later milestone if sermons and announcements are wanted.

2. **Playlist item types.** The design playlist holds a media file ("Baptism testimony.mov"), an "Announcements loop" and a sermon item. The app has songs, countdowns, scripture and headers. Options: (a) add a media-file item only; (b) add media file, announcements loop and sermon notes; (c) leave the types and just draw what exists. Recommendation: (a), because a clip in the service order is the one a church uses every week; the other two wait for their own libraries.

3. **Props.** The design has text props (service title strap, speaker name) and an announcement prop, each with its own AUD / BRD target. The app has image props, and the same role pills on every prop. Options: (a) add per-prop targets for the image props only; (b) add text props with a target each (a real feature: text object, font, position); (c) keep as is. Recommendation: (a) now; (b) goes with the lower-third work (KEY).

4. **Default Looks.** The design shows Full, Notes, Lower 3rd, BG only; the app seeds one Look, "Standard", and the owner's own Looks (Notes, Sermon). Options: (a) seed the four design Looks on a new library and leave existing libraries alone; (b) rename nothing and just match the look of the buttons; (c) seed them on every library. Recommendation: (a).

5. **The extras the design does not show.** Quick edit button under Preview, "Edit live slide…" under Live, the Configure link, the override row, and the screens button in the transport bar. Options: (a) keep all, but fit them into the design's layout (Quick edit stays only in the header; the live-edit and override controls move into one slim row under the monitors; screens button moves to the toolbar); (b) keep all where they are; (c) remove the duplicates (the preview Quick edit button and the Configure link). Recommendation: (a), because the monitors then match the design pixel for pixel and nothing the operator asked for is lost.

6. **Clear key and hints.** The design draws Clear with no hint and Stop with no hint; README says ⌘K / ⇧⌘K and "every transport action has a visible key hint"; the app uses esc / ⇧esc. Options: (a) keep esc, show "esc" on Clear and ⌘. on Stop; (b) match the picture: no hints on Clear and Stop; (c) change the keys to the README's ⌘K / ⇧⌘K. Recommendation: (a), since the keys are already muscle memory and the README principle asks for hints.

7. **Red in the meters.** The mockup meter turns red at the top; README says only Go Live, LIVE tags and the live ring may be red. Options: (a) keep cyan, with warning at the top; (b) copy the mockup and use red only above a clip level. Recommendation: (a), to keep the "red means on air" rule.

8. **Timer colour.** tokens.json says cyan; the picture draws them in the text and muted colours. Options: (a) follow the picture (text colour when running, muted when idle, warning on overrun); (b) keep cyan while running. Recommendation: (a), because the owner asked for pixel for pixel and the picture is the reference.

9. **Native controls vs the design's custom ones.** The design draws its own toggle, checkbox, slider and segmented control; the app uses the system ones (README says tokens tint system controls and do not replace them). Options: (a) build token-styled versions and use them in Show and the shared components only; (b) build them app-wide; (c) keep the system controls. Recommendation: (a) first, then (b) once the owner has seen Show.

10. **Sidebar toggle and service title.** The design has a sidebar-toggle button and a title like "Sunday 9:00 — 22 Nov". Options: (a) add the toggle, keep the playlist name as the title; (b) add the toggle and store a service date on the playlist so the title reads like the design; (c) neither. Recommendation: (b).
