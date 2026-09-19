# Nultra for iPhone

A private, native controller for your Nultra BLE switches. Your **iPhone 13 mini running iOS 26.2** talks directly to each switch over Bluetooth. The Raspberry Pi and an internet connection are not needed for switch control.


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

1. AirDrop `dist/Nultra-Updates.mobileconfig` after the Pi service has been configured. Install **Nultra Private Updates** under **Settings → General → VPN & Device Management**.


The private HTTPS leaf certificate lasts one year; renewal commands are in the Pi instructions. Reserve the Pi's IP address in your router. No GitHub token is embedded in the iPhone app or source JSON.


## Apple Shortcuts

1. Install this release, open Nultra, allow Bluetooth, and let it learn your switches' real names. Turn off demo mode.
2. Open **Shortcuts → + → Add Action**, search **Nultra**, and choose **Turn All Off**, **Turn All On**, or **Set Switch Power**.
3. For one switch, select its saved name and the desired On value. Name the shortcut, for example **Lights Off**, and optionally add it to your Home Screen or an automation.
4. Run it with the iPhone unlocked and switches nearby. Nultra opens, runs up to three brief transactions at once, and reports verified success or failure. Keep Nultra open until it finishes.

These actions use the phone's BLE directly. They do not run a permanent connection or require the Pi. They need the foreground app; this release does not promise locked-phone or unattended background switch control. Demo mode is rejected so a shortcut cannot report fake hardware success.

## Release process and runner usage

Ordinary `main` pushes, documentation edits, and tags do **not** start Actions. Do local checks during development. When ready for a release:

1. Bump `MARKETING_VERSION` and `CURRENT_PROJECT_VERSION` in `scripts/generate_project.py`; regenerate the project.
2. Write `docs/releases/vX.X.X.md`, run `bash scripts/check.sh` and `python3 -m unittest discover -s distribution/tests -v`, and commit/push `main`.
3. Push the reviewed commit to `release/vX.X.X`: `git push origin HEAD:refs/heads/release/vX.X.X`.
4. A single macOS job runs unit tests, builds the IPA once, and validates the iPhone interface. A short Linux job creates the `vX.X.X` tag and GitHub release only after validation succeeds, attaching the IPA, checksum, transfer ZIP, build information, and Pi update bundle. No second build runs for that tag.

Published versions are immutable: make a new version for further changes. Before publication, a failed build can be fixed by advancing the release branch. Manual **Run workflow** is available for a diagnostic build, with optional UI tests; it does not publish when run on `main`. Actions artifacts expire after seven days; the release assets remain.

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
