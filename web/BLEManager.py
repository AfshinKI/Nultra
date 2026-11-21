import asyncio
from bleak import BleakScanner, BleakClient
from dataclasses import dataclass
import time
import threading

from Scheduler import Scheduler


# Define the service and characteristic UUIDs.
SERVICE_UUID = "0000fe40-cc7a-482a-984a-7f2ed5b3e58f"
CHARACTERISTIC_UUIDS = {
    "switch": "0000fe41-8e22-4541-9d4c-21edae82ed19",
    "subscribe": "0000fe42-8e22-4541-9d4c-21edae82ed19",
    "battery": "0000fe43-8e22-4541-9d4c-21edae82ed19",
    "name": "0000fe44-8e22-4541-9d4c-21edae82ed19",
    "password": "0000fe45-8e22-4541-9d4c-21edae82ed19",
}

# Mapping of service UUIDs to device types.
SERVICE_TYPE_MAPPING = {
    SERVICE_UUID: "switch"
}

@dataclass
class NultraBLEDeviceInfo:
    address: str
    display_name: str
    rssi: int
    device_type: str
    battery: int
    switch_state: int
    version: str
    last_time: time = None


# Minimal definition for NultraBLEDevice
class NultraBLEDevice:
    def __init__(self, address, display_name=None, rssi=None, device_type="unknown", battery=None, switch_state=None, version=None, last_time=None):
        self.address = address
        self.display_name = display_name
        self.rssi = rssi
        self.device_type = device_type
        self.battery = battery
        self.switch_state = switch_state
        self.version = version
        self.last_time = last_time if last_time is not None else time.time()

        self.password = None
        self.client = None  # BleakClient instance


    # Use this when creating a new device
    @classmethod
    async def retrieve_and_create(cls, address, rssi):
        device_info = await cls._retrieve_device(address, rssi)
        return cls(
            address=device_info.address,
            display_name=device_info.display_name,
            rssi=device_info.rssi,
            device_type=device_info.device_type,
            battery=device_info.battery,
            switch_state=device_info.switch_state,
            version=device_info.version,
            last_time=device_info.last_time
        )
    
    # Use this when updating an existing device
    async def retrieve_and_update(self):
        device_info = await self._retrieve_device(self.address, self.rssi)
        self._set_info(device_info)


    @classmethod
    async def _retrieve_device(cls, address, rssi):
        async with BleakClient(address) as client:
            name_data = await client.read_gatt_char(CHARACTERISTIC_UUIDS["name"])
            if len(name_data) == 11:
                # Extract the first 8 bytes as the device name.
                device_name = name_data[:8].decode("utf-8", errors="replace")
                # Extract the last 3 bytes and format them as a version string.
                version_str = f"v{name_data[8]}.{name_data[9]}.{name_data[10]}"
            else:
                device_name = name_data.decode("utf-8", errors="replace")
                version_str = ""
            
            battery_data = await client.read_gatt_char(CHARACTERISTIC_UUIDS["battery"])
            switch_data = await client.read_gatt_char(CHARACTERISTIC_UUIDS["switch"])
            battery_percentage = battery_data[0] if battery_data else 0
            switch_state = switch_data[0] if switch_data else 0
            return NultraBLEDeviceInfo(
                address=address,
                display_name=device_name,
                rssi=rssi,
                device_type=SERVICE_TYPE_MAPPING.get(SERVICE_UUID, "unknown"),
                battery=battery_percentage,
                switch_state=switch_state,
                version=version_str,
                last_time=time.time()
            )


    def _stamp_time(self):
        self.last_time = time.time()


    def _set_info(self, device_info: NultraBLEDeviceInfo):
        self.display_name = device_info.display_name
        self.rssi = device_info.rssi
        self.device_type = device_info.device_type
        self.battery = device_info.battery
        self.switch_state = device_info.switch_state
        self.version = device_info.version
        self.last_time = device_info.last_time


    ### Public functions

    def get_info(self):
        return NultraBLEDeviceInfo(
            address=self.address,
            display_name=self.display_name,
            rssi=self.rssi,
            device_type=self.device_type,
            battery=self.battery,
            switch_state=self.switch_state,
            version=self.version,
            last_time=self.last_time)


    async def rename_device(self, new_name: str):
        if len(new_name) != 8:
            raise ValueError("New name must be exactly 8 characters.")
        await self.client.write_gatt_char(CHARACTERISTIC_UUIDS["name"],
                                           new_name.encode("ascii"), response=True)
        name_data = await self.client.read_gatt_char(CHARACTERISTIC_UUIDS["name"])
        if len(name_data) == 11:
            # Extract the first 8 bytes as the device name.
            self.display_name = name_data[:8].decode("utf-8", errors="replace")
            # Extract the last 3 bytes and format them as a version string.
            self.version_str = f"v{name_data[8]}.{name_data[9]}.{name_data[10]}"
        else:
            self.display_name = name_data.decode("ascii", errors="replace")
            self.version_str = ""

        self._stamp_time()
        return self.display_name


    async def connect(self):
        # If already connected, disconnect first.
        if self.client is not None:
            try:
                if self.client.is_connected:
                    await self.client.disconnect()
            except Exception:
                pass
            self.client = None
        if not self.password:
            raise ValueError("Configure this switch before sending a command")
        self.client = BleakClient(self.address, pair=True, timeout=60)
        await self.client.connect()
        await self.client.write_gatt_char(CHARACTERISTIC_UUIDS["password"],
                                           self.password.encode("ascii"), response=True)
        self._stamp_time()
        

    async def disconnect(self):
        if self.client is not None:
            try:
                await self.client.disconnect()
                self._stamp_time()
            except Exception as e:
                print(f"Error disconnecting from {self.address}: {e}")
            self.client = None
        

    async def toggle_switch(self, desired_state: int = None):
        if not self.client:
            raise Exception("Not connected to device")
        # If no desired_state is provided, toggle based on current state.
        if desired_state is None:
            switch_data = await self.client.read_gatt_char(CHARACTERISTIC_UUIDS["switch"])
            current_state = switch_data[0]
            desired_state = 1 if current_state == 0 else 0
        await self.client.write_gatt_char(CHARACTERISTIC_UUIDS["switch"],
                                        bytes([desired_state]), response=False)
        # Read the new state to confirm the change.
        switch_data = await self.client.read_gatt_char(CHARACTERISTIC_UUIDS["switch"])
        if not switch_data or switch_data[0] != desired_state:
            raise ValueError("Switch did not confirm requested state")
        self.switch_state = switch_data[0]
        self._stamp_time()
        return self.switch_state


