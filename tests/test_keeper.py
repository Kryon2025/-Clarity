"""保活看门狗基础测试（不真正拉起主程序）。"""

from __future__ import annotations

import os
import sys
import tempfile
import unittest
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parents[1] / "src"))

from shenqing.keeper_worker import is_process_alive  # noqa: E402
from shenqing.services import keeper  # noqa: E402


class KeeperTest(unittest.TestCase):
    def test_process_alive(self) -> None:
        self.assertTrue(is_process_alive(os.getpid()))
        self.assertFalse(is_process_alive(0))
        self.assertFalse(is_process_alive(-1))
        self.assertFalse(is_process_alive(99999999))

    def test_paths_under_data_dir(self) -> None:
        with tempfile.TemporaryDirectory() as tmp:
            old = os.environ.get("SHENQING_DATA_DIR")
            os.environ["SHENQING_DATA_DIR"] = tmp
            try:
                self.assertEqual(keeper.keeper_state_path().parent, Path(tmp))
                self.assertEqual(keeper.keeper_lock_path().name, "keeper.lock")
                self.assertEqual(keeper.keeper_state_path().name, "keeper.json")
            finally:
                if old is None:
                    os.environ.pop("SHENQING_DATA_DIR", None)
                else:
                    os.environ["SHENQING_DATA_DIR"] = old

    def test_main_command_has_run_py(self) -> None:
        command = keeper.main_command()
        self.assertTrue(command)
        if not getattr(sys, "frozen", False):
            self.assertTrue(Path(command[-1]).name == "run.py", command)
            self.assertTrue(Path(command[-1]).exists(), command)

    def test_disabled_by_env(self) -> None:
        with tempfile.TemporaryDirectory() as tmp:
            old_dir = os.environ.get("SHENQING_DATA_DIR")
            old_flag = os.environ.get("SHENQING_NO_KEEPER")
            os.environ["SHENQING_DATA_DIR"] = tmp
            os.environ["SHENQING_NO_KEEPER"] = "1"
            try:
                self.assertFalse(keeper.enabled())
                self.assertFalse(keeper.start_keeper())
                self.assertFalse((Path(tmp) / "keeper.json").exists())
            finally:
                os.environ.pop("SHENQING_NO_KEEPER", None)
                if old_flag is not None:
                    os.environ["SHENQING_NO_KEEPER"] = old_flag
                if old_dir is None:
                    os.environ.pop("SHENQING_DATA_DIR", None)
                else:
                    os.environ["SHENQING_DATA_DIR"] = old_dir


if __name__ == "__main__":
    unittest.main()
