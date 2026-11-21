# ADR-0001: Stack and repository layout

Status: Accepted, 2026-11-20 (stack approved by the owner as OPEN-01)

## Decision

- Swift 6, SwiftUI with AppKit where needed, Metal, AVFoundation. Apple Silicon, macOS 15 or later.
- Library code lives in one local Swift package, `Packages/WorshipFlowKit`, with one target per architecture module: `Domain`, `RenderEngine`, `MediaEngine`, `OutputEngine`. `Persistence` (GRDB/SQLite) and `Infrastructure/Blackmagic` are added when their first feature starts.
- The app target lives in `App/` and holds only the operator interface and wiring.
- `WORSHIPFLOW.xcodeproj` is generated from `project.yml` by XcodeGen and is checked in.
- Metal shaders are compiled at start-up from Swift source strings, not `.metal` files.

## Why

- A package per module makes the boundaries in `CLAUDE.md` compiler-enforced: `Domain` cannot import Metal because its target does not link it.
- `swift test` runs the package tests without Xcode UI and without connected hardware.
- SwiftPM's command-line build does not compile `.metal` files, so source-string shaders keep render tests runnable from `swift test`. Revisit if shader count or compile time grows.
- A generated project avoids hand-edited `.pbxproj` merge damage.

## Consequences

- XcodeGen is a build-time tool dependency (`brew install xcodegen`).
- Shader errors surface at start-up, so a render test must compile every shader.
