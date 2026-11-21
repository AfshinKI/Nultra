from flask import Flask, Response, abort, jsonify, render_template, request
from urllib.parse import urlsplit
from BLEManager import BLEManager, NultraBLEDeviceInfo
from settings import ADDRESS, load_settings
import hmac
import re
import time

app = Flask(__name__)
DAYS = ("Mon", "Tue", "Wed", "Thu", "Fri", "Sat", "Sun")
g_ble_manager = None

@app.before_request
def authorize():
    token = app.config.get("GATEWAY_TOKEN", "")
    if not token or g_ble_manager is None:
        abort(503)
    auth = request.authorization
    if not (auth and auth.type == "basic" and auth.username == "nultra" and
            hmac.compare_digest((auth.password or "").encode(), token.encode())):
        return Response(status=401, headers={"WWW-Authenticate": 'Basic realm="Nultra"'})
    if request.method not in {"GET", "HEAD", "OPTIONS"}:
        origin = request.headers.get("Origin")
        if (request.headers.get("X-Nultra-Request") != "1" or
                request.headers.get("Sec-Fetch-Site") == "cross-site" or
                (origin and urlsplit(origin).netloc != request.host)):
            abort(403)
    args = request.view_args or {}
    if "address" in args and (not ADDRESS.fullmatch(args["address"]) or
                              args["address"].upper() not in g_ble_manager.passwords):
        abort(404)
    checks = {
        "state": lambda v: v in (0, 1), "enable": lambda v: v in (0, 1),
        "new_name": lambda v: re.fullmatch(r"[ -~]{1,8}", v),
        "time": lambda v: re.fullmatch(r"(?:[01][0-9]|2[0-3]):[0-5][0-9]", v),
        "days": lambda v: v == "all" or set(v.split(",")).issubset(DAYS),
        "duration": lambda v: 1 <= v <= 1440, "action": lambda v: v in ("on", "off"),
        "name": lambda v: 1 <= len(v) <= 64 and v.isprintable(),
        "schedule_uuid": lambda v: re.fullmatch(r"[a-f0-9-]{36}", v),
    }
    if any(not validate(args[k]) for k, validate in checks.items() if k in args):
        abort(400)


@app.after_request
def security_headers(response):
    response.headers.update({
        "Cache-Control": "no-store",
        "Content-Security-Policy": "default-src 'self'; frame-ancestors 'none'; base-uri 'none'; form-action 'self'",
        "X-Content-Type-Options": "nosniff",
        "Referrer-Policy": "no-referrer",
    })
    return response


def get_seen_recently(last_time):
    if last_time is None:
        return -1
    duration = time.time() - last_time
    if duration < 360:
        return 1
    elif duration < 1800:
        return 0
    else:
        return -1
    
    
def create_device_dict(device: NultraBLEDeviceInfo):
    return {
        'address': device.address,
        'display_name': device.display_name,
        'rssi': device.rssi,
        'device_type': device.device_type,
        'battery': device.battery,
        'switch_state': device.switch_state,
        'version': device.version,
        'seen_recently': get_seen_recently(device.last_time)
    }


@app.get("/")
def main_page():
    devices = [create_device_dict(d) for d in g_ble_manager.get_all_devices_info().values()]
    return render_template("dashboard.html", devices=devices)


@app.get("/device_page/<address>")
def device_page(address):
    d = g_ble_manager.get_device_info(address)
    if not d:
        abort(404)
    return render_template("device.html", device=create_device_dict(d),
                           schedules=g_ble_manager.get_schedules(address),
                           timer=g_ble_manager.get_timer_setting(address), days=DAYS)


# Route to fetch the devices as JSON (instead of Dash's callback)
@app.route('/devices', methods=['GET'])
def get_devices():
    devices = g_ble_manager.get_all_devices_info()
    device_list = []
    for device in devices.values():
        device_list.append(create_device_dict(device))

    # Return the list as a JSON response
    return jsonify(device_list)


@app.route('/device/<address>', methods=['GET'])
def get_device(address):
    device = g_ble_manager.get_device_info(address)
    if device is None:
        return jsonify({'status': 'ERROR', 'message': 'Device not found'})
    return jsonify(create_device_dict(device))


# Route to fetch the current progress info
@app.route('/progress', methods=['GET'])
def get_progress():
        info = g_ble_manager.get_progress_info()
        return jsonify({
            'message': info.message,
            'progress': info.progress,
            'last_update': info.last_update
        })
    

@app.route('/toggle/<address>/<int:state>', methods=['POST'])
def toggle_device(address, state):
    try:
        g_ble_manager.toggle_device(address, state)
    except Exception as e:
        return jsonify({'status': 'ERROR', 'message': 'Request could not be completed.'}), 400
    return jsonify({'status': 'OK'})


