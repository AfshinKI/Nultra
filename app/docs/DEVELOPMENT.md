# Build, validation, and private installation

## Toolchain

The project targets iPhone on iOS 16+. Use a complete Xcode installation whose device support covers the owner's iOS version. Apple’s [Xcode system requirements](https://developer.apple.com/xcode/system-requirements) are the authoritative compatibility table. Install Xcode through the Mac App Store or [Apple Developer downloads](https://developer.apple.com/download/all/); older versions may require Apple Account sign-in.

The initial development Mac has macOS 13.0.1 and Command Line Tools with Swift 5.8.1, but **no Xcode.app or iOS SDK**. Xcode 14.2 is compatible with this macOS generation, but newer iPhones/iOS versions can require a newer Xcode and consequently a macOS upgrade. Do not install an incompatible latest Xcode or upgrade the OS blindly. First confirm the owner's iPhone/iOS version. Apple Account sign-in, developer agreements, and personal signing must be completed by the owner as needed.

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

The CLI check exhaustively validates all possible state and battery bytes, all valid advertisement state/battery combinations, and malformed credentials/names/advertisements. It also type-checks the shared SwiftUI/CoreBluetooth code against macOS, not iOS. XCTest adds named regression cases. GitHub Actions runs XCTest and a full unsigned iOS simulator build on app changes.

Local `swift test` initially fails because the incomplete Command Line Tools setup lacks the Xcode platform path. This is a toolchain limitation, not a passing test result. Use the dependency-free check script locally until Xcode is available.

## Install on the private iPhone

1. Open `Nultra.xcodeproj` in Xcode.
2. Add the owner's Apple Account in Xcode settings and select a signing team in the Nultra target. A personal team can be used where Apple permits local development signing; provisioning limitations/renewal depend on account type.
3. Connect and trust the iPhone. Enable Developer Mode if iOS requests it.
4. Select the physical iPhone and run the Nultra scheme. Resolve any signing or device-support message shown by Xcode.
5. Allow Bluetooth when tapping Find switches. Initial testing should release any active connection held by the Pi.
6. Enter the actual device password locally in the app. Never paste passwords into git issues or chat.
7. Complete HARDWARE_ACCEPTANCE.md before treating the build as ready for daily use.

An unsigned simulator build is not an installable iPhone app. There is no signed IPA or TestFlight release at this stage. A simulator can exercise demo screens but does not establish physical BLE compatibility.

## Reference boundaries