@dataclass
class ProgressInfo():
    message: str
    progress: int
    last_update: str


class BLEManager:
    def __init__(self, passwords, schedule_file):
        self.passwords = passwords
        self._devices = {}
        self._dev_lock = asyncio.Lock()
        self._task_lock = asyncio.Lock()
        self._task_set = set()
        self._task_queue = asyncio.Queue(maxsize=128)
        self._cancel_scan = False
        self._scheduler = Scheduler(schedule_file)
        self._progress_info = ProgressInfo("", 0, "")
        self._loop = asyncio.new_event_loop()
        self._thread = threading.Thread(target=self._run_event_loop, daemon=True)
        self._thread.start()

    ### Public functions

    # Getter functions

    def get_device_info(self, address):
        device = self._devices.get(address.upper(), None)
        if not device:
            return None
        return device.get_info()


    def get_all_devices_info(self):
        return self._get_all_devices_info()
    

    def get_progress_info(self):
        return self._progress_info
    
    # Schedule

    def get_schedules(self, address: str):
        return self._scheduler.get_schedules(address.upper())
    

    def add_schedule(self, address: str, name: str, time: str, action: str, days: list[str]):
        uuid = self._scheduler.add_schedule(address.upper(), name, time, action, days)
        return uuid
    

    def remove_schedule(self, address: str, uuid: str):
        self._scheduler.remove_schedule(address.upper(), uuid)
        return uuid
    

    def edit_schedule(self, address: str, uuid: str, name: str, time: str, action: str, days: list[str]):
        uuid = self._scheduler.edit_schedule(address.upper(), uuid, name, time, action, days)
        return uuid


    def enable_schedule(self, address: str, uuid: str):
        uuid = self._scheduler.enable_schedule(address.upper(), uuid)
        return uuid


    def disable_schedule(self, address: str, uuid: str):
        uuid = self._scheduler.disable_schedule(address.upper(), uuid)
        return uuid
    

    # Timer 

    def get_timer_setting(self, address: str):
        setting = self._scheduler.get_timer_setting(address.upper())
        return {
            'enabled': setting['enabled'],
            'duration': setting['duration'],
            'action': setting['action'],
        }
        
    
    def set_timer_setting(self, address: str, duration: int, action: str):
        self._scheduler.set_timer_setting(address.upper(), duration, action)

    def enable_timer(self, address: str):
        self._scheduler.enable_timer(address.upper())

    def disable_timer(self, address: str):
        self._scheduler.disable_timer(address.upper())

    def get_timer_remaining_percentage(self, address: str):
        return self._scheduler.get_timer_remaining_percentage(address.upper())       
        

    # Task queing functions

    def toggle_device(self, address, on):
        self._cancel_scan = True
        self._submit("toggle", address, on)


    def toggle_all_devices(self, on):
        self._cancel_scan = True
        self._submit("toggle_all", on)
    

    def rename_device(self, address, new_name):
        self._cancel_scan = True
        self._submit("rename", address, new_name)


    def scan_devices(self):
        self._submit("scan")


    def retrieve_device(self, address):
        self._submit("retrieve", address)


    ### Private functions

    def _submit(self, kind, *args):
        future = asyncio.run_coroutine_threadsafe(self._enqueue_task(kind, *args), self._loop)
        if not future.result(timeout=3):
            raise ValueError("Request already queued or queue is full")

    def _run_event_loop(self):
        asyncio.set_event_loop(self._loop)
        self._loop.run_until_complete(self._task_queue_consumer())

    async def _enqueue_task(self, task_type, *args):
        task_key = (task_type, *args)
        async with self._task_lock:
            if task_key in self._task_set or self._task_queue.full():
                return False
            self._task_set.add(task_key)
        await self._task_queue.put(task_key)
        return True


    async def _task_queue_consumer(self):
        await self._enqueue_task("scan")

        while True:
            # Update the scheduler's date if needed
            self._scheduler.check_date_change()
            for addr, dev in self._devices.items():
                # Check if the device is scheduled
                schedule_action = self._scheduler.get_schedule_action(addr.upper())
                if schedule_action:
                    self._update_status(f"Scheduled task: {addr} {schedule_action}", 0)
                    await self._exec_toggle_device(addr, 1 if schedule_action == "on" else 0)
                self._scheduler.update_schedule_state(addr.upper(), 'on' if dev.switch_state else 'off')
                # Check if the timer is due
                timer_action = self._scheduler.get_timer_action(addr.upper())
                if timer_action:
                    self._update_status(f"Timer due: {addr} {timer_action}", 0)
                    await self._exec_toggle_device(addr, 1 if timer_action == "on" else 0)
                self._scheduler.update_timer_state(addr.upper(), 'on' if dev.switch_state else 'off')

            
            # Check task queue
            try:
                task_key = await asyncio.wait_for(self._task_queue.get(), timeout=1)  # Get a task from the queue
                self._task_queue.task_done()  # Mark the task as done
            except asyncio.TimeoutError:
                task_key = None

            # Complete the task if available
            if task_key:
                task_type, *args = task_key
                if task_type == "toggle":
                    await self._exec_toggle_device(*args)
                elif task_type == "toggle_all":
                    await self._exec_toggle_all_devices(*args)
                elif task_type == "rename":
                    await self._exec_rename_device(*args)
                elif task_type == "scan":
                    await self._exec_scan_devices(progress_update=False if args else True)
                elif task_type == "retrieve":
                    await self._exec_retrieve_device(*args)
                else:
                    print(f"Unknown task type: {task_type}")
                
                # Remove task from the set after execution
                async with self._task_lock:
                    self._task_set.discard(task_key)

            else: # If no task in the queue, scan devices
                await self._exec_scan_devices(progress_update=False) 

            
            await asyncio.sleep(0.1)


    # Execute functions called from _task_queue_consumer() (They may lock the _dev_lock)

    async def _exec_toggle_device(self, address, on):
        device = self._devices.get(address.upper(), None)
        if not device:
            return None
        async with self._dev_lock:
            try:
                await self._toggle_with_retry(device, on)
            except Exception as e:
                pass


    async def _exec_toggle_all_devices(self, on):
        async with self._dev_lock:
            try:
                await self._toggle_all(on)
            except Exception as e:
                self._update_status(f"Error toggling all devices: {e}", 100)


    async def _exec_rename_device(self, address, new_name):
        if len(new_name) > 8:
            new_name = new_name[:8]
        else:
            new_name = new_name.ljust(8)
        device = self._devices.get(address.upper(), None)
        if not device:
            return None
            
        async with self._dev_lock:
            try:
                await self._do_rename(device, new_name)
            except Exception as e:
                self._update_status(f"Error renaming device {device.display_name}", 100)


    async def _exec_scan_devices(self, progress_update):
        async with self._dev_lock:
            try:
                devices = await self._scan_devices(progress_update)
                self._update_devices(devices)
            except Exception as e:
                self._update_status(f"Error scanning devices: {e}", 100)


    async def _exec_retrieve_device(self, address):
        device = self._devices.get(address.upper(), None)

        if not device:
            return None
        async with self._dev_lock:
            max_retries = 40
            delay = 0.1
            retrieved = False
            for attempt in range(1, max_retries + 1):
                try:
                    await device.retrieve_and_update()
                    retrieved = True
                    break
                except Exception as e:
                    if "Error.InProgress" in str(e):
                        await asyncio.sleep(delay)
                    else:
                        break
            if not retrieved:
                self._update_status(f"Failed to retrieve device {device.display_name}", 100)
            else:
                self._update_status(f"Retrieved device {device.display_name}", 100)

    # Other sub-functions (They won't lock the _dev_lock)

    def _update_devices(self, devices):
        # Add to dict, if exist, replace it with new
        for d in devices:
            self._devices[d.address.upper()] = d

        # TODO: Fix later
        # time_now = time.time()
        # for k in list(self._devices.keys()):  # Iterate over a copy of keys
        #     if time_now - self._devices[k].last_time > 6000:  # 100 min
        #         del self._devices[k]

    
    def _update_status(self, message, progress=None):
        self._progress_info = ProgressInfo(message, progress, time.strftime("%Y-%m-%d %H:%M:%S"))

    def _get_all_devices_info(self):
        return {key: device.get_info() for key, device in self._devices.copy().items()}

    ### Private async functions
    
    async def _scan_devices(self, progress_update):
        if progress_update:
            self._update_status("Starting BLE scan...", 0)
        advertisements = await BleakScanner.discover(timeout=3, return_adv=True)
        devices = [(dev, data) for dev, data in advertisements.values()
                   if dev.address.upper() in self.passwords]

        # Reset cancel flag
        if self._cancel_scan:
            self._cancel_scan = False
            self._update_status("Scan cancelled.", 100) if progress_update else None
            return []
        
        # Filter for candidate devices containing "Nultra" in their name.
        candidate_devices = devices

        if not candidate_devices:
            self._update_status("No candidate devices found.", 100) if progress_update else None
            return []
        
        self._update_status(f"Found {len(candidate_devices)} candidate from total {len(devices)} devices", 30) if progress_update else None

        # Check if the deivce is already in the list and skip deep scan
        deep_scan_skipped = 0
        deep_scan_devices = []
        for d, advertisement in candidate_devices:
            local_name = advertisement.local_name or d.name or ""
            if d.address in self._devices and local_name.startswith("Nultra") and len(local_name) >= 10:
                # Update the RSSI value to the latest from the scan.
                try:
                    # d.name format is "NultraXYYY" X: state, YYY: battery lavel
                    switch_state = int(local_name[6])
                    battery = int(local_name[7:10])
                    if switch_state not in (0, 1) or not 0 <= battery <= 100:
                        raise ValueError("Invalid advertisement")
                    known = self._devices[d.address]
                    known.rssi = advertisement.rssi
                    known.switch_state = switch_state
                    known.battery = battery
                    known.last_time = time.time()
                    deep_scan_skipped += 1
                except Exception as e:
                    deep_scan_devices.append((d, advertisement.rssi))
            else:
                deep_scan_devices.append((d, advertisement.rssi))

        if not deep_scan_devices:
            self._update_status('', 100)
            return []

        # Semaphore to limit concurrent connections (to avoid BLE errors)
        sem = asyncio.Semaphore(1)

        async def process_new_device(device, rssi):
            async with sem:
                return await self._process_candidate(device, rssi)

        tasks = [asyncio.create_task(process_new_device(d, rssi)) for d, rssi in deep_scan_devices]
        valid_devices = []
        total = len(deep_scan_devices)
        processed = 0

        for completed in asyncio.as_completed(tasks):
            try:
                progress = 30 + (processed / total) * (100 - 30)
                processed += 1
                result = await completed

                if isinstance(result, NultraBLEDevice):
                    valid_devices.append(result)

                    self._update_status(f"Processed device {result.display_name} successfully", progress) if progress_update else None
            except Exception as e:
                self._update_status(str(e), progress) if progress_update else None

        # Reset cancel flag
        message = ""   
        if self._cancel_scan:
            message = "Scan cancelled. "
            self._cancel_scan = False
        
        message += f"Deep scanned {len(valid_devices)}/{total} devices. Shallow scanned {deep_scan_skipped} devices "
        self._update_status(message, 100) # Keep this update even with progress_update=False
        return valid_devices
    

    async def _process_candidate(self, device, rssi): # bleak.backends.device.BLEDevice
        max_retries = 40
        delay = 0.1
        for attempt in range(1, max_retries + 1):
            # If cancel flag is set, return ASAP.
            if self._cancel_scan:
                return None
            
            try:
                device_instance = await NultraBLEDevice.retrieve_and_create(device.address, rssi)
                device_instance.password = self.passwords[device.address.upper()]
                return device_instance
            except Exception as e:
                if "Error.InProgress" in str(e):
                    await asyncio.sleep(delay)
                else:
                    raise Exception(f'Error processing device: {device.address}')
        return None

    
    async def _do_rename(self, device, new_name):
        self._update_status(f"Renaming device {device.display_name} to {new_name}", 0)
        try:
            await device.connect()
            updated_name = await device.rename_device(new_name)
            device.display_name = updated_name
        except Exception as e:
            self._update_status(f"Error renaming device {device.display_name}", 100)
            return device.display_name
        finally:
            await device.disconnect()
        

        self._update_status(f"Renamed device {device.display_name} to {updated_name}", 100)
        return updated_name
    

    async def _toggle_with_retry(self, device, desired_state, max_retries=2, progress_update=True):
        delay = 0.1
        self._update_status(f"Turning {device.display_name} {'on' if desired_state else 'off'}", 0) if progress_update else None
        for attempt in range(1, max_retries + 1):
            try:
                await device.connect()
                # Pass the desired_state (if any) to toggle_switch.
                new_state = await device.toggle_switch(desired_state)
                device.switch_state = new_state

                self._update_status(f"{device.display_name} turned {'on' if desired_state else 'off'} successfully on attempt {attempt + 1}", 100) if progress_update else None
                return device
            except Exception as e:
                if attempt == max_retries:
                    self._update_status(f"{e}", None) if progress_update else None
                    raise Exception(f'Error toggling device: {device.display_name}')
                await asyncio.sleep(delay)
            finally:
                await device.disconnect()
        return None


    async def _toggle_all(self, desired_state):
        await self._toggle_all_sequential(desired_state)


    async def _toggle_all_concurrent(self, desired_state):
        # Currently, this won't find switches successfully from pi.
        sem = asyncio.Semaphore(4)
        async def toggle_with_sem(device, desired_state):
            async with sem:
                return await self._toggle_with_retry(device, desired_state, max_retries=10, progress_update=False)
            
        tasks = [asyncio.create_task(toggle_with_sem(d, desired_state)) for d in self._devices.values()]
        processed = 0
        valid = 0
        total = len(self._devices)

        for completed in asyncio.as_completed(tasks):
            try:
                processed += 1
                progress = 30 + (processed / total) * (100 - 30)
                result = await completed
                if result:
                    valid += 1
                    self._update_status(f"Device {result.display_name} turned {'on' if desired_state else 'off'} successfully", progress)

            except Exception as e:
                self._update_status(str(e), progress)

        message = f"Turned {'on' if desired_state else 'off'} {valid}/{total} devices."
        self._update_status(message, 100)


    async def _toggle_all_sequential(self, desired_state):
        total = len(self._devices)
        remaining = self._devices.values()
        for attempt in range(1, 11):
            for d in remaining:
                try:
                    await self._toggle_with_retry(d, desired_state, max_retries=1, progress_update=False)
                    # Remove from remaining
                    remaining = [x for x in remaining if x.address != d.address]
                    self._update_status(f"Device {d.display_name} turned {'on' if desired_state else 'off'} successfully.", 100 * (total - len(remaining)) // total)
                except Exception as e:
                    pass
            if not remaining:
                break
        processed = total - len(remaining)
        message = f"Turned {'on' if desired_state else 'off'} {processed}/{total} devices."
        self._update_status(message, 100)
