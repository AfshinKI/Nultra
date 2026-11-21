# Mobile controllers

The iPhone and Android apps discover Nultra switches over Bluetooth LE. Each app can control individual switches, group lights into scenes, show battery readings, and run commands from home-screen widgets.

## First connection

1. Power one switch and open the app with Bluetooth permission. Open **Menu** and choose the newly discovered switch under **Switch password**. The identifier distinguishes devices before the app learns their names.
2. Hold the switch button for two seconds and release it to open its pairing window. Save the eight-character command password generated for that switch in Menu.
3. Enter that switch’s six-digit pairing PIN when the operating system prompts. Its name will appear on the dashboard after identification. If the window expires, repeat the battery check and retry discovery.

The iPhone uses device-only Keychain entries. Android encrypts credentials with an Android Keystore key and disables app data backups. Choose **Forget password** on iPhone or **Forget** on Android to remove a switch credential. Remove the Bluetooth bond through system settings when decommissioning a phone.

## iOS

Open `Nultra.xcodeproj` in Xcode on macOS. Run the **Nultra** scheme on an iPhone running iOS 16 or later. The Home Screen widgets require iOS 17 or later. For a personal device build, select your signing team for the app and widget extension. If Xcode requires new identifiers, give both targets your own bundle identifiers, and use the same registered App Group in the app and widget entitlements and in `Shared/WidgetSnapshot.swift`. The simulator’s demo mode exercises the interface. Bluetooth requires a physical iPhone.

Run the portable protocol tests from this directory with `swift test`.

## Android

Use JDK 17 and Android SDK platform 35. Open the `android` directory in Android Studio or run the following commands from this directory. Android 8 or later is required.

```sh
cd android
./gradlew testDebugUnitTest assembleDebug
```

The debug APK is written to `app/build/outputs/apk/debug/`. The release signing configuration accepts a developer-owned keystore through environment variables. Keep distribution keys outside the checkout.

The Gradle wrapper scripts and JAR are distributed under the [Apache License 2.0](android/gradle/wrapper/LICENSE).
