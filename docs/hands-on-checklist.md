# Hands-on checklist

For a person at the Mac. About 30 minutes. Tick each line or write what happened. Covers KI-011, KI-026, KI-029, KI-037, KI-040.

Build and open:

```bash
cd /Volumes/Storage/chilt/worshipflow && ./scripts/check.sh && open ~/Library/Developer/Xcode/DerivedData/WORSHIPFLOW-check/Build/Products/Debug/WorshipFlow.app
```

This creates the real library at `~/Library/Application Support/WORSHIPFLOW/Library.sqlite`.

## Modes, Blackout and transport (UI-001)

- [ ] The toolbar switcher shows Show, Edit, Media, Stage, Cues, Screens. Command-1 to Command-6 switch to each, also while the cursor is in a text field. Quit and reopen: the last mode is back.
- [ ] The transport bar (LIVE or STOPPED badge, the live words, "Song · Section · slide 3 of 9", Previous, Go Live, Next, Clear with its menu, Blackout, Stop, frame rate and dropped or late counts) is visible in every mode.
- [ ] With a song live, switch to Screens, then to Media: Space still advances and Shift-Space goes back (the arrow keys only move the selection), Escape clears, Return takes the selected slide live. In a text field they type instead.
- [ ] Press B with the slide grid focused: Audience goes black, Broadcast goes transparent (not black), Stage keeps its words and shows BLACKOUT. The transport badge reads BLACKOUT and the place is kept. Press B again: the same slide is back.
- [ ] While blacked out, press Next, or click a slide twice: the picture comes back on that slide. While blacked out, Escape then B: the screens come back with the words still cleared. Stop ends Blackout.
- [ ] Holding B does not flicker the screens. B in the search field or a text box types the letter. B does nothing with no slide live.
- [ ] A clip playing over the slide keeps playing through Blackout (check the media controller row under the dock in Show, or the clip strip above the transport bar in the other modes).
- [ ] AUD, STG and BRD pills: on while that role's screen runs, off when closed or disabled; unplug a display and its pill shows a warning triangle and the word fault to VoiceOver.
- [ ] Screens mode: "Run signal test…" opens the Hardware Test window. Cues mode shows only the one-line note.
- [ ] Show mode: Preview (blue ring) and Live (red ring, only while words are on screen) sit side by side at the top of the right column; Stage and Broadcast (every other enabled screen) are beneath, each captioned with its destination and a SIM badge for the simulated card; the Look row switches the Look (the rest are in its chevron menu); props toggle in the Props tab; the timers in the toolbar run.
- [ ] Quick edit (Command-E, the header button or the button under Preview) opens the Quick edit tab for the SELECTED slide and changes Preview only. "Edit live slide…" (Option-Command-E, the button under Live, or the Edit header) is the one that changes the live words, from any mode.

## Keyboard

- [ ] On launch, without clicking anything, Space does not type into the search field.
- [ ] Command-I opens Import lyrics. Paste two verses in English and Vietnamese, set two lines per slide, save.
- [ ] Click a slide, press Return: it goes live (red outline; Audience preview shows it).
- [ ] Space goes to the next slide; Shift-Space goes back. The arrow keys only move the selection (Preview): nothing on any screen changes until Return.
- [ ] Escape clears the words; the background stays.
- [ ] While typing in the slide's text field, Space types a space and does not advance the slide.
- [ ] Command-F puts the cursor in the search field at the top of Libraries in the sidebar (from any mode); type a Vietnamese word without accents; the song appears in the list beneath; Escape clears it and returns to the grid. There is no search field in the toolbar.

## Libraries and playlists

- [ ] Create a second library, rename it, delete it.
- [ ] Add two songs to the playlist, drag to reorder, remove one.
- [ ] In a playlist, Next at the end of song one continues into song two.

## Editing while live

- [ ] With a slide live, change a word in the editor: the thumbnail changes, the Audience preview does not.
- [ ] Edit live slide…, change a word, Apply to live: the Audience preview changes. (The Quick edit tab, by contrast, never changes it.)

## Screens (needs the second display free)

- [ ] Screens mode (Command-6): set Audience to the second display, Stage to Window. Open screens.
- [ ] The second display shows lyrics full-screen; the stage window shows current and next.
- [ ] Unplug the second display's cable: the app keeps running and reports the fault. Plug it back: the output returns on that display.
- [ ] Drag the stage window behind another window: its readout says "hidden", not an error.

## Themes, Looks, props

- [ ] Themes: make a custom theme, change font size and colour by typing and with the colour panel, use it for the song.
- [ ] Add a logo image as a prop; it stays across slide changes and Clear; toggle it off.
- [ ] Make a second Look that hides props on one screen; switch Looks.

## Stage

- [ ] Stage mode (Command-4): duplicate Standard, drag the clock, resize the current-slide box, add a timer element.
- [ ] Timers: add a 1-minute countdown, start it, let it pass zero: it shows a minus sign in the warning colour.

## Screens mode, light appearance, playlist headers and countdowns (UI-002)

- [ ] Show and Edit headers: the buttons carry words ("Add slide", "Reflow…", "Quick edit ⌘E"); narrow the window to the minimum (1100 x 640) and they become icons with tooltips and VoiceOver labels.
- [ ] The window shows the service name once (title and library as its subtitle); the right-hand pane is not empty.
- [ ] Clear is one split control: click hides the words; the arrow beside it offers Clear all (and stops a clip).
- [ ] Slide thumbnails show the theme colour, and the chosen background video or picture as one still frame, not flat black.
- [ ] Screens mode (Command-6): the list on the left (picture, name, role, destination, enable switch); click a screen, the settings change; the enable switch starts and stops it.
- [ ] Signal map, simulated card on (Developer): connector tiles appear in the card's own order; on a card that reports fill on the second connector the fill tile is SDI 2 and the key tile SDI 1; the map and every tile read SIMULATED; a fault is written on the tile in words.
- [ ] Signal map, real card: tiles follow what the card reports; no tile says SIMULATED; nothing names a converter, switcher or projector unless you typed it into "Connected to".
- [ ] "Connected to" note: type a note for a screen and for a mirror; it appears beside that destination on the map and is still there after a relaunch; removing a mirror removes its note.
- [ ] Presets: "Independent outputs" and "Fill + Key broadcast" list what would change before anything does; Cancel changes nothing; Apply moves the screens; if the card must change profile it asks first.
- [ ] A keyed screen shows three pictures: composite over the checkerboard, fill, and key (white where opaque), with the connector numbers the card reports.
- [ ] Verification card: says Simulated for the simulator, "Implemented, not hardware verified" for a real card; "Run signal test…" opens the Hardware Test window; "Export log bundle…" saves a zip and sends no video.
- [ ] Edit mode: the slide list is grouped by section; Text, Shape and Image buttons add the object to the selected slide. Media mode: the kinds are listed on the left with counts; Import… adds files. Stage mode: layouts, element buttons on top, elements and the screens that use the layout on the right.
- [ ] Appearance (View > Appearance): System, Dark, Light; the choice is kept after a relaunch; every mode is readable in Light (selected rows, chips, the transport bar); the output screens do not change colour.
- [ ] Playlist "+": Add header… and Add countdown…; headers are not numbered and cannot be selected; Next and Previous skip them; drag reorder works across songs, headers and countdowns.
- [ ] Countdown: Go Live on it shows the time on the audience screen in the theme's main text style and on the stage screen; at 0:00 it stays at 0:00 until you press Next; it never moves on by itself; deleting it while live clears the screens; relaunch with a header selected lands on the next song.

