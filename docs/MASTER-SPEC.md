# WORSHIPFLOW — Master Specification

| | |
|---|---|
| Version | 0.3 (development authorised; see `docs/adr/0003-spec-overrides.md` for points overridden by `CLAUDE.md`) |
| Date | 2026-11-20 |
| Source document | `WORSHIPFLOW_Complete_Research_Guide.html` (the "guide") |
| Code status | See `docs/14-current-status.md`. No hardware purchased. |

## 1. Status and how to read this document

This is the single reference that later task specs cite. Every requirement has a stable ID; cite the ID, not the section number.

### 1.1 Provenance labels

Every decision in this document carries one of three labels.

| Label | Meaning |
|---|---|
| **[G]** | Taken from the guide. |
| **[U]** | Stated by the project owner. |
| **[P]** | Proposed by the spec author. Not yet approved by the owner. |

Owner-stated facts so far, in full:

- **[U]** No DeckLink, Thunderbolt enclosure or ATEM is owned yet.
- **[U]** The app must install on other Macs without going through the App Store.
- **[U]** Development is authorised, with standing permission to build without check-ins (2026-11-20).
- **[U]** The project `CLAUDE.md` governs how the work is done and overrides this spec where they differ.
- **[U]** The stack in 5.1 is approved (OPEN-01, 2026-11-20).
- **[U]** The phase plan in section 7 and the feature placement in section 3 are approved (OPEN-02, 2026-11-20).

Everything else that is not in the guide is **[P]** until the owner approves it.

### 1.2 Precedence

1. An owner decision **[U]** overrides everything.
2. This spec overrides the guide on software scope and behaviour.
3. Vendor documentation overrides both this spec and the guide on hardware facts. The guide says its hardware claims must be validated against the exact device, driver and OS versions.

### 1.3 Requirement ID prefixes

| Prefix | Area |
|---|---|
| `PRES` | Presentation and worship features |
| `MEDIA` | Media, video and audio features |
| `SCRN` | Screens and video outputs |
| `AUTO` | Automation and control |
| `LIVE` | Live production and streaming |
| `HW` | Hardware and signal rules |
| `ARCH` | Architecture |
| `DIST` | Packaging and distribution |
| `NFR` | Non-functional requirements |
| `OPEN` | Open decisions |
| `UNV` | Unverified facts |

## 2. Product definition

### 2.1 What it is

**[G]** WORSHIPFLOW is a production system for displaying worship lyrics, Bible passages, slides, videos, announcements, confidence monitors and livestream graphics, with independent control of each output.

**[G]** The defining capability is *one content source, several different looks*. A single song shows at the same moment as:

- full-screen lyrics on the sanctuary screen,
- a lower third on the livestream, and
- current and next lines on the stage confidence display.

### 2.2 Goals

