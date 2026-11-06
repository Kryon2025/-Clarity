"""v0.9 应用使用时长统计：累计/空闲/休眠/日期切换/分类颜色/持久化。"""

from __future__ import annotations

import json
import os
import sys
import tempfile
import unittest
from datetime import datetime, timedelta
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parents[1] / "src"))

os.environ.setdefault("QT_QPA_PLATFORM", "offscreen")
os.environ["SHENQING_NO_SCAN"] = "1"

from PySide6.QtWidgets import QApplication  # noqa: E402

_APP = QApplication.instance() or QApplication([])

from shenqing.services import app_usage  # noqa: E402
from shenqing.bridge.app_bridge import AppBridge  # noqa: E402


class _Clock:
    def __init__(self, value: float = 100.0) -> None:
        self.value = value


class AppUsageTrackerTest(unittest.TestCase):
    def setUp(self) -> None:
        self._tmp = tempfile.TemporaryDirectory()
        self.path = Path(self._tmp.name) / "app_usage.json"
        self.clock = _Clock()
        self.wall = [datetime(2026, 11, 7, 10, 0, 0)]
        self.foreground = (1234, "chrome.exe")
        self.idle = 0
        self.locked = False
        self.tracker = self._make()

    def tearDown(self) -> None:
        self.tracker.shutdown()
        self._tmp.cleanup()

    def _make(self) -> app_usage.AppUsageTracker:
        return app_usage.AppUsageTracker(
            self.path,
            clock=lambda: self.clock.value,
            now_provider=lambda: self.wall[0],
            foreground_provider=lambda: self.foreground,
            idle_provider=lambda: self.idle,
            locked_provider=lambda: self.locked,
        )

    def _sample(self, seconds: float = 5.0, count: int = 1) -> None:
        for _ in range(count):
            self.clock.value += seconds
            self.tracker.sample()

    def _day(self) -> str:
        return self.wall[0].date().isoformat()

    def test_accumulates_foreground_minutes(self) -> None:
        self._sample(5.0, 12)  # 60 秒
        items = self.tracker.usage_for(self._day())
        self.assertEqual(len(items), 1)
        item = items[0]
        self.assertEqual(item["exe"], "chrome.exe")
        self.assertEqual(item["name"], "Chrome")
        self.assertAlmostEqual(item["minutes"], 1.0, delta=0.05)
        self.assertEqual(item["category"], "browser")
        self.assertTrue(item["color"].startswith("#"))
        self.assertAlmostEqual(self.tracker.total_minutes(self._day()), 1.0, delta=0.1)
        categories = self.tracker.category_totals(self._day())
        self.assertEqual(categories[0]["category"], "browser")
        self.assertEqual(categories[0]["name"], "浏览器")

    def test_idle_pauses_accumulation(self) -> None:
        self._sample(5.0, 12)
        before = self.tracker.total_minutes(self._day())
        self.idle = app_usage.IDLE_LIMIT_MS + 1
        self._sample(5.0, 12)
        self.assertAlmostEqual(self.tracker.total_minutes(self._day()), before, delta=0.01)

    def test_sleep_gap_is_discarded(self) -> None:
        self._sample(5.0, 2)
        before = self.tracker.total_minutes(self._day())
        self.clock.value += 3600  # 休眠 1 小时
        self.tracker.sample()
        self.assertAlmostEqual(self.tracker.total_minutes(self._day()), before, delta=0.01)

    def test_own_process_not_counted(self) -> None:
        self.foreground = (os.getpid(), "python.exe")
        self._sample(5.0, 12)
        self.assertEqual(self.tracker.usage_for(self._day()), [])
        self.foreground = (4321, "shenqing.exe")
        self._sample(5.0, 12)
        self.assertEqual(self.tracker.usage_for(self._day()), [])

    def test_locked_screen_pauses(self) -> None:
        self.locked = True
        self._sample(5.0, 12)
        self.assertEqual(self.tracker.usage_for(self._day()), [])

    def test_date_switch_and_persistence(self) -> None:
        self._sample(5.0, 12)
        self.tracker.flush()
        saved = json.loads(self.path.read_text(encoding="utf-8"))
        self.assertIn(self._day(), saved)
        self.assertIn("chrome.exe", saved[self._day()])
        self.assertEqual(set(saved[self._day()]["chrome.exe"]), {"minutes", "name"})
        # 切到第二天：旧数据落盘，新数据独立
        self.wall[0] = self.wall[0] + timedelta(days=1)
        self.foreground = (5678, "code.exe")
        self._sample(5.0, 12)
        self.tracker.flush()
        reloaded = self._make()
        try:
            self.assertEqual(reloaded.usage_for("2026-11-07")[0]["exe"], "chrome.exe")
            self.assertEqual(reloaded.usage_for("2026-11-08")[0]["exe"], "code.exe")
        finally:
            reloaded.shutdown()

    def test_week_usage(self) -> None:
        self._sample(5.0, 12)
        self.wall[0] = self.wall[0] + timedelta(days=2)
        self.foreground = (999, "wechat.exe")
        self._sample(5.0, 12)
        week = self.tracker.week_usage()
        exes = {item["exe"]: item["minutes"] for item in week}
        self.assertIn("chrome.exe", exes)
        self.assertIn("wechat.exe", exes)
        self.assertEqual(week[0]["minutes"], max(exes.values()))

    def test_category_and_color_overrides(self) -> None:
        self._sample(5.0, 12)
        self.assertTrue(self.tracker.set_category("chrome.exe", "dev"))
        self.assertEqual(self.tracker.category_for("chrome.exe"), "dev")
        self.assertTrue(self.tracker.set_color("chrome.exe", "#123456"))
        self.assertEqual(self.tracker.color_for("chrome.exe"), "#123456")
        self.assertFalse(self.tracker.set_category("chrome.exe", "nope"))
        self.assertFalse(self.tracker.set_color("chrome.exe", "red"))
        # 标签也接受
        self.assertTrue(self.tracker.set_category("chrome.exe", "学习"))
        self.assertEqual(self.tracker.category_for("chrome.exe"), "study")
        reloaded = self._make()
        try:
            self.assertEqual(reloaded.category_for("chrome.exe"), "study")
            self.assertEqual(reloaded.color_for("chrome.exe"), "#123456")
        finally:
            reloaded.shutdown()