## Show mode, design revision 2 (UI-003)

- [ ] The slide grid shows five thumbnails across at a 1440-point window and more when wider; sections keep their coloured labels.
- [ ] Media dock under the grid: tabs Backgrounds, Videos, Images, Audio; Background / Foreground choice; "+" adds files; the chevron folds it away. Click a picture or video with Background chosen: it plays behind the words at once, without leaving Show. With Foreground chosen (and a slide live) it plays over the words. A sound plays as a cue whichever choice is on. Drag the top edge of the dock to resize; quit and reopen: the height and the folded state are kept.
- [ ] A tile on screen now has the red ring and LIVE; a tile you chose that is not on screen is blue; red never appears on anything else.
- [ ] Media controller row (only while a clip, a sound or a background video is loaded): restart, play or pause, stop, name, elapsed and remaining, scrubber, loop, mute and volume, and the screens it is on (AUD, BRD). Loop on a clip makes it start again at its end. It stays visible when the dock is folded. In Edit, Media, Stage, Cues and Screens the clip strip above the transport bar still shows while a clip plays.
- [ ] Toolbar timers: by default the first elapsed timer and the first countdown, beside AUD, STG and BRD, in every mode. A countdown has a start or pause button. Past zero it turns the warning colour (not red). The Timers panel (Stage mode) has a toolbar toggle per timer. With no timers nothing is drawn.
- [ ] Quick edit tab: Command-E opens a fourth tab with the selected slide's two languages and notes, a "Preview only" chip and Done (Escape). Typing there changes the Preview slide, not the Audience screen. Escape or Done closes the tab and puts the focus on the grid. The tab is absent when nothing is being edited.
- [ ] Stage message (bottom of the right column, and in Stage mode): type and Send: it appears on the Stage screen only (a banner when the layout has no message element), never on Audience or Broadcast; it stays when you change slides; Clear removes it; Stop removes it; the clock icon lists the last five messages.
- [ ] Props tab: the AUD and BRD chips show only the roles whose screens show the props layer under the current Look; hide the layer for a screen in Screens and the chip goes. Cues tab: a note that nothing is wired yet. Audio tab: the audio panel.
- [ ] "Configure…" under the monitors opens the Screens mode.

## Media

- [ ] Media bin: Add… a video and a picture; drop another file onto the bin. Thumbnails appear.
- [ ] Set the video as background: it plays behind the words on the output.
- [ ] Play a clip with sound in the foreground: you hear it; pause, drag the scrubber, change volume, mute.
- [ ] Let the clip end: the words come back.

## Audio (KI-047)

- [ ] Add a sound file to the media bin. In Audio, press play at low volume: you hear it and the meter moves.
- [ ] Pause, drag the scrubber, toggle loop, mute.
- [ ] Choose another output device in the picker: sound moves to it. Unplug that device: sound falls back to the default and the app says so.
- [ ] Play a video with sound in the foreground: it comes out of the chosen device, once, not doubled.

## Slide objects

- [ ] Edit mode (Command-2): insert a rectangle, drag it, resize by its corner, change fill and opacity.
- [ ] Insert a text box, double-click to edit its text, add a shadow.
- [ ] Insert an image. Command-D duplicates, Delete removes, Command-Z undoes, Shift-Command-Z redoes.

## Safety (review fixes, KI-043)

- [ ] With a song live, hold Space for three seconds: it advances one slide only.
- [ ] With screens open, press Command-Q: the app asks before quitting. Cancel keeps everything running.
- [ ] With screens open, press Command-W or click the red button on the operator window: the app does not quit.
- [ ] With screens open, Command-H is unavailable or leaves the outputs showing.
- [ ] Shift-Escape during a foreground clip removes the words and stops the clip; plain Escape removes only the words.
- [ ] Change the theme of the song that is live: the output changes only when you go live again.
- [ ] Close screens during a clip with sound: the sound stops.
- [ ] Change the second display's resolution in System Settings while it shows an output: the output still fills the display.

## Data safety

- [ ] Type a word into a slide, wait six seconds, force-quit (Option-Command-Escape). Reopen: the word is there.
- [ ] Reopen the app: the same playlist item and slide are selected, and nothing is live.

## Hardware Test window and Blackout (FIX-D)

- [ ] Open the Hardware Test window (Help menu) with a show running in the operator window: Space, Return, the arrows and B do nothing to the show while the Hardware Test window is in front.
- [ ] Start a test, then try to open the screens from the operator window: the app refuses and says the Hardware Test is running.
- [ ] Quit the app during a test (Force Quit is fine). A folder ending `WorshipFlow-hardware-test-unfinished` (`WORSHIPFLOW-` on a report from an older build) is on the Desktop. Open the Hardware Test window again: it offers "Save its report...". Save it, and the folder disappears.
- [ ] Play a video clip with sound over a live slide, press B: the sound stops with the picture. Press B again: the sound is back at the same level.
- [ ] In a playlist, click a countdown, then click a slide of the song above it, then Go Live (Return): the slide goes live, not the countdown.

## Cues (CUE-002b)

