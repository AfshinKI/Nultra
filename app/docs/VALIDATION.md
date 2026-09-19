# Validation record

## 0.5 release in progress


The previous validated 0.4 release is recorded below for reference.

## Delivery status


- Compiler: Xcode 26.2 (17C52); SDK: iOS 26.2.
- Binary: arm64, Mach-O platform iOS device, minimum iOS 16.0.
- Downloaded IPA passed independent local validation and checksum comparison. The AirDrop ZIP was checked to contain the exact same IPA; the versioned local copy is `dist/Nultra-0.4.0.zip`.

## Automated checks

- 1,300 local protocol and transaction checks passed, including all possible state and battery bytes, all valid advertisement state/battery combinations, invalid credentials, malformed payloads, repeated broadcasts, cached-state protection, and GATT precedence.
- All Swift app sources passed local macOS SDK type checking.
- Xcode project and Info.plist passed structural validation.
- The unsigned iPhone Release build and final IPA packaging checks passed in that job.

## iPhone 13 mini / iOS 26.2 interface


- Six named cards fit in two columns; unnamed candidates stay hidden; online/offline LEDs are exposed to accessibility.
- All Off / All On, individual demo power, disconnected rename editing, and returning to automatic foreground listening pass.
- A custom password saves to Keychain and loads after app termination/relaunch. Restoring the default also survives another relaunch. The test checks that the loaded field is valid and no storage error is displayed.
- Large accessibility text and landscape Menu remain navigable.


Unit tests now include three-slot scheduling, duplicate target prevention, holding slots through cancellation acknowledgement, cross-transaction isolation, bulk partial-failure accounting, persistent catalog restoration/rename, hidden unnamed candidates, and 15-second presence expiry without removing saved switches.

Model and simulator tests do not measure physical BLE connection time or validate actual firmware behavior. Complete `HARDWARE_ACCEPTANCE.md` on real switches, including parallel operations.

## Mac setup


## Remaining owner checks

- Verify on/off and rename against an actual switch, including immediate disconnect after readback, timing, Pi connection contention, and recovery after range/radio loss.
- Complete `HARDWARE_ACCEPTANCE.md`, including physical-device VoiceOver and background/foreground checks.

These are on-device acceptance steps; no claim of physical switch compatibility or perpetual signing is made before they pass.