class AppUsageBridgeTest(unittest.TestCase):
    """bridge 暴露字段形状与日期/分类覆盖接口。"""

    def setUp(self) -> None:
        self._tmp = tempfile.TemporaryDirectory()
        os.environ["SHENQING_DATA_DIR"] = self._tmp.name
        self.bridge = AppBridge()
        tracker = self.bridge._app_usage
        tracker._days = {
            "2026-11-07": {
                "chrome.exe": {"minutes": 12.5, "name": "Chrome"},
                "code.exe": {"minutes": 3.0, "name": "VS Code"},
            }
        }
        self.bridge._app_usage_date = "2026-11-07"

    def tearDown(self) -> None:
        self.bridge._shutdown_services()
        try:
            self.bridge.deleteLater()
        except RuntimeError:
            pass
        self._tmp.cleanup()
        os.environ.pop("SHENQING_DATA_DIR", None)

    def test_properties_shape(self) -> None:
        bridge = self.bridge
        items = bridge.appUsageToday
        self.assertEqual(items[0]["exe"], "chrome.exe")
        self.assertEqual(items[0]["name"], "Chrome")
        self.assertGreater(items[0]["minutes"], 0)
        self.assertTrue(items[0]["color"].startswith("#"))
        self.assertIn("category", items[0])
        self.assertEqual(bridge.appUsageTotalMinutes, 16)
        self.assertGreater(len(bridge.appUsageWeek), 0)
        categories = bridge.appCategories
        self.assertEqual(categories[0]["name"], "浏览器")
        self.assertIn("category", categories[0])
        self.assertEqual(bridge.appUsageDate, "2026-11-07")

    def test_set_date_and_overrides(self) -> None:
        bridge = self.bridge
        bridge.setAppUsageDate("2026-11-01")
        self.assertEqual(bridge.appUsageDate, "2026-11-01")
        self.assertEqual(bridge.appUsageToday, [])
        self.assertTrue(bridge.setAppCategory("chrome.exe", "dev"))
        self.assertEqual(bridge._app_usage.category_for("chrome.exe"), "dev")
        self.assertTrue(bridge.setAppColor("chrome.exe", "#112233"))
        self.assertEqual(bridge._app_usage.color_for("chrome.exe"), "#112233")
        self.assertFalse(bridge.setAppCategory("chrome.exe", "unknown"))


if __name__ == "__main__":
    unittest.main()
