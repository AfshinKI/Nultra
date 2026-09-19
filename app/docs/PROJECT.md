# Nultra for iPhone

A private native iPhone app that discovers and controls Nultra switches directly through the phone's Bluetooth radio. The Raspberry Pi is a protocol reference, not an app dependency. No web server, account, cloud, or internet connection is required for switch control.

## Product scope

SwiftUI interface with a dark navy canvas, luminous mint accents, clear connection states, device cards, battery indicators, explicit on/off actions, device rename, and a custom app icon. Real hardware and preview/demo mode must remain clearly separated. Connections are short transactions; real names persist locally. The owner explicitly requested automatic use of a master credential, with its supplied default and an optional Keychain-backed override in Menu.

## Phases

2. **Native foundation:** Create a dependency-free SwiftUI/CoreBluetooth project, device models, protocol codecs, persistent switch identities, and a browsable demo.
3. **Direct BLE control:** Foreground scan, connect, discover characteristics, authenticate, read state, write and verify on/off, rename, disconnect, and recover from errors.
4. **Verification:** Run portable protocol tests locally; build with Xcode when available; verify permission denial, Bluetooth off, wrong password, dropped connections, and actual switch behavior on iPhone.
5. **Private delivery:** Configure personal signing, install on the owner's iPhone, complete hardware acceptance, and record validated firmware versions.

## Development process

- Document protocol facts before implementing them, with source file and commit references.
- Keep BLE logic separate from SwiftUI and byte parsing separate from CoreBluetooth.
- Treat a BLE connection, accepted password write, and verified physical state as distinct events. Do not imply authentication is cryptographically proven by a successful write.
- Disconnect immediately after every identity lookup and verified control/rename operation. Read back after every control/rename operation. Do not show unconfirmed optimistic state as success.
- Use short timeouts, actionable errors, and an explicit retry. No automatic toggles or writes on reconnect.
- Commit coherent milestones to the app repository. Do not commit signing keys, local account settings, or reference-server data. The supplied switch master credential is an explicit owner-authorized exception for this private app.
- Hardware sign-off is mandatory before calling the app ready for daily use. Simulator success does not validate Bluetooth.

See BLE_PROTOCOL.md for the source-derived contract and DEVELOPMENT.md for setup and validation.

## Confirmed delivery route


## Android expansion — v0.6.0


## iPhone background Shortcuts and backup server — v0.7.0

Shortcuts no longer request foreground presentation. Saved-switch power commands can use an optional user-configured fancy server when phone BLE is unavailable. No address or port is preset. Android remains direct BLE in this release. See [configuration, protocol limitations, and physical acceptance](SERVER_FALLBACK.md). VPN remains a design discussion only.
