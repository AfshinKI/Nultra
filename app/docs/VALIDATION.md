# Validation record — v0.11.0

Local validation on macOS 27.0 / Xcode 27.0:

- 37 Swift unit tests passed, including accepted-work lifetime, early return, overlapping request rejection, late-failure cleanup, expiration cancellation, and six-slot scheduling/disconnection accounting.
- 1,300 portable protocol checks plus widget/scene checks, macOS type-checking, and plist/project validation passed.
- 11 distribution/release tests passed.
- Eight iPhone 13 mini / iOS 27.0 UI tests passed according to the test-suite summary, including read-only active/queued/limit display, demo Shortcut rejection, scene membership, server/password persistence, and dashboard controls. A scene accessibility wrapper assertion was corrected to read the actual switch.
- 29 Android unit tests, release lint, debug build, and six Android 15/API 35 instrumentation tests passed. The new loopback fixture held six requests active, verified the seventh remained queued, then received all seven explicit Off commands after slots became available. It used fictional switches and did not contact the owner's server or lights.

Shortcuts acknowledge accepted work, not physical completion. A retained bounded task tries Bluetooth then enabled server fallback; late failures are silent. Widgets still await the attempt result. Six is the chosen app transaction limit, not an OS-reported radio maximum.


---

# Validation record — v0.8.0

Android adds optional server fallback and home-screen background controls. iPhone behaviour is unchanged; only its version/build changes to 0.8.0 (8).

Local validation passed:

- **24 Java unit tests**: existing protocol/transaction checks plus configured URL validation, stable-MAC matching, pinned mappings, duplicate/stale/invalid-address rejection, unknown state/battery handling, exact GET/POST routes, queue error rejection, and cancelled-client suppression.
- **Two Android 15/API 35 emulator instrumentation tests**: the widget-equivalent foreground-service PendingIntent sends GET then explicit Off without opening MainActivity, does not mistake queue admission for confirmed power, and clears active work; cancelling while a server GET is in flight prevents a subsequent POST.
- **Signed release APK UI smoke**: first launch, six compact demo cards, all/individual power, details, encrypted password persistence/reset, optional backup URL and enabled-state persistence across force-stop/relaunch, disabling fallback, and no runtime crash. Menu and server settings screenshots were visually reviewed.
- Release lint: zero errors; three advisories for the test runner version and existing launcher resource refinements. Signing matches the pinned existing certificate; package ID, API 26 minimum, versionCode 8, non-debuggable status, and new network/service permissions pass packaging checks.
- 1,300 portable Swift protocol checks, macOS type checking, plist/project validation, and five distribution tests. The distribution socket fixture required running outside the filesystem/network sandbox.


Physical Samsung BLE timing, launcher widget placement, locked-phone execution, and real server-controlled lights require [Android hardware acceptance](ANDROID.md). The emulator tests use only fictional switches and local fixture servers. No VPN is implemented.

---

# Validation record — v0.7.0


The iPhone change sets all three App Intents to background presentation, adds bounded BLE command execution, and introduces an opt-in server fallback with explicit/unique-name switch mapping. Android changes only its version/build number.

Local validation passed 1,300 portable protocol assertions, macOS type checking, plist/project validation, and five distribution tests. Full local SwiftPM/iOS builds require Xcode, which this Mac does not have; those checks run in CI. A read-only GET against the existing Pi returned nine recently seen switches with unique names and the expected fancy API fields. No physical light command was sent during this check.

The initial validation run was superseded before publication to shorten background BLE connection waiting to two seconds when a backup server is enabled. Its 29 Foundation tests, iPhone compilation, Android build, server-settings persistence UI test, password persistence test, and other completed UI tests passed. The corrected source passed the release workflow above: **29 Foundation XCTest cases, six iPhone 13 mini/iOS 26.2 UI tests, five distribution tests, iPhone Release build, Android tests/lint/signing, and publication**. Downloaded IPA metadata independently confirms `openAppWhenRun = false` for all three App Intents. The server-settings screenshot was visually reviewed.


- IPA verified as arm64 iPhoneOS, minimum iOS 16.0, version 0.7.0 build 7.


Physical iPhone BLE, cold background Shortcut presentation, locked-phone execution, real command fallback, and radio disconnect timing require the acceptance checklist in [SERVER_FALLBACK.md](SERVER_FALLBACK.md). Simulator success and server queue admission are not substitutes for physical command confirmation. The server code remains unchanged. No VPN was implemented.

---

# Validation record — v0.6.0

## Published packages


- Android: package `com.afshinki.nultra`, version 0.6.0, versionCode 6; Android 8.0/API 26 minimum; SDK 35 target; 61,748-byte universal APK without native ABI restrictions.

Downloaded workflow artifacts were independently checked against the published GitHub release asset digests and checksum files. Android signature verification passed with the pinned certificate. The downloaded APK's `classes.dex`, `AndroidManifest.xml`, and `resources.arsc` are byte-for-byte identical to the locally emulator-tested APK. The IPA passed independent platform, bundle, and version validation.

Local install packages: `dist/Nultra.apk`, `dist/Nultra.ipa`, and `dist/Nultra-0.6.0.zip`.

## Android validation


The signed release APK was installed on a local Android 15/API 35 arm64 emulator. `scripts/android_smoke.py` passed:

- First-launch permission guidance, with no named switches shown before identification.
- Six demo cards in two columns, All Off/All On, individual power, and switch details.
- Android Keystore password save, force-stop/relaunch, custom-password status, default reset, and another relaunch.
- No AndroidRuntime crash.


An initial CI setup attempt failed because the Android setup action's default included Google's retired `tools` package. The workflow now requests only the supported `platform-tools` package; the corrected release workflow passed. No app code changes were required for that CI failure.

## iPhone validation


## Distribution and Pi

Ordinary main pushes and tags do not trigger Actions. Release branches run one macOS iPhone job, one Linux Android job, and a short Linux publication job. iPhone simulator tests run only when iPhone source/assets/tests change or are explicitly requested.


## Remaining owner acceptance

Physical Samsung Galaxy BLE behavior, actual connection duration, firmware compatibility, radio failure recovery, and Samsung APK installation remain unverified. Complete [Android hardware acceptance](ANDROID.md) on the owner's phone. Emulator tests cannot validate physical BLE.
