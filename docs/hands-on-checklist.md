# Hands-on checklist

For a person at the Mac. About 30 minutes. Tick each line or write what happened. Covers KI-011, KI-026, KI-029, KI-037, KI-040.

Build and open:

```bash
cd /Volumes/Storage/chilt/worshipflow && ./scripts/check.sh && open ~/Library/Developer/Xcode/DerivedData/WORSHIPFLOW-check/Build/Products/Debug/WORSHIPFLOW.app
```

This creates the real library at `~/Library/Application Support/WORSHIPFLOW/Library.sqlite`.

## Keyboard

- [ ] On launch, without clicking anything, Space does not type into the search field.
- [ ] Command-I opens Import lyrics. Paste two verses in English and Vietnamese, set two lines per slide, save.
- [ ] Click a slide, press Return: it goes live (red outline; Audience preview shows it).
- [ ] Space and Right arrow go to the next slide; Left arrow goes back.
- [ ] Escape clears the words; the background stays.
- [ ] While typing in the slide's text field, Space types a space and does not advance the slide.
- [ ] Command-F puts the cursor in search; type a Vietnamese word without accents; the song appears; Escape returns to the grid.

## Libraries and playlists

- [ ] Create a second library, rename it, delete it.
- [ ] Add two songs to the playlist, drag to reorder, remove one.
- [ ] In a playlist, Next at the end of song one continues into song two.

## Editing while live

- [ ] With a slide live, change a word in the editor: the thumbnail changes, the Audience preview does not.
- [ ] Quick edit live slide, change a word, Apply: the Audience preview changes.

## Screens (needs the second display free)

- [ ] Screens panel: set Audience to the second display, Stage to Window. Open screens.
- [ ] The second display shows lyrics full-screen; the stage window shows current and next.
- [ ] Unplug the second display's cable: the app keeps running and reports the fault. Plug it back: the output returns on that display.
- [ ] Drag the stage window behind another window: its readout says "hidden", not an error.

## Themes, Looks, props

- [ ] Themes: make a custom theme, change font size and colour by typing and with the colour panel, use it for the song.
- [ ] Add a logo image as a prop; it stays across slide changes and Clear; toggle it off.
- [ ] Make a second Look that hides props on one screen; switch Looks.

## Stage

- [ ] Stage layouts: duplicate Standard, drag the clock, resize the current-slide box, add a timer element.
- [ ] Timers: add a 1-minute countdown, start it, let it pass zero: it shows a minus sign in the warning colour.

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

- [ ] Objects mode: insert a rectangle, drag it, resize by its corner, change fill and opacity.
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
