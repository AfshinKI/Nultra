# Physical iPhone acceptance checklist

Status: **not yet run**. Record iPhone model, iOS version, app commit, switch firmware, and test date. Do not record passwords.

| Scenario | Expected result | Result |
| --- | --- | --- |
| Fresh launch | Saved named list appears immediately; foreground listening starts automatically | Pending |
| Bluetooth denied | Clear Settings guidance; no crash or write | Pending |
| Bluetooth off | Clear status; scanning possible after radio restored | Pending |
| Discovery | Nearby Nultra appears even if advertisement omits service UUID | Pending |
| Foreground listening | Starts on launch/foreground/radio restoration; stops only in background or demo | Pending |
| Repeated broadcasts | Change switch from Pi; disconnected card updates power and battery without connecting | Pending |
| State freshness | Stop broadcasting; last-broadcast age increases, learned name remains | Pending |
| Active command | Broadcast does not override connected readback or confirm a write | Pending |
| Correct credential | One-time name/firmware lookup succeeds and disconnects immediately | Pending |
| Wrong credential | Report firmware error or unconfirmed command; never assert verified authentication | Pending |
| Explicit On | Send byte 1; confirm read-back and physical output | Pending |
| Explicit Off | Send byte 0; confirm read-back and physical output | Pending |
| Rapid taps | Only one command per switch outstanding; that switch stays disabled until disconnected | Pending |
| Read-back mismatch | Show failure; disconnect; do not publish success | Pending |
| Eight-byte rename | Edit disconnected; Save connects, writes, verifies, immediately disconnects | Pending |
| Bad rename | Reject short, long, emoji, accented or empty names before writing | Pending |
| Radio drop / walk away | Error or deadline, then explicit reconnection available | Pending |
| Pi owns connection | Useful timeout guidance; succeeds after Pi disconnect | Pending |
| Switch two devices | Up to three switches operate concurrently; each disconnects immediately, without cross-target state | Pending |
| Background / foreground | Link released in background; no autonomous writes on return | Pending |
| Identity persistence | Relaunch; real names remain; rediscovery does not connect known switches | Pending |
| Connection duration | Measure radio connection time for lookup/power/rename; no idle hold after readback | Pending |
| Failed discovery | No per-advertisement reconnect loop; explicit retry available | Pending |
| Browse / edit | Opening detail or typing rename never connects | Pending |
| Deadline | Entire attempt times out after 8 seconds, requests cancellation, no retries | Pending |
| Presence | Blue on fresh packet, gray after 15–17 seconds without packets; named card remains | Pending |
| Hidden candidates | No card until valid real name read succeeds | Pending |
| Master password | Save custom value, relaunch, verify use; restore default; no firmware password change | Pending |
| Bulk controls | All named targets attempted; up to six concurrent links; partial failures reported | Pending |
| Bulk background | Cancel current/pending work; no automatic command replay on return | Pending |
| Shortcuts cold launch | All Off opens app, awaits radio, verifies/disconnects all targets; reports actual failures | Pending |
| Shortcut selected device | Name selection resolves saved UUID, only that device changes | Pending |
| Shortcuts interrupted | Background/lock/cancel stops unfinished work without replay or fake success | Pending |
| Signal / battery | Fancy bar boundaries; five-second RSSI sampling; low battery icon red below 10% | Pending |
| Grid | Six switches fit in two columns at normal text size on 13 mini | Pending |
| Demo isolation | Label always visible; no real BLE control writes | Pending |
| Accessibility | VoiceOver announces controls; large text/landscape remain usable | Pending |

If immediate state read-back races the firmware, capture timing on hardware and add a bounded verification-read retry. Never retry the write automatically. If notifications are desired, first determine the subscribe characteristic's exact payload and behavior from firmware.