@app.route('/toggle_all/<int:state>', methods=['POST'])
def toggle_all_devices(state):
    try:
        g_ble_manager.toggle_all_devices(state)
    except Exception as e:
        return jsonify({'status': 'ERROR', 'message': 'Request could not be completed.'}), 400
    return jsonify({'status': 'OK'})


@app.route('/scan', methods=['POST'])
def scan_devices():
    try:
        g_ble_manager.scan_devices()
    except Exception as e:
        return jsonify({'status': 'ERROR', 'message': 'Request could not be completed.'}), 400
    return jsonify({'status': 'OK'})


@app.route('/retrieve/<address>', methods=['POST'])
def retrieve_device(address):
    try:
        g_ble_manager.retrieve_device(address)
    except Exception as e:
        return jsonify({'status': 'ERROR', 'message': 'Request could not be completed.'}), 400
    return jsonify({'status': 'OK'})


@app.route('/rename/<address>/<new_name>', methods=['POST'])
def rename_device(address, new_name):
    try:
        g_ble_manager.rename_device(address, new_name)
    except Exception as e:
        return jsonify({'status': 'ERROR', 'message': 'Request could not be completed.'}), 400
    return jsonify({'status': 'OK'})


### Schedule functions

@app.route('/schedule/get/<address>', methods=['GET'])
def get_schedule(address):
    schedules = g_ble_manager.get_schedules(address)
    return jsonify({
        'schedules': schedules
    })


@app.route('/schedule/add/<address>/<name>/<time>/<action>/<days>', methods=['POST'])
def add_schedule(address, name, time, action, days):
    try:
        if days == 'all':
            days = list(DAYS)
        else:
            days = days.split(',')
        g_ble_manager.add_schedule(address, name, time, action, days)
    except Exception as e:
        return jsonify({'status': 'ERROR', 'message': 'Request could not be completed.'}), 400
    return jsonify({'status': 'OK'})


@app.route('/schedule/remove/<address>/<schedule_uuid>', methods=['POST'])
def remove_schedule(address, schedule_uuid):
    try:
        g_ble_manager.remove_schedule(address, schedule_uuid)
    except Exception as e:
        return jsonify({'status': 'ERROR', 'message': 'Request could not be completed.'}), 400
    return jsonify({'status': 'OK'})


@app.route('/schedule/update/<address>/<schedule_uuid>/<name>/<time>/<action>/<days>', methods=['POST'])
def update_schedule(address, schedule_uuid, name, time, action, days):
    try:
        if days == 'all':
            days = list(DAYS)
        else:
            days = days.split(',')
        g_ble_manager.edit_schedule(address, schedule_uuid, name, time, action, days)
    except Exception as e:
        return jsonify({'status': 'ERROR', 'message': 'Request could not be completed.'}), 400
    return jsonify({'status': 'OK'})


@app.route('/schedule/toggle/<address>/<schedule_uuid>/<int:enable>', methods=['POST'])
def toggle_schedule(address, schedule_uuid, enable):
    try:
        if enable:
            g_ble_manager.enable_schedule(address, schedule_uuid)
        else:
            g_ble_manager.disable_schedule(address, schedule_uuid)
    except Exception as e:
        return jsonify({'status': 'ERROR', 'message': 'Request could not be completed.'}), 400
    return jsonify({'status': 'OK'})


@app.route('/timer/get/<address>', methods=['GET'])
def get_timer(address):
    setting = g_ble_manager.get_timer_setting(address)
    return jsonify({
        'timer_setting': setting
    })


@app.route('/timer/set/<address>/<int:duration>/<action>', methods=['POST'])
def set_timer(address, duration, action):
    try:
        g_ble_manager.set_timer_setting(address, duration, action)
    except Exception as e:
        return jsonify({'status': 'ERROR', 'message': 'Request could not be completed.'}), 400
    return jsonify({'status': 'OK'})

@app.route('/timer/toggle/<address>/<int:enable>', methods=['POST'])
def toggle_timer(address, enable):
    try:
        if enable:
            g_ble_manager.enable_timer(address)
        else:
            g_ble_manager.disable_timer(address)
    except Exception as e:
        return jsonify({'status': 'ERROR', 'message': 'Request could not be completed.'}), 400
    return jsonify({'status': 'OK'})


@app.route('/timer/remaining/<address>', methods=['GET'])
def get_remaining_percentage(address):
    try:
        remaining_percentage = g_ble_manager.get_timer_remaining_percentage(address)
    except Exception as e:
        return jsonify({'status': 'ERROR', 'message': 'Request could not be completed.'}), 400
    return jsonify({'status': 'OK', 'remaining_percentage': remaining_percentage})



if __name__ == "__main__":
    from waitress import serve
    token, passwords, directory = load_settings()
    app.config["GATEWAY_TOKEN"] = token
    g_ble_manager = BLEManager(passwords, directory / "schedules.json")
    serve(app, host="127.0.0.1", port=5050, max_request_body_size=16384)
