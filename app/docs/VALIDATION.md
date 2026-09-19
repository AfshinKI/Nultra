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
