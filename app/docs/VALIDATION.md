# Validation record — v0.6.0

## Android release preparation

The native Android app builds and signs locally with the pinned certificate. All 17 Java unit tests pass, covering valid/invalid advertisements, wire values, name/firmware decoding, ASCII validation, signal thresholds, authenticated transaction progression, readback mismatch, timeout, and late-callback suppression. Android release lint has no errors.

The actual signed APK installs and runs on a local Android 15 / API 35 arm64 emulator. Smoke acceptance covers first-launch permission messaging, six demo cards, All Off/All On, individual power, switch details, Android Keystore password save/relaunch/reset, and no runtime crashes. Final release asset and workflow details will be recorded after publication.


The iPhone implementation is unchanged from v0.5.0 except its version/build number. The local iPhone typecheck and 1,300 portable checks pass. The release workflow still builds and verifies its new IPA, but skips unchanged iPhone UI tests to save runner time.

Physical Samsung Galaxy BLE, radio timing, switch firmware, and installation behavior remain owner acceptance checks; see [Android hardware acceptance](ANDROID.md).

---

## Previous validated release — v0.5.0

## Delivered release


- Xcode 26.2; iOS 26.2 SDK; arm64 iPhone executable; minimum iOS 16.
- Local package: `dist/Nultra.ipa`; AirDrop wrapper: `dist/Nultra-0.5.0.zip`.
- Independent package validation checked device platform, version, executable permissions, Bluetooth purpose string, and checksum. The transfer ZIP contains the identical IPA.
- Packaged App Intents metadata contains Turn All Off, Turn All On, and Set Switch Power, with two automatic App Shortcuts.

## Automated and visual checks


- 23 Foundation XCTest cases, covering protocol, transaction lifecycle, scheduling, persistence, presentation, and shortcut target selection.
- Five Python distribution tests covering source metadata, route isolation, authenticated redirect handling, checksum rejection, and atomic publication.
- iPhone Release build and IPA validation.
- Five iPhone 13 mini / iOS 26.2 UI tests, covering the dashboard, demo controls, password persistence, accessibility/landscape navigation, spinner-only progress, and rejection of demo hardware Shortcuts.


Ordinary main pushes and tags do not trigger Actions. A release branch runs one macOS validation/build job and a short Linux publication job.

## Live Pi feed


- The configured read-only GitHub token successfully downloaded the private v0.5.0 release.
- HTTPS was verified from the Mac using the generated CA, without disabling certificate checks.
- The live source reports bundle `com.afshinki.nultra`, version 0.5.0, build 5, and the correct IPA size.
- The IPA downloaded from the live feed matches the release SHA-256 above.
- Requests for `/github-token` and `/tls/server.key` return 404.
- The service checks for new stable releases every 30 minutes. The private token and TLS private keys remain on the Pi and are not release assets.


## Remaining phone acceptance

Automated tests do not measure physical BLE connection duration or prove actual switch firmware behavior. Complete `HARDWARE_ACCEPTANCE.md` on the iPhone, including immediate disconnect, three-switch concurrency, rename, range/radio failure, and real Shortcuts execution.
