# HW-003 report: the real DeckLink bridge

**Verification level: Implemented, Unit Tested (pure parts only). Not Verified on hardware.** This Mac has no DeckLink card and no Desktop Video driver. The only runtime behaviour exercised here is "driver absent". Every call into the SDK below was written from the vendored SDK 16.0 headers and the manual's documented sequences and has never executed against a card.

## Files

Changed or created, all inside the permitted folders. Nothing in `sdk/`, `Package.swift`, `project.yml`, `SDIEngine` or anywhere else was touched. Both `Placeholder.swift` files were deleted.

`Packages/WorshipFlowKit/Sources/DeckLinkC`
- `include/DeckLinkBridge.h` — public Objective-C interface, plain ObjC, nullability and Sendable annotations, no C++ and no vendor types.
- `DeckLinkBridge.mm` — the Objective-C++ bridge.

`Packages/WorshipFlowKit/Sources/DeckLinkSDI`
- `DeckLinkEnvironment.swift` (`DeckLinkEnvironment`, `DeckLinkError`), `DeckLinkDeviceProvider.swift`, `DeckLinkDevice.swift` (`SDIDevice`), `DeckLinkOutputPort.swift` (`SDIOutputPort`), `DeckLinkInputPort.swift` (`SDIInputPort`, `DeckLinkFramePacking`), `DeckLinkConnectorLayout.swift`, `DeckLinkModeMapping.swift`, `DeckLinkMapping.swift`, `DeckLinkIdentifier.swift`, `DeckLinkSnapshot.swift`.

`Packages/WorshipFlowKit/Tests/DeckLinkSDITests` (61 tests, 8 suites)
- `DeckLinkDriverAbsentTests.swift`, `DeckLinkMappingTests.swift`, `DeckLinkFramePackingTests.swift`, `DeckLinkIdentifierTests.swift`, `DeckLinkConnectorLayoutTests.swift`, `DeckLinkInputMappingTests.swift`.

## SDK interfaces and call sequence

Headers: `DeckLinkAPI.h` (all interfaces below), `DeckLinkAPIModes.h` (`IDeckLinkDisplayMode`, `BMDDisplayMode`, `BMDPixelFormat`), `DeckLinkAPIDiscovery.h` (`IDeckLink`), `DeckLinkAPIVersion.h`, `DeckLinkAPIDispatch.cpp` (loads `/Library/Frameworks/DeckLinkAPI.framework`; returns null when absent).

**Driver presence.** `CreateDeckLinkAPIInformationInstance` returns null without the driver; otherwise `IDeckLinkAPIInformation::GetInt/GetString(BMDDeckLinkAPIVersion)`. The SDK loads its framework once per process, so a driver installed while the app runs is not noticed until restart (said in the header).

**Discovery.** `CreateDeckLinkIteratorInstance` + `IDeckLinkIterator::Next` for a synchronous scan; `CreateDeckLinkDiscoveryInstance` + `IDeckLinkDiscovery::InstallDeviceNotifications` with an `IDeckLinkDeviceNotificationCallback` (arrived, removed) for hot-plug; `UninstallDeviceNotifications` on stop. The provider reconciles scan results and notifications by persistent ID, groups sub-devices into cards by device group ID, and tells removed sub-devices they are gone so open ports fail.

**Per-device data.** `IDeckLink::GetModelName/GetDisplayName`; `IDeckLinkProfileAttributes` (QueryInterface from `IDeckLink`, active profile): `BMDDeckLinkPersistentID`, `DeviceGroupID`, `TopologicalID`, `SubDeviceIndex`, `NumberOfSubDevices`, `VideoIOSupport` (playback, capture), `SupportsInternalKeying`, `SupportsExternalKeying`, `SupportsInputFormatDetection`, `VideoOutputConnections`, `VideoInputConnections`, `Duplex`, `DeviceInterface`, `ProfileID`, `MinimumPrerollFrames`. Interface presence: QueryInterface for `IDeckLinkOutput`, `IDeckLinkInput`, `IDeckLinkKeyer`.

