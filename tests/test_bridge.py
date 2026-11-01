"""AppBridge 集成测试：空间 CRUD → 开始会话 → 自然结束 → 统计落盘。"""

from __future__ import annotations

import os
import sys
import tempfile
import unittest
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parents[1] / "src"))

_TMP = tempfile.mkdtemp(prefix="shenqing-test-")
os.environ["SHENQING_DATA_DIR"] = _TMP
os.environ["SHENQING_NO_SCAN"] = "1"
os.environ.setdefault("QT_QPA_PLATFORM", "offscreen")

from PySide6.QtWidgets import QApplication  # noqa: E402

_APP = QApplication.instance() or QApplication([])

from shenqing.bridge.app_bridge import AppBridge  # noqa: E402


class BridgeTest(unittest.TestCase):
    def setUp(self) -> None:
        self.bridge = AppBridge()

    def test_defaults_and_super(self) -> None:
        bridge = self.bridge
        spaces = bridge.spaces
        self.assertEqual(len(spaces), 4)
        self.assertTrue(bridge.superSpaceId)
        super_ids = [s["id"] for s in spaces if s["super"]]
        self.assertEqual(super_ids, [bridge.superSpaceId])
        self.assertEqual(len(bridge.spacesLight), 3)
        self.assertEqual(len(bridge.atmospheres), 4)

    def test_space_crud_and_whitelist(self) -> None:
        bridge = self.bridge
        before = len(bridge.spaces)
        new_id = bridge.spacesNew()
        self.assertEqual(len(bridge.spaces), before + 1)

        bridge.updateSpace(new_id, "阅读", 60, "探索")
        space = next(s for s in bridge.spaces if s["id"] == new_id)
        self.assertEqual(space["name"], "阅读")
        self.assertEqual(space["minutes"], 60)
        self.assertEqual(space["atmosphere"], "探索")

        bridge.toggleSpaceAllowedApp(new_id, "notion.exe", True)
        space = next(s for s in bridge.spaces if s["id"] == new_id)
        self.assertEqual(space["allowedCount"], 1)
        self.assertEqual(space["allowed_apps"], ["notion.exe"])

        bridge.deleteSpace(new_id)
        self.assertNotIn(new_id, [s["id"] for s in bridge.spaces])

    def test_start_and_finish_session(self) -> None:
        bridge = self.bridge
        space = bridge.spaces[0]
        bridge.startSpace(space["id"])
        self.assertIsNotNone(bridge.busy)
        self.assertTrue(bridge.busy)
        self.assertEqual(bridge.activeSpaceId, space["id"])
        self.assertEqual(bridge.activeSpaceName, space["name"])
        self.assertTrue(bridge.superSpaceId == space["id"])  # 超禅 → 重度遮罩
        self.assertTrue(bridge.locked)

        # 直接驱动计时器到点，避免真的等 180 分钟
        for _ in range(bridge.totalSeconds):
            bridge._session._on_timeout()

        self.assertFalse(bridge.busy)
        self.assertEqual(bridge.activeSpaceId, "")
        self.assertGreaterEqual(bridge.todayMinutes, 1.0)
        self.assertGreaterEqual(bridge.sessionCount, 1)

    def test_default_minutes_property(self) -> None:
        self.assertEqual(self.bridge.defaultMinutes, 25)
        self.bridge.setDefaultMinutes(50)
        self.assertEqual(self.bridge.defaultMinutes, 50)

    def test_plugin_manager_wired(self) -> None:
        plugins = self.bridge.plugins
        self.assertIsInstance(plugins, list)
        for plugin in plugins:
            self.assertIn("id", plugin)
            self.assertIn("enabled", plugin)
        # 未知插件不应该抛异常
        self.bridge.setPluginEnabled("not.exist", False)
        self.bridge.restartPlugins()


if __name__ == "__main__":
    unittest.main()
