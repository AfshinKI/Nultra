# Validation record

## Verified locally

- 733 dependency-free protocol checks passed: exhaustive byte bounds, all valid advertisement state/battery combinations, invalid credentials and malformed payloads.
- All Swift sources passed type-checking with the available macOS SDK.
- Xcode project and Info.plist passed `plutil` validation.
- Icon artwork is opaque and packaged in the required iPhone sizes.

## Verified with the iOS SDK on GitHub


- All five XCTest cases passed with zero failures.
- Unsigned Debug iPhone simulator build succeeded.
- The build has no App Intents dependency; the associated metadata-extraction warning is expected.

## Still required

- Xcode installation compatible with this Mac and the owner's iPhone OS, plus personal signing.
- Physical iPhone installation and all scenarios in HARDWARE_ACCEPTANCE.md.
- Wrong-password behavior and command timing against the actual switch firmware.
- VoiceOver, large Dynamic Type, landscape, and device-sheet interactions on an iPhone.

A successful simulator build does not prove authentication or physical control works on hardware. The reference client defines behavior to implement; firmware confirmation is still outstanding.
