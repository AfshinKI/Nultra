# Android app and APK delivery

## Scope and phases

1. Implement a native Android app using the documented fancy BLE protocol, preserving short connections, saved real names, two-column cards, live broadcasts, password settings, and parallel bulk controls.
2. Validate the protocol and transaction lifecycle, build a signed APK, and check Android permissions and packaging.
4. Test on the owner's Android hardware; emulator/build checks cannot validate the switch radio or firmware.

## Design

Android 8.0 (API 26) or newer. Native Java views and Android BluetoothGatt; no web wrapper or Pi dependency. Android identifies a peripheral by its Bluetooth address, separately from the iPhone's CoreBluetooth UUID. Saved names are read from GATT, never taken from state advertisement names.

The app listens only while its activity is foregrounded. Each transaction has one purpose and an eight-second total deadline: connect, discover service, authenticate, perform the operation, verify readback, disconnect and close. Up to three transactions can run concurrently. There is no bonding request, notification subscription, automatic command retry, or idle connection. A failed initial name lookup waits for the user's Retry command.

State and battery broadcasts update internal observations immediately, with a two-second UI cadence and five-second RSSI sampling. Online presence expires after 15 seconds. Names persist across launch, while power and battery start unknown. Custom passwords use Android Keystore AES-GCM encryption; backup is disabled to avoid restoring ciphertext without its device key.

Android 12+ requests Nearby devices. Android 8–11 requires location permission and enabled system Location for BLE scanning; Nultra does not derive location or request internet access. Permission and radio failures are shown in the app.

## Development and release


References: [Bluetooth permissions](https://developer.android.com/develop/connectivity/bluetooth/bt-permissions), [BluetoothGatt](https://developer.android.com/reference/android/bluetooth/BluetoothGatt), [app signing and update identity](https://developer.android.com/studio/publish/app-signing).

## Build and signing

The project pins Java 17, Gradle 8.11.1 (with distribution checksum), Android Gradle Plugin 8.9.2, Android SDK 35, and build tools 35.0.0. Open `android/` in Android Studio or use the checked-in Gradle wrapper. There are no third-party runtime libraries; JUnit is a test-only dependency.

```sh
# Set JAVA_HOME and ANDROID_HOME to your installed JDK and Android SDK.
android/gradlew -p android testDebugUnitTest lintRelease assembleDebug

# Release signing values should come from your private local backup or CI secrets.
export NULTRA_KEYSTORE=/absolute/path/to/nultra-release.jks
# Set NULTRA_STORE_PASSWORD privately; do not commit or paste it into logs.
bash scripts/build_apk.sh
```


`build_apk.sh` runs unit tests and lint, signs the release, verifies the signature against the pinned certificate, and checks package ID, minimum SDK, permission declarations, non-debuggable status, and release version. It emits `Nultra.apk`, its SHA-256, Android build information, and `android-release.json`.

## Emulator acceptance

With a booted Android emulator and `adb` on PATH, run `python3 scripts/android_smoke.py`. It installs the actual signed release APK and clears **only that emulator's Nultra data**, then tests first-launch permission messaging, six demo cards, bulk and individual controls, switch details, encrypted password save/relaunch/default reset, and crash logs. Screenshots and UI hierarchies are saved under `build/android-smoke/`. Do not run this data-clearing test against your everyday phone.

## Samsung hardware acceptance

- Install the release APK, grant Nearby devices, and discover a real switch with the Pi disconnected initially.
- Confirm only successfully named switches appear, names survive restart, and unseen switches turn gray without disappearing.
- Verify the advertisement power/battery state changes while disconnected, including changes made by another controller.
- Verify on, off, and rename, including password failure, range loss, radio off, and app backgrounding. Observe with firmware/Pi diagnostics that links are released promptly.
- Test All Off/All On with more than three switches, including an offline switch. Confirm partial failures are reported and no idle link remains.
- Test large system text, TalkBack, rotation, denied permissions, and password save/relaunch on the actual Samsung.
- Install a later APK over the existing app and confirm saved names/password survive. Do not uninstall to update.

The emulator cannot verify real BLE timing, MAC address stability on firmware using randomized addresses, or Samsung-specific radio behavior. Android remembers its own switch catalog; the iPhone's peripheral UUIDs cannot be reused as Android addresses.
