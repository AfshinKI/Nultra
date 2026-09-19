# Short BLE transactions

Owner requirement: minimize switch connection time. There is no persistent connected mode.

- Unknown switch: queue one identification transaction, authenticate with the owner-supplied master credential, read only the name/firmware characteristic, cancel the connection immediately, and persist the identity by iOS peripheral UUID.
- Known switch: display its saved real name. Observe power and battery from advertised local names without connecting. Reopening the dashboard or detail screen does not connect.
- Power: connect only after a user action, discover only password and power characteristics, authenticate, write the explicit target state, read it back, and immediately cancel the connection.
- Rename: edit locally while disconnected. Save starts a password/name transaction; write, verify name readback, disconnect, persist the verified name.
- At most three independent transactions are active. User commands take precedence over queued discovery lookups. Never retry failed identification on every advertisement. Explicit retry is available.
- An eight-second deadline covers the entire connection attempt, rather than restarting on each phase. Errors cancel the connection. Backgrounding cancels ordinary UI work; an active Shortcut can finish within its bounded execution window. Enabled server fallback may send the same explicit power request after failed BLE disconnection. Retain each active peripheral and its connection slot until CoreBluetooth acknowledges cancellation, so late callbacks cannot start another operation.

The UI uses compact two-column cards, with a direct power action and a separate name/details action. Remove the large dashboard introduction to prioritize switches. Large accessibility text may use one column. More switches than physically fit remain scrollable.

Validation must exercise the shared transaction state machine: every successful operation emits disconnect, all failures/cancellation/timeouts emit disconnect, late callbacks cannot emit writes, and a queued operation starts only when a slot is available; cancelled slots remain occupied until disconnection is acknowledged. Simulator tests cover a two-column grid, disconnected power actions, and editing rename before any connection. Physical connection durations still need measurement on the actual switches.

## Always-listening dashboard

The foreground app starts scanning automatically on launch, on returning from background, and after Bluetooth is restored. It never requires a Find button. Backgrounding stops scans and cancels ordinary UI transactions. Version 0.7 permits bounded background Shortcut transactions without enabling background discovery.

Successfully read real names persist across launches. Unnamed candidates remain internal and are not rendered as cards. Offline named switches stay visible. A blue LED means an advertisement was received in the previous 15 seconds; gray means no recent advertisement or scanning unavailable. Presence expires on a two-second UI clock (at most two seconds after the 15-second threshold) and does not open connections.

All On and All Off snapshot all saved named switches and queue explicit writes, with up to three connections at a time. Each target independently verifies and disconnects. The status reports successful and unsuccessful targets; offline switches are attempted, not silently omitted. Backgrounding cancels unfinished work without replaying it later.


## Compact display and Shortcuts (0.5)

Incoming broadcasts update an internal device snapshot without publishing every packet to SwiftUI. The foreground timer publishes telemetry at most once every two seconds; user commands/readback publish immediately. RSSI used for bars samples at most once per five seconds. Power/battery/presence packets are still processed throughout, and GATT readback retains precedence during a transaction.

The fancy thresholds are three bars at RSSI >= -60, two at >= -80, and one below -80. Unknown/offline signal shows zero filled bars. Cards show an icon-only battery, red with a small fill below 10% and green otherwise, and a yellow glowing bulb when on. Only switch details show the battery percentage. Busy controls render a spinner without stage text.

App Intents share the live BluetoothStore used by the foreground UI. All On, All Off, and a selected-switch action validate saved identities, reserve the operation, wait briefly for the radio, then use the same three-slot scheduler. Completion requires readback and disconnection; partial results throw an actionable Shortcuts error. Since 0.7, cancellation stops pending work, while scene backgrounding allows an active Shortcut to finish. The bluetooth-central background mode is enabled; no extension or permanent connection is added. See SERVER_FALLBACK.md for optional server queue semantics.
