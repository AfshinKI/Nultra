# Direct BLE protocol for the iPhone implementation


## Discovery and identity

`BLEManager._scan_devices` performs a 3-second unrestricted scan and filters names containing `Nultra`. Known devices can advertise `NultraXYYY`: X is one decimal switch-state digit and YYY is decimal battery percent. The iPhone should scan without a service filter so devices that omit service UUIDs from advertisements remain visible; accept Nultra names or the service UUID, then validate the GATT service on connection. Each fresh local-name packet updates the disconnected card immediately, including small battery changes. These are observed broadcast values, not confirmation of a control operation. Never use the cached `CBPeripheral.name` as a fresh state packet. Preserve the learned display name separately. During an active connection, GATT reads take precedence over broadcasts. Scanning continues in the foreground until stopped or backgrounded; retained cards show the age of the last broadcast.

iOS exposes a CoreBluetooth peripheral UUID, not the Linux Bluetooth MAC address. Use that UUID as local identity. Do not import Pi addresses as iPhone identities. Names are not unique IDs.

## GATT layout

| Role | UUID | Payload / usage |
| --- | --- | --- |
| Service | `0000fe40-cc7a-482a-984a-7f2ed5b3e58f` | Validate on connection |
| Switch | `0000fe41-8e22-4541-9d4c-21edae82ed19` | Read first byte; write one byte 0 or 1 without response |
| Subscribe | `0000fe42-8e22-4541-9d4c-21edae82ed19` | Declared but unused by the source; semantics unknown |
| Battery | `0000fe43-8e22-4541-9d4c-21edae82ed19` | Read first byte as percentage |
| Name | `0000fe44-8e22-4541-9d4c-21edae82ed19` | Read name and optional firmware; write exactly 8 ASCII bytes with response |
| Password | `0000fe45-8e22-4541-9d4c-21edae82ed19` | Write exactly 8 ASCII bytes with response after each connection |

## Connect and authenticate

`NultraBLEDevice.connect` connects and writes the password characteristic using `response=True`. At the owner’s explicit request, this private iPhone app uses a master credential automatically for every transaction. The supplied value is the default; the owner can save an override in Menu, stored in Keychain. Credentials are not logged. No persistent connected session exists.

No challenge, token, auth-status read, or positive authentication response is implemented in the server. A successful GATT password write is the strongest transport evidence available; successful command read-back must still be checked. Pairing/bonding, link encryption, lockout behavior, and firmware rejection behavior cannot be established from this client alone.

## Read and control

`_retrieve_device` reads name, battery, and switch. Name length exactly 11 means first 8 bytes are a UTF-8 name and final three unsigned bytes form `vA.B.C`; otherwise decode the entire name. iPhone should trim NUL padding for display, reject empty state/battery packets, reject state bytes other than 0/1, and reject battery percentages outside 0...100.

`toggle_switch` writes `[0]` or `[1]` to the switch characteristic with `response=False`, then reads the characteristic to confirm. The app uses explicit target states and waits for read-back. A mismatched read-back is a failed confirmation, not a successful toggle. Respect CoreBluetooth's write-without-response backpressure.

`rename_device` validates eight characters and ASCII-encodes, writes with response, and reads back the name. The app must validate **eight ASCII bytes**, which avoids accepting eight multibyte Unicode characters.

## iPhone transaction design

See [short connection requirements](SHORT_CONNECTIONS.md). Each connection has exactly one purpose:

- New identity: password write → name/firmware read → immediate disconnect. Save the real name by peripheral UUID for future launches.
- Power: password write → explicit power write → power readback → immediate disconnect.
- Rename: edit while disconnected, then password write → name write with response → name readback → immediate disconnect.

Discover only password plus the operation’s target characteristic. Power and battery normally come from advertisements; identification does not read them. One eight-second deadline covers the entire attempt. Every failure and background transition cancels the connection. Up to three distinct switches can be processed concurrently. Each connection slot stays occupied until CoreBluetooth confirms disconnection. No command retries or idle connected state exist. Listening starts automatically on launch and every return to the foreground.

## Unknowns requiring hardware checks

- Verify all deployed switches accept the owner-supplied master credential.
- Whether devices permit multiple BLE centrals. Disconnect the Pi during initial tests if it holds the link.
- Whether switch state reads immediately reflect writes or require a firmware delay.
- Notification format on the unused subscribe characteristic. Do not subscribe until this is known.
- Actual characteristic properties, authentication failure responses, maximum concurrent connections, and firmware compatibility.
- Whether advertised state and battery are reliable during another controller's activity.

The app must not reproduce the server scheduler as an iPhone background timer: iOS suspension makes that unreliable without a separate always-on controller.
