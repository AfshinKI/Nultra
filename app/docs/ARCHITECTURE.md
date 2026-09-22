# iPhone implementation architecture

## Components

- `NultraApp`: owns the store; backgrounding stops discovery and cancels ordinary UI work, but allows a bounded Shortcut command to finish; foregrounding starts listening.
- `SwitchProtocol`: Foundation-only wire codec and UUIDs.
- `SwitchTransaction`: Foundation-only operation state machine shared by the real transport and regression tests. Every terminal path requests disconnect. Late callbacks after cancellation cannot emit writes.
- `SwitchSchedule`: three connection slots held through cancellation acknowledgement, unique work per peripheral, bulk result accounting, and persistent named-switch catalog.
- `MasterPasswordStore`: validated eight-byte password in this-device-only Keychain storage, with default fallback only when no item exists.
- `SwitchDevice`: observed state, broadcast/read timestamps, identity lookup status.
- `KnownSwitch`: Codable real name and firmware keyed by peripheral UUID; persisted in UserDefaults. State/battery are not restored as fresh observations.
- `BluetoothStore`: main-queue CoreBluetooth adapter, up to six independent sessions, user-prioritized queue, eight-second total deadline, automatic first identification. Uses a per-transaction snapshot of the master credential from Keychain, with the supplied bundled default when no override exists.
- Views: compact two-column dashboard with direct power controls and separate name/details action. Details and rename editing never connect.

## Transaction lifecycle

Connect → discover password + target characteristic → authenticate → operation-specific write/read → immediately cancel connection → wait for disconnect acknowledgement → release that slot to the next queued operation.

Identification reads only the name characteristic (which includes firmware). Power writes only state then reads state. Rename waits for write acknowledgement then reads name. There is no ready/idle-connected phase, periodic metadata read, connection held while editing, or background reconnect. An eight-second timer starts with the connection request and is not reset by progress. Completion cancels CoreBluetooth before persisting the result.

Callbacks check peripheral identity and state. The adapter validates characteristic properties, honors write-without-response flow control, and forwards accepted events to the shared state machine. Service invalidation, malformed reads, transport errors, readback mismatches, timeout, and backgrounding all release the link. Physical cancellation timing is controlled by CoreBluetooth; the app cannot promise an exact radio disconnect latency.

New devices are looked up once per explicit scan session, with no automatic retry loop after failure. Successfully learned names survive relaunch and subsequent scans. A failed lookup has an explicit Retry action. User commands take priority over queued discovery requests; each peripheral has only one in-flight operation, while different peripherals can operate concurrently. Pending controls are disabled per switch.

## Data freshness

Foreground scanning receives repeated local-name broadcasts. Missing or malformed names update presence only. Never treat cached `CBPeripheral.name` as a fresh state packet. Broadcasts do not overwrite an active transaction’s state or confirm a command. Cards retain real names independently of broadcast names. Previously known devices show unknown power/battery until observed after relaunch.

The server exposes no authentication-status characteristic. A successful password write is not proof of authentication; command readback is still required. An unchanged requested state alone cannot prove the credential was accepted.

## Boundaries


Only verified names appear in `visibleDevices`; saved names are never removed because of missing advertisements. Presence uses fresh scan timestamps with a 15-second expiry. With server fallback disabled, an unavailable scanner forces gray LEDs. An enabled, recently checked server can also establish availability. The foreground timer expires presence without opening BLE links.

All broadcasts are processed internally. Passive view snapshots publish at most every two seconds; each device samples displayed RSSI at most every five seconds. User operations publish immediately. Three signal bars use the fancy thresholds: strong at -60 dBm or higher, medium at -80 dBm or higher, weak below that.

## Shortcuts and updates

App Intents share the main-actor BluetoothStore with the foreground app. Turn All Off, Turn All On, and Set Switch Power use the same scheduler and verified transaction completion. They reject demo mode, prevent concurrent shortcut batches, and surface partial failures. Actions do not open Nultra. A bluetooth-central background mode permits short commands; scanning remains foreground-only. Server-queued results are distinguished from BLE-confirmed completion.
