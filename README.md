# WorshipFlow

A native macOS application for presenting worship lyrics, Scripture, slides, video and live-production graphics on several independent screens: the sanctuary, a stage confidence monitor and a broadcast feed.

**Status: in development, not ready for use in a service.** The code is covered by unit tests and has been exercised through automation, but it has not yet been used hands-on through a full service, and nothing has been verified on real video hardware. See [docs/14-current-status.md](docs/14-current-status.md) and [docs/16-known-issues.md](docs/16-known-issues.md) for exactly what is and is not verified.

## What it does

- **One song, several looks.** The same slide is full-screen lyrics for the congregation, current and next lines for the band, and a transparent lower third for the stream.
- **Bilingual lyrics.** Two languages on every slide, with correct rendering and search for Vietnamese.
- **Preview and live are separate.** Editing never changes what the congregation sees until it is triggered.
- **Six working modes:** Show, Edit, Media, Stage, Cues and Screens.
- **Outputs:** Mac displays and windows today; Blackmagic DeckLink SDI output with fill and key is written but verified only against a simulated card.
- **Local-first.** Everything is stored in a SQLite library on the Mac. A service never needs the network.

## Requirements

- An Apple Silicon Mac, macOS 15 or later.
- Xcode 26 or later, and [XcodeGen](https://github.com/yonaskolb/XcodeGen) (`brew install xcodegen`).
- For SDI output: a Blackmagic DeckLink card and Blackmagic Desktop Video installed. Not needed to build or run.

## Build and test

```bash
./scripts/check.sh
```

This runs the package tests, regenerates the Xcode project from `project.yml`, and builds the app.

## Layout

| Path | Contents |
|---|---|
| `App/` | The SwiftUI and AppKit operator interface |
| `Packages/WorshipFlowKit/` | The engine, as one Swift package with a target per module: `Domain`, `Persistence`, `RenderEngine`, `MediaEngine`, `OutputEngine`, `SDIEngine`, `DeckLinkSDI`, `OperatorCore`, `CueEngine`, `ScriptureEngine` and others |
| `docs/` | The master specification, decision records (`docs/adr`), feature specs, status and known issues |
| `docs/UI/` | The interface design: tokens, logo, app icon and screens |
| `AI/` | Task briefs and reports from the build |

## Third-party material

- `Packages/WorshipFlowKit/Sources/DeckLinkC/sdk/` contains unmodified include files from the Blackmagic DeckLink SDK 16.0, each carrying Blackmagic Design's own licence notice. See [docs/adr/0006-decklink-sdk-licence.md](docs/adr/0006-decklink-sdk-licence.md). The Desktop Video driver is not included.
- [GRDB.swift](https://github.com/groue/GRDB.swift) is used for SQLite access.
- No Bible translation text is included in this repository.

"DeckLink" and "Blackmagic Design" are trademarks of Blackmagic Design Pty. Ltd. This project is not affiliated with or endorsed by Blackmagic Design.

## Licence

WorshipFlow is released under the [Apache License 2.0](LICENSE); see also [NOTICE](NOTICE). The licence does not grant use of the WorshipFlow name or logo for modified versions. The Blackmagic SDK include files noted above are under Blackmagic Design's own licence.

## Contributing

Bug reports from running the app are the most useful help right now. See [CONTRIBUTING.md](CONTRIBUTING.md).
