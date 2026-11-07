"""v0.12 UI 字号 / 字体 / 导航模式设置测试。"""

from __future__ import annotations

import json
import os
import sys
import tempfile
import unittest
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parents[1] / "src"))

os.environ.setdefault("QT_QPA_PLATFORM", "offscreen")
os.environ["SHENQING_NO_SCAN"] = "1"
os.environ["SHENQING_NO_KEEPER"] = "1"

from PySide6.QtWidgets import QApplication  # noqa: E402

_APP = QApplication.instance() or QApplication([])

from shenqing.bridge.app_bridge import AppBridge  # noqa: E402


class UISettingsBridgeTest(unittest.TestCase):
    def setUp(self) -> None:
        self._tmp = tempfile.TemporaryDirectory()
        os.environ["SHENQING_DATA_DIR"] = self._tmp.name
        self.bridge = AppBridge()
        self.toasts: list[str] = []
        self.bridge.toast.connect(self.toasts.append)

    def tearDown(self) -> None:
        self.bridge._shutdown_services()
        try:
            self.bridge.deleteLater()
        except RuntimeError:
            pass
        self._tmp.cleanup()
        os.environ.pop("SHENQING_DATA_DIR", None)

    def _reload(self) -> AppBridge:
        try:
            self.bridge._shutdown_services()
            self.bridge.deleteLater()
        except RuntimeError:
            pass
        self.bridge = AppBridge()
        return self.bridge

    def test_font_families(self) -> None:
        families = self.bridge.uiFontFamilies
        self.assertIsInstance(families, list)
        self.assertGreater(len(families), 0)
        self.assertLessEqual(len(families), 200)
        self.assertEqual(families, sorted(families))
        self.assertTrue(all(not family.startswith("@") for family in families))
        self.assertTrue(self.bridge.defaultFontFamily)

    def test_font_family_setting_persists(self) -> None:
        self.assertEqual(self.bridge.uiFontFamily, "")
        self.bridge.setUIFontFamily("  微软雅黑  ")
        self.assertEqual(self.bridge.uiFontFamily, "微软雅黑")
        bridge = self._reload()
        self.assertEqual(bridge.uiFontFamily, "微软雅黑")
        bridge.setUIFontFamily("")
        self.assertEqual(bridge.uiFontFamily, "")

    def test_font_scale_clamp_and_round(self) -> None:
        bridge = self.bridge
        self.assertAlmostEqual(bridge.uiFontScale, 1.0)
        cases = {
            0.5: 0.8,
            1.5: 1.4,
            1.44: 1.45 if False else 1.45,
            0.83: 0.85,
            1.03: 1.05,
            0.8: 0.8,
            1.4: 1.4,
        }
        # 1.44 夹到 1.4 后再按 0.05 吸附 => 1.4
        cases[1.44] = 1.4
        for raw, expected in cases.items():
            bridge.setUIFontScale(raw)
            self.assertAlmostEqual(bridge.uiFontScale, expected)
        bridge.setUIFontScale(1.15)
        self.assertAlmostEqual(bridge.uiFontScale, 1.15)
        self.assertEqual(bridge.uiFontScaleOptions, [0.85, 1.0, 1.15, 1.3])
        reloaded = self._reload()
        self.assertAlmostEqual(reloaded.uiFontScale, 1.15)

    def test_nav_mode_validation_and_persistence(self) -> None:
        bridge = self.bridge
        self.assertEqual(bridge.navMode, "expanded")
        for value in ("auto", "expanded", "icons", "custom"):
            bridge.setNavMode(value)
            self.assertEqual(bridge.navMode, value)
        bridge.setNavMode("icons")
        bridge.setNavMode("nope")
        self.assertEqual(bridge.navMode, "icons")
        bridge.setUIFontScale(1.15)
        reloaded = self._reload()
        self.assertEqual(reloaded.navMode, "icons")
        # 持久化到 settings.json
        path = Path(self._tmp.name) / "settings.json"
        saved = json.loads(path.read_text(encoding="utf-8"))
        self.assertEqual(saved["nav_mode"], "icons")
        self.assertAlmostEqual(saved["ui_font_scale"], 1.15, places=2)

    def test_settings_notify(self) -> None:
        changes: list[int] = []
        self.bridge.settingsChanged.connect(lambda: changes.append(1))
        self.bridge.setUIFontFamily("Arial")
        self.bridge.setUIFontScale(1.1)
        self.bridge.setNavMode("auto")
        self.assertGreaterEqual(len(changes), 3)


if __name__ == "__main__":
    unittest.main()
