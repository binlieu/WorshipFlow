# Hands-on checklist

For a person at the Mac. About 30 minutes. Tick each line or write what happened. Covers KI-011, KI-026, KI-029, KI-037, KI-040.

Build and open:

```bash
cd /Volumes/Storage/chilt/worshipflow && ./scripts/check.sh && open ~/Library/Developer/Xcode/DerivedData/WORSHIPFLOW-check/Build/Products/Debug/WORSHIPFLOW.app
```

This creates the real library at `~/Library/Application Support/WORSHIPFLOW/Library.sqlite`.

## Modes, Blackout and transport (UI-001)

- [ ] The toolbar switcher shows Show, Edit, Media, Stage, Cues, Screens. Command-1 to Command-6 switch to each, also while the cursor is in a text field. Quit and reopen: the last mode is back.
- [ ] The transport bar (LIVE or STOPPED badge, the live words, "Song · Section · slide 3 of 9", Previous, Go Live, Next, Clear with its menu, Blackout, Stop, frame rate and dropped or late counts) is visible in every mode.
- [ ] With a song live, switch to Screens, then to Media: Space and Right arrow still advance, Left arrow goes back, Escape clears, Return goes live. In a text field they type instead.
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
- [ ] Space and Right arrow go to the next slide; Left arrow goes back.
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
- [ ] Quit the app during a test (Force Quit is fine). A folder ending `WORSHIPFLOW-hardware-test-unfinished` is on the Desktop. Open the Hardware Test window again: it offers "Save its report...". Save it, and the folder disappears.
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
