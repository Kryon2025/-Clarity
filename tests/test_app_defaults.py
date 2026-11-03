"""app.py 引导逻辑测试：首次运行默认最高权限（不启动界面/UAC）。"""

from __future__ import annotations

import os
import sys
import tempfile
import unittest
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parents[1] / "src"))

os.environ.setdefault("QT_QPA_PLATFORM", "offscreen")
os.environ.setdefault("QT_QUICK_BACKEND", "software")

from shenqing.app import _apply_first_run_defaults  # noqa: E402
from shenqing.settings import Settings  # noqa: E402


class FirstRunDefaultsTest(unittest.TestCase):
    def test_first_run_defaults_to_admin(self) -> None:
        with tempfile.TemporaryDirectory() as tmp:
            path = Path(tmp) / "settings.json"
            settings = Settings(path)
            self.assertTrue(settings.is_new)
            self.assertFalse(settings.get("admin_mode", False))
            self.assertTrue(_apply_first_run_defaults(settings))
            self.assertTrue(settings.get("admin_mode"))
            self.assertTrue(settings.get("elevated_bootstrap"))
            # 已落盘，第二次启动不再是首次运行、不覆盖用户选择
            reloaded = Settings(path)
            self.assertFalse(reloaded.is_new)
            self.assertFalse(_apply_first_run_defaults(reloaded))
            self.assertTrue(reloaded.get("admin_mode"))

    def test_existing_user_choice_kept(self) -> None:
        with tempfile.TemporaryDirectory() as tmp:
            path = Path(tmp) / "settings.json"
            Settings(path).set("admin_mode", False)
            settings = Settings(path)
            self.assertFalse(_apply_first_run_defaults(settings))
            self.assertFalse(settings.get("admin_mode"))


if __name__ == "__main__":
    unittest.main()
