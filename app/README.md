# Nultra for iPhone

A private, native controller for your Nultra BLE switches. Your **iPhone 13 mini running iOS 26.2** talks directly to each switch over Bluetooth. The Raspberry Pi and an internet connection are not needed for switch control.


## Preview on iPhone 13 mini

Actual iOS 26.2 simulator captures; the shown switches are demo devices.


## Do I need a developer account?


## What is ready, and what is still a phone test?

The app implements discovery, per-switch password storage in Keychain, connection, on/off with state confirmation, battery/firmware readings, rename, and disconnect. A labeled demo lets you explore without touching real switches. The app controls **one connected switch at a time** and disconnects when backgrounded.


## 1. Get Nultra.ipa

**A verified copy is already saved in this workspace at `dist/Nultra.ipa`.** AirDrop that file to your phone and continue with step 2. The checksum and source/build details are beside it. For another computer or a future update, download it as follows:

2. Open the newest successful **iOS validation** run on `main`. Confirm the **build** job passed.
4. Keep this folder somewhere convenient. `BUILD-INFO.txt` records the source commit and Xcode version. Optional integrity check from that folder: `shasum -a 256 -c Nultra.ipa.sha256`.
5. AirDrop `Nultra.ipa` to your iPhone and save it in **Files**. You can also transfer it using iCloud Drive.


2. Connect the unlocked iPhone by USB and accept **Trust** when prompted. In Finder, select the iPhone, enable **Show this iPhone when on Wi-Fi**, and apply.
5. On the iPhone, trust your account under **Settings → General → VPN & Device Management**. Enable **Settings → Privacy & Security → Developer Mode**, restart, and confirm if prompted.


## 3. Install Nultra

4. Open Nultra. You can select **Explore the demo** first; demo mode never sends switch commands.


## 4. Keep it available


- Check **My Apps → Refresh All** every few days; a practical routine is every 3–4 days, with a manual refresh before travel. Verify the expiration countdown actually increases. Background refresh is an attempt, not a guarantee.


## 5. Connect your first real switch

1. If using demo mode, disconnect the sample switch, then turn off **Settings → Explore demo mode**.
2. Power your Nultra switch and place it near the iPhone. Release its Raspberry Pi BLE connection during the first test; some firmware may accept only one controller.
3. Tap **Find switches** and allow Bluetooth access. The app keeps listening for state and battery broadcasts while open. Tap **Stop listening** to stop. After returning from the background, tap **Find switches** again. Cards retain their last observed values and show their age.
4. Tap your switch. Enter its actual **8-character ASCII password**, then **Save & connect**. Use the credential configured in your switch/reference server; it is intentionally not copied into the app or this README.
5. Wait for **Connected** and the name/battery/state readings. Tap **On**, confirm the physical switch changes, then test **Off**. The app checks the state reported by the switch before confirming a command.
6. Rename uses exactly eight printable ASCII characters, such as `DESKLAMP`. Disconnect before choosing another switch.

If nothing appears, check **Settings → Privacy & Security → Bluetooth → Nultra**, the phone's Bluetooth radio, range, and switch power. If connection fails, disconnect the Pi and retry. If the password is wrong, disconnect and use **Use a different password**. A successful connection alone cannot prove firmware authentication; real command confirmation matters.

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
