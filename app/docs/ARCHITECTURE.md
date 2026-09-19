# iPhone implementation architecture

## Components

- `Nultra/App/NultraApp.swift`: Owns the observable Bluetooth store and disconnects real BLE sessions when backgrounded.
- `Nultra/Models/SwitchProtocol.swift`: Foundation-only byte codec; UUIDs, ASCII validation, advertisement parsing, name/firmware decoding, battery and power validation.
- `Nultra/Models/SwitchDevice.swift`: An identifiable snapshot keyed by the CoreBluetooth peripheral UUID. A confirmed read timestamp is distinct from advertised values.
- `Nultra/Bluetooth/BluetoothStore.swift`: Main-queue CoreBluetooth delegate and published UI state. Initializes the Bluetooth manager only when the user requests a scan. Demo mode requires no radio access.
- `Nultra/Security/CredentialStore.swift`: Generic-password Keychain items scoped by device UUID. Accessible only while unlocked, restricted to this device. Passwords never enter UserDefaults, logs, or git.
- `Nultra/Views`: Dashboard, per-device session/password/control sheet, settings, and shared visual styles.
- `Nultra/Assets.xcassets`: Generated brand artwork and packaged iPhone icons.

## Session transitions

Idle → connecting → discovering → sending password → initial reads → ready.

Ready → changing power → read-back → ready, or error/disconnect on mismatch.

Ready → renaming → acknowledged write → name read-back → ready, or error/disconnect.

Ready → refreshing → all three reads → ready.

Any active operation → timeout/error → disconnecting → idle. Backgrounding requests disconnect; radio loss clears the session. A peripheral service-change callback invalidates the connection. Writes are never retried automatically.

There is one active peripheral at a time. Until cancellation completes, a second connection is prevented. Callbacks validate the current peripheral and applicable phase. Characteristic capabilities are checked before the password write. Switch commands respect `canSendWriteWithoutResponse`, and the delegate resumes a queued write when the transport is ready.

The server has no authentication-status characteristic. The UI says “Connected,” not “Authentication verified.” If a wrong password is silently accepted by firmware at the GATT layer, command verification remains necessary. An unchanged requested state cannot independently prove successful authentication.

## Data freshness

Scanning runs for eight seconds or until stopped. Starting a new scan drops inactive discovery results so old devices are not presented as nearby. Power and battery from advertisements are unconfirmed hints. Connected controls show the last read value while waiting; controls remain disabled during operations. Disconnected cards are labeled “Tap to connect,” and the detail view includes the last read time. Refresh explicitly reads name, battery, and state. Notifications are not implemented because the reference client does not define their payload.

## Deliberate MVP boundaries

No Pi HTTP API, cloud account, analytics, background scheduler, notification subscription, password-change command, mass switching, or automatic reconnect. Hardware-dependent additions require documented protocol evidence first. No claim of firmware compatibility is made until hardware acceptance is completed.
