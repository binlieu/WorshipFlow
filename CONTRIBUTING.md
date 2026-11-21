# Contributing to WorshipFlow

Thank you for wanting to help. This project is in active development and not yet used in a real service, so the most valuable contributions right now are bug reports from actually running it.

## Reporting a problem

Open an issue and include:

- What you did, step by step, and what you expected.
- What happened instead. A screenshot helps.
- Your Mac model and macOS version.
- For video hardware: the card, its driver version, and the report from **Help → Hardware Test…** if you can run it. That report contains no names or passwords.

## Proposing a change

1. Open an issue first for anything larger than a small fix, so the approach can be agreed before you spend time on it.
2. Fork the repository and work on a branch.
3. Run `./scripts/check.sh` and make sure it passes.
4. Open a pull request that says what changed and why, and how you tested it.

## Ground rules for code

These come from `CLAUDE.md` and `AGENTS.md`, which are the full versions:

- **Native macOS only.** Swift, SwiftUI and AppKit. No web views for core functions.
- **Local-first.** Nothing in the live path may need the network.
- **Tests come with the change.** For anything touching live output, timing, storage or migrations, write the failing test first.
- **Never edit an existing database migration.** Add a new one.
- **Say what was verified.** Do not describe something as working on real hardware unless it was run on real hardware. The project tracks five levels: Implemented, Unit Tested, Simulated, Hardware Verified, Live-Service Verified.
- **No copyrighted content.** No Bible translation text, song lyrics, media or code from other presentation software.

## Licence of contributions

WorshipFlow is released under the Apache License 2.0 (see `LICENSE` and `NOTICE`). Under section 5 of that licence, anything you intentionally submit for inclusion is licensed under the same terms, including its patent grant, with no separate agreement needed. By opening a pull request you confirm you have the right to submit the work.

The files in `Packages/WorshipFlowKit/Sources/DeckLinkC/sdk/` belong to Blackmagic Design and carry their own licence notice. Do not modify them.
