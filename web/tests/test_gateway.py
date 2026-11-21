import secrets
import tempfile
import unittest
from pathlib import Path
from unittest.mock import Mock, patch

import main
from BLEManager import NultraBLEDeviceInfo
from Scheduler import Scheduler


class GatewayTest(unittest.TestCase):
    def setUp(self):
        self.address = "02:00:00:00:00:01"
        self.token = secrets.token_urlsafe(32)
        self.auth = ("nultra", self.token)
        self.command = {"X-Nultra-Request": "1"}
        self.manager = Mock(passwords={self.address: secrets.token_hex(4)})
        self.device = NultraBLEDeviceInfo(self.address, 'Lamp & TV', -42, 'switch', 50, 1, 'v1')
        self.manager.get_device_info.return_value = self.device
        self.manager.get_all_devices_info.return_value = {self.address: self.device}
        self.manager.get_schedules.return_value = []
        self.manager.get_timer_setting.return_value = dict(enabled=False, duration=5, action="off")
        for context in (patch.object(main, 'g_ble_manager', self.manager),
                        patch.dict(main.app.config, {'GATEWAY_TOKEN': self.token})):
            context.start()
            self.addCleanup(context.stop)
        self.client = main.app.test_client()

    def test_gateway_requires_credentials(self):
        self.assertEqual(self.client.get('/devices').status_code, 401)
        self.assertEqual(self.client.get('/devices', auth=self.auth).json[0]['address'], self.address)

    def test_authorized_commands_require_explicit_header(self):
        path = f"/toggle/{self.address}/1"
        self.assertEqual(self.client.post(path, auth=self.auth).status_code, 403)
        self.manager.toggle_device.assert_not_called()
        self.assertEqual(self.client.post(path, auth=self.auth, headers=self.command).status_code, 200)
        self.manager.toggle_device.assert_called_once_with(self.address, 1)

    def test_device_and_control_pages_render(self):
        for path in ("/", "/device_page/" + self.address):
            response = self.client.get(path, auth=self.auth)
            self.assertEqual(response.status_code, 200)
            self.assertIn(b'Lamp &amp; TV', response.data)
            self.assertIn("frame-ancestors 'none'", response.headers['Content-Security-Policy'])

    def test_offline_switch_is_not_treated_as_authorized(self):
        unknown = "02:00:00:00:00:02"
        self.assertEqual(self.client.post(f"/toggle/{unknown}/1", auth=self.auth, headers=self.command).status_code, 404)
        self.manager.toggle_device.assert_not_called()

    def test_active_timer_and_new_schedule_can_coexist_on_disk(self):
        with tempfile.TemporaryDirectory() as folder:
            path = Path(folder) / "schedules.json"
            scheduler = Scheduler(path)
            scheduler.set_timer_setting(self.address, 5, "off")
            scheduler.update_timer_state(self.address, "on")
            scheduler.add_schedule(self.address, "Read", "12:30", "on")
            loaded = Scheduler(path)
            self.assertEqual(loaded.get_schedules(self.address)[0]["name"], "Read")
            self.assertFalse(loaded.get_timer_setting(self.address)["activated"])
