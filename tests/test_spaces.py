"""空间模型单元测试。"""

from __future__ import annotations

import sys
import tempfile
import unittest
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parents[1] / "src"))

from shenqing.consts import ATMOSPHERE_VALUES, SPACE_MAX_MINUTES, SPACE_MIN_MINUTES
from shenqing.core.app_catalog import CATEGORIES, _classify
from shenqing.core.spaces import MAX_LIGHT_SPACES, SCHEMA_VERSION, SpaceManager


class SpaceManagerTest(unittest.TestCase):
    def setUp(self) -> None:
        self._tmp = tempfile.TemporaryDirectory()
        self.path = Path(self._tmp.name) / "spaces.json"

    def tearDown(self) -> None:
        self._tmp.cleanup()

    def test_defaults_created_once(self) -> None:
        manager = SpaceManager(self.path)
        spaces = manager.all()
        self.assertEqual(len(spaces), 4)
        self.assertEqual(len([s for s in spaces if s["super"]]), 1)
        self.assertTrue(manager.super_id)
        self.assertEqual(len(manager.light()), 3)
        # 再次加载不重复写默认值
        again = SpaceManager(self.path)
        self.assertEqual(len(again.all()), 4)

    def test_create_update_delete(self) -> None:
        manager = SpaceManager(self.path)
        space = manager.create("冥想")
        self.assertEqual(space["name"], "冥想")
        self.assertFalse(space["super"])

        updated = manager.update(space["id"], name="深度冥想", minutes=999, atmosphere="探索")
        assert updated is not None
        self.assertEqual(updated["name"], "深度冥想")
        self.assertEqual(updated["minutes"], SPACE_MAX_MINUTES)
        self.assertEqual(updated["atmosphere"], "探索")

        self.assertTrue(manager.delete(space["id"]))
        self.assertIsNone(manager.get(space["id"]))
        self.assertFalse(manager.delete(space["id"]))

    def test_minutes_clamped_and_snapped(self) -> None:
        manager = SpaceManager(self.path)
        space = manager.create("测试")
        for raw, expected in ((1, SPACE_MIN_MINUTES), (47, 45), (200, 200), (-5, SPACE_MIN_MINUTES)):
            updated = manager.update(space["id"], minutes=raw)
            assert updated is not None
            self.assertEqual(updated["minutes"], expected, msg=f"raw={raw}")

    def test_name_trimmed_to_limit(self) -> None:
        manager = SpaceManager(self.path)
        space = manager.create("x" * 50)
        self.assertEqual(len(space["name"]), 20)

    def test_allowed_apps(self) -> None:
        manager = SpaceManager(self.path)
        space = manager.create("白名单测试")
        self.assertTrue(manager.toggle_allowed_app(space["id"], "WeChat.exe", True))
        self.assertEqual(manager.get(space["id"])["allowed_apps"], ["wechat.exe"])
        self.assertTrue(manager.toggle_allowed_app(space["id"], "wechat.exe", True))
        self.assertEqual(manager.get(space["id"])["allowed_apps"], ["wechat.exe"])
        self.assertTrue(manager.toggle_allowed_app(space["id"], "wechat.exe", False))
        self.assertEqual(manager.get(space["id"])["allowed_apps"], [])

    def test_super_cannot_be_deleted(self) -> None:
        manager = SpaceManager(self.path)
        self.assertFalse(manager.delete(manager.super_id))
        self.assertEqual(len(manager.all()), 4)

    def test_light_quota(self) -> None:
        manager = SpaceManager(self.path)
        created = 0
        while True:
            space = manager.create()
            if space is None:
                break
            created += 1
            self.assertLessEqual(created, MAX_LIGHT_SPACES + 1)
        self.assertEqual(len(manager.light()), MAX_LIGHT_SPACES)

    def test_schema_version_written(self) -> None:
        SpaceManager(self.path)
        self.assertIn(f'"schemaVersion": {SCHEMA_VERSION}', self.path.read_text(encoding="utf-8"))

    def test_delete_only_space_recreates_one(self) -> None:
        manager = SpaceManager(self.path)
        for space in manager.all():
            manager.delete(space["id"])
        self.assertEqual(len(manager.all()), 1)
        self.assertTrue(manager.super_id)

    def test_atmosphere_fallback(self) -> None:
        self.assertTrue(ATMOSPHERE_VALUES)
        space = SpaceManager(self.path).create("氛围")
        manager = SpaceManager(self.path)
        updated = manager.update(space["id"], atmosphere="不存在的氛围")
        assert updated is not None
        self.assertIn(updated["atmosphere"], ATMOSPHERE_VALUES)


class CatalogClassifyTest(unittest.TestCase):
    def test_categories(self) -> None:
        self.assertIn("办公软件", CATEGORIES)
        self.assertEqual(_classify("Word", "C:/Office/WINWORD.EXE"), "办公软件")
        self.assertEqual(_classify("Anki", "C:/Apps/anki.exe"), "教育学习")
        self.assertEqual(_classify("计算器", "C:/Windows/calc.exe"), "实用工具")
        self.assertEqual(_classify("某个程序", "C:/Apps/foo.exe"), "其他")


if __name__ == "__main__":
    unittest.main()
