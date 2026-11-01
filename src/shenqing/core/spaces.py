"""空间（Space）：深清 v0.2 的核心数据模型。

一个空间 = 一张专注卡片：名称 + 时长 + 氛围 + 允许使用的应用（白名单）。
「超禅」是唯一的主卡（super=True），其余归入「轻禅」分组。
"""

from __future__ import annotations

import json
import time
import uuid

from PySide6.QtCore import QCoreApplication
from pathlib import Path
from typing import Any

from ..consts import (
    ATMOSPHERE_VALUES,
    SPACE_MAX_MINUTES,
    SPACE_MIN_MINUTES,
    SPACE_MINUTE_STEP,
    SPACE_NAME_LIMIT,
)
from ..paths import app_data_dir


#: 轻禅分组空间数量上限
MAX_LIGHT_SPACES = 12

#: spaces.json 结构版本
SCHEMA_VERSION = 2


def _new_id() -> str:
    return "sp_" + uuid.uuid4().hex[:10]


def _clamp_minutes(minutes: Any) -> int:
    try:
        value = int(round(float(minutes)))
    except (TypeError, ValueError):
        value = 25
    value = max(SPACE_MIN_MINUTES, min(SPACE_MAX_MINUTES, value))
    # 吸附到最近的步进（47 → 45，48 → 50）
    steps = round((value - SPACE_MIN_MINUTES) / SPACE_MINUTE_STEP)
    value = SPACE_MIN_MINUTES + steps * SPACE_MINUTE_STEP
    return max(SPACE_MIN_MINUTES, min(SPACE_MAX_MINUTES, value))


def _clean_name(name: Any, fallback: str = "新空间") -> str:
    text = str(name or "").strip()
    if not text:
        text = fallback
    return text[:SPACE_NAME_LIMIT]


def _clean_atmosphere(value: Any) -> str:
    text = str(value or "").strip()
    return text if text in ATMOSPHERE_VALUES else ATMOSPHERE_VALUES[0]


def _clean_apps(apps: Any) -> list[str]:
    if not isinstance(apps, list):
        return []
    result: list[str] = []
    for item in apps:
        exe = str(item or "").strip().lower()
        if exe and exe not in result:
            result.append(exe)
    return result


def default_spaces() -> list[dict]:
    """首次启动的默认空间（名字随界面语言）。

    这里刻意写完整的 QCoreApplication.translate(...) 调用而不是别名函数，
    这样 pyside6-lupdate 才能从 .py 里提取到这些文案。
    """
    return [
        {
            "name": QCoreApplication.translate("ShenQing", "专注"),
            "minutes": 180,
            "atmosphere": "静谧",
            "super": True,
        },
        {
            "name": QCoreApplication.translate("ShenQing", "睡眠"),
            "minutes": 180,
            "atmosphere": "静谧",
            "super": False,
        },
        {
            "name": QCoreApplication.translate("ShenQing", "工作学习"),
            "minutes": 45,
            "atmosphere": "秩序",
            "super": False,
        },
        {
            "name": QCoreApplication.translate("ShenQing", "学习"),
            "minutes": 120,
            "atmosphere": "专注",
            "super": False,
        },
    ]


#: 兼容旧引用（中文源文案，不用于新建）
DEFAULT_SPACES: list[dict] = [
    {"name": "专注", "minutes": 180, "atmosphere": "静谧", "super": True},
    {"name": "睡眠", "minutes": 180, "atmosphere": "静谧", "super": False},
    {"name": "工作学习", "minutes": 45, "atmosphere": "秩序", "super": False},
    {"name": "学习", "minutes": 120, "atmosphere": "专注", "super": False},
]

#: 旧命名迁移（v0.2 曾用 OPPO 禅定空间的「超禅/轻禅」叫法，v0.3 起改为中性命名）
_NAME_MIGRATION = {"超禅": "专注", "轻禅": "其他空间"}


