"""v0.8 时间：HTTP Date 解析 / 网络偏移缓存 / monotonic 会话计时。"""

from __future__ import annotations

import os
import sys
import tempfile
import time
import unittest
from datetime import datetime, timedelta
from pathlib import Path
from unittest import mock

sys.path.insert(0, str(Path(__file__).resolve().parents[1] / "src"))

os.environ.setdefault("QT_QPA_PLATFORM", "offscreen")

from PySide6.QtCore import QCoreApplication  # noqa: E402

_APP = QCoreApplication.instance() or QCoreApplication([])

from shenqing.core.session import SessionController, SessionState  # noqa: E402
from shenqing.services import timesync  # noqa: E402


class TimeSyncTest(unittest.TestCase):
    def test_parse_http_date(self) -> None:
        stamp = timesync._parse_http_date("Wed, 06 Nov 2026 15:00:00 GMT")
        self.assertIsNotNone(stamp)
        self.assertEqual(int(stamp), 1793977200)
        self.assertIsNone(timesync._parse_http_date("not a date"))
        self.assertIsNone(timesync._parse_http_date(""))

    def test_sync_and_cache(self) -> None:
        with tempfile.TemporaryDirectory() as tmp:
            old = os.environ.get("SHENQING_DATA_DIR")
            os.environ["SHENQING_DATA_DIR"] = tmp
            try:
                with mock.patch.object(
                    timesync, "_fetch_offset", return_value=(120.5, "https://api.github.com")
                ):
                    self.assertTrue(timesync.sync_now())
                self.assertAlmostEqual(timesync.offset_seconds(), 120.5)
                self.assertTrue(timesync.synced())
                self.assertEqual(timesync.source(), "https://api.github.com")
                cache = Path(tmp) / timesync.CACHE_NAME
                self.assertTrue(cache.exists())
                # now() 使用偏移
                self.assertAlmostEqual(timesync.now().timestamp(), time.time() + 120.5, delta=2)
            finally:
                if old is None:
                    os.environ.pop("SHENQING_DATA_DIR", None)
                else:
                    os.environ["SHENQING_DATA_DIR"] = old

    def test_sync_failure_keeps_previous(self) -> None:
        with tempfile.TemporaryDirectory() as tmp:
            old = os.environ.get("SHENQING_DATA_DIR")
            os.environ["SHENQING_DATA_DIR"] = tmp
            try:
                with mock.patch.object(timesync, "_fetch_offset", return_value=None):
                    self.assertFalse(timesync.sync_now())
            finally:
                if old is None:
                    os.environ.pop("SHENQING_DATA_DIR", None)
                else:
                    os.environ["SHENQING_DATA_DIR"] = old


class MonotonicSessionTest(unittest.TestCase):
    def test_sleep_skips_to_finish(self) -> None:
        clock = [1000.0]
        finished: list[tuple] = []
        with mock.patch("shenqing.core.session.time.monotonic", lambda: clock[0]):
            session = SessionController()
            session.finished.connect(lambda *args: finished.append(args))
            session.start(30)
            self.assertEqual(session.remaining, 1800)
            clock[0] += 3600  # 电脑休眠 1 小时
            session._on_timeout()
        self.assertEqual(len(finished), 1)
        elapsed, completed, _pauses = finished[0]
        self.assertEqual(elapsed, 1800)
        self.assertTrue(completed)
        self.assertIs(session.state, SessionState.IDLE)

    def test_manual_ticks_still_countdown(self) -> None:
        session = SessionController()
        finished: list[tuple] = []
        session.finished.connect(lambda *args: finished.append(args))
        session.start(1)
        for _ in range(60):
            session._on_timeout()
        self.assertTrue(finished)
        self.assertEqual(finished[0][0], 60)

    def test_extend(self) -> None:
        session = SessionController()
        session.start(1)
        self.assertTrue(session.extend(20))
        self.assertEqual(session.total, 21 * 60)
        self.assertEqual(session.remaining, 21 * 60)
        session.stop()
        self.assertFalse(session.extend(5))


if __name__ == "__main__":
    unittest.main()
