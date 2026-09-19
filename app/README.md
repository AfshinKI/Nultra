# Nultra

A private native iPhone controller for Nultra BLE switches. Built with SwiftUI and CoreBluetooth. The phone talks directly to each switch; the Raspberry Pi server is not needed.


## Start here

1. Read [the project plan](docs/PROJECT.md) and [the BLE protocol](docs/BLE_PROTOCOL.md).
2. Open `Nultra.xcodeproj` in Xcode and choose your signing team under **Signing & Capabilities**.
3. Run the `Nultra` scheme on your iPhone (iOS 16 or later).
4. Tap **Find switches**, select a switch, and enter its eight-character password.
5. Use **On** / **Off**. The app reads the switch back before confirming a change.

You can explore the interface through **Explore the demo** without Bluetooth permission or hardware. Demo switches are clearly labeled. Connect to one switch at a time; disconnect it before selecting another.

## Included

- Foreground discovery, connection, credential write, state/battery/firmware reads.
- Explicit on/off with read-back verification; eight-byte ASCII device rename.
- Per-device passwords in Keychain, operation deadlines, and connection errors.
- Dark SwiftUI interface, accessibility labels, Dynamic Type, and a custom icon.
- Protocol tests, reproducible Xcode project, and an unsigned simulator build workflow.

## Development

There are no third-party app dependencies. `swift test` runs XCTest coverage with a complete Xcode installation. `bash scripts/check.sh` runs 733 protocol checks and macOS SDK type checking using Apple Silicon Command Line Tools. The latter does **not** compile or run an iOS app.

See [development and private installation](docs/DEVELOPMENT.md), [architecture](docs/ARCHITECTURE.md), and [hardware acceptance](docs/HARDWARE_ACCEPTANCE.md). This is an initial implementation; physical BLE behavior must be validated before daily use.
