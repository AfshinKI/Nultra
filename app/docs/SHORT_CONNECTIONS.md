# Short BLE transactions

Owner requirement: minimize switch connection time. There is no persistent connected mode.

- Unknown switch: queue one identification transaction, authenticate with the owner-supplied master credential, read only the name/firmware characteristic, cancel the connection immediately, and persist the identity by iOS peripheral UUID.
- Known switch: display its saved real name. Observe power and battery from advertised local names without connecting. Reopening the dashboard or detail screen does not connect.
- Power: connect only after a user action, discover only password and power characteristics, authenticate, write the explicit target state, read it back, and immediately cancel the connection.
- Rename: edit locally while disconnected. Save starts a password/name transaction; write, verify name readback, disconnect, persist the verified name.
- Only one transaction is active. User commands take precedence over queued discovery lookups. Never retry failed identification on every advertisement. Explicit retry is available.
- An eight-second deadline covers the entire connection attempt, rather than restarting on each phase. Errors and backgrounding cancel the connection and do not retry commands. Retain the active peripheral until CoreBluetooth acknowledges cancellation, so late callbacks cannot start another operation.

The UI uses compact two-column cards, with a direct power action and a separate name/details action. Remove the large dashboard introduction to prioritize switches. Large accessibility text may use one column. More switches than physically fit remain scrollable.

Validation must exercise the shared transaction state machine: every successful operation emits disconnect, all failures/cancellation/timeouts emit disconnect, late callbacks cannot emit writes, and a queued operation starts only after disconnection. Simulator tests cover a two-column grid, disconnected power actions, and editing rename before any connection. Physical connection durations still need measurement on the actual switches.
