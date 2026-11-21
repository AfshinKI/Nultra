import uuid
import json
import copy
import datetime
import threading
import os
import tempfile

class Scheduler:
    '''
    Parse given json file, store schedules in a dict.
    It can add/remove schedules, and update json file.
    Handle today's queue.
    '''

    def __init__(self, schedule_file='schedules.json'):
        self._init_params()
        self._schedule_file = schedule_file
        # Check if the schedule file exists, if not create it
        if not os.path.exists(schedule_file):
            with open(schedule_file, 'w') as f:
                json.dump({"version": self._version, "devices": {}}, f, indent=4)
        # Check if the schedule version is compatible, if not, update it
        self._update_schedule_json(schedule_file)
        self._load_schedules()


    def _init_params(self):
        self._schedule_file = None
        self._schedule = {} # Master schedule
        self._queues_date = None
        self._lock = threading.Lock() # Lock for schedule access

        self._default_timer = {
            "enabled": False,
            "duration": 5,
            "action": "off",
            "activated": False,
            "remaining_duration": None,
            "due_time": None
        }
        self._version = '1.1.0' # Version of the schedule

    # Handle schedule and today's queue

    def _set_default_schedule_for_device(self, address: str):
        # Set default schedule for the device
        self._schedule["devices"][address] = {
            "schedules": [],
            "timer": self._default_timer.copy()
        }

    def add_schedule(self, address: str, name: str, time: str, action: str, days=['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun']):
        with self._lock:
            new_uuid = str(uuid.uuid4())
            if address not in self._schedule["devices"]:
                self._set_default_schedule_for_device(address)

            # Check if the schedule already exists
            if any(entry['time'] == time and entry['action'] == action and entry['days'] == days for entry in self._schedule["devices"][address]["schedules"]):
                print(f"Schedule already exists for {address} at {time} with action {action}")
                return None
            
            now = datetime.datetime.now().strftime('%H:%M')
            schedule = {
                "uuid": new_uuid,
                "name": name,
                "time": time,
                "action": action,
                "days": days,
                "enabled": True,
                "done": True if time < now else False
            }

            self._schedule["devices"][address]["schedules"].append(schedule)
            self._save_schedules()
        return new_uuid


    def remove_schedule(self, address: str, uuid: str):
        with self._lock:
            if address in self._schedule["devices"]:
                self._schedule["devices"][address]["schedules"] = [entry for entry in self._schedule["devices"][address]["schedules"] if entry["uuid"] != uuid]
            self._save_schedules()
        return uuid
    

    def edit_schedule(self, address: str, uuid: str, name: str, time: str, action: str, days=['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun']):
        with self._lock:
            found = False
            now = datetime.datetime.now().strftime('%H:%M')
            if address in self._schedule["devices"]:
                for entry in self._schedule["devices"][address]["schedules"]:

                    if entry["uuid"] == uuid:
                        entry["name"] = name
                        entry["time"] = time
                        entry["action"] = action
                        entry["days"] = days
                        entry["done"] = True if time < now else False
                        found = True
                        break
            if not found:
                print(f"Schedule with UUID {uuid} not found for address {address}")
                return None
            
            self._save_schedules()
        return uuid
    

    def enable_schedule(self, address: str, uuid: str):
        with self._lock:
            found = False
            if address in self._schedule["devices"]:
                for entry in self._schedule["devices"][address]["schedules"]:
                    if entry["uuid"] == uuid:
                        entry["enabled"] = True
                        found = True
                        break
            if not found:
                print(f"Schedule with UUID {uuid} not found for address {address}")
                return None

            self._save_schedules()
        return uuid
    

    def disable_schedule(self, address: str, uuid: str):
        with self._lock:
            found = False
            if address in self._schedule["devices"]:
                for entry in self._schedule["devices"][address]["schedules"]:
                    if entry["uuid"] == uuid:
                        entry["enabled"] = False
                        found = True
                        break
            if not found:
                print(f"Schedule with UUID {uuid} not found for address {address}")
                return None
            
            self._save_schedules()
        return uuid


    def get_schedules(self, address: str) -> list[dict]:
        if address not in self._schedule["devices"]:
            return []
        return self._schedule["devices"][address]["schedules"]
    

    def get_schedule_action(self, address: str):
        # Get the schedules for a specific address
        now = datetime.datetime.now().strftime('%H:%M')
        today = datetime.datetime.today().strftime('%a')
        with self._lock:
            if address in self._schedule["devices"]:
                for entry in self._schedule["devices"][address]["schedules"]:
                    if entry["time"] <= now and today in entry["days"] and not entry["done"] and entry["enabled"]:
                        # Return the action of the schedule
                        return entry["action"]
        return None
    

    def update_schedule_state(self, address: str, switch_state: str):
        now = datetime.datetime.now().strftime('%H:%M')
        with self._lock:
            if address in self._schedule["devices"]:
                for entry in self._schedule["devices"][address]["schedules"]:
                    if entry["time"] <= now and entry["action"] == switch_state:
                        # Update the schedule state
                        entry["done"] = True
    

    def _load_schedules(self):
        # Load schedules from a JSON file
        if os.path.exists(self._schedule_file):
            with open(self._schedule_file, 'r') as f:
                self._schedule = json.load(f)
        else:
            self._schedule = {}

        # clean up timers activated, remaining_duration, due_time
        for address in self._schedule["devices"].keys():
            self._reset_timer_state(address)

        self._check_date_change()
        self._mark_past_schedules_done()


    def check_date_change(self):
        with self._lock:
            self._check_date_change()


    def _check_date_change(self):
        # Check if the date has changed
        today = datetime.datetime.today().strftime('%Y-%m-%d')
        if self._queues_date == today:
            return
        self._queues_date = today
        self._reset_done_flag()


    def _mark_past_schedules_done(self):
        # Mark past schedules as done
        now = datetime.datetime.now().strftime('%H:%M')
        today = datetime.datetime.today().strftime('%a')
        with self._lock:
            for address in self._schedule["devices"]:
                for entry in self._schedule["devices"][address]["schedules"]:
                    if entry["time"] < now and today in entry["days"] and not entry["done"]:
                        entry["done"] = True


    def _reset_done_flag(self):
        # Reset the done flag for all schedules
        for address in self._schedule["devices"]:
            for entry in self._schedule["devices"][address]["schedules"]:
                entry["done"] = False


    # Handle timer

    def get_timer_setting(self, address: str) -> dict:
        # Get the timer setting for a specific address
        if address in self._schedule["devices"]:
            return self._schedule["devices"][address]["timer"]
        else:
            return self._default_timer
        
        
    def set_timer_setting(self, address: str, duration: int, action: str):
        with self._lock:
            if not address in self._schedule["devices"]:
                # Initialize the device if it doesn't exist
                self._set_default_schedule_for_device(address)

            # Set the timer setting for a specific address
            self._schedule["devices"][address]["timer"]["enabled"] = True
            self._schedule["devices"][address]["timer"]["duration"] = duration
            self._schedule["devices"][address]["timer"]["action"] = action
            self._reset_timer_state(address)
            self._save_schedules()


    def enable_timer(self, address: str):
        # Enable the timer for a specific address
        with self._lock:
            if not address in self._schedule["devices"]:
                # Initialize the device if it doesn't exist
                self._set_default_schedule_for_device(address)
            self._schedule["devices"][address]["timer"]["enabled"] = True
            self._save_schedules()


    def disable_timer(self, address: str):
        # Disable the timer for a specific address
        with self._lock:
            if not address in self._schedule["devices"]:
                # Initialize the device if it doesn't exist
                self._set_default_schedule_for_device(address)
            self._schedule["devices"][address]["timer"]["enabled"] = False
            # Reset the timer state
            self._reset_timer_state(address)
            self._save_schedules()


    def update_timer_state(self, address: str, switch_state: str):
        with self._lock:
            if address in self._schedule["devices"]:
                timer = self._schedule["devices"][address]["timer"]

                activated = timer["activated"]
                if activated:
                    if switch_state == timer["action"]: # Already satisfied
                        self._reset_timer_state(address)
                    else: # Update remaining duration
                        timer["remaining_duration"] = timer["due_time"] - datetime.datetime.now()
                else:
                    if switch_state != timer["action"] and timer["enabled"]: 
                        timer["activated"] = True
                        timer["remaining_duration"] = timer["duration"] # Reserve for pausing feature
                        timer["due_time"] = datetime.datetime.now() + datetime.timedelta(minutes=timer["duration"])


    def get_timer_action(self, address: str):
        now = datetime.datetime.now()
        timer_state = self._get_timer_state(address)
        if timer_state and timer_state['activated']:
            # Check if the timer is due
            if now >= timer_state["due_time"]:
                return timer_state["action"]
        return None
    
    
    def get_timer_remaining_percentage(self, address: str):
        now = datetime.datetime.now()
        timer_state = self._get_timer_state(address)
        if timer_state and timer_state['activated']:
            # Check if the timer is due
            if now >= timer_state["due_time"]:
                return 0
            else:
                remaining_duration = (timer_state["due_time"] - now).total_seconds() / 60
                return (remaining_duration / timer_state["duration"]) * 100
        return 0


    def _get_timer_state(self, address: str):
        if address in self._schedule["devices"]:
            return self._schedule["devices"][address]["timer"]
        return None


    def _reset_timer_state(self, address: str):
        # Reset the timer state for a specific address
        if address in self._schedule["devices"]:
            timer = self._schedule["devices"][address]["timer"]
            timer["activated"] = False
            timer["remaining_duration"] = None
            timer["due_time"] = None
        

    # Handle schedule json file

    def _save_schedules(self):
        # Save schedules to a JSON file
        # Create a temporary file in the same directory
        snapshot = copy.deepcopy(self._schedule)
        for device in snapshot["devices"].values():
            device["timer"].update(activated=False, remaining_duration=None, due_time=None)
        self._write_file(snapshot)

    def _write_file(self, snapshot):
        folder = os.path.dirname(os.path.abspath(self._schedule_file))
        with tempfile.NamedTemporaryFile("w", dir=folder, delete=False) as tmp_file:
            temp_name = tmp_file.name
            try:
                json.dump(snapshot, tmp_file, indent=4)
                tmp_file.flush()
                os.fsync(tmp_file.fileno())
            except BaseException:
                os.unlink(temp_name)
                raise
        os.replace(temp_name, self._schedule_file)

    def _update_schedule_json(self, file: str):
        # Update original schedule json file to the latest version
        with open(file, 'r') as f:
            schedules = json.load(f)

        # new json
        new_schedules = {}

        if "version" not in schedules: # Old version
            new_schedules["version"] = self._version
            new_schedules["devices"] = {}
            for address, entries in schedules.items():
                for entry in entries:
                    entry["done"] = False
                new_schedules["devices"][address] = {
                    "schedules": entries,
                    "timer": {
                        "enabled": False,
                        "duration": 5,
                        "action": "off",
                        "activated": False,
                        "remaining_duration": None,
                        "due_time": None
                    }
                }
        elif schedules["version"] < self._version:
            new_schedules = schedules
            for device in new_schedules["devices"].values():
                for entry in device["schedules"]:
                    if "done" not in entry:
                        entry["done"] = False
                # Update the timer to the new format
                timer = device["timer"]
                if "enabled" not in timer:
                    timer["enabled"] = False
                if "duration" not in timer:
                    timer["duration"] = 5
                if "action" not in timer:
                    timer["action"] = "off"
                if "activated" not in timer:
                    timer["activated"] = False
                if "remaining_duration" not in timer:
                    timer["remaining_duration"] = None
                if "due_time" not in timer:
                    timer["due_time"] = None
            new_schedules["version"] = self._version
        elif schedules["version"] == self._version:
            return True
        else:
            print("Automated conversion is not supported. Please update the schedule manually.")            
            return False
        
        # Save the new schedules to the file
        self._write_file(new_schedules)
        return True
    
