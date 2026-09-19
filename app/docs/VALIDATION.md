# Validation record

## Delivery status


- Compiler: Xcode 26.2 (17C52); SDK: iOS 26.2.
- Binary: arm64, Mach-O platform iOS device, minimum iOS 16.0.
- Downloaded IPA passed independent local validation and checksum comparison. The AirDrop ZIP was checked to contain the exact same IPA; the versioned local copy is `dist/Nultra-0.3.0.zip`.

## Automated checks

- 1,287 local protocol and transaction checks passed, including all possible state and battery bytes, all valid advertisement state/battery combinations, invalid credentials, malformed payloads, repeated broadcasts, cached-state protection, and GATT precedence.
- All Swift app sources passed local macOS SDK type checking.
- Xcode project and Info.plist passed structural validation.
- The unsigned iPhone Release build and final IPA packaging checks passed in that job.

## iPhone 13 mini / iOS 26.2 interface

Both UI tests passed. The packaged app, project and UI test sources matched the tested revision. Only packaging and documentation changed between those revisions.


Transaction tests cover identification, both power directions, rename write acknowledgement and readback, mismatched readback, every live phase interrupted by timeout/error/background cancellation, ignored late callbacks, unexpected disconnection, and persistent identity serialization. The transport invokes cancellation immediately when the shared state machine emits disconnect, before saving results. There is no idle connected state.

Simulator and model tests do not measure physical BLE connection time or validate actual firmware behavior. Measure the connect-to-disconnect duration on real switches and complete `HARDWARE_ACCEPTANCE.md`.

## Mac setup


## Remaining owner checks

- Verify on/off and rename against an actual switch, including immediate disconnect after readback, timing, Pi connection contention, and recovery after range/radio loss.
- Complete `HARDWARE_ACCEPTANCE.md`, including physical-device VoiceOver and background/foreground checks.

These are on-device acceptance steps; no claim of physical switch compatibility or perpetual signing is made before they pass.
