# iPhone background commands and optional server fallback

Implemented for iPhone. Android continues using direct Bluetooth in this version.

## Configure and use


The app remembers server configuration and switch mappings. Exact unique names match automatically; duplicate or missing names require an explicit selection. First command pins the server MAC address. An explicit/pinned address never silently rematches by name. Changing the server URL clears mappings. This prevents confusion between iOS peripheral UUIDs and Linux BLE MAC addresses. No server-only switches are added to the phone catalog, and All On/Off targets only saved phone switches, not every device on the server.

Bluetooth remains preferred. While the app is visible, a switch absent from recent phone advertisements can use the server directly. A background Shortcut first tries its saved Bluetooth peripheral, since absence of background advertisements does not prove the switch is out of range. Failed BLE power operations can fall back only after the BLE session disconnects. Missing peripherals and disabled Bluetooth can use the enabled server. Rename and identification remain direct BLE operations.

While Nultra is open, the enabled server's cached device list is fetched every 15 seconds; a response older than 30 seconds cannot make a switch appear reachable. Background Shortcuts make bounded on-demand requests. There is no permanent background polling, BLE scan, VPN, or idle switch connection.

## Server API contract


- `GET /devices`: JSON array with `address`, `display_name`, `seen_recently`, `switch_state`, `battery` (other fields ignored).
- `seen_recently == 1` means the Pi saw the switch within **six minutes**, not proof it can connect now. Older values are rejected for fallback.
- `POST /toggle/<MAC>/0` or `/1`: explicit off/on. `status == OK` means **queued**, not completed. HTTP errors, JSON errors, redirects, and `status == ERROR` are failures.
- The server catches execution failures asynchronously and exposes no per-command receipt. Therefore the app never claims a queued request is hardware-confirmed and never optimistically sets its power state. Later GET responses provide server-reported state, which can itself be cached. Retries are not sent automatically after uncertain HTTP results.
- Requests have 5-second request / 8-second resource timeouts. At most three operations occupy scheduler slots, across both BLE and HTTP.
- The phone password is used only for phone BLE; it is never sent to the server. The Pi uses its own configured credentials.

The server may spend longer connecting/retrying than the phone. This app cannot shorten the existing server's BLE implementation without changing that read-only project.

## Shortcuts

All three App Intents set `openAppWhenRun = false`. They initialize Bluetooth without starting foreground scanning, retrieve saved peripherals, and keep the existing authenticate/write/read/disconnect transaction. `bluetooth-central` permits command callbacks in the background. Scene background transitions stop discovery but do not cancel an active Shortcut. A bounded background task, 24-second command deadline, cancellation handling, and immediate disconnect prevent an indefinite session.

Saved password accessibility is AfterFirstUnlockThisDeviceOnly (including migration of existing entries when readable), enabling background access after the first device unlock following a restart. It is not synced to another device. iOS still decides execution time and may require unlock/permission; this is not a promise of unlimited or guaranteed locked-phone execution. Demo commands are rejected.

## Physical acceptance (requires iPhone)

1. Run all three actions from Shortcuts with Show When Run off, including cold app launch, and confirm no Nultra window appears.
2. Repeat after backgrounding, locking, and restarting/unlocking the phone. Verify BLE readback and immediate disconnect. Cancel midway; ensure no later server fallback is launched by cancelled work.
3. Configure server, grant LAN permission, use unique names; disable Bluetooth and send explicit on/off. Confirm server reports queued and physical lights actually change.
4. Check mixed local/remote All On/Off, server offline, stale server switch, denied LAN permission, ambiguous names, changed URL, and explicit mapping after rename.
5. Ensure normal discovery/polling stop when backgrounded, no idle BLE connections remain, and re-enabling foreground scanning updates broadcasts.

## VPN design question — not implemented

Apple's system per-app VPN on iOS requires MDM-managed apps/device configuration ([NETunnelProviderManager](https://developer.apple.com/documentation/networkextension/netunnelprovidermanager)). A consumer VPN extension requires OS consent and appropriate signing/entitlements; it is not an invisible app-private connection.

A future app-only authenticated encrypted transport (for example, HTTPS to a separately configured home gateway, or a userspace tunnel carrying only Nultra API traffic) could operate during app/Shortcut execution without routing unrelated phone traffic. It would require gateway setup, credentials, reachability through the home router/NAT, and appropriate protection for the existing unauthenticated server API. iOS background execution limits would still apply. None is installed/configured in this change.
