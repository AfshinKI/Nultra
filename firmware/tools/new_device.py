"""Create the credentials for a single switch before building its firmware."""
import os
import secrets
import string
from pathlib import Path

header = Path(__file__).resolve().parents[1] / "BLE_Peripheral_Lite/Core/Inc/device_credentials.h"
password = "".join(secrets.choice(string.ascii_letters + string.digits) for _ in range(8))
pin = secrets.randbelow(900000) + 100000
try:
    fd = os.open(header, os.O_CREAT | os.O_EXCL | os.O_WRONLY, 0o600)
except FileExistsError:
    raise SystemExit("A device credential file already exists. Archive it privately before provisioning another device.")
with os.fdopen(fd, "w", encoding="ascii") as out:
    out.write(f'#pragma once\n#define NULTRA_PAIRING_PIN {pin}U\n#define NULTRA_COMMAND_PASSWORD "{password}"\n')
print(f"Created {header.name}. Read it privately to record this switch’s PIN and command password.")