class SpaceManager:
    """空间增删改查 + JSON 持久化（spaces.json）。"""

    def __init__(self, path: Path | None = None) -> None:
        self.path = path or (app_data_dir() / "spaces.json")
        self._spaces: list[dict] = []
        self.load()

    # ---------- 持久化 ----------
    def load(self) -> None:
        self._spaces = []
        try:
            if self.path.exists():
                data: Any = json.loads(self.path.read_text(encoding="utf-8"))
                raw = data.get("spaces") if isinstance(data, dict) else data
                if isinstance(raw, list):
                    for item in raw:
                        if isinstance(item, dict):
                            self._spaces.append(self._normalize(item))
        except (OSError, json.JSONDecodeError):
            self._spaces = []
        if not self._spaces:
            self._spaces = [self._normalize(item) for item in default_spaces()]
            self._ensure_single_super()
            self.save()

    def save(self) -> None:
        try:
            self.path.parent.mkdir(parents=True, exist_ok=True)
            payload = {
                "schemaVersion": SCHEMA_VERSION,
                "spaces": self._spaces,
                "updated": int(time.time()),
            }
            self.path.write_text(
                json.dumps(payload, ensure_ascii=False, indent=2),
                encoding="utf-8",
            )
        except OSError:
            pass

    @staticmethod
    def _normalize(item: dict) -> dict:
        raw_name = _clean_name(item.get("name"))
        return {
            "id": str(item.get("id") or _new_id()),
            "name": _NAME_MIGRATION.get(raw_name, raw_name),
            "minutes": _clamp_minutes(item.get("minutes", 25)),
            "atmosphere": _clean_atmosphere(item.get("atmosphere")),
            "allowed_apps": _clean_apps(item.get("allowed_apps")),
            "super": bool(item.get("super", False)),
        }

    def _ensure_single_super(self) -> None:
        supers = [space for space in self._spaces if space["super"]]
        if len(supers) == 1:
            return
        if not supers:
            self._spaces[0]["super"] = True
            return
        keep = supers[0]
        for space in supers[1:]:
            space["super"] = False
        if keep not in self._spaces:  # pragma: no cover - 理论不可达
            self._spaces[0]["super"] = True

    # ---------- 查询 ----------
    def all(self) -> list[dict]:
        """超禅在前，其余保持创建顺序。"""
        supers = [s for s in self._spaces if s["super"]]
        lights = [s for s in self._spaces if not s["super"]]
        return supers + lights

    def light(self) -> list[dict]:
        return [s for s in self._spaces if not s["super"]]

    def get(self, space_id: str) -> dict | None:
        for space in self._spaces:
            if space["id"] == space_id:
                return space
        return None

    @property
    def super_id(self) -> str:
        for space in self._spaces:
            if space["super"]:
                return space["id"]
        return ""

    # ---------- 增删改 ----------
    def create(self, name: str | None = None) -> dict | None:
        if len(self.light()) >= MAX_LIGHT_SPACES and self._spaces:
            return None  # 轻禅已满（超禅不占额度）
        space = self._normalize(
            {
                "name": name
                or QCoreApplication.translate("ShenQing", "空间 %1").replace(
                    "%1", str(len(self._spaces) + 1)
                ),
                "minutes": 45,
                "atmosphere": "秩序",
                "super": not self._spaces,
            }
        )
        self._spaces.append(space)
        self.save()
        return space

    def update(
        self,
        space_id: str,
        *,
        name: str | None = None,
        minutes: Any = None,
        atmosphere: str | None = None,
    ) -> dict | None:
        space = self.get(space_id)
        if space is None:
            return None
        if name is not None:
            space["name"] = _clean_name(name, space["name"])
        if minutes is not None:
            space["minutes"] = _clamp_minutes(minutes)
        if atmosphere is not None:
            space["atmosphere"] = _clean_atmosphere(atmosphere)
        self.save()
        return space

    def delete(self, space_id: str) -> bool:
        space = self.get(space_id)
        if space is None:
            return False
        if space["super"]:
            return False  # 超禅唯一且不可删
        self._spaces.remove(space)
        if not self._spaces:
            # 从不让列表空掉：补一张默认空间
            self._spaces.append(self._normalize({"name": "专注", "minutes": 45}))
        if space["super"]:
            self._spaces[0]["super"] = True
        self.save()
        return True

    def set_allowed_apps(self, space_id: str, apps: list[str]) -> bool:
        space = self.get(space_id)
        if space is None:
            return False
        space["allowed_apps"] = _clean_apps(apps)
        self.save()
        return True

    def toggle_allowed_app(self, space_id: str, exe: str, enabled: bool) -> bool:
        space = self.get(space_id)
        if space is None:
            return False
        value = str(exe or "").strip().lower()
        if not value:
            return False
        apps = list(space["allowed_apps"])
        if enabled and value not in apps:
            apps.append(value)
        elif not enabled and value in apps:
            apps.remove(value)
        space["allowed_apps"] = apps
        self.save()
        return True

    def set_super(self, space_id: str) -> bool:
        space = self.get(space_id)
        if space is None:
            return False
        for item in self._spaces:
            item["super"] = False
        space["super"] = True
        self.save()
        return True
