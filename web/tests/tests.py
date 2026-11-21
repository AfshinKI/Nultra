import unittest
import datetime
import shutil
import tempfile
from unittest.mock import patch

import sys
import os
sys.path.append(os.path.abspath(os.path.join(os.path.dirname(__file__), '..')))
from Scheduler import Scheduler

class TestScheduler(unittest.TestCase):
    def setUp(self):
        """Initialize a fresh scheduler instance before each test."""
        temp = tempfile.TemporaryDirectory()
        self.addCleanup(temp.cleanup)
        schedule_path = os.path.join(temp.name, "schedule.json")
        shutil.copyfile(os.path.join(os.path.dirname(__file__), "dummy_schedule.json"), schedule_path)
        # Keep minute-based timer tests independent of execution time and midnight.
        self.clock = datetime.datetime(2026, 1, 5, 12, 0)
        real_datetime = datetime.datetime
        case = self
        class Clock(real_datetime):
            @classmethod
            def now(cls): return case.clock
            @classmethod
            def today(cls): return case.clock
        override = patch.object(datetime, "datetime", Clock)
        override.start()
        self.addCleanup(override.stop)
        self.scheduler = Scheduler(schedule_path)
        self.address = "02:00:00:00:00:01"
        self.dummy_address = "02:00:00:00:00:02"


    def test_01_schedules_after_now_are_not_done(self):
        """Test if schedules after now are not marked as done."""
        print(__name__)
        now = datetime.datetime.now().strftime('%H:%M')
        schedules = self.scheduler.get_schedules(self.address)
        for schedule in schedules:
            # Initially, all schedules before now should be marked as done, and those after now should not.
            if schedule['time'] > now:
                self.assertFalse(schedule['done'])
            else:
                self.assertTrue(schedule['done'])


    def test_02_get_schedule_action_should_be_none(self):
        """Test if the scheduled action is None when no schedule is present."""
        self.assertIsNone(self.scheduler.get_schedule_action(self.dummy_address))


    def test_03_add_schedule_and_action_will_not_be_none_when_time_comes(self):
        """Test adding a schedule and checking if action is not None when the time comes."""
        due_time = (datetime.datetime.now() + datetime.timedelta(minutes=1)).strftime('%H:%M')

        desired_state = 'on'
        schedule_uuid = self.scheduler.add_schedule(self.address, 'test_03', due_time, desired_state)
        self.assertIsNotNone(schedule_uuid)

        # Ensure the schedule is added
        schedules = self.scheduler.get_schedules(self.address)
        self.assertTrue(any(s["uuid"] == schedule_uuid for s in schedules))

        # Wait for 1 min for the task to become due
        self.clock += datetime.timedelta(minutes=1)

        # Check if the task appears in due tasks
        scheduled_action = self.scheduler.get_schedule_action(self.address)
        self.assertEqual(scheduled_action, desired_state)

        # Update state
        self.scheduler.update_schedule_state(self.address, desired_state)

        # scheduled action should be None now
        scheduled_action = self.scheduler.get_schedule_action(self.address)
        self.assertIsNone(scheduled_action)

        # Remove the schedule
        self.assertIsNotNone(self.scheduler.remove_schedule(self.address, schedule_uuid))

        # Ensure the schedule is removed
        schedules = self.scheduler.get_schedules(self.address)
        self.assertFalse(any(s["uuid"] == schedule_uuid for s in schedules))


    def test_04_add_and_remove_before_due(self):
        """Test adding a schedule and removing it before it's due."""
        due_time = (datetime.datetime.now() + datetime.timedelta(minutes=1)).strftime('%H:%M')

        schedule_uuid = self.scheduler.add_schedule(self.address, 'test_04', due_time, 'on')
        self.assertIsNotNone(schedule_uuid)

        # Ensure the schedule is added
        schedules = self.scheduler.get_schedules(self.address)
        self.assertTrue(any(s["uuid"] == schedule_uuid for s in schedules))

        # Remove the schedule **before** it's due
        self.assertIsNotNone(self.scheduler.remove_schedule(self.address, schedule_uuid))

        # Ensure the schedule is removed
        schedules = self.scheduler.get_schedules(self.address)
        self.assertFalse(any(s["uuid"] == schedule_uuid for s in schedules))


    def test_05_add_and_edit_schedule(self):
        """Test adding a schedule and editing it."""
        due_time = (datetime.datetime.now() + datetime.timedelta(minutes=1)).strftime('%H:%M')

        schedule_uuid = self.scheduler.add_schedule(self.address, 'test_05', due_time, 'on')
        self.assertIsNotNone(schedule_uuid)

        # Ensure the schedule is added
        schedules = self.scheduler.get_schedules(self.address)
        self.assertTrue(any(s["uuid"] == schedule_uuid for s in schedules))

        # Edit the schedule
        new_due_time = (datetime.datetime.now() + datetime.timedelta(minutes=1)).strftime('%H:%M')
        self.assertIsNotNone(self.scheduler.edit_schedule(self.address, schedule_uuid, 'test_05_edited', new_due_time, 'off'))

        # Ensure the schedule is updated
        schedules = self.scheduler.get_schedules(self.address)
        edited_schedule = next((s for s in schedules if s["uuid"] == schedule_uuid), None)
        self.assertIsNotNone(edited_schedule)
        self.assertEqual(edited_schedule["time"], new_due_time)
        self.assertEqual(edited_schedule["action"], 'off')
        self.assertEqual(edited_schedule["name"], 'test_05_edited')

        # wait for 1 minute to check if the task is due
        self.clock += datetime.timedelta(minutes=1)
        # Check if the task appears in due tasks
        scheduled_action = self.scheduler.get_schedule_action(self.address)
        self.assertEqual(scheduled_action, 'off')

        # Remove the schedule
        self.assertIsNotNone(self.scheduler.remove_schedule(self.address, schedule_uuid))
        # Ensure the schedule is removed
        schedules = self.scheduler.get_schedules(self.address)
        self.assertFalse(any(s["uuid"] == schedule_uuid for s in schedules))


    def test_06_add_schedule_past_time_of_day_will_be_marked_as_done(self):
        """Test adding a schedule with a past time of day."""
        # Get the current time
        now = datetime.datetime.now()
        # Create a time string for 1 minute ago
        past_time = (now - datetime.timedelta(minutes=1)).strftime('%H:%M')
        # Add a schedule with the past time
        schedule_uuid = self.scheduler.add_schedule(self.address, 'test_06', past_time, 'on')
        self.assertIsNotNone(schedule_uuid)
        # Ensure the schedule is added
        schedules = self.scheduler.get_schedules(self.address)
        self.assertTrue(any(s["uuid"] == schedule_uuid for s in schedules))
        # Check if the schedule is marked as done
        schedule = next((s for s in schedules if s["uuid"] == schedule_uuid), None)
        self.assertIsNotNone(schedule)
        self.assertTrue(schedule['done'])

        # Remove the schedule
        self.assertIsNotNone(self.scheduler.remove_schedule(self.address, schedule_uuid))
        # Ensure the schedule is removed
        schedules = self.scheduler.get_schedules(self.address)
        self.assertFalse(any(s["uuid"] == schedule_uuid for s in schedules))


    def test_07_edit_schedule_past_time_of_day_will_be_marked_as_done(self):
        """Test editing a schedule with a past time of day."""
        # Get the current time
        now = datetime.datetime.now()
        # future time
        future_time = (now + datetime.timedelta(minutes=1)).strftime('%H:%M')
        # Add a schedule with the future time
        schedule_uuid = self.scheduler.add_schedule(self.address, 'test_07', future_time, 'on')
        self.assertIsNotNone(schedule_uuid)
        # Ensure the schedule is added
        schedules = self.scheduler.get_schedules(self.address)
        self.assertTrue(any(s["uuid"] == schedule_uuid for s in schedules))
        # Check if the schedule is not marked as done
        schedule = next((s for s in schedules if s["uuid"] == schedule_uuid), None)
        self.assertIsNotNone(schedule)
        self.assertFalse(schedule['done'])

        # Edit the schedule to a past time
        past_time = (now - datetime.timedelta(minutes=1)).strftime('%H:%M')
        self.assertIsNotNone(self.scheduler.edit_schedule(self.address, schedule_uuid, 'test_07_edited', past_time, 'off'))
        # Ensure the schedule is updated
        schedules = self.scheduler.get_schedules(self.address)
        edited_schedule = next((s for s in schedules if s["uuid"] == schedule_uuid), None)
        self.assertIsNotNone(edited_schedule)
        self.assertEqual(edited_schedule["time"], past_time)
        self.assertEqual(edited_schedule["action"], 'off')
        self.assertEqual(edited_schedule["name"], 'test_07_edited')
        # Check if the schedule is marked as done
        schedule = next((s for s in schedules if s["uuid"] == schedule_uuid), None)
        self.assertIsNotNone(schedule)
        self.assertTrue(schedule['done'])

        # Remove the schedule
        self.assertIsNotNone(self.scheduler.remove_schedule(self.address, schedule_uuid))
        # Ensure the schedule is removed
        schedules = self.scheduler.get_schedules(self.address)
        self.assertFalse(any(s["uuid"] == schedule_uuid for s in schedules))



    def test_08_edit_schedule_from_past_time_to_future_time_will_reset_done_flag(self):
        """Test editing a schedule from a past time to a future time."""
        # Get the current time
        now = datetime.datetime.now()
        # Create a time string for 1 minute ago
        past_time = (now - datetime.timedelta(minutes=1)).strftime('%H:%M')
        # Add a schedule with the past time
        schedule_uuid = self.scheduler.add_schedule(self.address, 'test_08', past_time, 'on')
        self.assertIsNotNone(schedule_uuid)
        # Ensure the schedule is added
        schedules = self.scheduler.get_schedules(self.address)
        self.assertTrue(any(s["uuid"] == schedule_uuid for s in schedules))
        # Check if the schedule is marked as done
        schedule = next((s for s in schedules if s["uuid"] == schedule_uuid), None)
        self.assertIsNotNone(schedule)
        self.assertTrue(schedule['done'])

        # Edit the schedule to a future time
        future_time = (now + datetime.timedelta(minutes=1)).strftime('%H:%M')
        self.assertIsNotNone(self.scheduler.edit_schedule(self.address, schedule_uuid, 'test_08_edited', future_time, 'off'))
        # Ensure the schedule is updated
        schedules = self.scheduler.get_schedules(self.address)
        edited_schedule = next((s for s in schedules if s["uuid"] == schedule_uuid), None)
        self.assertIsNotNone(edited_schedule)
        self.assertEqual(edited_schedule["time"], future_time)
        self.assertEqual(edited_schedule["action"], 'off')
        self.assertEqual(edited_schedule["name"], 'test_08_edited')
        # Check if the schedule is not marked as done
        schedule = next((s for s in schedules if s["uuid"] == schedule_uuid), None)
        self.assertIsNotNone(schedule)
        self.assertFalse(schedule['done'])

        # Remove the schedule
        self.assertIsNotNone(self.scheduler.remove_schedule(self.address, schedule_uuid))
        # Ensure the schedule is removed
        schedules = self.scheduler.get_schedules(self.address)
        self.assertFalse(any(s["uuid"] == schedule_uuid for s in schedules))


    # Timer tests
    def test_09_edit_timer_settings(self):
        """Test editing timer settings."""
        duration = 1
        action = 'off'
        # Edit the timer settings
        self.scheduler.set_timer_setting(self.address, duration=duration, action=action)
        timer_settings = self.scheduler.get_timer_setting(self.address)
        self.assertIsNotNone(timer_settings)
        self.assertEqual(timer_settings['enabled'], True)
        self.assertEqual(timer_settings['duration'], duration)
        self.assertEqual(timer_settings['action'], action)


    def test_10_activate_timer(self):
        """Test activating the timer."""
        # Set the timer settings
        duration = 1
        action = 'off'
        self.scheduler.set_timer_setting(self.address, duration=duration, action=action)
        setting = self.scheduler.get_timer_setting(self.address)
        self.assertIsNotNone(setting)
        self.assertEqual(setting['enabled'], True)
        self.assertEqual(setting['duration'], duration)
        self.assertEqual(setting['action'], action)
        # Activate the timer
        self.scheduler.update_timer_state(self.address, 'on')
        percentage = self.scheduler.get_timer_remaining_percentage(self.address)
        self.assertIsNotNone(percentage)

        # Wait for 1 minute to check if the timer is activated
        self.clock += datetime.timedelta(minutes=1)
        # Check if the timer is due
        timer_action = self.scheduler.get_timer_action(self.address)
        self.assertEqual(timer_action, action)


    def test_11_deactivate_timer_will_remove_task_from_queue(self):
        """Test deactivating the timer."""
        self.scheduler.enable_timer(self.address)
        self.scheduler.update_timer_state(self.address, 'on')
        percentage = self.scheduler.get_timer_remaining_percentage(self.address)
        self.assertIsNotNone(percentage)
        # Disable the timer
        self.scheduler.disable_timer(self.address)
        # Check if the timer is deactivated
        timer_settings = self.scheduler.get_timer_setting(self.address)
        self.assertIsNotNone(timer_settings)
        self.assertEqual(timer_settings['enabled'], False)
        # Check if the timer task is removed from the queue
        percentage = self.scheduler.get_timer_remaining_percentage(self.address)
        self.assertEqual(percentage, 0)

        # Back to the original state
        self.scheduler.enable_timer(self.address)


    def test_12_edit_timer_will_remove_task_from_queue(self):
        """Test editing timer settings will remove task from due tasks."""
        self.scheduler.set_timer_setting(self.address, duration=1, action='off')
        self.scheduler.update_timer_state(self.address, 'on')
        percentage = self.scheduler.get_timer_remaining_percentage(self.address)
        self.assertIsNotNone(percentage)
        # Edit the timer settings
        self.scheduler.set_timer_setting(self.address, duration=2, action='off')
        # Check if the timer task is removed from the queue
        percentage = self.scheduler.get_timer_remaining_percentage(self.address)
        self.assertEqual(percentage, 0)


    def test_13_timer_task_will_be_removed_if_condition_is_already_met(self):
        """Test if timer task will be removed if condition is already met."""
        # Edit the timer settings
        self.scheduler.set_timer_setting(self.address, duration=1, action='off')
        # Queue in the timer task
        self.scheduler.update_timer_state(self.address, 'on')
        percentage = self.scheduler.get_timer_remaining_percentage(self.address)
        self.assertIsNotNone(percentage)
        self.scheduler.update_timer_state(self.address, 'off')
        percentage = self.scheduler.get_timer_remaining_percentage(self.address)
        self.assertIsNotNone(percentage)


if __name__ == '__main__':
    unittest.main()
