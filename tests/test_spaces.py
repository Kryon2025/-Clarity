"""多空间模型测试（v0.6，schemaVersion 5）。

- 浅清 / 覆清可多张，深清固定一张；
- 迁移：v4 每档一张原样迁入，v2/v3 主空间并入覆清。
"""

from __future__ import annotations

import json
import sys
import tempfile
import unittest
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parents[1] / "src"))

from PySide6.QtWidgets import QApplication  # noqa: E402

_APP = QApplication.instance() or QApplication([])

from shenqing.core.spaces import (  # noqa: E402
    MODES,
    SCHEMA_VERSION,
    SpaceManager,
    default_name,
)


class SpaceManagerTest(unittest.TestCase):
    def setUp(self) -> None:
        self._tmp = tempfile.TemporaryDirectory()
        self.path = Path(self._tmp.name) / "spaces.json"

    def tearDown(self) -> None:
        self._tmp.cleanup()

    def _write(self, payload) -> None:
        self.path.write_text(
            json.dumps(payload, ensure_ascii=False), encoding="utf-8"
        )

    # ---------- 默认数据 ----------
    def test_defaults_three_spaces(self) -> None:
        manager = SpaceManager(self.path)
        self.assertEqual(SCHEMA_VERSION, 6)
        self.assertEqual([s["mode"] for s in manager.all()], list(MODES))
        self.assertEqual(manager.get_by_mode("light")["name"], "浅清空间")
        self.assertEqual(manager.get_by_mode("medium")["name"], "覆清空间")
        self.assertEqual(manager.get_by_mode("heavy")["name"], "深清空间")
        self.assertEqual([s["name"] for s in manager.by_mode("light")], ["浅清空间"])
        self.assertEqual(manager.by_mode("heavy")[0]["mode"], "heavy")

    # ---------- 多空间增删 ----------
    def test_add_spaces_light_medium(self) -> None:
        manager = SpaceManager(self.path)
        light = manager.add("light")
        medium = manager.add("medium")
        self.assertIsNotNone(light)
        self.assertIsNotNone(medium)
        self.assertEqual(len(manager.by_mode("light")), 2)
        self.assertEqual(len(manager.by_mode("medium")), 2)
        self.assertEqual(len(manager.all()), 5)
        # 新空间彼此独立
        self.assertNotEqual(light["id"], manager.by_mode("light")[0]["id"])
        self.assertEqual(light["minutes"], 45)
        self.assertEqual(medium["minutes"], 90)

    def test_heavy_cannot_add_or_delete(self) -> None:
        manager = SpaceManager(self.path)
        self.assertIsNone(manager.add("heavy"))
        heavy_id = manager.by_mode("heavy")[0]["id"]
        self.assertFalse(manager.delete(heavy_id))
        self.assertFalse(manager.set_name(heavy_id, "改名"))
        self.assertEqual(manager.by_mode("heavy")[0]["name"], default_name("heavy"))
        self.assertEqual(len(manager.by_mode("heavy")), 1)

    def test_heavy_has_no_whitelist(self) -> None:
        manager = SpaceManager(self.path)
        heavy = manager.by_mode("heavy")[0]
        # 深清空间不设置白名单：按 id 与旧 mode 调用都被拒绝，且数据不变
        self.assertFalse(manager.toggle_allowed_app(heavy["id"], "steam.exe", True))
        self.assertEqual(manager.get(heavy["id"])["allowed_apps"], [])
        self.assertFalse(manager.toggle_allowed_app("heavy", "steam.exe", True))
        self.assertEqual(manager.get_by_mode("heavy")["allowed_apps"], [])
        self.assertFalse(manager.set_allowed_apps(heavy["id"], ["steam.exe"]))
        self.assertEqual(manager.get(heavy["id"])["allowed_apps"], [])
        saved = json.loads(self.path.read_text(encoding="utf-8"))
        heavy_saved = next(s for s in saved["spaces"] if s["mode"] == "heavy")
        self.assertEqual(heavy_saved["allowed_apps"], [])

    def test_delete_keeps_at_least_one_per_mode(self) -> None:
        manager = SpaceManager(self.path)
        first_light = manager.by_mode("light")[0]["id"]
        self.assertFalse(manager.delete(first_light))
        second = manager.add("light")
        self.assertTrue(manager.delete(first_light))
        self.assertEqual(len(manager.by_mode("light")), 1)
        self.assertEqual(manager.by_mode("light")[0]["id"], second["id"])
        # 覆清 / 深清各自仍保底一张
        self.assertEqual(len(manager.by_mode("medium")), 1)
        self.assertEqual(len(manager.by_mode("heavy")), 1)

    def test_set_name_and_minutes_by_id(self) -> None:
        manager = SpaceManager(self.path)
        space = manager.add("light")
        self.assertTrue(manager.set_name(space["id"], "读书"))
        self.assertEqual(manager.get(space["id"])["name"], "读书")
        updated = manager.set_minutes(space["id"], 33)
        self.assertEqual(updated["minutes"], 33)
        # 夹取范围
        self.assertEqual(manager.set_minutes(space["id"], 999)["minutes"], 240)
        self.assertEqual(manager.set_minutes(space["id"], 0)["minutes"], 1)
        # 空名字拒绝
        self.assertFalse(manager.set_name(space["id"], "   "))

    def test_allowed_apps_per_space(self) -> None:
        manager = SpaceManager(self.path)
        first = manager.by_mode("medium")[0]
        second = manager.add("medium")
        self.assertTrue(manager.toggle_allowed_app(first["id"], "Notion.EXE", True))
        self.assertTrue(manager.toggle_allowed_app(second["id"], "wechat.exe", True))
        self.assertEqual(manager.get(first["id"])["allowed_apps"], ["notion.exe"])
        self.assertEqual(manager.get(second["id"])["allowed_apps"], ["wechat.exe"])
        self.assertTrue(manager.toggle_allowed_app(first["id"], "notion.exe", False))
        self.assertEqual(manager.get(first["id"])["allowed_apps"], [])

    # ---------- 旧接口兼容（mode → 该档第一张） ----------
    def test_legacy_mode_api_maps_to_first_space(self) -> None:
        manager = SpaceManager(self.path)
        extra = manager.add("light")
        self.assertTrue(manager.set_name("light", "读书"))
        self.assertEqual(manager.get_by_mode("light")["name"], "读书")
        self.assertEqual(manager.get(extra["id"])["name"], default_name("light") + " 2")
        self.assertEqual(manager.set_minutes("medium", 999)["minutes"], 240)
        self.assertTrue(manager.toggle_allowed_app("medium", "x.exe", True))
        self.assertIn("x.exe", manager.get_by_mode("medium")["allowed_apps"])
        self.assertFalse(manager.set_name("heavy", "不许改"))
        self.assertEqual(len(manager.light()), 2)

    # ---------- 持久化 ----------
    def test_schema_and_persistence(self) -> None:
        manager = SpaceManager(self.path)
        extra = manager.add("light")
        manager.set_minutes(extra["id"], 30)
        manager.set_name(extra["id"], "晨读")
        reloaded = SpaceManager(self.path)
        self.assertEqual(len(reloaded.all()), 4)
        saved = json.loads(self.path.read_text(encoding="utf-8"))
        self.assertEqual(saved["schemaVersion"], 6)
        self.assertEqual(len(saved["spaces"]), 4)
        item = next(s for s in saved["spaces"] if s["id"] == extra["id"])
        self.assertEqual(set(item), {"id", "mode", "name", "minutes", "atmosphere", "allowed_apps"})
        self.assertEqual(item["name"], "晨读")
        self.assertEqual(reloaded.get(extra["id"])["minutes"], 30)

    # ---------- 迁移 ----------
    def test_migrate_v4_one_per_mode(self) -> None:
        self._write(
            {
                "schemaVersion": 4,
                "spaces": [
                    {
                        "id": "sp_l",
                        "mode": "light",
                        "name": "读书",
                        "minutes": 30,
                        "atmosphere": "静谧",
                        "allowed_apps": ["notion.exe"],
                    },
                    {
                        "id": "sp_m",
                        "mode": "medium",
                        "name": "工作",
                        "minutes": 60,
                        "atmosphere": "静谧",
                        "allowed_apps": ["code.exe"],
                    },
                    {
                        "id": "sp_h",
                        "mode": "heavy",
                        "name": "深清空间",
                        "minutes": 120,
                        "atmosphere": "静谧",
                        # 旧数据里残留的深清白名单，迁移时必须清空
                        "allowed_apps": ["steam.exe"],
                    },
                ],
            }
        )
        manager = SpaceManager(self.path)
        light = manager.get_by_mode("light")
        medium = manager.get_by_mode("medium")
        heavy = manager.get_by_mode("heavy")
        self.assertEqual((light["id"], light["name"], light["minutes"]), ("sp_l", "读书", 30))
        self.assertEqual(light["allowed_apps"], ["notion.exe"])
        self.assertEqual((medium["id"], medium["name"], medium["minutes"]), ("sp_m", "工作", 60))
        self.assertEqual(medium["allowed_apps"], ["code.exe"])
        self.assertEqual(heavy["minutes"], 120)
        self.assertEqual(heavy["allowed_apps"], [])
        self.assertEqual(len(manager.all()), 3)
        # 迁移后立即按 v5 保存
        saved = json.loads(self.path.read_text(encoding="utf-8"))
        self.assertEqual(saved["schemaVersion"], 6)

    def test_migrate_v2_main_space_into_medium(self) -> None:
        self._write(
            {
                "schemaVersion": 2,
                "spaces": [
                    {
                        "name": "专注",
                        "minutes": 180,
                        "atmosphere": "静谧",
                        "super": True,
                        "allowed_apps": ["steam.exe"],
                    },
                    {"name": "睡眠", "minutes": 180, "super": False},
                ],
            }
        )
        manager = SpaceManager(self.path)
        self.assertEqual([s["mode"] for s in manager.all()], list(MODES))
        medium = manager.get_by_mode("medium")
        self.assertEqual(medium["name"], "专注")
        self.assertEqual(medium["minutes"], 180)
        self.assertEqual(medium["allowed_apps"], ["steam.exe"])
        self.assertEqual(manager.get_by_mode("light")["name"], "浅清空间")
        self.assertEqual(manager.get_by_mode("heavy")["name"], "深清空间")

    def test_migrate_legacy_without_version(self) -> None:
        # v3：没有 schemaVersion 的单空间文件
        self._write(
            {
                "spaces": [
                    {"name": "清空间", "minutes": 90, "atmosphere": "秩序", "super": True}
                ]
            }
        )
        manager = SpaceManager(self.path)
        self.assertEqual(manager.get_by_mode("medium")["name"], "清空间")
        self.assertEqual(manager.get_by_mode("medium")["minutes"], 90)
        self.assertEqual(len(manager.all()), 3)

    def test_v5_multi_spaces_preserved(self) -> None:
        self._write(
            {
                "schemaVersion": 5,
                "spaces": [
                    {"id": "a", "mode": "light", "name": "晨读", "minutes": 20, "allowed_apps": []},
                    {"id": "b", "mode": "light", "name": "夜读", "minutes": 40, "allowed_apps": []},
                    {"id": "c", "mode": "medium", "name": "工作", "minutes": 60, "allowed_apps": []},
                    # v5 文件里如果被写入深清白名单，加载时也要清空
                    {"id": "d", "mode": "heavy", "name": "深清空间", "minutes": 120, "allowed_apps": ["steam.exe"]},
                ],
            }
        )
        manager = SpaceManager(self.path)
        self.assertEqual([s["id"] for s in manager.by_mode("light")], ["a", "b"])
        self.assertEqual([s["name"] for s in manager.all()], ["晨读", "夜读", "工作", "深清空间"])
        self.assertEqual(manager.get_by_mode("heavy")["allowed_apps"], [])

    def test_corrupt_file_falls_back(self) -> None:
        self.path.write_text("{ not json", encoding="utf-8")
        manager = SpaceManager(self.path)
        self.assertEqual(len(manager.all()), 3)
        self.assertEqual(manager.get_by_mode("medium")["name"], "覆清空间")


if __name__ == "__main__":
    unittest.main()
