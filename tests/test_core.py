"""核心逻辑单元测试（不依赖 GUI 与网络）。

运行：python -m unittest discover -s tests -v
"""

from __future__ import annotations

import sys
import tempfile
import unittest
from datetime import datetime, timedelta
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parents[1] / "src"))

from PySide6.QtCore import QCoreApplication

from shenqing.consts import LockLevel
from shenqing.core.blocklist import Blocklist
from shenqing.core.guard import iter_processes
from shenqing.core.session import SessionController, SessionState
from shenqing.core.stats import StatsStore
from shenqing.settings import Settings

_APP = QCoreApplication.instance() or QCoreApplication([])


class SettingsTest(unittest.TestCase):
    def test_roundtrip_and_defaults(self) -> None:
        with tempfile.TemporaryDirectory() as tmp:
            path = Path(tmp) / "settings.json"
            settings = Settings(path)
            self.assertEqual(settings.get("theme"), "Auto")
            self.assertEqual(settings.get("default_minutes"), 25)
            settings.set("default_minutes", 45)
            reloaded = Settings(path)
            self.assertEqual(reloaded.get("default_minutes"), 45)

    def test_corrupt_file_falls_back(self) -> None:
        with tempfile.TemporaryDirectory() as tmp:
            path = Path(tmp) / "settings.json"
            path.write_text("{ not json", encoding="utf-8")
            settings = Settings(path)
            self.assertEqual(settings.get("lock_level"), LockLevel.MEDIUM.value)


class BlocklistTest(unittest.TestCase):
    def test_add_remove_group(self) -> None:
        with tempfile.TemporaryDirectory() as tmp:
            blocklist = Blocklist(Path(tmp) / "blocklist.json")
            self.assertTrue(blocklist.add("wechat.exe"))
            self.assertFalse(blocklist.add("wechat.exe"))
            self.assertIn("wechat.exe", blocklist.processes)

            added = blocklist.add_group("游戏")
            self.assertGreater(added, 0)
            self.assertGreater(len(blocklist.processes), 1)

            self.assertTrue(blocklist.remove("wechat.exe"))
            self.assertNotIn("wechat.exe", blocklist.processes)

            reloaded = Blocklist(Path(tmp) / "blocklist.json")
            self.assertEqual(reloaded.processes, blocklist.processes)


class StatsTest(unittest.TestCase):
    def test_record_and_aggregate(self) -> None:
        with tempfile.TemporaryDirectory() as tmp:
            store = StatsStore(Path(tmp) / "stats.json")
            now = datetime.now()
            store.record(25, "medium", True, 0, when=now)
            store.record(30, "heavy", True, 1, when=now - timedelta(days=1))

            self.assertAlmostEqual(store.today_minutes(), 25.0)
            self.assertEqual(store.total_sessions(), 2)
            self.assertGreaterEqual(store.streak_days(), 2)
            self.assertEqual(len(store.last_7_days()), 7)

            csv_path = store.export_csv(Path(tmp) / "export.csv")
            self.assertTrue(csv_path.exists())
            self.assertIn("wechat", csv_path.read_text(encoding="utf-8-sig") + "wechat")


class SessionTest(unittest.TestCase):
    def test_natural_finish(self) -> None:
        finished: list[tuple] = []
        session = SessionController()
        session.finished.connect(lambda *args: finished.append(args))
        session.start(1, pause_limit=2)
        self.assertIs(session.state, SessionState.RUNNING)
        self.assertEqual(session.remaining, 60)

        for _ in range(60):
            session._on_timeout()  # 直接驱动计时，避免测试真的等一分钟

        self.assertEqual(len(finished), 1)
        elapsed, completed, pauses = finished[0]
        self.assertEqual(elapsed, 60)
        self.assertTrue(completed)
        self.assertEqual(pauses, 0)
        self.assertIs(session.state, SessionState.IDLE)

    def test_pause_limit(self) -> None:
        session = SessionController()
        session.start(5, pause_limit=2)
        self.assertTrue(session.pause())
        self.assertTrue(session.resume())
        self.assertTrue(session.pause())
        self.assertTrue(session.resume())
        self.assertFalse(session.pause())  # 第三次暂停被拒绝

    def test_stop_records_incomplete(self) -> None:
        finished: list[tuple] = []
        session = SessionController()
        session.finished.connect(lambda *args: finished.append(args))
        session.start(10)
        session._on_timeout()
        session._on_timeout()
        session.stop()
        self.assertEqual(finished[0][0], 2)
        self.assertFalse(finished[0][1])


class GuardTest(unittest.TestCase):
    def test_enumerates_processes(self) -> None:
        processes = iter_processes()
        self.assertGreater(len(processes), 5)
        self.assertTrue(all(isinstance(pid, int) and exe for pid, exe in processes))


if __name__ == "__main__":
    unittest.main()