- [ ] Cues mode (Command-5): press + under Macros, name it, add three actions (a Look, a stage message, a timer). Press Run: the Look changes, the message shows on the Stage screen, the timer runs. The Activity list says what ran.
- [ ] Make a macro, then open Show and its Cues tab: the macro is a button; clicking it runs it. "Next scheduled event" names the next event, or says there is none.
- [ ] Slide actions: give one slide a Look change. Click the slide (preview only): nothing changes. Double-click it: the Look changes. Quick edit it, or press Escape: it does not run again.
- [ ] A slide action list refuses "Next slide" and similar, and says why.
- [ ] Delete a macro that a MIDI binding or another macro uses: you are told what uses it, and "Delete anyway" removes those references.
- [ ] Re-flow a song whose slides have actions (Command-I on it, change one slide's words): the sheet lists the actions that will be dropped; unchanged slides keep theirs.
- [ ] Schedule: add an event a minute ahead that runs a macro: it runs once. Close the app, wait past a second event, reopen: it is not run late and a notice says it was missed.
- [ ] Close the lid (sleep) over a scheduled time and wake: the missed event is reported, not run.
- [ ] Start a Hardware Test, then let a scheduled event come due: it does not run, and a notice says why.
- [ ] MIDI is off on a fresh library. Turn it on, choose your pad controller, press Learn and tap a pad: a binding appears. Tap it: the command runs once even if you hold the pad. Bind the same pad twice: both rows show a warning.
- [ ] Unplug the controller: the status says it is offline. Plug it back in: it reconnects by itself.
- [ ] Send a MIDI note from another program to "WorshipFlow In" with Virtual ports on: it runs its binding.
- [ ] Remote control is off on a fresh library. Turn it on: the pairing code, a countdown and the address are shown, with the plain-HTTP sentence. On a phone on the same Wi-Fi open the address, enter the code: the phone pairs, shows the slide, and Next works.
- [ ] Press Next on the phone and Space on the Mac at the same time many times: the show advances once per press, in order, never twice at once.
- [ ] Revoke the phone: its next tap is refused. Revoke all with two phones: both are refused. Turn remote control off: the phone cannot reach the page.
- [ ] Make a macro "Next, wait 30 seconds, Next" and run it, then press Blackout before 30 seconds pass: the second Next never happens and the activity list says "cancelled: 1 waiting step". The same with Clear, Clear all and Stop. Blackout off cancels nothing.
- [ ] Open the Hardware Test window and start a test. A MIDI pad and the phone do nothing to the show (the phone is told the test is running); the Mac's buttons and keys still work. A scheduled event that falls due during the test shows under "Not run" in the Cues schedule afterwards; Dismiss all clears it.
- [ ] Revoke a phone: it is refused at once. Quit and reopen with remote control on: it is still refused. Switch remote control on and off quickly several times: afterwards the switch, the shown address and the real state agree. Join another Wi-Fi network while it is on: the address shown changes within a moment.

## LIB-004c scripture

- [ ] Command-J opens Scripture with the cursor in the reference field. With no translation installed it says so and offers Import.
- [ ] Import a translation file you may use: progress, then a plain result. Import the same file again: you are asked before it is replaced. Remove it: you are asked first.
- [ ] Type `John 3:16-18` and Return: slides appear and the Preview monitor shows the first. Nothing changes on the audience screen. Type `Giăng 3:16`: the same verse.
- [ ] Return again goes live; Space steps on, the arrows move the selection; Next at the last slide stays. Mouse: click a slide (Preview only), double-click (live).
- [ ] Choose a second translation: both languages show on each slide; a verse missing in one shows the other alone. Check the stage and livestream screens show current and next, and the lower third.
- [ ] Add to playlist, quit, reopen: the item is there and opens. Remove its translation: the item stays, says "not installed", and Next into it stops with a message.
- [ ] Save as presentation: it opens and can be edited. Search a Vietnamese word without accents: the verse is found and opens.
- [ ] (FIX-F) Step from the last slide of a song into a scripture playlist item with Next, then with a MIDI pad or the phone: the centre shows the passage, not "no presentation". Quit while a passage item is selected and reopen: the centre shows it.
- [ ] (FIX-F) Open a passage from the playlist, change the second translation, press Go Live, then Next past its last slide: the show goes on to the next playlist item. Type something new in the reference field without pressing Return and change a translation: the passage on screen does not change and your typing stays.
- [ ] (FIX-F) With a passage shown, remove its translation: the passage turns into the "not installed" message and Add to playlist does not add it; what is live does not change. Replace a translation with a changed file: the shown passage takes the new words.
- [ ] (FIX-F) Type `Psalm 119; Psalm 78; Psalm 89; Psalm 105` with one verse per slide: you are told how many slides it would be and asked to narrow it. Press Import twice quickly (or while the replace question is open): the second is ignored and the button is dimmed.
- [ ] (FIX-F) With a playlist item whose translation is removed between two songs: Next stops with a message; Next again skips it and says so. Do something else (Go Live on another slide) and Next again: it stops again.
- [ ] (FIX-F, KI-094) Open the same scripture item under two different audience themes or verses-per-slide settings: the slide count can differ. That is expected.
- [ ] (FIX-F) The X of the Scripture view closes the passage too: Preview goes empty, live is untouched.

## LIB-005 program export and import

Use a scratch library on both "Macs" (two `--library` files), and a folder standing for a USB stick. Do not use the real library for the first run.

- [ ] Build a short program at home: a song with a picture object on a slide, a song with a section order, a header, a countdown, a Bible passage, a slide action that plays a clip. File > Export Program…: the sheet lists items, media files and total size. Put a file on a drive, unplug the drive, and open the sheet again: the file is listed as unreadable and the button says "Export without the missing files…".
- [ ] Export: a save panel appears and asks before replacing a file. The result is one file in Finder (a package, not a folder), with the WorshipFlow icon behaviour of a document. Cancel in the middle of a large export: nothing is left at the destination or next to it.
- [ ] On the other library: File > Import Program…, then again by double-clicking the file in Finder, then by dropping it on the window. Each shows the summary first. Import: the playlist plays slide for slide, the picture and the clip are there, with the original drive disconnected. Quit, move the whole library folder to another place, reopen with `--library` there: the pictures and clips are still found.
- [ ] Import the same file again: the summary says nothing to import and the button is off.
- [ ] Change a lyric at church, change it differently at home, export again, import: the summary lists the song as having different content. Try each answer: Keep both (copy titled "(imported)" and a "(imported)" playlist that plays it), Keep mine, Use the imported one.
- [ ] Open a program that has a Bible passage in a library without that translation: the item imports and says "not installed".
- [ ] Hand-edit a copy of the package so a path says `../x` or is absolute, or replace a media file by a link: opening it says in plain words that it was not opened and nothing changes in the library.
- [ ] Look for the Finder icon and the single-file display on a Mac that has the app in Applications (Launch Services registration was not tried).

## MEDIA-010 live media control

- [ ] Media mode: click a video in the bin. The sidebar shows a player for it with play, pause, a scrubber, the time, Loop and Mute. Nothing changes on the screens. Click a sound: the same without a picture. Click a picture: the picture alone. Start the app with `--silent-audio`: the preview stays silent.
- [ ] Double-click a video (layer choice Background), or press "Send to live background": the live screens change, the slides' thumbnails and the Preview monitor do not, and the Show inspector says "Live background override" with a Drop button. Press Next several times: the override stays. Drop: each slide's own background (or the theme's) shows again.
- [ ] Clear menu (the chevron next to Clear): Clear background, Clear foreground and Clear music, with Control-Option-B, F and M. Each takes away only its own layer. Go Live, Next or a new choice from the bin brings a background back. Blackout on, Clear background, Blackout off: the words come back and the background stays cleared.
- [ ] Put a video behind the words (its sound is off), then click the speaker in the controller row: you hear it, and the icon matches. Press Next: it stays on. Blackout: silent; lifting it brings the sound back.
- [ ] Media mode, Folders, +: choose a folder of videos. They appear as a source. Copy a new video into the folder: it appears when the copy is complete (not while it is growing). Rename and delete one in Finder: the bin follows. Play folder on the background: the videos play one after another in name order and start again. Rename the folder in Finder: it shows as missing; "Point to the folder again…" fixes it. The show is never held up.
- [ ] Drag a video from the bin onto one slide's thumbnail in Show or Edit, then drag a picture from Finder onto another: each shows a small mark. Go live on a slide with a mark: its background plays. Right-click it, "Clear this slide's background": the mark goes (one Command-Z brings it back); "Set background…" there picks from the bin. If that slide is live, the screens keep the old background until you take the slide live again. Command-Z with that slide selected in Edit undoes a drop. Quit and reopen: the marks are still there.
- [ ] Check what was not seen by the coordinator's run: the drag and drop gestures themselves, the folder open panel, the double click, the real Clear menu popup and the player's video picture.

## UI-004 name, About, rounded borders, editor drag

- [ ] The app is called WorshipFlow in the menu bar, the Dock, the window title and the About window (WorshipFlow.app in Finder). The library is the same one as before: your songs and playlists are there. Nothing moved.
- [ ] Menu WorshipFlow > About WorshipFlow, and Help > About and version...: the icon, a short paragraph, one version line (version, build number, commit, build date), Copy puts that line on the clipboard, "Developed by Simon Lieu" with a mail link, the licence, the project link and the third-party notices. It follows Dark and Light. Press Space or Return in it: the show does not move.
- [ ] Hardware Test: the report's environment section and `summary.txt` carry the same version line as About.
- [ ] Look at the mode switcher, the AUD, STG and BRD pills, the timers, and the AUD pill at the end of the media controller, in Dark and Light, on a normal and a Retina display: every outline is complete and round, nothing is cut off at the ends, and the last pill is not clipped by the window edge.
- [ ] Edit mode: insert a rectangle and a text box. Press on one and drag slowly and fast: it follows the pointer with no lag and starts after a few points of movement; letting go leaves it where you dropped it; one Undo puts it back. The thumbnails and the saved file change when you let go, not during. With another slide live, dragging never changes the live screens. Grab the corner square by its general area (not only the tiny square). Double-click a text box to type in it. A click without moving only selects.

## FIX-G review fixes (MEDIA-010, LIB-005)

- [ ] Put a video with sound behind the words, unmute it (speaker in the controller row), then Clear background: the sound stops with the picture. Next brings both back. Stop: silent. Blackout: silent, and back when it lifts.
- [ ] Give two slides the same bin video as their own background. Remove that video from the bin: a sheet names both slides first. After removing, the slides still show the mark, now a warning triangle, and show their words on the theme's own background. Re-flow a song whose slide had its own background: unchanged slides keep it; the loss list names a slide that cannot.
- [ ] Export a program whose slides have their own backgrounds, delete the bin items and import it on a second Mac (or a second library): the backgrounds and their files come back.
- [ ] Import a program with "Use the imported one" while a slide of the same song is open with text typed a second ago: the open slide shows the imported words and your typing does not come back; the result says where the backup is (`Backups` next to the library) and that backup opens as a library with your typing in it. With the song live, "Use the imported one" keeps both and says so.
- [ ] Import something big onto a nearly full drive: it says there is not enough room before copying anything.
- [ ] Hot folders: follow a folder on a USB drive, unplug the drive, relaunch: the app opens at once, the folder says "missing" or "not answering", the show works. Plug it back: the files return (and a remembered hot-folder background plays again). Rename the followed folder in Finder: it keeps working. Drop a file that macOS cannot read into the folder: it is listed as unreadable once, not retried every two seconds. Play folder with an unreadable file in it: it skips it and says so once.
- [ ] Media mode: select a video; the player starts muted, the speaker button turns the sound on, the line under it says which output it would use. Send the item live: the player pauses.

## UI-005a shared components and Show

- [ ] Open Show at 1440 x 900 in Dark and Light and hold it beside `docs/UI/screens/01-operator-show.png` and `09-operator-show-light.png`: toolbar, sidebar, grid, dock, inspector and transport bar line up; the toolbar's sidebar button hides and shows the sidebar (Option-Command-S).
- [ ] Drag the edge between the sidebar and the slides, between the slides and the inspector, and the line between the song list and the playlist: they move within 240-380, 320-440 and the sidebar's height. Hide the sidebar and bring it back.
- [ ] Tab through the toolbar, the header, the Look row, the tabs and the transport bar with full keyboard access on: every segmented control, toggle and tab can be reached and operated with Space; with VoiceOver on each says its name, its value (on or off, selected) and what it does. Up and Down in the song list change the song.
- [ ] Props: each toggle switches its prop (the design's pill with the cyan "on"); the slider in the media controller scrubs and the volume changes the sound; both can be moved with the arrow keys and VoiceOver.
- [ ] Edit, Stage and Screens have no transport bar: Space, Return, the arrows, B and Escape still move the show; the toolbar shows LIVE and the slide while something is on the screens.
- [ ] The Clear button is one button with a menu (Clear words with Escape, Clear all, the layers); Stop has no key hint; the screens button is in the toolbar.
- [ ] Edit live slide, the live background override (Drop) and Configure are in the slim row under the monitors; Quick edit is in the header only and gets a blue ring while its tab is open.

## UI-005b the features Show's design draws

- [ ] Toolbar timers read `00:10:32` and `25:00`; Quick edit's fields are named English and Tiếng Việt for a bilingual song and "Saved 2 s ago" counts up after you type.
- [ ] Playlist menu > Set service date and time…: the window title reads "Sunday 9:00 — 22 Nov" (in your language); Remove date brings the playlist name back; export and import the program: the date comes back.
- [ ] Libraries: New library > Sermons and Announcements (icons, order); Library kind changes the icon.
- [ ] Right-click a bin tile > Add to playlist: select the item (the bin player shows it, the screens do not change); Go Live plays it; Next moves on and stops it; Stop ends it. Do it with a video, a picture and a sound.
- [ ] Playlist menu > Add announcements loop…: pictures cycle until you press Next; a single video repeats.
- [ ] A song from a Sermons library added to the playlist shows "Sermon — title" with the text icon.
- [ ] Props tab: click AUD, BRD pills; right-click > Show on; Add text prop… with Vietnamese words: it appears only on the screens you picked; speaker notes still appear on stage screens only.
- [ ] A new library starts with Full, Notes, Lower 3rd and BG only; an existing library keeps its own Looks.
- [ ] Unplug a screen while the show runs: the card says which output stopped; Retry output after plugging it back; Details shows the recorded text and Copy copies it.

- [ ] UI-005i: the interface text is Inter (rounded "G", flat-topped "1"); menus and the title bar stay the system font. About lists Inter. A song titled in Vietnamese, Chinese, Thai or Burmese shows no boxes in the library list, and rows keep their height.

## FIX-H review fixes (UI-005a, UI-005b)

- [ ] Announcements loop live, then play a clip from the bin or the dock: the loop does not put its picture back over your clip, and the playlist stops showing the loop as live. Clear the foreground while a loop runs: the same.
- [ ] Blackout, then Next onto a video, a loop and a sound in the playlist: Blackout lifts and the picture and sound start together. The same after Clear and Clear background.
- [ ] A file the bin lists but whose drive is unplugged: Go Live or Next onto it says which file, nothing is marked live and the screens keep what they had.
- [ ] Switch to another playlist or delete the playlist while a loop or a sound is live: it stops; Next and Previous still work.
- [ ] A screen with a mirror: unplug the mirror's display, Retry output: only the mirror restarts (the primary does not blink).
- [ ] With macOS System Settings > Keyboard > "Keyboard navigation" ON, in Edit, Stage and Screens (no transport bar): Tab to a toggle, a checkbox, a segmented control, a tab, a slider and a button: Space and Return act on that control and the show does not move; the arrows move the slider and the segmented control; Escape returns focus to the show, then Space advances the show.
- [ ] Sliders: Tab to the volume and position sliders; left and right arrows move them a step, Page Up and Down more, Home and End to the ends; with VoiceOver each says Position or its volume name and its value, and VoiceOver's adjust action moves it. A muted volume slider is dimmed and takes no key or click. A disabled toggle, checkbox and segmented control are dimmed and ignore clicks and Space.
- [ ] VoiceOver on a segmented control and on the tabs: each segment or tab says its name and whether it is selected; the prop pills say AUD, STG or BRD for the prop, on or off, and act as toggles.
- [ ] Props: click a pill (it dims and stays), click again (it comes back). Add text prop: the sheet says "Saved off. Switch it on when you want it shown."; the prop is off in the list; untick every screen and Save is refused with a line saying why.
- [ ] In Edit, Stage and Screens the toolbar chip names the live video or loop, not a blank slide.
- [ ] Add a second audience screen after the Notes Look was made: it follows the Notes Look's audience entry.
- [ ] Open a library copy that a newer build has migrated (or one with an extra row in grdb_migrations, made on a scratch copy): the app says the library was last opened by a newer WorshipFlow, names the steps, changes nothing, and offers Quit or Open a different library. Do not do this on the real library.

## UI-005j measuring Show against the mockup (by hand)

1. `scripts/design-rects docs/UI/mockups/01-operator-show.html /tmp/design.json` writes every visible element's rectangle, font, colour and radius from the mockup (WebKit, 1440 x 900, Inter loaded from `Vendor/Inter`; add `--light` for the light theme, `--png out.png` for a picture of the render).
2. `UI_PREFIX=UI-005j scripts/design-capture.sh` builds a throw-away copy of the app, captures it at 1440 x 900 and also writes `<prefix>-show-dark.rects.json`: the rectangles of every view tagged with `.wfRect("id")` (debug builds only).
3. `scripts/compare-rects.py /tmp/design.json <app>.rects.json scripts/design-map-show.json --top 5` prints, per region, the elements mapped and within 1 point; add `--all --bad --rects` for every element still out, `--unmapped` for the unmapped lists with their reasons.
4. Check by eye: the window's top bar is the app's own (drag it; the three window buttons sit at its left); Add to playlist is in a song's context menu; the extras row is at the bottom of the right column.

## UI-005h output looks (by hand)

- [ ] Existing library: open it with this build. Songs that use the built-in theme (or none) now show Inter type on the design's teal-to-navy gradient; your own themes look exactly as before. The theme list has "Classic full screen" and "Classic lower third": pick one for a song and its old look returns.
- [ ] Audience screen: the two languages are centred as one group, white 600 and yellow 500, soft shadow, no outline; a looping background still plays over the gradient and a slide's own background covers it. Vietnamese marks are not clipped on the longest line.
- [ ] Broadcast screen (Lower 3rd Look): a dark rounded plate with a teal-to-blue bar sits above the bottom, grows upwards with a second line, and disappears on Clear and Blackout. In Screens the Key preview shows a light grey plate, a white bar and white text on black; the Fill preview shows the plate and text.
- [ ] Stage screen: current lyric, the second language on one line, NEXT and the next line in grey-blue (not green), the clock at the top right and the countdown below it in teal (red when it runs over); send a message: a yellow band with dark text along the bottom. A stage layout you made earlier looks as before.
- [ ] Not built, so do not look for them: the W watermark on the audience screen and the section label "CHORUS x2" on the stage.
- [ ] With real hardware only: send the lower third's fill and key to the keyer and check the plate's transparency, the edges of the plate and the text against the checkerboard. Nothing here has seen a keyer.

## FIX-I keyboard, backgrounds and the warning card (by hand)

- [ ] Click a slide, then a media bin tile, then the sidebar, then the inspector, then close a sheet: after each, Space still advances and Shift-Space goes back. (Build 101 lost these keys after a click in the media bin.)
- [ ] The slide grid has a quiet blue edge when it has the arrows; click the media bin and the edge moves to the bin. A click in the sidebar, playlist or inspector leaves it where it was. Opening a presentation gives it back to the grid.
- [ ] Slide grid: Left, Right, Up, Down move the blue Preview ring only; the Live ring and every screen stay still. Return takes the selected slide live. Right on the last slide of a song opened from the playlist selects the next playlist item (a header is skipped; a countdown, file or loop is selected as an item, a song opens on its first slide); Left on the first slide goes back to the last slide of the previous item. At the ends of the playlist, and for a song opened from the library, it stops.
- [ ] Media bin (Show dock or the Media mode): the arrows move the selection and the player; Return sends the selected item live on the layer the bin's switch says. Arrows never change the live clip.
- [ ] Put a bin picture live as the background, press Clear background (or Control-Option-B), then Next and Previous: the bin tile is no longer LIVE, the inspector row is gone, and the slides show their own or the theme's background. Clear foreground and Clear all drop their bin choices too. Blackout twice changes nothing.
- [ ] Every slide thumbnail (grid, list, Edit, Preview monitor) shows the background the slide will have; a video shows one still with a small film mark; remove a file from disk and its thumbnail shows the missing mark. The Live monitor still shows the real picture including a bin choice.
- [ ] Unplug an output (or use the simulated card's unplug): the red message fades after about 5 seconds, the toolbar pill and the monitor keep the fault, a click on the pill shows the card again with Retry output and Details. Keep the pointer over the card (or Tab onto its buttons): it stays until you leave.

## FIX-J fit, cache, loading and stage parts (by hand)

- [ ] Open a song with a long English line and a Vietnamese translation on the built-in theme: the audience screen shows every line inside the picture (the text is a little smaller than a short slide's, both languages by the same amount); nothing is cut off at the top. The Preview thumbnail and the Live monitor agree.
- [ ] Type a very long first line (a paragraph): the words stay inside the title-safe frame at the smallest size, the thumbnail has a small warning triangle and the editor shows "These words do not fit this theme at its smallest size". Shorten the line and both go away.
- [ ] A Classic theme and a theme you made: a long line is not shrunk (it behaves as before). In the theme editor turn on "Shrink the words to fit their boxes": it shrinks now.
- [ ] Select a slide (Preview), then Go Live: the words appear at once (no half-second pause on the first slide after a long idle). Stage clock and timers tick all service without the lyrics flickering.
- [ ] Stage editor: duplicate the built-in layout, drag the current-slide box: its second-language line goes with it; resize it: the line scales with it. Same for the next-slide box and the word NEXT.
- [ ] Damaged data (only if you have a copy of a library to spare): a theme or stage layout the app cannot read is skipped, the others still list, and one message names the skipped one.
- [ ] If the bundled font is ever missing (a damaged app), one red bar says screens are using a system font. A hardware-test report's machine section has an "Output font" line.

## UI-005c Edit

- [ ] Edit: select a text box, drag each of the eight handles and press Command-Z once (one step each); type a hex colour, "0 4 16" in the shadow field and "2" in the outline field; switch Object / Slide / Theme; type words in the Slide tab and see the filmstrip follow; pick a weight in Style.

## UI-005d Media

- [ ] In Media: click each row of the list; click a tile (blue ring, strip shows it), double-click (goes live as the layer switch says, red ring only while on air); play, restart and stop in the strip; Live background / Live foreground; the clear icons (tooltip with the key, greyed when nothing to clear, each clears only its layer; Clear in the transport bar still works); switch grid / list; add a folder; drag a tile on a slide; change the output device; play a sound and watch the Audio cue card and the Levels move.

## UI-005g Cues

- [ ] Cues: hover an action row: move, edit and remove appear at its right; Tab through the row reaches them; the edit popover still opens.
- [ ] Cues: rename a macro in the bar's title (Return or leaving the field); delete from the ellipsis menu in the bar; "..." on a MIDI row deletes that binding.
- [ ] Cues: the left column's Stream Deck row cannot be clicked; Schedule sits below Control inputs.
- [ ] Cues: dark and light, a window narrower than 1440: the bar's Run button stays at the right.

## FIX-K (build after 115)

- [ ] Edit: click a lyric box (the dashed rectangles over the words), drag it, drag each of its eight handles, press the arrow keys (Shift for 10): only that slide's words move; Command-Z undoes the whole drag in one step; the other slides and the screens do not change.
- [ ] Edit: select a lyric box: Position fields, "Reset to theme position" and "Apply to all slides in this song" in the inspector; the same two in the box's right-click menu.
- [ ] Edit: add a text box, a shape and an image; drag, resize from every handle and nudge each.
- [ ] Media: click a video tile: no clear icon lights; send it live as the background: only the background icon lights, with a film glyph and a tooltip naming the clip; as a picture: a photo glyph.
- [ ] Transport bar: Clear has no arrow and no menu; Escape, the icons and the Show menu still clear.
- [ ] Edit, Stage, Screens: no red LIVE chip at the top right; the mode tabs sit at the left next to the title.
- [ ] Show with a long song and a full bin: drag the sidebar and inspector edges (a blue line follows, the columns move on release); reorder slides, playlist items, drop a tile on a slide and a file on the bin: nothing hitches.

## UI-005e Stage

- [ ] Stage: pick a layout card; rename the layout in the bar; Duplicate and Delete…; Timers… sheet; add each element with the bar buttons; drag a box and its corner handle; Shows / Size (type and stepper) / Weight / Colour (swatch and hex); element list selects the box; the Assigned to switch moves a stage screen to this layout; Send and Clear in the Stage message; the built-in layout shows the buttons disabled.
- [ ] Stage: select, drag and resize each box (all eight handles, lyric boxes included) on your own layout; Command-Z undoes one drag; arrow keys nudge 1 pt, Shift 10; on Standard a drag changes nothing and Duplicate is offered.

## UI-005f Screens

- [ ] Screens: select each screen in the list and from its tile in the map; rename it, change its role and destination; switch Fill and key and Fill alpha; type a "Connected to" label and see "typed by you" in the map; choose a plan under the map and Apply or Cancel; Stop and Start output; add and remove a mirror; scroll to the bottom for the Look list, Props and Developer; check the SIMULATED marks appear only with the simulated card; dark and light.

## FIX-M drag and drop

- [ ] Show with a long song and a full bin: drag a slide to another place (it lands at once; the label under the pointer is small), drag a bin tile onto a slide (its background changes at once), drop a file from Finder on the bin, on the dock and on a slide, and reorder the playlist: no hitch you can see.
- [ ] Two-minute measuring procedure (the system's drag session cannot be replayed without a hand): open Terminal, run `sample WorshipFlow 20 -file ~/Desktop/drag.txt` (use any scratch folder, not a folder shared with others), and while it runs do three drags, each about 5 seconds: a slide to another place, a bin tile onto a slide, a file from Finder onto the bin. Open the file and look at the main thread: lines under `NSDisplayCycleFlush` and `NSHostingView.layout` are the window redrawing; more than about 10 percent of the 20 seconds busy, or a single stretch of more than 8 ms between the drops, is a hitch worth reporting with the file. Or: Instruments, template Animation Hitches, attach to WorshipFlow, do the same three drags, and read the hitch list (each row longer than 8 ms is one).
- [ ] Optional, no hand needed: `scripts/measure-drags.sh` builds a debug copy against a throw-away library and prints the replayed numbers.


## FIX-N canvases and keys

- [ ] Stage, a custom layout: click a box, then press Space (Next), Return (Go Live), B (blackout: an amber BLACKOUT tag appears in the toolbar, B again removes it) and Escape (CLEARED appears). Drag a box, release, press the same keys. Open and close a sheet (Section orders), press them again. None needs an extra Escape.
- [ ] Stage: click a box, hold the Right arrow for two seconds and let go: the box moves as you hold, the stage screen changes once, and one Undo takes the whole run back.
- [ ] Edit: click a text box, press the arrows (1 point, Shift 10 points) and Space, Return, B. Press Tab until a button in the toolbar has focus: the arrows still nudge the box you clicked last, and Space presses the button.
- [ ] Edit, a lyric box: drag it, press Command-Tab away in the middle of the drag and back, then type a position in the inspector: it saves. "Apply to all slides in this song" asks "Apply this position to N slides?" and one Undo puts every slide back.
- [ ] Clear background icon: with a picture theme or a theme with a motion background it is lit and its tooltip says "Clear background: theme video" or "picture".


## FIX-O drops and the show state

- [ ] Show, a song with many slides: drag a bin tile onto a slide, a slide to another place, files from Finder onto a slide and onto the dock. Each should land at once with no catch in the pointer, and nothing else on the screen should flicker (inspector, transport bar, toolbar).
- [ ] Press Space (Next) and Shift-Space with the grid, the inspector and the media dock in view: the red marker moves, the transport line and the Preview picture follow, and nothing else redraws. Press B, B, then Escape: the amber tag and the Blackout button follow, and every thumbnail but the live one stays as it was.
- [ ] Do the same keys in Edit, Media, Stage, Cues and Screens and look at the toolbar tag, the transport bar and the AUD, STG and BRD pills.
- [ ] Optional: `scripts/measure-drags.sh` (with `UI_SNAPSHOT_FIXO=1`) prints drop and gesture times and view body counts; `scripts/fixo-modes.sh` checks every mode for parts that did not follow.

## FIX-P review fixes

- [ ] Edit, a lyric box: set its position on slide 1, choose "Apply to all slides in this song", then press Undo without leaving slide 1: every slide goes back. Redo applies it again.
- [ ] Apply to all, then edit the position on slide 3, select slide 2 and press Undo: slides 1 and 2 go back, slide 3 keeps its edit, and the message says "Position restored on 2 of 3 slides; 1 was edited since."
- [ ] Stage: drag a box and, while still holding the mouse button, click another application's window or press Command-Tab: the box stays where it was when you left (it does not jump again when you come back and move). Do the same in Edit with a text box and with a handle.
- [ ] Stage, a custom layout: select a box, switch to another layout and press the arrows: the slide selection moves (no box is selected), and a box you were nudging when you switched is written to the layout you left.
- [ ] System Settings, Keyboard: set "Delay Until Repeat" to the longest, then hold an arrow on the Stage canvas and in Edit: one run, one Undo step.
- [ ] After clicking a box, press Tab until a radio group (Hardware Test, or a sheet that has one) has focus: the arrows change the choice, not the box.
- [ ] MIDI: with a real controller bound to Next, press pads while scrolling a long song and playing a clip: the slide follows within a blink. Note any delay.

## FIX-Q Next, Previous and drops on the main thread

- [ ] Show, a song with many slides, a media clip chosen as the background or loaded as the clip over the words: while it plays the Media controller row under the grid shows its time and the scrubber moves ten times a second. Stop the clip: the row goes away. Press Space (Next) and Shift-Space a few times with nothing loaded: the red marker, the transport line and the previews follow as before.
- [ ] Media mode: play a sound: the Audio cue card and the sound's own row show the time and the meter move; stop it: both go quiet, "No sound playing" shows. (These clocks now run only while something plays.)
- [ ] Drag a slide to another place, a bin tile onto a slide, a file from Finder onto a slide and onto the dock, with the media dock showing and nothing playing: each should land with no catch. The window should feel the same or better than the version before; this is the check the measuring cannot make (the screen was locked while measuring).
- [ ] Cues mode, Slide actions with a long song: press Next from the transport bar or the Space key: the list follows without a pause.
- [ ] Optional, no hand needed: `WF_CONFIG=Release scripts/fixq-run.sh` (gestures), `WF_CONFIG=Release scripts/measure-drags.sh` (drops) and `WF_CONFIG=Release FIXP=midi scripts/fixp-run.sh` (MIDI) build a Release copy with the timing hooks (`WF_MEASURE`) against a throw-away library and print the numbers. Run them on an unlocked screen with the Mac otherwise idle for the cleanest numbers.

## FIX-R which FIX-Q changes stay

- [ ] Show, a long song, nothing loaded: press Space and Shift-Space quickly for ten seconds, then go on pressing slowly. The red marker should follow either way. This is the one thing the measuring cannot say: with the idle tick removed (kept, KI-192) the same press measures about 1.3 to 1.9 times longer in a burst, and shorter in total work. If the operator window feels slower to answer after a pause than during a burst of presses, tell the coordinator: unit (b) can be reverted (four files, see the FIX-R report).
- [ ] Cues mode with a long song: press Next ten times: the list follows without a pause (46 ms measured before, 12 after).
- [ ] Optional, no hand needed: the interleaved method of FIX-R is in `AI/reports/FIX-R-report.md`; the scripts it used are `scripts/fixq-run.sh` and `scripts/measure-drags.sh` with `WF_CONFIG=Release`, run per variant.

## FIX-S the crash on clicking a playlist song (KI-193)

- [ ] Launch with the Performance test library. In Show, open a song with many slides, wait a few seconds, then click a song in the playlist that has fewer slides, then one with more, then the first one again, quickly, ten times. No crash, the grid always shows the song you clicked. Try it also in list view (the Grid and List switch) and in Edit mode (film strip on the left).
- [ ] Switch to the other library in the sidebar, then click a playlist row whose song is in the first library. Same: no crash.
- [ ] Open Launchpad and Spotlight and search "WorshipFlow": only the one in Applications should be listed. (Copies left in Xcode's DerivedData folders may stay listed until Spotlight rebuilds its index; they are marked not to be indexed from now on.)


## UI-006c Edit

- [ ] Edit: select a box, use Align > each of the 7 and press Command-Z once after each (one step); switch Audience / Stage / Broadcast and check the boxes disappear and Text / Shape / Image are disabled; pick 100 % and scroll the canvas, drag a box while zoomed; type in a words field and watch "Saving..." then "Saved just now" then counting up; cut the library file's write permission and check "Not saved".

## UI-006d Media

- [ ] unplug a disk with a bin item on it (or rename the file) and bring the app forward: callout and warning mark appear; Locate... and pick the file in its new place: the item returns, a slide that used it as background shows it again; choose a file of another kind: refused with a message; put the disk back: the callout goes. Make a collection from the "+", from a tile menu and by dragging a tile onto it; rename, delete (items stay); remove an item from the bin and see the count drop; relaunch and see it again; Up/Down in an open collection; light and dark; VoiceOver on the callout and rows.

## UI-006e Stage

- [ ] Stage: on your own layout click the eye of Notes, the canvas box fades and the stage screen drops it; click again. Tick Auto-fit on the lyric and send a long verse: it shrinks, never under 64 px. Change the 2nd lang. colour. Plus menu: make Band, Speaker, Clock only. Tab to an eye button with keyboard access: Space acts on it; click elsewhere and Space, Return, B, Escape act on the show again.

## UI-006f Screens

- [ ] Screens: press Add screen (a "Screen N" appears, off, in a window; select it and choose a destination, turn it on). With the screens closed press Identify screens: every display shows a label for three seconds (operator display, a screen's name, or "No screen is set to this display"). Open the screens: the button is disabled and says why. Select a screen and press Remove screen: Cancel keeps it; Remove deletes it and selects its neighbour; with one screen left the button is disabled. Relaunch: the list is as left. Dark and light. VoiceOver reads the three buttons.

## UI-006g Cues

- [ ] Cues: choose F1 for a macro in the Trigger menu; with focus on the slide grid press F1: the macro runs and Activity says "key macro ...". Focus the search field or a text box and press F1: nothing runs. Hold F1: it runs once.
- [ ] Give F1 to a second macro: the first loses it (the menu said so). Delete a macro: its key is free. Quit and reopen: the keys are back.
- [ ] Cues: Dry run on a macro with a Wait: groups "Right away" and "After n s" in the order Run uses; Run afterwards does the same. Nothing changes on any screen while the popover is open; Escape closes it; VoiceOver reads each step.
- [ ] Cues: a second presentation with slide actions appears in the left column; clicking it opens it in Preview (Live unchanged) and shows its slides.

## FIX-T review fixes

- [ ] (1) open a Media bin that holds a tile with a stored length of 1e300 (edit a scratch library) and see "–:–", no crash; (2) import a hand-made package with `"size": 9223372036854775807` and see the plain refusal; (3) with a Bible passage in the playlist, press Next and remove it from the playlist at the same moment: Next stops with the message; (4) Close screens with an SDI card or the simulator and see the window answer at once; (5) name a playlist "Hardware Test" and press Space, Return, B and the arrows in the operator window: they work.

## UI-007c Edit layers, lock, fit and video

- [ ] Edit: Video menu, add a clip, see the still; go live and see it play in its box on a window screen and the monitor; Stop it; lock a box and try to drag, arrow, Delete; hide a box; Fit a long text box; Background fill; undo each once.

## UI-007d Media marks, markers and Cues marker actions

- [ ] Media: select a video, move the player to 0:04, press Mark in; to 0:09, Mark out. Play in the player: it starts at 0:04 and stops at 0:09; with Loop it starts again at 0:04. Open the list button: type `0:06` for In; clear Out. Right-click Mark in: Clear.
- [ ] Add marker at 0:07, rename it "Lower third on", move it by typing a time, delete it; they stay in time order; relaunch: they are back.
- [ ] Take a slide live, press Live foreground on the marked clip: it starts at the in mark and the words return at the out mark; with the clip looping it restarts at the in mark. Edit the marks while it plays: nothing changes until it is started again.
- [ ] Cues: choose the clip in Playback markers; give a marker "Prop on"; try to add "Next slide": refused with the reason. Play the clip live: Activity says "marker ... at 00:07.0 in ...", the prop shows once; seek over the marker with the transport scrubber: it does not run; seek back and play past: it runs again. Play the clip in the Media preview: nothing runs.
- [ ] With a loop (Live background): the marker runs once per pass. Take the screens down (Stop): nothing runs.
- [ ] Activity Monitor or Instruments: with no marked clip playing there is no 50 ms timer from the app.
- [ ] Light and dark; VoiceOver on Mark in, Mark out, Add marker, the list button and each marker row.

## UI-007e Stage Section elements

- [ ] Stage: your own layout, Section menu, add Section and Next section; with a song live (sections set), the stage screen shows the section name, and NEXT plus the following section on the last slide before a change; hide with the eye; audience and broadcast screens never show them.

## UI-007f Screens key label, signal chain and own Look

- [ ] Screens, select a keyed broadcast screen: type a key label and press Return (the key tile shows it; blank shows the fill's). Add a chain (enclosure, converter), name and reorder it: the map shows the boxes with "typed by you".
- [ ] Choose a Look for one screen: its row shows "Look: name"; select another Look for the show: that screen does not change, the others do; delete the Look: the screen follows the show's Look again.
- [ ] Relaunch: all kept. Dark and light, VoiceOver.

## FIX-V review fixes (macro keys, Remove screen, section order, Stage preview)

- [ ] F5 with a macro in Show/Cues runs once, holding it runs once; in Edit, Stage, Screens, Media, in Settings, and with a button focused in Edit nothing happens; the Trigger menu's first line; F11/F12 and Fn behaviour. Remove screen while open: refusal alert; closed: dialog text with Look names and stage layout; the button not red. Section order: remove rows 1 and 3 in quick succession; drag a row. Edit Stage preview with Speaker preset and Band with Next hidden. Open and close the screens 20 times and compare memory. Media: bring the app forward repeatedly (no check burst), rename a file's folder and wait up to a minute or use Locate.

## FIX-U Show window update after a command

- [ ] Show, with a song live: press Escape (Clear), then Return on a slide, then B twice (Blackout on and off): the amber word in the toolbar appears with Cleared and Blackout and goes away when lifted; the pinned "Edit live slide" row at the bottom of the right column is there while words are live and goes away on Clear; the transport bar's badge and text change with each; nothing is cut or moved (the LIVE badge keeps its width and the headline starts 10 pt after it).
- [ ] Next, Previous and a click on a far slide still scroll the grid to the selection when it is off screen.
- [ ] Feel: Clear, Blackout and Go Live after Clear on a 200-slide song with the real screen unlocked; the report's numbers come from a locked screen.

## FIX-W

- [ ] Play a clip with a marker 0.3 s before its end and one with a marker just before a Pause: the marker runs once.
- [ ] Put a video object on a slide with its file on an unplugged disk, go live: the banner names the clip; replug, publish again: the banner goes.
- [ ] Put five video objects on one slide: the fifth is named in the banner.
- [ ] In Edit give the broadcast screen its own Look and press Broadcast: it matches the broadcast window; add Section to a stage layout: Edit's Stage shows it.
- [ ] Remove the first of two mirrors that have key notes and chains: the second keeps its own.

## FIX-X

- [ ] Video object on the live slide, Blackout, wait, lift: the clip is mid-play, not at its first frame, and an unmuted clip is silent during Blackout.
- [ ] Blackout, then Stop: the video objects' players close.
- [ ] Marker with actions, press the trash button: the alert names the marker and the action count, Return cancels, Escape cancels, "Delete marker" deletes, and the alert is not drawn red.
- [ ] Marker without actions: the trash button deletes it at once.

## FIX-Y

- [ ] Clip with marks 1 s to 2 s used as a video object: loops only inside the marks; change a mark on air, trigger the slide again.
- [ ] Video object live: Clear, wait, un-clear: mid-play, not frame 0; an unmuted object is silent while cleared; Clear background keeps the object playing; Stop closes it.
- [ ] Mark in from the playhead (12.37), open the list, Tab through the In field and a marker time field: the time stays 00:12.4 as shown but the stored value is unchanged (check the marker does not move).
- [ ] Type a key note, click another screen without Return, come back: the note is there; also a chain label.
- [ ] Look panel text, Delete asks with Cancel default, no red; Show inspector line appears only when a screen has its own Look and wraps in the 299 pt column.
- [ ] A hung network volume plus a USB disk with a bin file: the USB file's offline mark updates within about 8 s.
- [ ] Identify screens, then Open screens: labels go at once; rename a screen while they show.
- [ ] Stage editor: hide the only Current slide: refused with the sentence; add Next slide, then it hides.
- [ ] Import a program with equal marks / a picture with marks / a duplicate marker id: read the result's warnings.

## OUT-002f

- [ ] Go Live on a slide whose new content is a text box, a "Shrink to fit box" box and a shape, with and without previewing it first: no visible hitch at the change.
- [ ] Blackout with a stage screen open, before and after changing a slide once: the BLACKOUT word and the black audience screen appear together.
- [ ] Go Live on a previewed slide: it appears at once, not a frame later.
- [ ] A slide image on a network volume, connection dropped, slides changed repeatedly: only the first change waits; after reconnecting, changes behave as before.
- [ ] Drag a window output between displays of different refresh rates: the Screens readout shows no burst of dropped or late frames.

## FIX-AA

- [ ] Install a new build and open it: the window opens without a permission question. Open Hardware Test: the question about the Desktop may appear then, and an unfinished run on the Desktop is offered after it is answered.

## FIX-AB

1. Open a long song with sections (20 or more slides). Press Space repeatedly through to the last slide: the grid scrolls so the live slide stays in view.
2. Click the first slide, then use the arrow keys (Down, Right) past the bottom of the window: the grid scrolls to keep the Preview slide in view.
3. Click a slide already in view: the grid does not jump. Go Live on a slide far above the window: it scrolls up to it.
4. Switch to the list view and repeat 1 and 2. Open a Scripture passage with many slides and repeat 1.
5. In the Show media bin, click a video (Background chosen): picture and sound together. Press the speaker button: muted; click the video again: heard again.
   Press Blackout: silent; lift it: the sound returns. Set a slide's own background video and go to that slide with no bin background: it stays muted.
6. Drop the bin background ("Use the slide's own background"), then go to a slide with its own video: no sound until you unmute.

## FIX-AC

1. Put a video object with sound on a slide, go Live, press Clear: the sound continues. Press Clear all or Blackout: silent. Lift it: it continues from where it was. Stop: it closes.
2. Export a program and open it in build 221 or older: the "saved by a newer WorshipFlow (format 2)" message. A package made by build 221 still opens in the new build.
3. A fresh library on the packaged build: Scripture lists the King James Version with its copyright line; Import still works. Remove it and relaunch: it is not put back.
4. A library that already has a KJV: unchanged after the first launch of the new build.
