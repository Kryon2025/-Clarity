"""覆清 dock 显示控制器测试（不真正拉起窗口，只测安全逻辑与 Win32 工具）。"""

from __future__ import annotations

import os
import sys
import unittest
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parents[1] / "src"))

os.environ.setdefault("QT_QPA_PLATFORM", "offscreen")
os.environ.setdefault("QT_QUICK_BACKEND", "software")

from PySide6.QtCore import Qt  # noqa: E402
from PySide6.QtGui import QWindow  # noqa: E402
from PySide6.QtWidgets import QApplication  # noqa: E402

_APP = QApplication.instance() or QApplication([])

from shenqing.services.dock_reveal import (  # noqa: E402
    DockRevealController,
    exe_basename,
    foreground_exe,
    is_topmost,
    set_topmost,
    window_exe,
    window_ids_for_exe,
)


class _FakeBridge:
    def __init__(
        self,
        busy: bool = True,
        level: str = "medium",
        whitelist: list[str] | None = None,
    ) -> None:
        self.busy = busy
        self.sessionLevel = level
        self.sessionWhitelist = list(whitelist or [])
        self.topmost_calls: list[bool] = []

    def setOverlayTopmostEnabled(self, enabled: bool) -> None:
        self.topmost_calls.append(bool(enabled))


class DockRevealHelpersTest(unittest.TestCase):
    def test_exe_basename(self) -> None:
        self.assertEqual(exe_basename("C:\\Windows\\System32\\Notepad.EXE"), "notepad.exe")
        self.assertEqual(exe_basename('"C:\\Apps\\charmap.exe"'), "charmap.exe")
        self.assertEqual(exe_basename("charmap.exe"), "charmap.exe")
        self.assertEqual(exe_basename(""), "")
        self.assertEqual(exe_basename(None), "")

    def test_win32_helpers_degrade_gracefully(self) -> None:
        self.assertEqual(window_ids_for_exe("definitely-not-running-xyz.exe"), [])
        self.assertFalse(is_topmost(0))
        self.assertFalse(set_topmost(0, True))
        self.assertEqual(window_exe(0), "")
        self.assertIsInstance(foreground_exe(), str)


class DockRevealControllerTest(unittest.TestCase):
    def test_not_eligible_does_nothing(self) -> None:
        controller = DockRevealController(_FakeBridge(busy=False))
        controller.handle_app_launched("notepad.exe")
        self.assertFalse(controller._watch_timer.isActive())
        self.assertFalse(controller._activate_timer.isActive())
        controller.restore()
        controller.sync_session()

        light = DockRevealController(_FakeBridge(level="light"))
        light.handle_app_launched("notepad.exe")
        self.assertFalse(light._watch_timer.isActive())
        self.assertFalse(light._activate_timer.isActive())

    def test_medium_without_overlay_is_safe(self) -> None:
        controller = DockRevealController(
            _FakeBridge(level="medium", whitelist=["notepad.exe"])
        )
        # 离屏测试没有真实 LockOverlay 顶层窗口：应安全跳过，不抛异常
        controller.handle_app_launched("notepad.exe")
        self.assertFalse(controller._watch_timer.isActive())
        controller.restore()
        self.assertFalse(controller._watch_timer.isActive())

    def test_sync_session_restore(self) -> None:
        controller = DockRevealController(_FakeBridge(busy=True))
        controller.sync_session()  # eligible，不应报错
        controller.sync_session()
        controller.restore()


class DockRevealOverlayTest(unittest.TestCase):
    """用离屏 QWindow 冒充 LockOverlay，验证 hide()/show() 行为。"""

    def setUp(self) -> None:
        self.overlay = QWindow()
        self.overlay.setObjectName("LockOverlay")
        self.overlay.setFlags(Qt.FramelessWindowHint | Qt.WindowStaysOnTopHint)
        self.overlay.show()

    def tearDown(self) -> None:
        self.overlay.close()
        self.overlay.deleteLater()

    def test_hide_and_show_overlay(self) -> None:
        bridge = _FakeBridge(busy=True, level="medium", whitelist=["charmap.exe"])
        controller = DockRevealController(bridge)
        try:
            self.assertTrue(self.overlay.isVisible())
            self.assertTrue(controller._hide_overlay())
            self.assertFalse(self.overlay.isVisible())
            self.assertTrue(controller._hidden)
            self.assertTrue(controller._watch_timer.isActive())
            self.assertEqual(bridge.topmost_calls[-1], False)
            self.assertTrue(controller._show_overlay())
            self.assertTrue(self.overlay.isVisible())
            self.assertFalse(controller._hidden)
            self.assertEqual(bridge.topmost_calls[-1], True)
        finally:
            controller.restore()

    def test_sync_session_stops_watch_after_session_end(self) -> None:
        bridge = _FakeBridge(busy=True, level="medium", whitelist=["charmap.exe"])
        controller = DockRevealController(bridge)
        try:
            controller.sync_session()
            self.assertTrue(controller._watch_timer.isActive())
            controller._hide_overlay()
            self.assertTrue(controller._hidden)
            bridge.busy = False  # 会话结束
            controller.sync_session()
            self.assertFalse(controller._hidden)
            self.assertFalse(controller._watch_timer.isActive())
        finally:
            controller.restore()


if __name__ == "__main__":
    unittest.main()
