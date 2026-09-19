# Short BLE transactions

Owner requirement: minimize switch connection time. There is no persistent connected mode.

- Unknown switch: queue one identification transaction, authenticate with the owner-supplied master credential, read only the name/firmware characteristic, cancel the connection immediately, and persist the identity by iOS peripheral UUID.
- Known switch: display its saved real name. Observe power and battery from advertised local names without connecting. Reopening the dashboard or detail screen does not connect.
- Power: connect only after a user action, discover only password and power characteristics, authenticate, write the explicit target state, read it back, and immediately cancel the connection.
- Rename: edit locally while disconnected. Save starts a password/name transaction; write, verify name readback, disconnect, persist the verified name.
- At most three independent transactions are active. User commands take precedence over queued discovery lookups. Never retry failed identification on every advertisement. Explicit retry is available.
- An eight-second deadline covers the entire connection attempt, rather than restarting on each phase. Errors and backgrounding cancel the connection and do not retry commands. Retain each active peripheral and its connection slot until CoreBluetooth acknowledges cancellation, so late callbacks cannot start another operation.

The UI uses compact two-column cards, with a direct power action and a separate name/details action. Remove the large dashboard introduction to prioritize switches. Large accessibility text may use one column. More switches than physically fit remain scrollable.

Validation must exercise the shared transaction state machine: every successful operation emits disconnect, all failures/cancellation/timeouts emit disconnect, late callbacks cannot emit writes, and a queued operation starts only when a slot is available; cancelled slots remain occupied until disconnection is acknowledged. Simulator tests cover a two-column grid, disconnected power actions, and editing rename before any connection. Physical connection durations still need measurement on the actual switches.

## Always-listening dashboard (0.4)

The foreground app starts scanning automatically on launch, on returning from background, and after Bluetooth is restored. It never requires a Find button. Backgrounding still stops scans and cancels transactions. This is foreground monitoring, not iOS background execution.

Successfully read real names persist across launches. Unnamed candidates remain internal and are not rendered as cards. Offline named switches stay visible. A green LED means an advertisement was received in the previous 15 seconds; red means no recent advertisement or scanning unavailable. Presence expires on a one-second UI clock and does not open connections.

All On and All Off snapshot all saved named switches and queue explicit writes, with up to three connections at a time. Each target independently verifies and disconnects. The status reports successful and unsuccessful targets; offline switches are attempted, not silently omitted. Backgrounding cancels unfinished work without replaying it later.
