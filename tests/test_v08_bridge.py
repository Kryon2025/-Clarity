"""v0.8 bridge：睡眠/系统/壁纸/结束卡片/速启跳转/防休眠等接口。"""

from __future__ import annotations

import os
import sys
import tempfile
import unittest
from datetime import datetime, timedelta
from pathlib import Path
from unittest import mock

sys.path.insert(0, str(Path(__file__).resolve().parents[1] / "src"))

os.environ.setdefault("QT_QPA_PLATFORM", "offscreen")
os.environ["SHENQING_NO_SCAN"] = "1"

from PySide6.QtWidgets import QApplication  # noqa: E402

_APP = QApplication.instance() or QApplication([])

from shenqing.bridge import app_bridge as bridge_module  # noqa: E402
from shenqing.bridge.app_bridge import AppBridge  # noqa: E402
from shenqing.services import sleep_mode, timesync  # noqa: E402


class BridgeV08Test(unittest.TestCase):
    def setUp(self) -> None:
        self._tmp = tempfile.TemporaryDirectory()
        os.environ["SHENQING_DATA_DIR"] = self._tmp.name
        self.bridge = AppBridge()
        self.toasts: list[str] = []
        self.bridge.toast.connect(self.toasts.append)

    def tearDown(self) -> None:
        try:
            self.bridge._session.stop()
        except Exception:  # noqa: BLE001
            pass
        try:
            self.bridge.deleteLater()
        except RuntimeError:
            pass
        self._tmp.cleanup()
        os.environ.pop("SHENQING_DATA_DIR", None)

    def _start_medium(self, minutes: int = 2) -> None:
        space = next(s for s in self.bridge.spaces if s["mode"] == "medium")
        self.bridge._begin_space_session(space, "medium", minutes)

    # ---------- 默认 / 卡片 ----------
    def test_new_properties(self) -> None:
        bridge = self.bridge
        self.assertIsInstance(bridge.dailyQuote, str)
        self.assertEqual(bridge.lastSession, {})
        card = bridge.todayFocusCard
        self.assertEqual(card["sessions"], 0)
        self.assertIn("date", card)
        self.assertFalse(bridge.onboardingDone)
        bridge.setOnboardingDone(True)
        self.assertTrue(bridge.onboardingDone)
        self.assertIsInstance(bridge.overlayWidgets, list)
        self.assertFalse(bridge.aiConfigured)
        self.assertEqual(bridge.sleepSchedules, [])
        self.assertIsInstance(bridge.systemVolume, int)

    def test_last_session_and_focus_card_after_session(self) -> None:
        bridge = self.bridge
        self._start_medium(1)
        for _ in range(bridge.totalSeconds):
            bridge._session._on_timeout()
        self.assertFalse(bridge.busy)
        last = bridge.lastSession
        self.assertGreaterEqual(last["minutes"], 1)
        self.assertEqual(last["level"], "medium")
        self.assertTrue(last["startMs"] > 0)
        self.assertGreaterEqual(last["endMs"], last["startMs"])
        self.assertTrue(last["quote"])
        self.assertEqual(bridge.todaySessions, 1)
        card = bridge.todayFocusCard
        self.assertEqual(card["sessions"], 1)
        self.assertGreaterEqual(card["minutes"], 1)
        self.assertTrue(card["timeRange"])
        text = bridge.shareSummary()
        self.assertIn("深清", text)

    def test_extend_session(self) -> None:
        bridge = self.bridge
        self._start_medium(2)
        before = bridge.totalSeconds
        self.assertTrue(bridge.extendSession(20))
        self.assertEqual(bridge.totalSeconds, before + 20 * 60)
        self.assertFalse(bridge.extendSession(20) is False)  # 仍在运行可继续延长
        bridge._session.stop()

    def test_stats_use_network_calibrated_time(self) -> None:
        bridge = self.bridge
        fake_now = datetime(2030, 1, 2, 10, 0, 0)
        with mock.patch.object(timesync, "now", return_value=fake_now):
            self._start_medium(1)
            for _ in range(bridge.totalSeconds):
                bridge._session._on_timeout()
            self.assertEqual(bridge.todaySessions, 1)
            card = bridge.todayFocusCard
            self.assertEqual(card["date"], "2030-01-02")
            self.assertGreater(bridge.todayMinutes, 0)
            last = bridge.lastSession
            self.assertEqual(
                datetime.fromtimestamp(last["startMs"] / 1000).date().isoformat(),
                "2030-01-02",
            )

    def test_recent_sessions_and_countdown(self) -> None:
        bridge = self.bridge
        self._start_medium(1)
        for _ in range(bridge.totalSeconds):
            bridge._session._on_timeout()
        sessions = bridge.recentSessions
        self.assertEqual(len(sessions), 1)
        self.assertEqual(sessions[0]["level"], "medium")
        self.assertGreaterEqual(sessions[0]["minutes"], 1)
        self.assertTrue(sessions[0]["startMs"] > 0)
        self.bridge.setCountdownDate("2030-01-10")
        with mock.patch.object(timesync, "today", return_value=datetime(2030, 1, 2).date()):
            self.assertEqual(bridge.countdownDays, 8)
        self.bridge.setOnboardingDone(True)
        self.bridge.setOverlayWidgetOrder(["com.shenqing.focus_stats:main"])
        self.assertEqual(
            bridge.overlayWidgetOrder, ["com.shenqing.focus_stats:main"]
        )

    # ---------- 速启跳转 ----------
    def test_open_spaces_page(self) -> None:
        seen_main: list[int] = []
        seen_mode: list[str] = []
        self.bridge.showMainRequested.connect(lambda: seen_main.append(1))
        self.bridge.spacesPageRequested.connect(seen_mode.append)
        self.bridge.openSpacesPage("light")
        self.assertEqual(seen_main, [1])
        self.assertEqual(seen_mode, ["light"])
        self.bridge.openSpacesPage("nope")
        self.assertEqual(seen_mode[-1], "")

    # ---------- 防休眠 / 音量 / 电源 ----------
    def test_power_keep_awake_on_session(self) -> None:
        bridge = self.bridge
        with (
            mock.patch.object(bridge_module.power, "keep_awake") as keep,
            mock.patch.object(bridge_module.power, "allow_sleep") as allow,
        ):
            self._start_medium(1)
            self.assertTrue(keep.called)
            bridge._session.stop()
            self.assertTrue(allow.called)

    def test_system_volume_and_power(self) -> None:
        bridge = self.bridge
        with mock.patch.object(bridge_module.system_control, "get_volume", return_value=37):
            bridge._volume = -1
            self.assertEqual(bridge.systemVolume, 37)
        with mock.patch.object(
            bridge_module.system_control, "set_volume", return_value=True
        ) as setter:
            bridge.setSystemVolume(120)
            self.assertEqual(setter.call_args[0][0], 100)
            self.assertEqual(self.bridge.systemVolume, 100)
        with mock.patch.object(
            bridge_module.system_control, "power_action", return_value=True
        ) as action:
            bridge.systemPower("shutdown")
            action.assert_called_once_with("shutdown")
        self.assertTrue(any("关机" in t for t in self.toasts))

    # ---------- 睡眠模式 ----------
    def test_sleep_schedule_api(self) -> None:
        bridge = self.bridge
        new_id = bridge.addSleepSchedule("23:30")
        self.assertTrue(new_id)
        self.assertEqual(bridge.sleepSchedules, ["23:30"])
        self.assertTrue(bridge.sleepRemindersEnabled)
        bridge.setSleepReminders(False)
        self.assertFalse(bridge.sleepRemindersEnabled)
        self.assertTrue(bridge.removeSleepSchedule(new_id))
        self.assertEqual(bridge.sleepSchedules, [])

    def test_sleep_auto_lock_and_unlock(self) -> None:
        bridge = self.bridge
        bridge.addSleepSchedule("23:30")
        fake_now = datetime(2026, 11, 6, 23, 30, 10)
        with (
            mock.patch.object(timesync, "now", return_value=fake_now),
            mock.patch.object(bridge, "notify"),
        ):
            bridge._tick_sleep()
        self.assertTrue(bridge.busy)
        self.assertEqual(bridge.sessionLevel, "heavy")
        self.assertTrue(bridge._sleep_lock_active)
        chances = bridge.unlockChances
        # 连续点 10 次时钟 → 解锁并结束睡眠锁定
        for _ in range(10):
            result = bridge.clickClockForUnlock()
        self.assertTrue(result)
        self.assertFalse(bridge.busy)
        self.assertEqual(bridge.unlockChances, chances - 1)
        self.assertFalse(bridge._sleep_lock_active)

    def test_sleep_reminder_notified_once(self) -> None:
        bridge = self.bridge
        bridge.addSleepSchedule("23:30")
        fake_now = datetime(2026, 11, 6, 22, 30, 5)
        with (
            mock.patch.object(timesync, "now", return_value=fake_now),
            mock.patch.object(bridge, "notify") as notify,
        ):
            bridge._tick_sleep()
            bridge._tick_sleep()
        self.assertEqual(notify.call_count, 1)

    def test_clock_unlock_without_chance(self) -> None:
        bridge = self.bridge
        bridge._sleep_lock_active = True
        bridge._sleep._unlock_used = bridge._sleep.unlock_total
        for _ in range(10):
            result = bridge.clickClockForUnlock()
        self.assertFalse(result)
        self.assertTrue(any("解锁机会已用完" in t for t in self.toasts))


if __name__ == "__main__":
    unittest.main()
