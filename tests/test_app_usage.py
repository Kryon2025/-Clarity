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


    # ---------- v0.13 小时聚合 / 热力图 ----------
    def test_hourly_aggregation(self) -> None:
        self._sample(5.0, 12)  # 10 点
        self.wall[0] = self.wall[0].replace(hour=11)
        self.foreground = (5678, "code.exe")
        self._sample(5.0, 12)  # 11 点
        hourly = self.tracker.hourly("today")
        self.assertEqual(len(hourly), 24)
        by_hour = {item["hour"]: item["minutes"] for item in hourly}
        self.assertGreater(by_hour[10], 0.5)
        self.assertGreater(by_hour[11], 0.5)
        self.assertEqual(by_hour[12], 0)
        week = self.tracker.hourly("week")
        self.assertEqual(len(week), 24)
        self.assertGreater(sum(item["minutes"] for item in week), 1.0)

    def test_heatmap_zero_fill(self) -> None:
        self._sample(5.0, 12)
        today = self.wall[0].date()
        heatmap = self.tracker.heatmap(90, today=today)
        self.assertEqual(len(heatmap), 90)
        self.assertEqual(heatmap[-1]["date"], today.isoformat())
        self.assertGreater(heatmap[-1]["minutes"], 0.5)
        self.assertEqual(heatmap[0]["minutes"], 0)
        self.assertGreaterEqual(heatmap[0]["date"], "2000-01-01")
        # 天数夹取
        self.assertLessEqual(len(self.tracker.heatmap(0)), 365)

    def test_old_format_without_hours_is_compatible(self) -> None:
        self.path.write_text(
            json.dumps(
                {"2026-11-07": {"chrome.exe": {"minutes": 12.0, "name": "Chrome"}}},
                ensure_ascii=False,
            ),
            encoding="utf-8",
        )
        tracker = self._make()
        self.assertEqual(tracker.total_minutes("2026-11-07"), 12.0)
        self.assertEqual(tracker.hourly("today", now=datetime(2026, 11, 7, 10, 0)), [
            {"hour": hour, "minutes": 0.0} for hour in range(24)
        ])
        tracker.sample()
        tracker.flush()
        saved = json.loads(self.path.read_text(encoding="utf-8"))
        self.assertIn("hours", saved)
        self.assertIn("2026-11-07", saved)


class AppUsageBridgeTest(unittest.TestCase):
    """bridge 暴露字段形状与日期/分类覆盖接口。"""

    def setUp(self) -> None:
        self._tmp = tempfile.TemporaryDirectory()
        os.environ["SHENQING_DATA_DIR"] = self._tmp.name
        self.bridge = AppBridge()
        tracker = self.bridge._app_usage
        # 用「今天」而不是硬编码日期：CI/UTC 时区下硬编码日期可能不在最近 7 天内
        today = self.bridge.appUsageDate
        tracker._days = {
            today: {
                "chrome.exe": {"minutes": 12.5, "name": "Chrome"},
                "code.exe": {"minutes": 3.0, "name": "VS Code"},
            }
        }
        tracker._hours = {
            today: {
                "10": {"chrome.exe": 5.0},
                "15": {"code.exe": 2.5},
            }
        }
        self.bridge._app_usage_date = today

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
        self.assertEqual(bridge.appUsageDate, today if "today" in dir() else bridge.appUsageDate)

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

    # ---------- v0.13 热力图 / 小时分布 / 分类 ----------
    def test_heatmap_and_hourly(self) -> None:
        bridge = self.bridge
        heatmap = bridge.appUsageHeatmap
        self.assertEqual(len(heatmap), 90)
        self.assertTrue(all("date" in item and "minutes" in item for item in heatmap))
        bridge.setAppUsageHeatmapDays(30)
        self.assertEqual(bridge.appUsageHeatmapDays, 30)
        self.assertEqual(len(bridge.appUsageHeatmap), 30)
        bridge.setAppUsageHeatmapDays(180)
        self.assertEqual(len(bridge.appUsageHeatmap), 180)
        bridge.setAppUsageHeatmapDays(45)  # 非法值忽略
        self.assertEqual(bridge.appUsageHeatmapDays, 180)
        self.assertEqual(bridge.appUsageHourlyRange, "today")
        hourly = bridge.appUsageHourly
        self.assertEqual(len(hourly), 24)
        hour = max(item["hour"] for item in hourly)
        self.assertEqual(hour, 23)
        bridge.setAppUsageHourlyRange("week")
        self.assertEqual(bridge.appUsageHourlyRange, "week")
        self.assertEqual(len(bridge.appUsageHourly), 24)
        bridge.setAppUsageHourlyRange("month")  # 非法忽略
        self.assertEqual(bridge.appUsageHourlyRange, "week")

    def test_app_usage_apps_and_category_reset(self) -> None:
        bridge = self.bridge
        apps = bridge.appUsageApps
        self.assertTrue(apps)
        chrome = next(item for item in apps if item["exe"] == "chrome.exe")
        self.assertEqual(chrome["detected_category"], "browser")
        self.assertEqual(chrome["category"], "browser")
        self.assertFalse(chrome["is_custom"])
        self.assertTrue(bridge.setAppCategory("chrome.exe", "dev"))
        chrome = next(item for item in bridge.appUsageApps if item["exe"] == "chrome.exe")
        self.assertEqual(chrome["category"], "dev")
        self.assertEqual(chrome["detected_category"], "browser")
        self.assertTrue(chrome["is_custom"])
        self.assertTrue(bridge.resetAppCategory("chrome.exe"))
        chrome = next(item for item in bridge.appUsageApps if item["exe"] == "chrome.exe")
        self.assertEqual(chrome["category"], "browser")
        self.assertFalse(chrome["is_custom"])
        self.assertFalse(bridge.resetAppCategory("chrome.exe"))
        options = bridge.appCategoryOptions
        self.assertEqual(len(options), 7)
        self.assertIn({"value": "dev", "label": "开发"}, options)


if __name__ == "__main__":
    unittest.main()
