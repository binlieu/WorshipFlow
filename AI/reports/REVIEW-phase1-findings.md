# Independent review of Phase 1 — findings

Date: 2026-11-20. Reviewer: Sonnet subagent, read-only, nothing run. Line numbers approximate. "Confirmed" means the full code path was read; "Plausible" means not fully traced or depends on macOS behaviour.

| # | Severity | Finding | Where | Confidence | Owner |
|---|---|---|---|---|---|
| R1 | Critical | Key auto-repeat is treated as fresh presses: holding Space, Right or Down runs the live deck forward, across playlist items. | `App/Sources/AppModel.swift` key monitor; `OperatorCore/KeyRouting.swift` | Confirmed | FIX-B |
| R2 | High | A text layer taller than 16384 px makes `rasterize` throw; `encode` rethrows; the frame is not presented, so the screen freezes on the previous slide. | `RenderEngine/Compositor.swift`, `TextRasterizer.swift`; `OutputEngine/OutputRenderer.swift` | Confirmed | FIX-A |
| R3 | High | A failed draft save is put back in `pendingDrafts` but never rescheduled; `flush()` does not see it; deleting the open presentation or its library clears `pendingDrafts`. | `OperatorCore/WorkspaceModel.swift`, `DebouncedSaver.swift`, `WorkspaceModel+Library.swift` | Confirmed | FIX-B |
| R4 | High | Closing the operator window quits the app; Quit has no confirmation while live; Hide may hide output windows. | `App/Sources/WorshipFlowApp.swift` | Quit confirmed; Hide plausible | FIX-B (menus, quit), FIX-A (`canHide`) |
| R5 | High | Output windows are never re-framed or re-checked after a display reconfiguration. | `OutputEngine/MetalOutput.swift`, `DisplayOutput.swift` | Plausible | FIX-A |
| R6 | Medium | The main thread stats image files every 0.5 s and can hang on a sleeping or missing volume. | `App/Sources/AppModel.swift` `updateReadouts` | Plausible | FIX-B |
| R7 | Medium | The render thread stats image files about once a second; a momentary read failure installs a nil texture so the image vanishes. | `RenderEngine/Compositor.swift` `imageTexture` | Stat confirmed | FIX-A |
| R8 | Medium | Clear hides the words but leaves a foreground clip and its audio playing; the rule is not stated anywhere. | `Domain/SceneComposer.swift` | Confirmed | FIX-B |
| R9 | Medium | A foreground clip that fails or stalls after opening is never reported; the words stay hidden; with no stored duration nothing ends it. | `MediaEngine/MediaRegistry.swift`, `VideoPlayerSource.swift`; `Domain/SceneComposer.swift` | Plausible | FIX-A (report), follow-up (app reaction) |
| R10 | Medium | Images (slide objects, theme backgrounds, props) decode per screen after going live, so they pop in late and screens differ. | `RenderEngine/Compositor.swift`, `ImageLoading.swift` | Confirmed | FIX-A |
| R11 | Medium | Reflow can leave a playlist item's section order with no slides; Next then silently skips the song. | `Persistence/LibraryStore+Structure.swift`; `OperatorCore/WorkspaceModel+Transport.swift` | Plausible | FIX-B |
| R12 | Medium | Settings and media writes are not flushed at quit or resign-active; a failed settings write is not retried. | `App/Sources/WorshipFlowApp.swift`, `AppModel.flushWorkspace`; `OperatorCore/SettingsModel.swift`, `MediaModel.swift` | Plausible | FIX-B |
| R13 | Medium | Choosing a theme for the presentation that is live changes the audience at once, undocumented. | `OperatorCore/WorkspaceModel+Themes.swift` | Confirmed | FIX-B |
| R14 | Medium | `MediaFrameResolver` and `PreviewRenderer` never flush their `CVMetalTextureCache`. | `OutputEngine/MediaFrames.swift`; `App/Sources/Thumbnails.swift` | Plausible | FIX-A, FIX-B |
| R15 | Medium | Every keystroke republishes all scenes and recomputes every thumbnail on the main thread. | `OperatorCore` edit path; `App/Sources/Thumbnails.swift` | Plausible | FIX-B |
| R16 | Medium | Opening screens compiles shaders and builds windows on the main thread, once per output, in sequence. | `OutputEngine/MetalOutput.swift` | Plausible | FIX-A |
| R17 | Medium | Close screens stops outputs and the shared video but not the media registry: clip audio continues. | `App/Sources/AppModel.swift` `stopScreens` | Confirmed | FIX-B |
| R18 | Medium | A lock is held across AVFoundation calls on the render thread; the KVO callback takes the same lock. | `MediaEngine/VideoPlayerSource.swift` | Plausible, unlikely | FIX-A |

## Reviewed and found sound

Semaphore and frame lifetime in `OutputRenderer.tick`; output start, stop, unplug and replug sequencing; routing never moves a screen to another display; `ShowState` keeps the live deck as a value copy and restore goes to preview only; stage-only content is composed only for stage screens; all screens read one snapshot; persistence transaction boundaries, cascades, sort-order renumbering and search-index maintenance; the legacy import never overwrites non-empty tables; media still cache and registry locking; bounded text, shape and image caches.

## Not reviewed

Media transport and thumbnail arithmetic, reflow splitting, search folding, slide object sanitising, SwiftUI views (focus and sheets), whether the render run loop spins, bookmark lifetimes, display-id stability, anything needing hardware. No build or test was run by the reviewer.

## Coordinator decisions on the open questions

- **R8:** Clear keeps its meaning (words only). A new **Clear all** command (Shift-Escape and a button) clears the words and stops any foreground clip. Stop already removes everything.
- **R13:** the theme of a live presentation is captured when it is triggered; changing it applies from the next trigger. Editing a theme that is in use still changes live at once (KI-027, accepted).
- **R4:** closing the operator window never quits while screens are open; Quit asks for confirmation while screens are open; output windows are excluded from Hide.
