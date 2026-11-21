# WORSHIPFLOW — the app as built (for the UI design session)

These are screenshots of the real, running macOS app on 2026-11-20. It is a native SwiftUI and AppKit app. The design should restyle and refine this interface; the structure below already exists and works.

## Window layout

One operator window, three columns and a bottom bar:

- **Left column:** library picker with its presentations on top; playlist picker with its items below. A red dot marks the playlist item that is on screen.
- **Centre:** the open presentation. Title, theme picker, and buttons (Add slide, Re-flow lyrics, Add to playlist). Below that, a grid of slide thumbnails grouped by section (Verse 1, Chorus…) with a coloured dot per section; the live slide has a red outline and a LIVE badge. Under the grid, an editor for the selected slide: first language, second language, speaker notes — or, in Objects mode, a canvas with an inspector.
- **Right column (scrolls):** Live screens (one preview per output: Audience, Stage, Broadcast), Media bin, Audio, Timers and clock, Screens (destinations, themes, layers, SDI connector map), Looks, Props.
- **Bottom bar:** state (STOPPED or LIVE), the live text, and transport buttons: Previous, Go Live, Next, Clear, Stop, Quick edit live slide, Open or Close screens. While a video clip plays, a transport strip appears above it (pause, scrubber, elapsed and remaining, mute, volume, Stop clip).
- **Toolbar:** sidebar toggle, app name, buttons that open sheets (Import lyrics, Section orders, Themes, Stage layouts), and search.

## Screens in this folder

| File | What it shows |
|---|---|
| `01-workspace-song-live.png` | The main workspace with a bilingual song live: English with Vietnamese, section headers, live outline, Audience and Stage previews, Screens panel. |
| `02-workspace-foreground-video.png` | A video clip playing in the foreground: Audience preview shows the clip with no words, Stage still shows current and next lyrics, the clip transport strip is visible, Media bin below. |
| `03-slide-objects-editor.png` | Objects mode: the slide canvas with a rectangle and a selected text box, the object inspector, and undo, redo, duplicate, delete. |
| `04-slide-objects-live.png` | The same slide after Go Live, with the objects on the Audience preview. |
| `05-theme-editor.png` | Themes sheet: built-in and custom themes, live preview, background choice, font, size, colour, outline, frame and alignment. |
| `06-section-order-editor.png` | Section orders sheet: a palette of the song's sections and an ordered list built from them. |
| `07-stage-layout-editor.png` | Stage layouts sheet: a 16:9 canvas with current lyrics, next lyrics, clock, a countdown and a message as movable boxes, plus an inspector. |
| `08-timers-and-clock.png` | Right column: stage layout picker, a running countdown with Pause, Reset, Rename, Delete, and the 12 or 24 hour clock setting. |
| `09-media-bin.png` | Media bin: thumbnail tiles, a BACKGROUND badge, a "Missing file" tile, kind filter, Set as background, Play in foreground. |
| `10-audio-panel.png` | Audio: output device picker, mute, volume, level meter, list of sound files with a scrubber. |
| `11-screens-sdi-connector-map.png` | Screens panel with an SDI card: connector map (1 fill, 2 key, 3 mirror, 4 unused), a keyed Broadcast screen, status and frame counters. |
| `12-screens-mirror.png` | The same panel scrolled: a mirror destination with its own status line. |

## Things the design must respect

- **macOS native.** Standard window chrome, toolbar, sheets, menus and keyboard shortcuts. No web views.
- **Dark by default.** It runs in a dim sanctuary; a light appearance is optional.
- **Live state must be unmistakable.** Red is reserved for "this is on screen now" (LIVE badge, live outline, on-screen dot, the clip strip). Do not use red for anything else.
- **Bilingual text.** English with Vietnamese, including stacked diacritics (ễ, ậ, ở). Any font must render them without clipping.
- **Operated by volunteers under time pressure.** Large, labelled transport buttons; nothing important hidden behind a hover.
- **Three kinds of screen:** Audience, Stage and Broadcast. The same slide looks different on each.
- **Honest status.** A simulated device is always labelled "Simulated"; faults are stated in words.

## What does not exist yet

An app icon, a logo, a designed colour and type system, an onboarding or first-run screen, and a preferences window. These are open for the design to define.
