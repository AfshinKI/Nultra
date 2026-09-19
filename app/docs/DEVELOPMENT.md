# Build, validation, and private installation

## Toolchain

The project targets iPhone on iOS 16+. Use a complete Xcode installation whose device support covers the owner's iOS version. Apple’s [Xcode system requirements](https://developer.apple.com/xcode/system-requirements) are the authoritative compatibility table. Install Xcode through the Mac App Store or [Apple Developer downloads](https://developer.apple.com/download/all/); older versions may require Apple Account sign-in.


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
  -derivedDataPath build CODE_SIGNING_ALLOWED=NO build

# Apple Silicon Mac with Command Line Tools only
bash scripts/check.sh
```

The CLI check exhaustively validates all possible state and battery bytes, all valid advertisement state/battery combinations, and malformed credentials/names/advertisements. It also type-checks the shared SwiftUI/CoreBluetooth code against macOS, not iOS. XCTest adds named regression cases, including repeated broadcast updates and protecting active GATT state. The reference checkout must track the `fancy` branch; see `FANCY_REFERENCE.md`. GitHub Actions runs XCTest and a full unsigned iOS simulator build on app changes.

Local `swift test` initially fails because the incomplete Command Line Tools setup lacks the Xcode platform path. This is a toolchain limitation, not a passing test result. Use the dependency-free check script locally until Xcode is available.

## Alternative: install directly with Xcode


1. Open `Nultra.xcodeproj` in Xcode.
2. Add the owner's Apple Account in Xcode settings and select a signing team in the Nultra target. A personal team can be used where Apple permits local development signing; provisioning limitations/renewal depend on account type.
3. Connect and trust the iPhone. Enable Developer Mode if iOS requests it.
4. Select the physical iPhone and run the Nultra scheme. Resolve any signing or device-support message shown by Xcode.
5. Allow Bluetooth when tapping Find switches. Initial testing should release any active connection held by the Pi.
6. Enter the actual device password locally in the app. Never paste passwords into git issues or chat.
7. Complete HARDWARE_ACCEPTANCE.md before treating the build as ready for daily use.


## Reference boundaries


## iPhone 13 mini interface checks

`UITests/NultraUITests.swift` exercises demo connect, on/off, rename, disconnect, leaving demo mode, and large-text/landscape navigation. The GitHub interface job creates an iPhone 13 mini with the iOS 26.2 simulator runtime and exports screenshot attachments and an xcresult bundle. These validate UI behavior, not BLE transport or personal provisioning.


`bash scripts/build_ipa.sh` compiles a Release `iphoneos` binary without signing, checks arm64/platform metadata, packages `Payload/Nultra.app` into `dist/Nultra.ipa`, and produces a SHA-256 checksum plus source/build information. `python3 scripts/verify_ipa.py path/to/Nultra.ipa` independently validates the ZIP layout, iPhone metadata, Bluetooth purpose string, and Mach-O platform. No Apple credentials, signing certificates, profiles, or public distribution are involved in CI. Artifacts stay in the private app repository.
