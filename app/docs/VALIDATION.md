# Validation record

## Delivery status


- Compiler: Xcode 26.2 (17C52); SDK: iOS 26.2.
- Binary: arm64, Mach-O platform iOS device, minimum iOS 16.0.
- Downloaded IPA passed independent local validation and checksum comparison.

## Automated checks

- 733 local protocol checks passed, including all possible state and battery bytes, all valid advertisement state/battery combinations, invalid credentials, and malformed payloads.
- All Swift app sources passed local macOS SDK type checking.
- Xcode project and Info.plist passed structural validation.
- The unsigned iPhone Release build and final IPA packaging checks passed in that job.

## iPhone 13 mini / iOS 26.2 interface

Both UI tests passed on the packaged source revision. The device-package and interface jobs completed successfully. The screenshots came from the preceding successful run with identical app and UI test sources.


Simulator tests do not validate physical BLE transport or personal provisioning. The earlier generic simulator startup issue does not apply to these successful device-specific checks.

## Mac setup


## Remaining owner checks

- Verify on/off and rename against an actual switch, including wrong-password behavior, timing, Pi connection contention, and reconnect after range/radio loss.
- Complete `HARDWARE_ACCEPTANCE.md`, including physical-device VoiceOver and background/foreground checks.

These are on-device acceptance steps; no claim of physical switch compatibility or perpetual signing is made before they pass.
