# iPhone implementation architecture

## Components

- `NultraApp`: owns the store; backgrounding cancels active and queued work, foregrounding resumes listening when previously enabled.
- `SwitchProtocol`: Foundation-only wire codec and UUIDs.
- `SwitchTransaction`: Foundation-only operation state machine shared by the real transport and regression tests. Every terminal path requests disconnect. Late callbacks after cancellation cannot emit writes.
- `SwitchDevice`: observed state, broadcast/read timestamps, identity lookup status.
- `KnownSwitch`: Codable real name and firmware keyed by peripheral UUID; persisted in UserDefaults. State/battery are not restored as fresh observations.
- `BluetoothStore`: main-queue CoreBluetooth adapter, one active operation, user-prioritized queue, eight-second total deadline, automatic first identification. Uses the owner-supplied bundled master credential; no password-entry or Keychain flow.
- Views: compact two-column dashboard with direct power controls and separate name/details action. Details and rename editing never connect.

## Transaction lifecycle

Connect → discover password + target characteristic → authenticate → operation-specific write/read → immediately cancel connection → wait for disconnect acknowledgement → release next queued operation.

Identification reads only the name characteristic (which includes firmware). Power writes only state then reads state. Rename waits for write acknowledgement then reads name. There is no ready/idle-connected phase, periodic metadata read, connection held while editing, or background reconnect. An eight-second timer starts with the connection request and is not reset by progress. Completion cancels CoreBluetooth before persisting the result.

Callbacks check peripheral identity and state. The adapter validates characteristic properties, honors write-without-response flow control, and forwards accepted events to the shared state machine. Service invalidation, malformed reads, transport errors, readback mismatches, timeout, and backgrounding all release the link. Physical cancellation timing is controlled by CoreBluetooth; the app cannot promise an exact radio disconnect latency.

New devices are looked up once per explicit scan session, with no automatic retry loop after failure. Successfully learned names survive relaunch and subsequent scans. A failed lookup has an explicit Retry action. User commands take priority over queued discovery requests; an in-flight transaction finishes before the next begins. Pending controls are disabled per switch.

## Data freshness

Foreground scanning receives repeated local-name broadcasts. Missing or malformed names update presence only. Never treat cached `CBPeripheral.name` as a fresh state packet. Broadcasts do not overwrite an active transaction’s state or confirm a command. Cards show observation age and retain real names independently of broadcast names. Previously known devices show unknown power/battery until observed after relaunch.

The server exposes no authentication-status characteristic. A successful password write is not proof of authentication; command readback is still required. An unchanged requested state alone cannot prove the credential was accepted.

## Boundaries

No Pi HTTP dependency, analytics, background scheduler, notification subscription, password-change command, or automatic command retries. The master credential is deliberately bundled for this owner’s private app and must not be treated as a protected secret against someone possessing its binary. Hardware acceptance remains necessary.
