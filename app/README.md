# Nultra for iPhone

A private, native controller for your Nultra BLE switches. Your **iPhone 13 mini running iOS 26.2** talks directly to each switch over Bluetooth. The Raspberry Pi and an internet connection are not needed for switch control.


## Preview on iPhone 13 mini

Actual iOS 26.2 simulator captures; the shown switches are demo devices.


## Do I need a developer account?


## What is ready, and what is still a phone test?

The app implements discovery, automatic one-time name lookup, persistent real names, live battery/state broadcasts, on/off with readback, and rename. Every lookup or change uses a brief connection followed by immediate disconnection. A labeled demo lets you explore without touching real switches. The compact dashboard uses **two columns**. The app processes one transaction at a time and never remains connected while idle or while you edit a name.


## 1. Get Nultra.ipa


2. Open the newest successful **iOS validation** run on `main`. Confirm the **build** job passed.
4. Keep this folder somewhere convenient. `BUILD-INFO.txt` records the source commit and Xcode version. Optional integrity check from that folder: `shasum -a 256 -c Nultra.ipa.sha256`.
5. AirDrop `Nultra.ipa` to your iPhone and save it in **Files**. You can also transfer it using iCloud Drive.


### If AirDrop accepts the IPA but it does not appear in Files


2. Connect the unlocked iPhone by USB and accept **Trust** when prompted. In Finder, select the iPhone, enable **Show this iPhone when on Wi-Fi**, and apply.
5. On the iPhone, trust your account under **Settings → General → VPN & Device Management**. Enable **Settings → Privacy & Security → Developer Mode**, restart, and confirm if prompted.


## 3. Install Nultra

4. Open Nultra. You can select **Explore the demo** first; demo mode never sends switch commands.


## 4. Keep it available


- Check **My Apps → Refresh All** every few days; a practical routine is every 3–4 days, with a manual refresh before travel. Verify the expiration countdown actually increases. Background refresh is an attempt, not a guarantee.


## 5. Connect your first real switch

1. If using demo mode, turn off **Settings → Explore demo mode**.
2. Power your Nultra switch and place it near the iPhone. Release its Raspberry Pi BLE connection during the first test; some firmware may accept only one controller.
3. Tap **Find switches** and allow Bluetooth access. The app keeps listening for state and battery broadcasts while open. Tap **Stop listening** to stop. Listening resumes after returning from the background if it was previously enabled. Cards retain their last observed values and show their age.
4. New switches automatically make one brief connection using your configured master password to read their real name and firmware, then immediately disconnect. Names are saved on your phone. Known switches are monitored through broadcasts without reconnecting.
5. Tap the bulb/state control on a card to change power. The app connects, authenticates, writes the requested state, verifies readback, and immediately disconnects. Tap the real name to open details with explicit **On** and **Off** buttons.
6. Tap the real name → **Rename**, enter exactly eight printable ASCII characters such as `DESKLAMP`, then **Save name**. Editing stays disconnected; Save briefly connects, writes, verifies, and disconnects.

If nothing appears, check **Settings → Privacy & Security → Bluetooth → Nultra**, the phone's Bluetooth radio, range, and switch power. If connection fails, disconnect the Pi and retry. If a name lookup fails, use **Retry name lookup**; it will not repeatedly reconnect on each advertisement. This private build uses the owner-supplied master credential automatically. A successful connection alone cannot prove firmware authentication; real command confirmation matters.

Complete the short [hardware acceptance checklist](docs/HARDWARE_ACCEPTANCE.md). Report the app commit, firmware, and symptom if a test fails—never your password.

## Updating Nultra


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
