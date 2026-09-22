# Build, validation, and private installation

## Toolchain

The project targets iPhone on iOS 16+. Use a complete Xcode installation whose device support covers the owner's iOS version. Apple’s [Xcode system requirements](https://developer.apple.com/xcode/system-requirements) are the authoritative compatibility table. Install Xcode through the Mac App Store or [Apple Developer downloads](https://developer.apple.com/download/all/); older versions may require Apple Account sign-in.

The development Mac now has macOS 27.0 and full Xcode 27.0, selected at `/Applications/Xcode.app/Contents/Developer`. The iPhoneOS 27 SDK and iOS 27 simulator runtime are installed. The hosted fallback remains on Xcode 26.2. See [LOCAL_FIRST.md](LOCAL_FIRST.md) for the readiness results, Desktop file-provider issue, and local validation commands. Apple sign-in and GitHub CLI authentication are separate.

No Homebrew packages, npm dependencies, or third-party BLE SDKs are required. The checked-in Xcode project opens directly. Regenerate only after changing the source layout:

```sh
python3 scripts/generate_project.py
```

The generator recreates Info.plist and project settings; reselect a local signing team afterwards. The bundle ID defaults to `com.afshinki.nultra` and can be changed if signing requires a unique ID. Icons are already checked in; `python3 scripts/package_icons.py` repackages them with macOS `sips`.

## Validation commands

```sh
# Full Xcode environment
swift test
xcodebuild -project Nultra.xcodeproj -scheme Nultra \
  -sdk iphonesimulator -destination 'generic/platform=iOS Simulator' \
  -derivedDataPath build CODE_SIGNING_ALLOWED=YES CODE_SIGN_IDENTITY=- build

# Apple Silicon Mac with Command Line Tools only
bash scripts/check.sh
```

The CLI check exhaustively validates all possible state and battery bytes, all valid advertisement state/battery combinations, and malformed credentials/names/advertisements. It also type-checks the shared SwiftUI/CoreBluetooth code against macOS, not iOS. XCTest adds named regression cases, including repeated broadcast updates, GATT precedence, and terminal disconnection for every transaction, timeout, cancellation, and error. The reference checkout must track the `fancy` branch; see `FANCY_REFERENCE.md`. GitHub Actions runs only on explicit manual requests; simulator UI tests are opt-in. Simulator signing gives Keychain a consistent application identity across relaunch; no Apple account or developer certificate is needed.

Use `swift test --scratch-path /private/tmp/nultra-swift-build` on this Mac. The Desktop file provider attached Finder metadata to default build products, causing a signing failure; the temporary scratch directory avoids this. Full Xcode is now installed.

## Alternative: install directly with Xcode


1. Open `Nultra.xcodeproj` in Xcode.
2. Add the owner's Apple Account in Xcode settings and select a signing team in the Nultra target. A personal team can be used where Apple permits local development signing; provisioning limitations/renewal depend on account type.
3. Connect and trust the iPhone. Enable Developer Mode if iOS requests it.
4. Select the physical iPhone and run the Nultra scheme. Resolve any signing or device-support message shown by Xcode.
5. Allow Bluetooth when opening Nultra. Initial testing should release any active connection held by the Pi.
6. The owner-supplied master credential is used automatically. New switches briefly connect once to learn and persist their real name.
7. Complete HARDWARE_ACCEPTANCE.md before treating the build as ready for daily use.


## Reference boundaries


## iPhone 13 mini interface checks

`UITests/NultraUITests.swift` exercises six-card two-column layout, disconnected on/off, rename editing without connection, automatic return to disconnected state, leaving demo mode, foreground listening, online/offline LEDs, hidden unnamed candidates, bulk controls, Keychain password save/relaunch/default reset, and large-text/landscape navigation. The GitHub interface job creates an iPhone 13 mini with the iOS 26.2 simulator runtime and exports screenshot attachments and an xcresult bundle. These validate UI behavior, not BLE transport or personal provisioning.


`bash scripts/build_ipa.sh` compiles a Release `iphoneos` binary without signing, checks arm64/platform metadata, packages `Payload/Nultra.app` into `dist/Nultra.ipa`, and produces a SHA-256 checksum plus source/build information. `python3 scripts/verify_ipa.py path/to/Nultra.ipa` independently validates the ZIP layout, iPhone metadata, Bluetooth purpose string, and Mach-O platform. No Apple credentials, signing certificates, profiles, or public distribution are involved in CI. Artifacts stay in the private app repository.


## Local-first releases and Android builds

The current policy and exact commands are in [LOCAL_FIRST.md](LOCAL_FIRST.md).
Build/test locally and upload release assets with GitHub CLI. PR labels and merges
no longer allocate runners. The hosted workflow is a manual, cost-acknowledged
fallback only. See [ANDROID.md](ANDROID.md) for Android signing and hardware checks.
