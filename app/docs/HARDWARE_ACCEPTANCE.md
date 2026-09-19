# Physical iPhone acceptance checklist

Status: **not yet run**. Record iPhone model, iOS version, app commit, switch firmware, and test date. Do not record passwords.

| Scenario | Expected result | Result |
| --- | --- | --- |
| Fresh launch | No Bluetooth prompt until Find switches; demo is available | Pending |
| Bluetooth denied | Clear Settings guidance; no crash or write | Pending |
| Bluetooth off | Clear status; scanning possible after radio restored | Pending |
| Discovery | Nearby Nultra appears even if advertisement omits service UUID | Pending |
| Foreground listening | Continues until Stop listening or background; can restart | Pending |
| Repeated broadcasts | Change switch from Pi; disconnected card updates power and battery without connecting | Pending |
| State freshness | Stop broadcasting; last-broadcast age increases, learned name remains | Pending |
| Active command | Broadcast does not override connected readback or confirm a write | Pending |
| Correct credential | Name, version, battery and power read successfully | Pending |
| Wrong credential | Report firmware error or unconfirmed command; never assert verified authentication | Pending |
| Explicit On | Send byte 1; confirm read-back and physical output | Pending |
| Explicit Off | Send byte 0; confirm read-back and physical output | Pending |
| Rapid taps | Only one command outstanding; controls disabled until confirmation | Pending |
| Read-back mismatch | Show failure; disconnect; retain actual read value | Pending |
| Eight-byte rename | Write with response; confirm name and firmware | Pending |
| Bad rename | Reject short, long, emoji, accented or empty names before writing | Pending |
| Radio drop / walk away | Error or deadline, then explicit reconnection available | Pending |
| Pi owns connection | Useful timeout guidance; succeeds after Pi disconnect | Pending |
| Switch two devices | Disconnect first; correct per-device password and state | Pending |
| Background / foreground | Link released in background; no autonomous writes on return | Pending |
| Keychain persistence | Relaunch and rediscover same peripheral; saved credential works | Pending |
| Forget password | Saved credential deleted; asks for password on next connection | Pending |
| Demo isolation | Label always visible; no real BLE control writes | Pending |
| Accessibility | VoiceOver announces controls; large text/landscape remain usable | Pending |

If immediate state read-back races the firmware, capture timing on hardware and add a bounded verification-read retry. Never retry the write automatically. If notifications are desired, first determine the subscribe characteristic's exact payload and behavior from firmware.