| ID | Goal | Label |
|---|---|---|
| G-1 | An operator can run a complete service from one Mac. | [G] |
| G-2 | Each output has its own formatting, layers and role while sharing the same content. | [G] |
| G-3 | Outputs reach displays over native HDMI or USB-C, 3G-SDI through a DeckLink Duo 2, and the network through NDI. | [G] |
| G-4 | Livestream graphics can be composited over cameras by an ATEM switcher using Fill and Key. | [G] |
| G-5 | The app installs on other Macs from an installer file, outside the App Store. | [U] |
| G-6 | Bilingual lyrics, including English with Vietnamese, render correctly on every output. | [P] (inferred from the guide's worked example) |

### 2.3 Non-goals

| ID | Non-goal | Label |
|---|---|---|
| NG-1 | 4K output over the DeckLink Duo 2. The card is 3G-SDI, HD up to 1080p60. | [G] |
| NG-2 | App Store distribution. | [U] |
| NG-3 | Windows, Linux or Intel Mac support. | [P] |
| NG-4 | Camera switching, broadcast keying and the final programme feed. The ATEM does these. | [G] |
| NG-5 | Mixing microphones and instruments. The audio mixer does this. | [G] |
| NG-6 | Importing documents from other presentation software. Not in the guide. | [P] |
| NG-7 | Reproducing the interface, artwork, file formats or wording of any existing product. See 2.4. | [P] |

### 2.4 Originality

**[G]** The guide says its feature list is adapted from the capabilities of established presentation software and is not evidence that a shipped WORSHIPFLOW exists.

**[P]** This spec therefore describes *function only*. The interface layout, icons, artwork, sample content, document format and user-facing terminology are to be designed fresh. Feature names in section 3 are working names from the guide; the names shown to users are an open decision (OPEN-10).

## 3. Feature catalogue

All 64 features from the guide, in its five groups. Names and purposes are the guide's **[G]**. Phase placement is **[U]**, approved 2026-11-20. Dependency and acceptance are **[P]**.

**Phase** refers to section 7. Each feature has exactly one phase.

**Depends on** uses these classes:

| Class | Meaning |
|---|---|
| none | Buildable and verifiable on the development Mac alone. |
| hardware | Code can be written now; it can only be verified with the named device. |
| licence | Needs an agreement, SDK licence or paid account with a third party. |
| backend | Needs a server that the project would have to run. |

### 3.1 Presentation and worship (13)

| ID | Feature | Purpose | Phase | Depends on | Acceptance |
|---|---|---|---|---|---|
| PRES-01 | Slide editor | Create lyric slides, sermon visuals, shapes, images, and text compositions. | 1 | none | A slide with text, a shape and an image saves, reopens unchanged and renders on an output identically to the editor preview (snapshot test). |
| PRES-02 | Presentation libraries | Organize songs, sermons, Scripture passages, and other content. | 1 | none | Create, rename and delete libraries; move a presentation between them; contents survive a relaunch. |
| PRES-03 | Service playlists | Arrange content in a sequence for a service or event. | 1 | none | Drag presentations into a playlist, reorder them, and step through the whole playlist with the keyboard. |
| PRES-04 | Song arrangements | Reorder verses, choruses, bridges, and endings without changing the source. | 1 | none | Two arrangements of one song play in different orders; editing a lyric updates both. |
| PRES-05 | Reflow editor | Break long lyrics or paragraphs into appropriately sized slides. | 1 | none | Pasted text of 40 lines splits into slides at a chosen line count; moving a break re-splits without losing text. |
| PRES-06 | Themes & templates | Keep font, placement, color, and formatting consistent. | 1 | none | Applying a theme restyles every slide in a presentation; editing the theme updates them all. |
| PRES-07 | Quick edit | Correct words during an event without rebuilding a presentation. | 1 | none | A text correction made on a live slide reaches every output within one second without a visible flash. |
| PRES-08 | Quick search | Find stored songs, presentations, and related content quickly. | 1 | none | Search by title or lyric phrase returns results within 200 ms on a library of 2,000 songs. Matching ignores Vietnamese diacritics when the query has none. |
| PRES-09 | Bible integration | Search passages by reference or keywords and turn verses into slides. | 4 | licence | A reference such as "John 3:16-18" produces themed slides from a bundled public-domain translation. Licensed translations follow OPEN-05. |
| PRES-10 | Multiple translations | Show two translations or languages in one presentation. | 1 | none | A slide shows two independently styled text areas, English and Vietnamese, on every output. Bible dual-translation depends on PRES-09. |
| PRES-11 | Song lyric services | Import lyrics from licensed external catalog services. | 4 | licence | With an authorised account, a searched song imports as a presentation with sections labelled. Provider follows OPEN-06. |
| PRES-12 | Planning integrations | Align content with the planned order of service. | 4 | licence | A service plan pulled from the chosen scheduling platform creates a playlist with items linked to library presentations. Platform follows OPEN-07. |
| PRES-13 | Cloud workspace | Keep media, themes, playlists, and presentations synchronized. | 5 | backend | A change made on one Mac appears on a second Mac signed in to the same workspace. Needs OPEN-09 settled first. |

### 3.2 Media, video and audio (12)

| ID | Feature | Purpose | Phase | Depends on | Acceptance |
|---|---|---|---|---|---|
| MEDIA-01 | Media bin | Store and trigger images, clips, and motion backgrounds. | 1 | none | Imported images and video appear with thumbnails and trigger on click and from a slide. |
| MEDIA-02 | Motion backgrounds | Play moving visual layers behind lyrics. | 1 | none | A looping 1080p video plays behind lyrics for 30 minutes with no visible seam at the loop point and no dropped frames. |
| MEDIA-03 | Foreground videos | Display videos as primary presentation content. | 1 | none | A video plays above the background with transport controls and returns to the previous state when it ends. |
| MEDIA-04 | Live video inputs | Ingest camera or capture-device signals. | 2 | hardware | A camera or capture device appears as a source and shows on a chosen screen. A USB camera covers development. SDI input needs the DeckLink and a connector set as an input, which Plans A and B do not leave free. |
| MEDIA-05 | Audio library | Organize music and sound cues. | 2 | none | Imported audio files play from a list with level control and a visible meter. |
| MEDIA-06 | Audio routing | Assign soundtrack and media audio to the correct destinations. | 2 | hardware | Media audio can be sent to a chosen sound device; embedding in SDI is verified on the DeckLink. Rule HW-08 applies. |
| MEDIA-07 | Object fills & effects | Apply outlines, shadows, masks, fills, and other formatting. | 1 | none | Text outline and shadow render identically in the editor and on outputs (snapshot test). |
| MEDIA-08 | Persistent props | Place logos or graphics above normal presentation content. | 1 | none | A logo stays visible across slide changes until switched off, and can be excluded from a screen by its Look. |
| MEDIA-09 | Temporary messages | Display notifications, greetings, or urgent changes. | 3 | none | A saved message with a fill-in field shows on the audience screen and clears on command or after a set time. |
| MEDIA-10 | Announcements | Run lobby or preservice content independently. | 3 | none | An announcement playlist loops on one output while the operator changes slides on another. |
| MEDIA-11 | Masks | Reveal or hide designated areas of an output. | 3 | none | A mask image hides a chosen region of one output and leaves others untouched. |
| MEDIA-12 | Network streams | Play supported HTTP live-stream media as an input. | 4 | none | An HLS URL plays as a media source and recovers on its own after a 10-second network loss. |

### 3.3 Screens and video outputs (13)

| ID | Feature | Purpose | Phase | Depends on | Acceptance |
|---|---|---|---|---|---|
| SCRN-01 | Independent outputs | Render distinct compositions to different video devices. | 1 | none | The second display and an output window show different compositions of the same live slide at the same time (see 4.5). Extending this to SDI and NDI is covered by SCRN-11 and SCRN-12. |
| SCRN-02 | Audience screens | Send polished presentation content to congregation or livestream. | 1 | none | A screen with the audience role shows slides, media and props, and never shows stage-only content. |
| SCRN-03 | Stage screens | Show confidence text and cues for performers. | 1 | none | A screen with the stage role shows the assigned stage layout and never the audience composition. |
| SCRN-04 | Single display | Use one dedicated output for one composition. | 1 | none | A screen mapped to one display fills it at native resolution with correct aspect ratio. |
| SCRN-05 | Mirrored displays | Send the same composition to multiple endpoints. | 2 | none | One screen mapped to two outputs shows frame-identical content on both. |
| SCRN-06 | Grouped displays | Stretch one composition across a multi-screen wall. | 5 | hardware | One composition spans two physical displays with no gap or overlap at the join. Needs two matched displays or projectors. |
| SCRN-07 | Edge blending | Seamlessly combine overlapping projector images. | 5 | hardware | Two overlapping projectors show one image with an adjustable blend region and no visible bright band. Needs two projectors. |
| SCRN-08 | Screen Looks | Control which layers and effects appear on each destination. | 1 | none | Switching a Look changes which layers each audience screen shows, in one action. |
| SCRN-09 | Alternate themes | Use different lyric formatting on the same underlying slide. | 1 | none | The same slide is full-screen centred on one screen and a lower third on another, with no duplicate content. |
| SCRN-10 | Alpha-key output | Send keyed graphics for compositing over camera video. | 2 | hardware | The ATEM keys a lower third over a camera with clean edges and no black box, using Fill and Key from the DeckLink. Depends on UNV-02 and UNV-03. |
| SCRN-11 | DeckLink SDI output | Send video via Blackmagic playback/capture hardware. | 2 | hardware | Each of the four SDI connectors carries its assigned composition at 1080p59.94 for 60 minutes with zero dropped frames reported by the driver. |
| SCRN-12 | NDI output | Deliver video to compatible receivers over Ethernet. | 2 | licence | A screen published as NDI is received by an NDI monitor on a second device on the network, with alpha preserved. Depends on UNV-05. |
| SCRN-13 | Syphon output (Mac) | Share rendered frames with supported applications locally. | 2 | none | A screen published over Syphon appears in a Syphon client on the same Mac. |

### 3.4 Automation and control (14)

| ID | Feature | Purpose | Phase | Depends on | Acceptance |
|---|---|---|---|---|---|
| AUTO-01 | Slide actions | Fire cues automatically when a slide becomes active. | 3 | none | A slide with a media action and a Look action fires both when it goes live, in a defined order. |
| AUTO-02 | Macros | Group several actions into one reusable command. | 3 | none | A named macro of three actions runs from a button, a slide and the remote API with the same result. |
| AUTO-03 | MIDI input | Map controller buttons to presentation commands. | 3 | none | A MIDI note advances the slide. Verified with a virtual MIDI port; a physical controller is a field check. |
| AUTO-04 | MIDI output | Trigger compatible lighting or production devices. | 3 | none | A slide action sends a chosen MIDI message, seen in a MIDI monitor. |
| AUTO-05 | DMX lighting | Coordinate presentation with compatible lighting systems. | 5 | hardware | A slide action sets DMX channel values over the network, seen in a DMX monitor, then confirmed on a real fixture. |
| AUTO-06 | Timecode | Run production cues in sync with a clock or media timeline. | 5 | hardware | Cues fire within one frame of their timecode position from an external source. |
| AUTO-07 | Timeline | Schedule media, slides, and automation in a timed sequence. | 5 | none | A recorded sequence of slide changes replays against an audio track with the same timing, within one frame. |
| AUTO-08 | Playback markers | Trigger an action at a timestamp inside a clip. | 3 | none | A marker at a chosen time in a video fires its action within one frame of that time. |
| AUTO-09 | Stream Deck control | Use tactile buttons for operation during events. | 3 | hardware | Stream Deck buttons trigger next, previous, clear and a macro. Needs a Stream Deck. |
| AUTO-10 | Remote API | Allow authorized third-party systems to issue commands. | 3 | none | An authenticated HTTP request advances the slide and reads back the live state; an unauthenticated one is refused. |
| AUTO-11 | Cross-computer linking | Synchronize content triggering across compatible computers. | 5 | hardware | Triggering a slide on one Mac triggers the same slide on a linked Mac within 100 ms. Needs a second Mac. |
| AUTO-12 | Calendar scheduling | Run selected operational cues at scheduled times. | 3 | none | A scheduled event fires its action at the set time, including after the Mac wakes from sleep. |
| AUTO-13 | Web-based control | Operate playback from an authorized browser/device. | 3 | none | A phone on the same network, after signing in, can step slides and see the current and next text. |
| AUTO-14 | External protocols | Integrate specialized broadcast and production systems. | 5 | hardware | Defined per protocol. The guide names none, so the list is OPEN-08. |

### 3.5 Live production and streaming (12)

| ID | Feature | Purpose | Phase | Depends on | Acceptance |
|---|---|---|---|---|---|
| LIVE-01 | Stage layout editor | Customize performer-friendly confidence displays. | 1 | none | A layout with resized current, next and clock elements saves and shows on the stage screen as designed. |
| LIVE-02 | Current & next slide | Show present and upcoming lines simultaneously. | 1 | none | The stage screen shows the live slide and the following slide, and both update within one frame of a change. |
| LIVE-03 | Stage messages | Send private instructions to presenters or musicians. | 3 | none | A typed message shows on stage screens only and never on an audience screen. |
| LIVE-04 | Countdowns and clocks | Display countdown, elapsed time, or time of day. | 1 | none | A countdown, an elapsed timer and a wall clock each show on a stage layout and stay within one second over an hour. |
| LIVE-05 | Preview surfaces | See live video outputs inside an operator layout. | 1 | none | The operator window shows a live thumbnail of each output that matches the real output. |
| LIVE-06 | Operator workspace | Manage playlists, media, and live output status in one place. | 1 | none | Playlist, slide grid, media bin and output status are visible together on a 1920 × 1080 display. |
| LIVE-07 | Live editing | Revise content while a different slide remains live. | 1 | none | Editing a queued presentation leaves the live output unchanged until that content is triggered. |
| LIVE-08 | Local recording | Capture a produced output to a media file. | 4 | none | A 60-minute recording of one output plays back in sync with no dropped frames. |
| LIVE-09 | RTMP streaming | Stream an encoded output to compatible video services. | 4 | licence | A stream to a test RTMP server runs for 60 minutes; a real service needs the owner's streaming account. |
| LIVE-10 | Resilient streaming | Use specialized streaming integrations where supported. | 5 | licence | Defined once a service is chosen. The guide names none. |
| LIVE-11 | Media subscriptions | Access licensed motion graphics and templates. | 5 | licence | Defined once a content provider is chosen. The guide names none. |
| LIVE-12 | Team collaboration | Coordinate several production operators and editors. | 5 | backend | Two signed-in users edit different presentations in one workspace without overwriting each other. Needs OPEN-09. |

### 3.6 Catalogue totals

| Group | Count | Phase 1 | Phase 2 | Phase 3 | Phase 4 | Phase 5 |
|---|---|---|---|---|---|---|
| Presentation and worship | 13 | 9 | 0 | 0 | 3 | 1 |
| Media, video and audio | 12 | 5 | 3 | 3 | 1 | 0 |
| Screens and video outputs | 13 | 6 | 5 | 0 | 0 | 2 |
| Automation and control | 14 | 0 | 0 | 9 | 0 | 5 |
| Live production and streaming | 12 | 6 | 0 | 1 | 2 | 3 |
| **Total** | **64** | **26** | **8** | **13** | **6** | **11** |

## 4. Outputs and hardware

### 4.1 Transports [G]

| ID | Transport | What it carries | Typical endpoint |
|---|---|---|---|
| HW-01 | HDMI or USB-C display | Native digital video, sometimes embedded audio | Projector, TV, monitor, HDMI switcher |
| HW-02 | Thunderbolt to PCIe | PCIe traffic between the Mac and the enclosure | DeckLink Duo 2 in a PCIe enclosure |
| HW-03 | 3G-SDI over BNC coax | Broadcast video and optional embedded audio | Router, SDI monitor, SDI-to-HDMI converter |
| HW-04 | Ethernet, NDI | Live video over a network | NDI receivers |
| HW-05 | Ethernet, API | Remote commands and state | Controllers, dashboards, automation |
| HW-06 | MIDI and DMX | Control messages and lighting cues | Control surfaces, lighting devices |
| HW-07 | USB | Peripheral input or control | MIDI interface, control pad, keyboard |

### 4.2 Signal rules

| ID | Rule | Label |
|---|---|---|
| HW-08 | Play each audio signal down one path only. Microphones and instruments stay on the mixer; the livestream mix goes to the ATEM once; app playback audio must not arrive through both the mixer and an SDI or HDMI source. | [G] |
| HW-09 | The production format is 1920 × 1080 at 59.94 fps on every device that supports it. 59.94 and 60 are different modes and must not be mixed. | [G] |
| HW-10 | The DeckLink Duo 2 has four SDI BNC connectors and no HDMI. An HDMI-only destination needs a powered SDI-to-HDMI converter per signal. Passive BNC-to-HDMI cables do not work. | [G] |
| HW-11 | A Fill and Key pair uses two SDI connectors and two ATEM HDMI inputs. | [G] |
| HW-12 | A DeckLink output is an SDI video device, not an extra desktop display. | [G] |
| HW-14 | DeckLink outputs do not count against the Mac's native display limit. | [P] (inferred from HW-12) |
| HW-13 | Fault-finding order: confirm the card in Desktop Video Setup, then test SDI output in a Blackmagic utility, then check the app's screen mapping. | [G] |

### 4.3 Output assignments

Plans A and B are the guide's **[G]**. **[P]** The app supports both and lets the operator switch between them in screen configuration.

**Plan A: four independent outputs**

| Connector | Content | Destination |
|---|---|---|
| SDI 1 | Main lyrics and presentation | Sanctuary projector |
| SDI 2 | Stage confidence layout | Stage monitor |
| SDI 3 | Livestream graphics | ATEM HDMI input through a converter |
| SDI 4 | Announcements or lobby feed | Lobby monitor |

Plan A gives no separate transparency signal to the switcher.

**Plan B: Fill and Key broadcast**

| Connector | Signal | Purpose |
|---|---|---|
| SDI 1 | Fill | Full-colour graphics |
| SDI 2 | Key | Matte marking opaque and transparent areas |
| SDI 3 | Main presentation | Sanctuary output |
| SDI 4 | Stage confidence | Performer output |

Which connector of the pair carries Fill and which carries Key is UNV-03.

**Plan C: no DeckLink [P]**

One native output for the sanctuary, one for the stage, and NDI for the livestream. This plan needs no enclosure, card or converters. Whether it is sufficient is OPEN-04.

### 4.4 Equipment [G]

| Item | Why |
|---|---|
| Mac mini or other production Mac | Runs the app and renders every composition |
| Thunderbolt PCIe enclosure | External slot for the DeckLink |
| DeckLink Duo 2 | Four configurable 3G-SDI channels |
| Thunderbolt cable | Carries PCIe; ordinary USB-C data cables may not |
| Blackmagic Desktop Video | Driver, firmware and utilities |
| 75-ohm BNC coax | SDI runs |
| SDI-to-HDMI converters | One per HDMI-only destination |
| HDMI cables | Converter to TV, projector or ATEM |

**[U]** None of the DeckLink, enclosure or ATEM is owned yet. **[P]** Purchase waits until the Phase 1 exit criterion is met and UNV-01 is resolved.

### 4.5 Development Mac (measured 2026-11-20)

| Item | Value |
|---|---|
| Model | Mac mini, Apple M4, 10 cores, 16 GB |
| macOS | 27.2 |
| Displays | Two 1920 × 1080 displays attached, both running at 100 Hz |
| Thunderbolt | Three ports, nothing attached |
| Tools | Xcode 26.6, Swift 6.3.3 |
| Free space | 52 GB internal, 391 GB on the external Storage volume |
| Storage volume | Case-sensitive APFS, file ownership disabled, USB |

**[P]** Consequences for testing on this Mac:

- **Two displays, three roles.** Operator, audience and stage need three surfaces. In Phases 0 and 1 the operator uses the first display, the audience output uses the second, and the stage output is verified in an output window (ARCH-13). A third display is an optional field check, not a prerequisite, and would reach the limit in UNV-08.
- **Refresh rate.** Timing tests set the second display to a 60 Hz mode, or 59.94 if it offers one (UNV-09). A result measured at 100 Hz does not count toward NFR-01 or HW-09.

## 5. Architecture and distribution

Section 5.1 is **[U]**, approved 2026-11-20. The rest of section 5 is **[P]** except where marked.

### 5.1 Stack

| ID | Decision |
|---|---|
| ARCH-01 | A native macOS app in Swift, for Apple Silicon. |
| ARCH-02 | SwiftUI with AppKit where needed for the operator interface. |
| ARCH-03 | One Metal compositor renders every screen. Outputs never render their own frames. |
| ARCH-04 | AVFoundation decodes video and audio. |
| ARCH-05 | The DeckLink SDK is reached through a thin Objective-C++ bridge. No other module includes its headers. |
| ARCH-06 | CoreMIDI handles MIDI. |
| ARCH-07 | A web or Electron shell is ruled out: it cannot give frame-accurate SDI output. |

### 5.2 Modules

| ID | Module | Responsibility |
|---|---|---|
| ARCH-10 | Content model | Presentations, slides, themes, arrangements, libraries, playlists. No rendering code. |
| ARCH-11 | Storage | Local documents plus a search index. The app works fully offline. |
| ARCH-12 | Render engine | Builds one composition per screen from the live state and the screen's Look. |
| ARCH-13 | Output targets | Native display, output window, DeckLink, NDI, Syphon, recorder and stream encoder. All take frames from ARCH-12 through one interface. The output window lets any screen be checked without a spare display. |
| ARCH-14 | Stage renderer | Stage layouts, drawn by the same engine with stage-only data. |
| ARCH-15 | Control plane | Actions, macros, MIDI, remote API, web control, scheduling. Every trigger source goes through one command path. |
| ARCH-16 | Operator interface | Workspace, editors and previews. Holds no state that the control plane cannot reach. |

### 5.3 Layer order

Bottom to top: background media, live video, foreground media, slide content, announcements, props, messages, mask. A Look chooses which layers a screen shows (SCRN-08).

### 5.4 Text rendering

| ID | Requirement |
|---|---|
| ARCH-20 | Text is laid out with the system text engine so that Vietnamese stacked diacritics (for example ễ, ậ, ở) are shaped correctly. |
| ARCH-21 | Line height leaves room for stacked marks; no glyph is clipped at any theme size. Verified by snapshot test on a fixed Vietnamese sample. |
| ARCH-22 | A font lacking a glyph falls back to one that has it, never to an empty box. |
| ARCH-23 | Outline and shadow follow the full glyph including its marks. |

### 5.5 Testing

| ID | Requirement |
|---|---|
| ARCH-30 | The content model and control plane have unit tests. |
| ARCH-31 | The render engine has snapshot tests: an offscreen frame compared with a stored reference image. |
| ARCH-32 | Each hardware-dependent feature has a written field checklist, run on the real device and recorded with the driver and OS versions. |
| ARCH-33 | A feature marked "hardware" is not reported as done until its field checklist passes. Before that it is reported as "written, unverified". |

### 5.6 Distribution

| ID | Requirement | Label |
|---|---|---|
| DIST-01 | The app is distributed outside the App Store. | [U] |
| DIST-02 | Builds are signed with a Developer ID certificate and notarized by Apple. This needs a paid Apple Developer Program membership. | [P] |
| DIST-03 | The deliverable is a disk image or installer package that opens on another Mac without a security warning. | [P] |
| DIST-04 | The app runs with the hardened runtime and without the App Store sandbox. | [P] |
| DIST-05 | Updates are delivered by an in-app updater. | [P] |
| DIST-06 | Blackmagic Desktop Video is not bundled. The app detects its absence and tells the operator to install it. | [P] |
| DIST-07 | The app starts and runs every non-SDI feature on a Mac with no DeckLink and no Desktop Video. | [P] |
| DIST-08 | Minimum system: Apple Silicon, macOS 15 or later. Subject to OPEN-03. | [P] |

## 6. Non-functional requirements

All **[P]**. Numbers are starting targets to be confirmed by measurement in Phase 0.

| ID | Requirement | Verified by |
|---|---|---|
| NFR-01 | Every output holds its frame rate. Zero dropped frames over a 60-minute run with a motion background and lyric changes on two outputs. | Soak test with the frame counter |
| NFR-02 | The app counts dropped and late frames per output and shows them to the operator. | Inspection |
| NFR-03 | A slide trigger reaches every output within 100 ms. | Timed capture |
| NFR-04 | All outputs change on the same frame for the same trigger. | Side-by-side capture |
| NFR-05 | If an output device disappears mid-service, the app keeps running, the other outputs continue, the operator is warned, and the output resumes when the device returns. | Unplug test |
| NFR-06 | After a crash or forced quit, relaunch restores the open playlist and selected slide. Outputs stay clear until the operator triggers. | Kill test |
| NFR-07 | Edits are saved automatically. A forced quit loses no more than five seconds of editing. | Kill test |
| NFR-08 | The app never shows a system dialog, notification or its own alert on an audience or stage output. | Inspection |
| NFR-09 | The remote API and web control refuse unauthenticated requests and are off by default. | Unit test |
| NFR-10 | The app prevents display sleep and system sleep while any output is active. | Timed test |
| NFR-11 | Memory stays within a budget that leaves the 16 GB development Mac out of swap with four 1080p outputs. The budget is set after Phase 0 measurement (UNV-04). | Soak test |
| NFR-12 | Every feature works with the network unplugged, except those whose purpose is the network. | Offline test |

## 7. Phases

The phases and their feature placement are **[U]**, approved 2026-11-20. Estimates and exit criteria are **[P]**. Estimates assume one owner directing and automated coding agents writing the code. They are ranges, not commitments.

| Phase | Name | Features | Estimate | Exit criterion |
|---|---|---|---|---|
| 0 | Render spike | Proves ARCH-03 | 1 week | Lyrics over a looping video on the second display set to 60 Hz, English and Vietnamese, meeting NFR-01 for 60 minutes. Memory and GPU load recorded. |
| 1 | Service MVP | 26 | 8–12 weeks | A full service is run from a playlist with the audience output on the second display and the stage output in an output window. |
| 2 | Outputs | 8 | 4–6 weeks | Syphon verified on the development Mac. NDI verified on a second device on the network. DeckLink and Fill and Key verified on the real card and ATEM. |
| 3 | Control | 13 | 6–8 weeks | A service is run from a controller and from a phone, with macros and slide actions. |
| 4 | Streaming and content | 6 | 6–10 weeks | A service is recorded and streamed, and Scripture and planned songs are pulled in. |
| 5 | Long tail | 11 | 3–6 months or more | Per feature. No single exit. |

Notes:

- The Phase 1 estimate here is longer than the 6–10 weeks first quoted in conversation. Placing every feature moved 26 into Phase 1.
- Phase 2 splits in two. NDI, Syphon, mirroring and audio need no purchase, though NDI needs any second computer to receive it. DeckLink output and Fill and Key cannot finish until the hardware arrives.
- Phases 3 and 4 do not depend on each other and can swap.
- Licence and backend features are bounded by agreements and running costs, not by coding time. No date is given for all 64.
- Phase 5 is optional for a single church. Each item should be justified separately before work starts.

## 8. Open decisions and unverified facts

### 8.1 Open decisions

| ID | Decision | Blocks |
|---|---|---|
| OPEN-01 | Approve the stack in 5.1. **Closed: approved 2026-11-20.** | — |
| OPEN-02 | Approve the phase plan and the feature placement in section 3. **Closed: approved 2026-11-20.** | — |
| OPEN-03 | Minimum macOS version for target Macs. | DIST-08 |
| OPEN-04 | Is SDI needed at all, or does Plan C cover the venue? Needs the count of sanctuary screens, stage screens and stream feeds. | Hardware purchase, Phase 2 |
| OPEN-05 | Which Bible translations, and who holds the licence for each. **Partly decided 2026-11-20 [U]:** the owner states the Vietnamese 1925 translation (VI1925) is legal and free to use, and it is to be included. An English translation is still to be chosen. | PRES-09 |
| OPEN-06 | Which song lyric service. | PRES-11 |
| OPEN-07 | Which planning platform. | PRES-12 |
| OPEN-08 | Which external protocols. | AUTO-14 |
| OPEN-09 | Cloud backend: who hosts it, who pays, and whether Phase 5 sync is wanted. | PRES-13, LIVE-12 |
| OPEN-10 | User-facing feature names and the interface language or languages. | Phase 1 interface work |
| OPEN-11 | Is the app for one church or for distribution to others? This sets the bar for DIST-02 to DIST-05 and for NDI terms. | Phase 2, distribution |

### 8.2 Unverified facts

These must not be treated as true in any task spec until resolved.

| ID | Claim | State on 2026-11-20 | How to resolve |
|---|---|---|---|
| UNV-01 | Blackmagic Desktop Video supports macOS 27 on Apple Silicon. | The readme found lists macOS 15 as its minimum and does not mention 27. | Read the current Desktop Video release notes before buying. |
| UNV-02 | The DeckLink Duo 2 does external Fill and Key at 1080p59.94. | The SDK lists the Duo 2 as keying-capable. The resolution limit was not confirmed. | Read the keying table in the DeckLink SDK manual. |
| UNV-03 | In the keying pair, SDI 1 is Fill and SDI 2 is Key. | The guide says so. No independent confirmation was found. | Check on the card. |
| UNV-04 | An M4 with 16 GB sustains four 1080p59.94 compositions, Fill and Key, and stream encoding. | Never measured. | Phase 0 measurement, then a soak test on the card. |
| UNV-05 | The NDI SDK may be bundled in an app given to other churches. | Terms not read. | Read the NDI SDK licence before SCRN-12 ships outside the owner's Macs. |
| UNV-06 | The chosen Thunderbolt enclosure works with the Duo 2 on Apple Silicon. | No enclosure chosen. | Vendor compatibility list; card length and PCIe lanes. |
| UNV-07 | Code signing and git behave on the Storage volume, which is case-sensitive with ownership disabled. | Not tested. | First build. Fallback: keep code on the internal drive. |
| UNV-08 | The base M4 Mac mini drives three native displays in the needed combination. | Apple documents up to three, depending on resolution and refresh rate. | Check the exact port combination before relying on a third native output. |
| UNV-09 | The attached displays offer a 59.94 Hz mode. | Both were running at 100 Hz when measured. Available modes were not listed. | List the display modes at the start of Phase 0. |

## 9. Reference links [G]

| Resource | Use |
|---|---|
| https://www.blackmagicdesign.com/products/decklink | DeckLink Duo 2 and SDI overview |
| https://www.blackmagicdesign.com/support/family/capture-and-playback | Desktop Video drivers and compatibility |
| https://www.blackmagicdesign.com/products/atemmini | ATEM switchers |
| https://www.apple.com/mac-mini/specs/ | Native display capability |
| https://support.renewedvision.com/hc/en-us | The guide's feature-workflow research reference |
