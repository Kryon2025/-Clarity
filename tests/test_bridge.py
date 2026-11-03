"""AppBridge 集成测试（v0.6 多空间 + 保活无关）。"""

from __future__ import annotations

import json
import os
import sys
import tempfile
import unittest
from pathlib import Path
from unittest import mock

sys.path.insert(0, str(Path(__file__).resolve().parents[1] / "src"))

os.environ.setdefault("QT_QPA_PLATFORM", "offscreen")
os.environ["SHENQING_NO_SCAN"] = "1"
os.environ["SHENQING_NO_KEEPER"] = "1"

from PySide6.QtWidgets import QApplication  # noqa: E402

_APP = QApplication.instance() or QApplication([])

from shenqing.bridge.app_bridge import AppBridge  # noqa: E402
from shenqing.core.guard import DEFAULT_WHITELIST  # noqa: E402


class BridgeTest(unittest.TestCase):
    def setUp(self) -> None:
        self._tmp = tempfile.TemporaryDirectory()
        os.environ["SHENQING_DATA_DIR"] = self._tmp.name
        self.bridge = AppBridge()
        self.toasts: list[str] = []
        self.space_changes: list[int] = []
        self.bridge.toast.connect(self.toasts.append)
        self.bridge.spacesChanged.connect(lambda: self.space_changes.append(1))

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

    # ---------- 基础 ----------
    def test_spaces_flat_with_view_fields(self) -> None:
        bridge = self.bridge
        spaces = bridge.spaces
        self.assertEqual(len(spaces), 3)
        self.assertEqual([s["mode"] for s in spaces], ["light", "medium", "heavy"])
        for item in spaces:
            self.assertTrue(
                {"id", "mode", "name", "minutes", "allowedCount", "fixedName"} <= set(item)
            )
        self.assertFalse(spaces[0]["fixedName"])
        self.assertFalse(spaces[1]["fixedName"])
        self.assertTrue(spaces[2]["fixedName"])
        self.assertEqual(spaces[2]["name"], "深清空间")
        self.assertEqual(spaces[0]["allowedCount"], 0)
        # 兼容属性仍在
        self.assertEqual(bridge.space["mode"], "medium")
        self.assertEqual(bridge.spaceMinutes, 90)
        self.assertEqual(len(bridge.spacesLight), 2)
        self.assertEqual([m["label"] for m in bridge.modes], ["浅清", "覆清", "深清"])

    def test_add_space_for(self) -> None:
        bridge = self.bridge
        light_id = bridge.addSpaceFor("light")
        self.assertTrue(light_id)
        self.assertEqual(len(bridge.spaces), 4)
        self.assertEqual(len([s for s in bridge.spaces if s["mode"] == "light"]), 2)
        self.assertTrue(any("新增" in t for t in self.toasts))
        changes = len(self.space_changes)
        medium_id = bridge.addSpaceFor("medium")
        self.assertTrue(medium_id)
        self.assertEqual(len(bridge.spaces), 5)
        self.assertGreater(len(self.space_changes), changes)
        # 深清固定一张，不能新增
        self.assertEqual(bridge.addSpaceFor("heavy"), "")
        self.assertEqual(len([s for s in bridge.spaces if s["mode"] == "heavy"]), 1)
        # 非法档位
        self.assertEqual(bridge.addSpaceFor("nope"), "")

    def test_delete_space_for(self) -> None:
        bridge = self.bridge
        heavy_id = next(s["id"] for s in bridge.spaces if s["mode"] == "heavy")
        self.assertFalse(bridge.deleteSpaceFor("heavy", heavy_id))
        self.assertTrue(any("不可删除" in t for t in self.toasts))
        light_id = next(s["id"] for s in bridge.spaces if s["mode"] == "light")
        # 每档最后一张不可删
        self.assertFalse(bridge.deleteSpaceFor("light", light_id))
        extra_id = bridge.addSpaceFor("light")
        # mode 不匹配
        self.assertFalse(bridge.deleteSpaceFor("medium", extra_id))
        self.assertTrue(bridge.deleteSpaceFor("light", light_id))
        self.assertEqual(len([s for s in bridge.spaces if s["mode"] == "light"]), 1)
        self.assertEqual([s["id"] for s in bridge.spaces if s["mode"] == "light"], [extra_id])

    def test_set_space_name_and_minutes(self) -> None:
        bridge = self.bridge
        extra_id = bridge.addSpaceFor("light")
        self.assertTrue(bridge.setSpaceName(extra_id, "读书"))
        item = next(s for s in bridge.spaces if s["id"] == extra_id)
        self.assertEqual(item["name"], "读书")
        self.assertTrue(bridge.setSpaceMinutes(extra_id, 33))
        item = next(s for s in bridge.spaces if s["id"] == extra_id)
        self.assertEqual(item["minutes"], 33)
        # 范围夹取
        bridge.setSpaceMinutes(extra_id, 999)
        self.assertEqual(next(s for s in bridge.spaces if s["id"] == extra_id)["minutes"], 240)
        # 深清固定：改名失败、改时长成功
        heavy_id = next(s["id"] for s in bridge.spaces if s["mode"] == "heavy")
        self.assertFalse(bridge.setSpaceName(heavy_id, "改名"))
        self.assertTrue(any("不可修改" in t for t in self.toasts))
        self.assertTrue(bridge.setSpaceMinutes(heavy_id, 60))
        self.assertEqual(next(s for s in bridge.spaces if s["id"] == heavy_id)["minutes"], 60)
        # 不存在的空间
        self.assertFalse(bridge.setSpaceName("sp_missing", "x"))
        self.assertFalse(bridge.setSpaceMinutes("sp_missing", 10))

    def test_toggle_space_allowed_app_by_id(self) -> None:
        bridge = self.bridge
        medium_id = next(s["id"] for s in bridge.spaces if s["mode"] == "medium")
        self.assertTrue(bridge.toggleSpaceAllowedApp(medium_id, "Notion.EXE", True))
        item = next(s for s in bridge.spaces if s["id"] == medium_id)
        self.assertEqual(item["allowedCount"], 1)
        self.assertTrue(bridge.toggleSpaceAllowedApp(medium_id, "notion.exe", False))
        self.assertEqual(next(s for s in bridge.spaces if s["id"] == medium_id)["allowedCount"], 0)
        self.assertFalse(bridge.toggleSpaceAllowedApp("sp_missing", "x.exe", True))
        # 深清空间不设置白名单：拒绝 + toast，数据不变
        heavy_id = next(s["id"] for s in bridge.spaces if s["mode"] == "heavy")
        self.assertFalse(bridge.toggleSpaceAllowedApp(heavy_id, "steam.exe", True))
        self.assertTrue(any("不设置白名单" in t for t in self.toasts))
        self.assertEqual(
            next(s for s in bridge.spaces if s["mode"] == "heavy")["allowedCount"], 0
        )

    def test_legacy_mode_methods(self) -> None:
        bridge = self.bridge
        extra_id = bridge.addSpaceFor("light")
        # setSpaceMinutesFor(mode) → 该档第一张
        bridge.setSpaceMinutesFor("light", 30)
        first_light = next(s for s in bridge.spaces if s["mode"] == "light")
        self.assertEqual(first_light["minutes"], 30)
        self.assertEqual(next(s for s in bridge.spaces if s["id"] == extra_id)["minutes"], 45)
        bridge.setSpaceNameFor("light", "读书")
        self.assertEqual(next(s for s in bridge.spaces if s["mode"] == "light")["name"], "读书")
        # 深清改名依旧失败 + toast
        bridge.setSpaceNameFor("heavy", "不许改")
        self.assertEqual(
            next(s for s in bridge.spaces if s["mode"] == "heavy")["name"], "深清空间"
        )
        # toggleSpaceAllowedAppFor(mode) → 该档第一张
        self.assertTrue(bridge.toggleSpaceAllowedAppFor("medium", "code.exe", True))
        medium = next(s for s in bridge.spaces if s["mode"] == "medium")
        self.assertEqual(medium["allowedCount"], 1)
        # 深清档拒绝白名单 + toast
        self.assertFalse(bridge.toggleSpaceAllowedAppFor("heavy", "steam.exe", True))
        self.assertTrue(any("不设置白名单" in t for t in self.toasts))
        self.assertEqual(
            next(s for s in bridge.spaces if s["mode"] == "heavy")["allowedCount"], 0
        )

    # ---------- 会话 ----------
    def test_start_space_uses_own_minutes_and_whitelist(self) -> None:
        bridge = self.bridge
        space_id = bridge.addSpaceFor("light")
        bridge.setSpaceName(space_id, "读书")
        bridge.setSpaceMinutes(space_id, 2)
        bridge.toggleSpaceAllowedApp(space_id, "notion.exe", True)
        for item in bridge.spaces:
            if item["mode"] == "medium":
                bridge.setSpaceMinutes(item["id"], 90)  # 不影响本次
        bridge.startSpace(space_id)
        self.assertTrue(bridge.busy)
        self.assertEqual(bridge.totalSeconds, 120)
        self.assertEqual(bridge.sessionLevel, "light")
        self.assertEqual(bridge.activeSpaceId, space_id)
        self.assertEqual(bridge.activeSpaceName, "读书")
        self.assertIn("notion.exe", bridge._guard._whitelist)
        self.assertEqual(bridge.sessionWhitelist, ["notion.exe"])
        self.assertFalse(bridge._guard._strict)
        for _ in range(bridge.totalSeconds):
            bridge._session._on_timeout()
        self.assertFalse(bridge.busy)
        self.assertGreaterEqual(bridge.todayMinutes, 1.0)

    def test_start_space_missing_toasts(self) -> None:
        self.bridge.startSpace("sp_missing")
        self.assertFalse(self.bridge.busy)
        self.assertTrue(any("不存在" in t for t in self.toasts))

    def test_start_mode_uses_first_space_of_mode(self) -> None:
        bridge = self.bridge
        second = bridge.addSpaceFor("light")
        bridge.setSpaceMinutes(second, 3)
        bridge.setSpaceMinutesFor("light", 2)  # 第一张
        bridge.startMode("light")
        self.assertTrue(bridge.busy)
        self.assertEqual(bridge.totalSeconds, 120)
        self.assertEqual(bridge.sessionLevel, "light")
        bridge.stopSession()
        self.assertFalse(bridge.busy)

    def test_start_mode_heavy_level(self) -> None:
        bridge = self.bridge
        bridge._session.stop()  # 确保空闲
        # 只验证档位解析与不能提前结束，不真正驱动 180 分钟
        heavy_id = next(s["id"] for s in bridge.spaces if s["mode"] == "heavy")
        bridge.startSpace(heavy_id)
        self.assertTrue(bridge.busy)
        self.assertEqual(bridge.sessionLevel, "heavy")
        self.assertTrue(bridge._guard._strict)
        # 深清不设置白名单：守卫白名单只剩系统进程，空间白名单为空
        self.assertEqual(bridge.sessionWhitelist, [])
        self.assertEqual(set(bridge._guard._whitelist), set(DEFAULT_WHITELIST))
        self.assertNotIn("steam.exe", bridge._guard._whitelist)
        self.assertEqual(bridge.totalSeconds, 180 * 60)
        bridge.stopSession()  # 深清不可提前结束
        self.assertTrue(bridge.busy)
        bridge._session.stop()
        self.assertFalse(bridge.busy)

    def test_heavy_legacy_whitelist_ignored(self) -> None:
        """旧文件里深清空间残留白名单时：加载清空、bridge 拒绝、启动时不加载。"""
        payload = {
            "schemaVersion": 5,
            "spaces": [
                {"id": "l", "mode": "light", "name": "浅清空间", "minutes": 30, "allowed_apps": []},
                {"id": "m", "mode": "medium", "name": "覆清空间", "minutes": 60, "allowed_apps": []},
                {
                    "id": "h",
                    "mode": "heavy",
                    "name": "深清空间",
                    "minutes": 120,
                    "allowed_apps": ["steam.exe", "wechat.exe"],
                },
            ],
        }
        (Path(self._tmp.name) / "spaces.json").write_text(
            json.dumps(payload, ensure_ascii=False), encoding="utf-8"
        )
        try:
            self.bridge.deleteLater()
        except RuntimeError:
            pass
        self.bridge = AppBridge()
        bridge = self.bridge
        bridge.toast.connect(self.toasts.append)
        heavy = next(s for s in bridge.spaces if s["mode"] == "heavy")
        self.assertEqual(heavy["allowedCount"], 0)
        self.assertFalse(bridge.toggleSpaceAllowedApp("h", "steam.exe", True))
        bridge.startSpace("h")
        self.assertTrue(bridge.busy)
        self.assertEqual(bridge.sessionLevel, "heavy")
        self.assertEqual(set(bridge._guard._whitelist), set(DEFAULT_WHITELIST))
        self.assertNotIn("steam.exe", bridge._guard._whitelist)
        self.assertNotIn("wechat.exe", bridge._guard._whitelist)
        bridge._session.stop()
        self.assertFalse(bridge.busy)

    def test_dock_apps_uses_medium_first_space(self) -> None:
        bridge = self.bridge
        first_medium = next(s for s in bridge.spaces if s["mode"] == "medium")
        bridge.toggleSpaceAllowedApp(first_medium["id"], "notion.exe", True)
        second = bridge.addSpaceFor("medium")
        bridge.toggleSpaceAllowedApp(second, "wechat.exe", True)
        exes = [item["exe"] for item in bridge.dockApps]
        self.assertEqual(exes, ["notion.exe"])
        # 改第一张白名单后 dock 跟着变
        bridge.toggleSpaceAllowedApp(first_medium["id"], "notion.exe", False)
        self.assertEqual(bridge.dockApps, [])

    # ---------- 搜索 / 设置 ----------
    def test_search_includes_spaces(self) -> None:
        bridge = self.bridge
        space_id = bridge.addSpaceFor("light")
        bridge.setSpaceName(space_id, "读书")
        results = bridge.search("读书")
        hit = next(item for item in results if item["kind"] == "space")
        self.assertEqual(hit["payload"]["id"], space_id)
        self.assertEqual(hit["payload"]["mode"], "light")
        self.assertEqual(hit["sub"], "浅清")
        # 原有搜索项仍在
        self.assertTrue(any(item["kind"] == "theme" for item in bridge.search("主题")))

    def test_launch_app_emits_signal(self) -> None:
        bridge = self.bridge
        launched: list[str] = []
        bridge.appLaunched.connect(launched.append)
        with mock.patch.object(os, "startfile") as startfile:
            bridge.launchApp("charmap.exe")
        startfile.assert_called_once_with("charmap.exe")
        self.assertEqual(launched, ["charmap.exe"])
        # 启动失败：不 emit、toast 提示
        with mock.patch.object(os, "startfile", side_effect=OSError("boom")):
            bridge.launchApp("charmap.exe")
        self.assertEqual(launched, ["charmap.exe"])
        self.assertTrue(any("启动应用失败" in t for t in self.toasts))

    def test_theme_and_default_minutes(self) -> None:
        bridge = self.bridge
        self.assertEqual(bridge.themeMode, "solid")
        bridge.setThemeMode("glass")
        self.assertEqual(bridge.themeMode, "glass")
        bridge.setDefaultMinutes(50)
        self.assertEqual(bridge.defaultMinutes, 50)


if __name__ == "__main__":
    unittest.main()
