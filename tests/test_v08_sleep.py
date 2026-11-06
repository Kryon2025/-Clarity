"""v0.8 睡眠模式数据与提醒。"""

from __future__ import annotations

import sys
import tempfile
import unittest
from datetime import datetime
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parents[1] / "src"))

from shenqing.services.sleep_mode import (  # noqa: E402
    DEFAULT_UNLOCK_CHANCES,
    LOCK_KIND,
    SleepManager,
    normalize_time,
)


class SleepManagerTest(unittest.TestCase):
    def setUp(self) -> None:
        self._tmp = tempfile.TemporaryDirectory()
        self.path = Path(self._tmp.name) / "sleep.json"
        self.manager = SleepManager(self.path)

    def tearDown(self) -> None:
        self._tmp.cleanup()

    def test_normalize_time(self) -> None:
        self.assertEqual(normalize_time("9:05"), "09:05")
        self.assertEqual(normalize_time("23:59"), "23:59")
        self.assertEqual(normalize_time("24:00"), "")
        self.assertEqual(normalize_time("abc"), "")

    def test_add_remove_schedule(self) -> None:
        new_id = self.manager.add_schedule("23:30")
        self.assertTrue(new_id)
        self.assertEqual(self.manager.schedules()[0]["time"], "23:30")
        self.assertEqual(self.manager.add_schedule("23:30"), "")  # 重复
        self.assertTrue(self.manager.remove_schedule(new_id))
        self.assertEqual(self.manager.schedules(), [])
        self.manager.add_schedule("22:00")
        self.assertTrue(self.manager.remove_schedule("22:00"))
        self.assertFalse(self.manager.remove_schedule("08:00"))

    def test_due_lock_and_fired(self) -> None:
        self.manager.add_schedule("23:30")
        now = datetime(2026, 11, 6, 23, 30, 5)
        due = self.manager.due_lock(now)
        self.assertIsNotNone(due)
        self.manager.mark_fired("2026-11-06", due["time"], LOCK_KIND)
        self.assertIsNone(self.manager.due_lock(now))
        self.assertIsNone(self.manager.due_lock(datetime(2026, 11, 6, 23, 31, 0)))

    def test_reminders(self) -> None:
        self.manager.add_schedule("23:30")
        due = self.manager.due_reminders(datetime(2026, 11, 6, 22, 30, 10))
        self.assertEqual(len(due), 1)
        self.assertEqual(due[0]["offset"], 60)
        self.manager.mark_fired("2026-11-06", "23:30", 60)
        self.assertEqual(self.manager.due_reminders(datetime(2026, 11, 6, 22, 30, 50)), [])
        self.assertTrue(self.manager.reminders_enabled)
        self.manager.set_reminders(False)
        self.assertEqual(self.manager.due_reminders(datetime(2026, 11, 7, 22, 30, 0)), [])

    def test_unlock_chances_and_month_reset(self) -> None:
        self.assertEqual(self.manager.unlock_total, DEFAULT_UNLOCK_CHANCES)
        self.assertEqual(self.manager.unlock_chances, DEFAULT_UNLOCK_CHANCES)
        for index in range(DEFAULT_UNLOCK_CHANCES):
            self.assertTrue(self.manager.try_unlock())
            self.assertEqual(
                self.manager.unlock_chances, DEFAULT_UNLOCK_CHANCES - index - 1
            )
        self.assertFalse(self.manager.try_unlock())
        self.assertIn("本月剩余 0/", self.manager.unlock_chance_label)
        # 模拟跨月：重置已用次数
        self.manager._unlock_month = "2000-01"
        self.assertTrue(self.manager._reset_month_if_needed(datetime(2026, 11, 6, 1, 0)))
        self.assertEqual(self.manager.unlock_chances, DEFAULT_UNLOCK_CHANCES)

    def test_persistence(self) -> None:
        self.manager.add_schedule("21:10")
        self.manager.set_reminders(False)
        self.manager.try_unlock()
        reloaded = SleepManager(self.path)
        self.assertEqual(reloaded.schedule_times(), ["21:10"])
        self.assertFalse(reloaded.reminders_enabled)
        self.assertEqual(reloaded.unlock_chances, DEFAULT_UNLOCK_CHANCES - 1)


if __name__ == "__main__":
    unittest.main()
