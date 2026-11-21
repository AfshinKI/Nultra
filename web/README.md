# Local Bluetooth gateway

The gateway runs on a Linux computer with BlueZ and a Bluetooth LE adapter in range of the switches. Its dashboard offers power, rename, weekly schedules and timers. It can also act as the mobile apps’ backup controller. Schedules follow the gateway host’s local time.

## Install and provision

Use Python 3.11 or later. From this directory, create a virtual environment and install the dependencies.

```sh
python3 -m venv .venv
. .venv/bin/activate
python -m pip install -r requirements.txt
python settings.py
```

The setup prompt asks for the switch’s Bluetooth address and eight-character command password. You can find the address using Bluetooth settings or `bluetoothctl scan on`. Enter the command password generated for that switch by the firmware provisioning tool. Run setup once per switch.

The setup command creates a user-private `~/.config/nultra/gateway.json` containing a newly generated gateway login token and the switch credentials. It honors `XDG_CONFIG_HOME`. Read the token locally with `python -c 'from settings import load_settings; print(load_settings()[0])'` and keep it in your password manager. Schedules are stored alongside the configuration.

## Pair and run

For each switch, hold its button for two seconds, then release it. Within the pairing window, use the gateway host’s Bluetooth settings or an interactive `bluetoothctl` session with a keyboard-capable agent to pair with its address. Use the six-digit pairing PIN generated for that switch. A display-less gateway needs a BlueZ agent that can accept the PIN.

```sh
python main.py
```

Open [the local dashboard](http://127.0.0.1:5050) and sign in as `nultra` with the gateway token. Run the gateway as an ordinary OS user with permission to use Bluetooth. Restart it after provisioning another switch. Commands may take several seconds to reach a switch. The dashboard refreshes its readings every five seconds.

## Access from another device

The gateway listens on loopback. To use a browser on another computer, forward the port over SSH and open the local dashboard there.

```sh
ssh -N -L 5050:127.0.0.1:5050 your-user@your-gateway
```

For mobile fallback, configure a trusted HTTPS reverse proxy to the loopback listener, or use a loopback tunnel on the phone. A reverse proxy must pass the original Host and Authorization headers and terminate TLS with a certificate the device trusts. Enter the URL and gateway token in the app. Access to the token grants control over all switches provisioned on that gateway.

## API and tests

`GET /devices` lists readings. `POST /toggle/<address>/<state>` queues an explicit state of 0 or 1 for a configured switch. Both endpoints require HTTP Basic authentication with username `nultra`. Write requests also require the header `X-Nultra-Request: 1`. A successful queue response reports acceptance. Use a later reading to check state.

```sh
python -m unittest discover -s tests
```