**Profiles.** `IDeckLinkProfileManager` (absent means one profile) → `GetProfiles` → `IDeckLinkProfileIterator::Next` → `IDeckLinkProfile`; per-profile attributes through `IDeckLinkProfileAttributes` on the profile (so what a profile would do is readable without activating it). Activation: `GetProfile(id)` → `IDeckLinkProfile::IsActive` / `SetActive`, then wait up to a timeout for `IDeckLinkProfileCallback::ProfileActivated` (callback installed with `IDeckLinkProfileManager::SetCallback`, only on first activation, because the SDK keeps one callback per device). `ProfileChanging` returns immediately as the manual requires. The Swift side refuses to switch a pair that has an open port instead of stopping it.

**Output.** `IDeckLinkOutput`: `DoesSupportVideoMode(connection unspecified, mode, bmdFormat8BitBGRA, bmdNoVideoOutputConversion, flags = default or bmdSupportedVideoModeKeying, &actual, &supported)`; `GetDisplayMode` (size and frame duration are compared with the app's, by exact cross-multiplication, so 59.94 versus 60 cannot be confused); `RowBytesForPixelFormat`; `EnableVideoOutput(mode, bmdVideoOutputFlagDefault)`; for keying `IDeckLinkKeyer::Enable(true)` + `SetLevel(255)`; `SetScheduledFrameCompletionCallback(IDeckLinkVideoOutputCallback)`; frames from `CreateVideoFrame(w, h, rowBytes, bmdFormat8BitBGRA, bmdFrameFlagDefault)`, pooled (cap 16); bytes written through `QueryInterface(IID_IDeckLinkVideoBuffer)` + `StartAccess(write)` / `GetBytes` / `GetSize` / `EndAccess` (the 16.0 way: `IDeckLinkVideoFrame` has no `GetBytes`); `ScheduleVideoFrame(frame, index*duration, duration, timeScale)`; `StartScheduledPlayback(index*duration, timeScale, 1.0)`; `GetBufferedVideoFrameCount`; `StopScheduledPlayback(0, nullptr, 0)`; `IDeckLinkKeyer::Disable`; `DisableVideoOutput`. Completion callback `ScheduledFrameCompleted(frame, result)` maps `bmdOutputFrameCompleted/DisplayedLate/Dropped/Flushed` one to one; the pool entry holds the frame index, so the engine gets its own index back. Status also reads `GetReferenceStatus`. The one copy into the SDK buffer is `DLBPackBGRA` (stride-aware, optional un-premultiply); it is public so it can be tested without a card.

**Keying.** `IDeckLinkProfileAttributes::GetFlag(BMDDeckLinkSupportsExternalKeying)`, `DoesSupportVideoMode` with `bmdSupportedVideoModeKeying` on BGRA, `IDeckLinkKeyer` as above, per manual section 2.4.8. External keying only; internal keying is exposed as data.

**Input.** `IDeckLinkInput`: `DoesSupportVideoMode(... bmdFormat8BitYUV, bmdNoVideoInputConversion ...)`; `SetCallback(IDeckLinkInputCallback)`; `EnableVideoInput(mode, bmdFormat8BitYUV, bmdVideoInputEnableFormatDetection | default)`; `StartStreams`. On `VideoInputFormatChanged` the documented restart (`PauseStreams`, `EnableVideoInput` with the detected mode, `FlushStreams`, `StartStreams`) runs on a private serial queue, with RGB 4:4:4 detected → BGRA, else YUV. `VideoInputFrameArrived`: frames with `bmdFrameHasNoInputSource` become "no signal"; others are converted with `CreateVideoConversionInstance` + `IDeckLinkVideoConversion::ConvertNewFrame(src, bmdFormat8BitBGRA, bmdColorspaceRec709, nullptr, &dst)` and read through `IDeckLinkVideoBuffer`; timestamp from `IDeckLinkVideoInputFrame::GetHardwareReferenceTimestamp` (nanoseconds, converted to the mode's time scale in Swift). `StopStreams`, `DisableVideoInput` on stop.

**Reference counting and threads.** All COM pointers are in a small `ComPtr` RAII holder. SDK callbacks touch only `shared_ptr` state objects, never an ObjC object that might be deallocating, and no handler is called under a bridge lock. No C++ exception leaves an ObjC method or an SDK callback (`try/catch(...)` at every entry).

## Results of what was run

| What | Result |
|---|---|
| `swift build --package-path Packages/WorshipFlowKit --target DeckLinkSDI` | succeeds, no warnings from my code (incremental and after touching every file) |
| `clang++ -fobjc-arc -Wall -Wextra` over `DeckLinkBridge.mm` | no warnings from my code |
| `swift test --package-path Packages/WorshipFlowKit --filter DeckLinkSDITests` (the real package) | **Final run: `Test run with 61 tests in 8 suites passed after 0.312 seconds`.** In between, the package briefly could not compile because of the other agent's unfinished `Tests/OutputEngineTests/HWTEST_BundleTests.swift` (types such as `HardwareTestReport` did not exist yet); that is what the scratch run below covered, and the retry afterwards succeeded. |
| Same tests in a scratch package **outside the repository**, `<session scratchpad>/wf-hw003-15199` (copies of Domain, SDIEngine, DeckLinkC, DeckLinkSDI and the test target, with the same target settings; deleted afterwards) | `Test run with 61 tests in 8 suites passed after 0.303 seconds` |
| Same filter in the real package with `--sanitize=address` (earlier, when the package compiled) | `Test run with 61 tests in 8 suites passed`, no sanitizer report |

The driver-absent tests are written with `.enabled(if: !driverIsPresent, "...")`, so on a Mac that has the driver they are skipped with a recorded reason rather than failing. Tests cover: driver-absent environment, provider, monitoring refusal, discovery error and snapshot; `SDIVideoMode.allKnown` mapped both ways plus the literal `BMDDisplayMode` codes from the header; completion mapping (including unknown → dropped); keying mapping; error mapping per context; BGRA packing into a fake buffer (row order, stride padding, padding untouched, impossible arguments, un-premultiply agreeing with `FillKeySplitter` over a grid of values, full-HD round trip); persistent-ID text round trips and rejections; the Duo 2 connector layout as the manual's table; input signal and timestamp conversion; conformance to `SDIDevice`, `SDIOutputPort`, `SDIInputPort`.

## What the adapter models

- **A card is a group of sub-devices.** `DeckLinkDevice` is one card (device group ID), holding one `IDeckLink` per sub-device. `SDIDeviceInfo.connectorCount` is the layout's connector count (4 on a Duo 2). `supportsExternalKeying` is true if any of the card's profiles supports it; whether the current one does is checked when a port is enabled.
- **Connector layout.** The SDK exposes no connector-to-sub-device mapping. For the Duo 2 the adapter encodes the table in the manual (section 2.4.11) and says so (`source: manualTableDuo2`); for any other model it assumes connector *n* is sub-device *n-1* (`source: subDeviceOrder`). Both appear in the status snapshot.
- **Ports bind late.** `openOutput(connector:)` only claims the connector. The sub-device is chosen in `enable`, once it is known whether the output is keyed, because the answer depends on the profile.
- **No silent profile changes.** `enable(keying: .external)` on a profile without a keyer throws `keyingUnavailable`; `DeckLinkDevice.profileSupportingExternalKeying` says which profile to switch to, and `activateProfile(_:forPair:)` does it, refusing if a port is open on the pair.
- **Hot-plug.** Removal fails open ports once via `onFailure(.deviceDisconnected)`; ports from before a removal stay dead (`portClosed` after replug), as in the simulator.
- **Keyer level, status.** `DeckLinkOutputPort.setKeyerLevel`, `statusSnapshot()` on provider, device, ports and the bridge (plain values).

## Questions a hardware test must answer

1. How many `IDeckLink` objects does a Duo 2 enumerate, with which `SubDeviceIndex`, names, persistent IDs and `DeviceGroupID` (is the group ID non-zero and shared by all four)? Do inactive sub-devices still enumerate after switching to the one-sub-device profile? Does `NumberOfSubDevices` change with the profile?
2. Which profile is the Duo 2's default, and what are the profile IDs it lists? Does the manual's table hold: in `2dhd` SD0=SDI 1, SD1=SDI 3, SD2=SDI 2, SD3=SDI 4; in `1dfd` SD0 drives SDI 1 and 2, SD1 drives SDI 3 and 4?
3. **Which physical connector carries the fill and which the key?** The manual's table says SDI 2 is "out/fill" and SDI 1 is "in/key" under `1dfd` (fill on the higher number), and `IDeckLinkKeyer::Enable` says the fill goes on "CH A" and the key on "CH B". `SDIConnectorPlanner` assumes fill on the lower connector. The adapter reports `DeckLinkKeyRoute` (fill/key connectors) as data and does not swap anything. The loopback test (UNV-03) must say which is true, and the planner or the UI wording then has to follow.
4. Does the external keyer require the one-sub-device full-duplex profile? Does `SupportsExternalKeying` read true for that profile and false for the half-duplex one, as the per-profile attributes suggest?
5. Does `DoesSupportVideoMode` with the keying flag say yes for BGRA at 1080p59.94, and for each of the other nine modes (UNV-02)? Does it say yes without keying for each? Does any mode come back with a different `actualMode`?
6. Does the card accept BGRA frames for non-keyed SDI output (alpha dropped) and give the colours expected? Is the colour matrix Rec.709? Does `RowBytesForPixelFormat(BGRA, 1920)` equal 7680, and is the buffer at least `rowBytes*height`?
7. For keyed output, does the keyer expect premultiplied colour on the fill (what the compositor produces) or straight colour? The adapter supports both (`fillAlphaMode`); the manual does not say. Does the key equal the alpha, and does `SetLevel(255)` give the full key?
8. Do completion results behave as the scheduler assumes with a preroll of 3: no `DisplayedLate` or `Dropped` over 10 minutes at 1080p59.94 (UNV-04); does `StopScheduledPlayback(0, nullptr, 0)` flush queued frames as `Flushed`; what is `MinimumPrerollFrames`?
9. Is a display time of `index * duration` with the mode's own time scale accepted from frame 0 (preroll starting at index 0, `StartScheduledPlayback` at 0)? Does the output start without a glitch?
10. What does the output show after `DisableVideoOutput` (black, last frame, no signal)? The bridge does not set an idle-output operation.
11. Is the SDI output level (A or B, 3G) acceptable to the ATEM chain at 1080p59.94? The bridge sets no SDI link or level A/B configuration.
12. Half duplex: under `2dhd` can SDI 1 be an output while SDI 2 is an input (the loopback), or does a sub-device in half-duplex block its partner (`E_ACCESSDENIED`, `Duplex` attribute)? What do the connector pairs allow under `1dfd` (input on SDI 1 and output on SDI 2 of the same sub-device)? The adapter currently refuses an output and an input on the same physical connector.
13. Does profile activation complete, how long does it take, does `ProfileActivated` arrive for the right ID, do other sub-devices' streams stop, and does the chosen profile persist across app restarts and Desktop Video Setup?
14. Input: does format detection report the signal (`VideoInputFormatChanged`) within a frame or two; does the restart sequence from a private queue work; are frames flagged `bmdFrameHasNoInputSource` with the cable removed; does YUV to BGRA conversion with `ConvertNewFrame` and `bmdColorspaceRec709` reproduce the sent pattern within tolerance; is the hardware timestamp monotonic and in the expected scale; what does an interlaced or unknown-mode signal do?
15. Hot-plug: on unplugging the Thunderbolt enclosure does `DeckLinkDeviceRemoved` arrive for every sub-device, and what does an in-flight `ScheduleVideoFrame` return? Does the persistent ID come back unchanged on replug?
16. Do four outputs at once (two pairs, or four independent connectors under `2dhd`) keep zero late and dropped frames, and what is the CPU and Thunderbolt load (UNV-04)? The pool cap is 16 frames per output.
17. Does `GetReferenceStatus` report sensibly with no reference input?
18. Does the SDK's `GetDisplayMode` for `bmdModeHD1080p6000` report 1000/60000, and for the 59.94 modes 1001/60000? (The bridge fails the enable with an explanation if its numbers differ from the app's, so a mismatch will appear as a clear error, not a silent wrong rate.)

## Outside the scope but worth knowing (not tested, not mine to change)

- The driver is loaded at run time as `/Library/Frameworks/DeckLinkAPI.framework`, which Blackmagic signs, not this app. A hardened-runtime build normally needs library validation relaxed (`com.apple.security.cs.disable-library-validation`) to load it, and an App Sandbox build cannot reach it. Whoever owns `project.yml` and the entitlements should check this before the build goes to the tester; it would show as "driver absent" on a Mac that does have the driver.
- No `Package.swift` change was needed. The existing linker settings are sufficient; `dispatch` comes with libSystem.

## What `SDIEngine` lacks (defined locally, for the coordinator to fold in)

`SDIInputPort` and `SDIDevice.openInput` appeared in `SDIEngine` (HWTEST-001) while I worked, so `DeckLinkInputPort` and `DeckLinkDevice` conform to them; I did not edit `SDIEngine`. Still missing there, defined or worked around in `DeckLinkSDI`:

1. **A hardware-fault error.** `SDIError` has no case for "the card refused or failed for a reason other than unplugging". Such failures are mapped to `.deviceDisconnected` (its advice, reconnect and retry, is the right one) and the real text is kept in `lastErrorDetail` on each port and in the snapshots. Suggest `SDIError.hardwareFault(String)`.
2. **Fill and key connector routing.** `SDIAssignment` and `SDIConnectorPlanner` fix fill on the first connector of the pair; the manual's table suggests fill on the higher one. `DeckLinkKeyRoute` carries the physical fill and key connectors and is exposed on `DeckLinkOutputPort.keyRoute`; the planner and the operator wording need to use it once question 3 is answered.
3. **Profiles.** Nothing in `SDIDevice` expresses profiles, duplex or per-connector roles (output, input, key). Defined here: `DeckLinkProfileInfo`, `DeckLinkSubDeviceInfo`, `DeckLinkConnectorLayout`, `DeckLinkDevice.activateProfile(_:forPair:)`, `profileSupportingExternalKeying`.
4. **Hot-plug and a provider protocol.** There is no device-provider protocol or arrival/removal event in `SDIEngine`. Defined here: concrete `DeckLinkDeviceProvider` and `DeckLinkDeviceEvent` (`arrived`, `removed`, `changed`).
5. **Keyer level** and the detected-format callback with the SDK's own numbers: `DeckLinkOutputPort.setKeyerLevel`, `DeckLinkInputPort.onFormatDetected`.
6. `SDICapturedFrame.mode` is not optional, so frames that arrive in a mode the app does not offer (for example 1080i50) are not delivered; they are counted in `framesWithoutKnownMode`, and `signal` reads `.noSignal` for them.
7. `SDIOutputPort.startPlayback` cannot throw; a failure to start is reported through `onFailure`.

## Everything that could not be verified

- All of it against a card: discovery with real devices, the Duo 2 connector table, profile activation, output, keying, completion results, buffered counts, pre-roll behaviour, input detection and conversion, hot-plug, reference status. No call that reaches `IDeckLinkOutput`, `IDeckLinkInput`, `IDeckLinkKeyer`, `IDeckLinkProfile*`, `IDeckLinkVideoConversion` or `IDeckLinkDiscovery` has run once.
- The frame pool, completion bookkeeping, the input callback and the format-change restart have no unit test: they sit behind SDK interfaces that need a fake `IDeckLinkOutput`/`IDeckLinkInput` (about forty pure virtual methods) in C++, which would have to live in shipped sources. I judged that not worth the surface and left them for the hardware run; the code was written to be correct by construction (one lock, no handler under the lock) but that is a claim, not evidence.
- Thread-safety was checked only with AddressSanitizer on the driver-absent path; no ThreadSanitizer run, no stress.
- That the driver can be loaded by a signed, hardened build (see above).
