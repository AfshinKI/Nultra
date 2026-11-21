"""Per-user gateway configuration. Run this module to provision a switch."""
import getpass
import json
import os
from pathlib import Path
import re
import secrets
import stat
import tempfile

ADDRESS = re.compile(r"(?:[0-9A-Fa-f]{2}:){5}[0-9A-Fa-f]{2}")


def directory():
    return Path(os.environ.get("XDG_CONFIG_HOME", Path.home() / ".config")) / "nultra"


def read_config(path):
    if path.stat().st_mode & (stat.S_IRWXG | stat.S_IRWXO):
        raise SystemExit(f"Set permissions to 0600 on {path}")
    return json.loads(path.read_text())


def load_settings():
    folder = directory()
    path = folder / "gateway.json"
    if not path.is_file():
        raise SystemExit("Run python settings.py to provision the gateway first")
    config = read_config(path)
    token, devices = config.get("token", ""), config.get("devices", {})
    if not isinstance(token, str) or not re.fullmatch(r"[A-Za-z0-9_-]{32,128}", token):
        raise SystemExit("Missing or invalid gateway token")
    if not isinstance(devices, dict) or any(not ADDRESS.fullmatch(address) or
            not isinstance(password, str) or not re.fullmatch(r"[ -~]{8}", password)
            for address, password in devices.items()):
        raise SystemExit("Invalid device configuration")
    return token, {address.upper(): value for address, value in devices.items()}, folder


if __name__ == "__main__":
    folder = directory()
    folder.mkdir(parents=True, mode=0o700, exist_ok=True)
    path = folder / "gateway.json"
    config = read_config(path) if path.exists() else {"token": secrets.token_urlsafe(32), "devices": {}}
    address = input("Switch Bluetooth address: ").strip().upper()
    if not ADDRESS.fullmatch(address):
        raise SystemExit("Expected six hexadecimal octets separated by colons")
    password = getpass.getpass("Eight-character switch command password: ")
    if not re.fullmatch(r"[ -~]{8}", password):
        raise SystemExit("Expected eight printable ASCII characters")
    config["devices"][address] = password
    with tempfile.NamedTemporaryFile("w", dir=folder, delete=False) as temp:
        json.dump(config, temp, indent=2)
        temp.write("\n")
    os.replace(temp.name, path)
    print(f"Saved configuration to {path}. Use its token to sign in as nultra.")
