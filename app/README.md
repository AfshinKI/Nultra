# Nultra for iPhone and Android

A private, native controller for your Nultra BLE switches. Android now has its own native app and signed APK; see the Android installation section below. Your **iPhone 13 mini running iOS 26.2** talks directly to each switch over Bluetooth. The Raspberry Pi and an internet connection are not needed for switch control.


## Install on Samsung Galaxy / Android


1. Open the downloaded APK using your browser or **My Files → Downloads**.
2. If prompted, allow **Install unknown apps** for that browser or My Files, then return and install Nultra. On Samsung, search Settings for **Install unknown apps** if the wording differs. If Samsung Auto Blocker prevents installation, review its warning under **Settings → Security and privacy → Auto Blocker**; temporarily disabling it is only needed if you choose to sideload, and you can restore it after installation. [Samsung Auto Blocker guide](https://example.invalid).
3. Open Nultra and choose **Allow Bluetooth access**. On Android 12+, grant **Nearby devices**. Android 8–11 requires location permission and system Location enabled for BLE scanning; the app does not collect location or access the internet.
4. Let the app discover your switches and read their real names. Tap a bulb to change power; tap the name for settings and rename. Use Menu to set the master password or explore the demo.


See [Android development, signing, and hardware checks](docs/ANDROID.md). Physical Samsung BLE testing is still required.


## Preview on iPhone 13 mini

Actual iOS 26.2 simulator captures; the shown switches are demo devices.


## Do I need a developer account?


## What is ready, and what is still a phone test?

The app implements discovery, automatic one-time name lookup, persistent real names, live battery/state broadcasts, on/off with readback, and rename. Every lookup or change uses a brief connection followed by immediate disconnection. A labeled demo lets you explore without touching real switches. The compact dashboard uses **two columns**. The app processes up to three switch transactions in parallel and never remains connected while idle or while you edit a name.


## 1. Get Nultra.ipa


### If AirDrop accepts the IPA but it does not appear in Files


2. Connect the unlocked iPhone by USB and accept **Trust** when prompted. In Finder, select the iPhone, enable **Show this iPhone when on Wi-Fi**, and apply.
5. On the iPhone, trust your account under **Settings → General → VPN & Device Management**. Enable **Settings → Privacy & Security → Developer Mode**, restart, and confirm if prompted.


## 3. Install Nultra

4. Open Nultra. You can select **Explore the demo** first; demo mode never sends switch commands.


## 4. Keep it available


- Check **My Apps → Refresh All** every few days; a practical routine is every 3–4 days, with a manual refresh before travel. Verify the expiration countdown actually increases. Background refresh is an attempt, not a guarantee.


## 5. Connect your first real switch

1. If using demo mode, turn off **Menu → Explore demo mode**.
2. Power your Nultra switch and place it near the iPhone. Release its Raspberry Pi BLE connection during the first test; some firmware may accept only one controller.
3. Open Nultra and allow Bluetooth access. Listening starts automatically whenever the app is open. Saved switches remain visible across launches and while offline. A small blue LED means seen within 15 seconds; gray means not currently seen. New switches only appear after their real name has been read.
4. New switches automatically make one brief connection using your configured master password to read their real name and firmware, then immediately disconnect. Names are saved on your phone. Known switches are monitored through broadcasts without reconnecting.
5. Tap the bulb on a card to change power. The app connects, authenticates, writes the requested state, verifies readback, and immediately disconnects. Tap the real name to open details with explicit **On** and **Off** buttons.
6. Tap the real name → **Rename**, enter exactly eight printable ASCII characters such as `DESKLAMP`, then **Save name**. Editing stays disconnected; Save briefly connects, writes, verifies, and disconnects.


Complete the short [hardware acceptance checklist](docs/HARDWARE_ACCEPTANCE.md). Report the app commit, firmware, and symptom if a test fails—never your password.


One-time iPhone steps:

1. AirDrop `dist/Nultra-Updates.mobileconfig` (the Pi service is already configured). Install **Nultra Private Updates** under **Settings → General → VPN & Device Management**.


The private HTTPS leaf certificate lasts one year; renewal commands are in the Pi instructions. Reserve the Pi's IP address in your router. No GitHub token is embedded in the iPhone app or source JSON.


## Apple Shortcuts

1. Install this release, open Nultra, allow Bluetooth, and let it learn your switches' real names. Turn off demo mode.
2. Open **Shortcuts → + → Add Action**, search **Nultra**, and choose **Turn All Off**, **Turn All On**, or **Set Switch Power**.
3. For one switch, select its saved name and the desired On value. Name the shortcut, for example **Lights Off**, and optionally add it to your Home Screen or an automation.
4. Run it from Shortcuts with **Show When Run** disabled if offered. Nultra no longer requests its window to open. It runs up to three brief transactions at once and reports Bluetooth confirmation, server queue acceptance, or failure. If an existing shortcut retains old behavior after updating, remove and re-add its Nultra action.

Actions use the phone's BLE first, with optional backup-server fallback. Open the app once to grant permissions and learn names; unlock once after a phone restart. iOS controls background execution time, so locked-phone execution needs device testing. Demo mode is rejected.

### Optional backup server (iPhone and Android)


A nearby switch uses phone Bluetooth. If unavailable, an enabled reachable server that recently saw the switch can receive the on/off command. Server replies mean **queued**, not physically confirmed. The server is checked every 15 seconds while the app is open; Shortcuts use on-demand requests. Rename stays Bluetooth-only. Android widgets also use bounded on-demand requests. See [server behavior, limits, and phone checks](docs/SERVER_FALLBACK.md).

### Android background controls

1. Install the new `Nultra.apk` **over the existing app** to retain switches, password, and settings. Do not uninstall first.
2. Open Nultra, grant Nearby devices, and discover your real switches. Leave demo mode off. Configure the optional server under **Menu → Backup server**.
3. On your Samsung home screen, long-press an empty area → **Widgets → Nultra**. Add the widget and choose **All switches** or a saved switch.
4. Tap **Off** or **On** on the widget. Nultra runs a short foreground service without opening its app window. The widget reports the result; Android may show an active-task notification. No service, scan, or server polling remains running after the action.

A widget action has a 24-second limit, up to three concurrent operations, and no automatic HTTP retry. Large batches or unreachable switches can partially finish; check the reported result. A server “queued” result is not physical confirmation. Samsung power-management and real BLE behaviour still need testing on your phone. Apple Shortcuts itself is iPhone-only; the Android equivalent provided here is the home-screen widget.

## Widgets, power toggles, and battery alerts (v0.9.0)


The Android widget defaults to **2×1**, remains resizable, and controls one saved light or all lights. The switch detail page on both platforms now uses a single power toggle. Busy controls are disabled, and the displayed state follows confirmed device/server readings.

Enable **Battery alerts** in Menu and allow notifications. Set a threshold from 1–50% (default 5%). A switch sends one local notification when a received reading is at or below that threshold. It rearms only after the battery rises at least ten points above the threshold that triggered the alert, so small fluctuations and app restarts do not repeat it. Demo readings never notify. These are local notifications from incoming Bluetooth/server observations, not remote push monitoring while the app is stopped.


## Release process and runner usage

Pushes, ordinary PRs, documentation edits, and tags do **not** start hosted builds. Run local checks during development, and use a PR to merge changes into `main` before publishing.

1. Bump `MARKETING_VERSION` and `CURRENT_PROJECT_VERSION` in `scripts/generate_project.py`; regenerate the project. Set matching `versionName` and an increased `versionCode` in `android/app/build.gradle`.
2. Write `docs/releases/vX.X.X.md`, run `bash scripts/check.sh`, Android unit tests/lint, and `python3 -m unittest discover -s distribution/tests -v`. Open and merge the PR into `main`.
3. For automatic publication after merge, add the `publish-release` label to the PR before merging. Otherwise, in Actions → **iPhone and Android release** → **Run workflow**, select `main` and enable **Publish a new version**. Publication from other branches is rejected before build jobs start. Both platforms are always built for publication.
4. Leave **Run expensive iPhone simulator tests** off unless UI validation is needed. Run those tests locally when possible; if no compatible local Xcode is available, enable them for UI changes. Diagnostic runs can select just `ios` or `android` to avoid an unrelated build. Adding the `validate-ios-ui` label to a same-repository PR requests one iPhone build with simulator tests; it does not build Android or publish. Remove and re-add that label only if the PR changes and needs another check.
5. A short Linux preflight checks matching versions, release notes, and already-published versions, and runs distribution tests. macOS runs Swift tests and builds the IPA; Linux runs Android tests/lint and builds the APK. Publication creates the `vX.X.X` tag and a release titled exactly `vX.X.X` at the validated commit. No second build runs for the tag.

Published versions are immutable: bump the version for further changes. A failed run may be retried using **Re-run failed jobs** to retain successful build outputs. Diagnostic runs leave **Publish a new version** disabled and never publish. An explicitly labeled release PR publishes only on its successful merge into main, using the merge commit. Swift and Gradle caches reduce repeated work; ZIP/APK/IPA uploads avoid redundant compression. Artifacts expire after seven days; release assets remain. Publication runs are serialized per branch instead of cancelling a release halfway through asset upload.

## Build it yourself (optional)

The checked-in `Nultra.xcodeproj` has no third-party app dependencies. CI uses **Xcode 26.2 on macOS 15**, matching your iOS version. Xcode 26.2 requires macOS 15.6 or later; this Mac is on 13.0.1, so Xcode 26.2 was not installed locally. The hosted build avoids an OS upgrade for this installation route. [Apple toolchain requirements](https://developer.apple.com/xcode/system-requirements)

On a compatible Mac with Xcode:

```sh
swift test
bash scripts/build_ipa.sh
# Output: dist/Nultra.ipa, checksum, and build information
```

On this Mac with Command Line Tools only:

```sh
bash scripts/check.sh
```

That runs portable protocol checks and macOS type checking; it does not build an iPhone IPA. Project structure changes can be regenerated with `python3 scripts/generate_project.py`.


The BLE implementation follows the latest `fancy` branch of the reference server. See [broadcast behavior and web UI adaptations](docs/FANCY_REFERENCE.md).

Battery-saving BLE behavior is specified in [short connections](docs/SHORT_CONNECTIONS.md).

Use **All Off** or **All On** at the top to update every saved named switch. Up to three short connections run concurrently; the result reports failures, including unavailable switches. Backgrounding cancels unfinished operations.
