"""多空间模型（v0.6，schemaVersion 5）：浅清 / 覆清可多张，深清固定一张。

- light / medium：可以有多个「空间」（默认各一张：浅清空间 / 覆清空间），
  可以新增、改名、删除、改时长、改白名单；每档至少保留一张。
- heavy：只有一张固定空间（名称固定「深清空间」，fixedName），不可新增 / 删除 / 改名，
  只能改时长；深清不设置白名单（allowed_apps 恒为空）。
- 数据文件：{"schemaVersion": 5, "spaces": [{id, mode, name, minutes, atmosphere, allowed_apps}]}
- 迁移：v4（每档一张）原样迁入；v2/v3 的主空间并入覆清（medium），缺失档位补默认。
"""

from __future__ import annotations

import json
import time
import uuid
from typing import Any

from PySide6.QtCore import QCoreApplication

from ..consts import SPACE_MAX_MINUTES, SPACE_MIN_MINUTES, SPACE_MINUTE_STEP
from ..paths import app_data_dir

SCHEMA_VERSION = 6
MODES = ("light", "medium", "heavy")

#: 各档位默认时长（分钟）
DEFAULT_MINUTES = {"light": 45, "medium": 90, "heavy": 1}
#: 深清空间名固定（不可改）
HEAVY_NAME_KEY = "深清空间"
#: 空间名长度上限
NAME_LIMIT = 20


def _new_id() -> str:
    return "sp_" + uuid.uuid4().hex[:10]


def default_name(mode: str) -> str:
    return {
        "light": QCoreApplication.translate("ShenQing", "浅清空间"),
        "medium": QCoreApplication.translate("ShenQing", "覆清空间"),
        "heavy": QCoreApplication.translate("ShenQing", HEAVY_NAME_KEY),
    }[mode]


def fixed_name(mode: str) -> bool:
    """该档位空间名是否固定（只有深清固定）。"""
    return str(mode) == "heavy"


def clamp_minutes(minutes: Any) -> int:
    try:
        value = int(round(float(minutes)))
    except (TypeError, ValueError):
        value = 45
    value = max(SPACE_MIN_MINUTES, min(SPACE_MAX_MINUTES, value))
    steps = round((value - SPACE_MIN_MINUTES) / SPACE_MINUTE_STEP)
    value = SPACE_MIN_MINUTES + steps * SPACE_MINUTE_STEP
    return max(SPACE_MIN_MINUTES, min(SPACE_MAX_MINUTES, value))


def _clean_apps(apps: Any) -> list[str]:
    if not isinstance(apps, list):
        return []
    result: list[str] = []
    for item in apps:
        exe = str(item or "").strip().lower()
        if exe and exe not in result:
            result.append(exe)
    return result


def clean_name(name: Any, fallback: str) -> str:
    text = str(name or "").strip()[:NAME_LIMIT]
    return text or fallback


class SpaceManager:
    """多空间增删改查 + JSON 持久化（spaces.json，schemaVersion 5）。"""

    def __init__(self, path=None) -> None:
        self.path = path or (app_data_dir() / "spaces.json")
        self._spaces: list[dict] = self._defaults()
        self.load()

    # ---------- 默认 / 归一化 ----------
    def _new_space(self, mode: str, *, name: str | None = None) -> dict:
        return {
            "id": _new_id(),
            "mode": mode,
            "name": clean_name(name, default_name(mode)),
            "minutes": DEFAULT_MINUTES[mode],
            "atmosphere": "静谧",
            "allowed_apps": [],
        }

    def _defaults(self) -> list[dict]:
        return [self._new_space(mode) for mode in MODES]

    def _normalize(self, mode: str, item: dict) -> dict:
        # 深清空间名固定、且不设置白名单；其余档位保留用户改名后的名字
        name = default_name(mode) if fixed_name(mode) else clean_name(
            item.get("name"), default_name(mode)
        )
        return {
            "id": str(item.get("id") or _new_id()),
            "mode": mode,
            "name": name,
            "minutes": clamp_minutes(item.get("minutes", DEFAULT_MINUTES[mode])),
            "atmosphere": "静谧",
            "allowed_apps": [] if fixed_name(mode) else _clean_apps(item.get("allowed_apps")),
        }

    # ---------- 持久化 / 迁移 ----------
    def _read_raw(self) -> tuple[int, list[dict]]:
        version = 0
        raw_items: list[dict] = []
        try:
            if self.path.exists():
                data: Any = json.loads(self.path.read_text(encoding="utf-8"))
                raw = data.get("spaces") if isinstance(data, dict) else data
                if isinstance(data, dict):
                    try:
                        version = int(data.get("schemaVersion", 0))
                    except (TypeError, ValueError):
                        version = 0
                if isinstance(raw, list):
                    raw_items = [item for item in raw if isinstance(item, dict)]
        except (OSError, json.JSONDecodeError):
            raw_items = []
            version = 0
        return version, raw_items

    def _migrate(self, version: int, raw_items: list[dict]) -> list[dict]:
        if version >= SCHEMA_VERSION:
            # v5：扁平列表，按 mode 归一化，深清只保留第一张
            spaces: list[dict] = []
            heavy_seen = False
            for item in raw_items:
                mode = str(item.get("mode") or "")
                if mode not in MODES:
                    continue
                if mode == "heavy":
                    if heavy_seen:
                        continue
                    heavy_seen = True
                spaces.append(self._normalize(mode, item))
            return self._complete(spaces)
        if version >= 4:
            # v4：每档一张，原样迁入（深清名固定）
            spaces = []
            for item in raw_items:
                mode = str(item.get("mode") or "")
                if mode not in MODES:
                    continue
                if mode == "heavy" and any(s["mode"] == "heavy" for s in spaces):
                    continue
                spaces.append(self._normalize(mode, item))
            return self._complete(spaces)
        if raw_items:
            # v2/v3：单一/多空间，主空间（super）并入覆清
            source = next((item for item in raw_items if item.get("super")), raw_items[0])
            spaces = self._defaults()
            medium = self._normalize("medium", source)
            medium["id"] = next(s["id"] for s in spaces if s["mode"] == "medium")
            for index, item in enumerate(spaces):
                if item["mode"] == "medium":
                    spaces[index] = medium
                    break
            return spaces
        return self._defaults()

    def _complete(self, spaces: list[dict]) -> list[dict]:
        """补齐缺失档位、保证深清唯一，并按 light→medium→heavy 重排。"""
        result = list(spaces)
        for mode in MODES:
            existing = [s for s in result if s["mode"] == mode]
            if mode == "heavy":
                existing = existing[:1]
                result = [s for s in result if s["mode"] != mode] + existing
            if not existing:
                result.append(self._new_space(mode))
        ordered: list[dict] = []
        for mode in MODES:
            ordered.extend(s for s in result if s["mode"] == mode)
        return ordered

    def load(self) -> None:
        version, raw_items = self._read_raw()
        spaces = self._migrate(version, raw_items)
        # v6：深清默认 1 分钟——旧文件里深清若仍是旧默认 180 分钟，改回 1 分钟
        if version < 6:
            for space in spaces:
                if space["mode"] == "heavy" and space["minutes"] == 180:
                    space["minutes"] = DEFAULT_MINUTES["heavy"]
        # 去重 id（损坏数据兜底）
        seen: set[str] = set()
        for space in spaces:
            if space["id"] in seen:
                space["id"] = _new_id()
            seen.add(space["id"])
        self._spaces = spaces
        self.save()

    def save(self) -> None:
        try:
            self.path.parent.mkdir(parents=True, exist_ok=True)
            payload = {
                "schemaVersion": SCHEMA_VERSION,
                "spaces": [
                    {
                        "id": space["id"],
                        "mode": space["mode"],
                        "name": space["name"],
                        "minutes": space["minutes"],
                        "atmosphere": space.get("atmosphere", "静谧"),
                        "allowed_apps": list(space.get("allowed_apps", [])),
                    }
                    for space in self._spaces
                ],
                "updated": int(time.time()),
            }
            self.path.write_text(
                json.dumps(payload, ensure_ascii=False, indent=2), encoding="utf-8"
            )
        except OSError:
            pass

    # ---------- 查询 ----------
    def all(self) -> list[dict]:
        """扁平列表：浅清 → 覆清 → 深清（同档保持创建顺序）。"""
        return [space for mode in MODES for space in self._spaces if space["mode"] == mode]

    def by_mode(self, mode: str) -> list[dict]:
        value = str(mode or "")
        return [space for space in self._spaces if space["mode"] == value]

    def get(self, space_id: str) -> dict | None:
        value = str(space_id or "")
        if not value:
            return None
        for space in self._spaces:
            if space["id"] == value:
                return space
        return None

    # ---------- 旧接口兼容（mode → 该档第一张） ----------
    def get_by_mode(self, mode: str) -> dict | None:
        items = self.by_mode(mode)
        return items[0] if items else None

    def light(self) -> list[dict]:
        """浅清 + 覆清各第一张（v0.5 旧接口语义）。"""
        result: list[dict] = []
        for mode in ("light", "medium"):
            space = self.get_by_mode(mode)
            if space is not None:
                result.append(space)
        return result

    @property
    def space(self) -> dict:
        return self.get_by_mode("medium") or self._spaces[0]

    @property
    def super_id(self) -> str:
        space = self.get_by_mode("medium") or (self._spaces[0] if self._spaces else None)
        return str(space["id"]) if space else ""

    # ---------- 增删改 ----------
    def add(self, mode: str) -> dict | None:
        """新增一张空间；深清固定一张，返回 None。"""
        value = str(mode or "")
        if value not in MODES or fixed_name(value):
            return None
        count = len(self.by_mode(value))
        name = default_name(value)
        if count:
            name = clean_name(f"{name} {count + 1}", default_name(value))
        space = self._new_space(value, name=name)
        self._spaces.append(space)
        self.save()
        return space

    def delete(self, space_id: str) -> bool:
        """删除一张空间；深清 / 每档最后一张不可删。"""
        space = self.get(space_id)
        if space is None:
            return False
        mode = str(space["mode"])
        if fixed_name(mode):
            return False
        if len(self.by_mode(mode)) <= 1:
            return False
        self._spaces.remove(space)
        self.save()
        return True

    def set_name(self, space_id: str, name: str) -> bool:
        """改名（space_id 优先；传 mode 时映射到该档第一张，兼容旧调用）。"""
        space = self.get(space_id) or self.get_by_mode(str(space_id))
        if space is None or fixed_name(space["mode"]):
            return False
        text = clean_name(name, "")
        if not text:
            return False
        space["name"] = text
        self.save()
        return True

    def set_minutes(self, space_id: str, minutes: Any) -> dict | None:
        """改时长（space_id 优先；传 mode 时映射到该档第一张）。"""
        space = self.get(space_id) or self.get_by_mode(str(space_id))
        if space is None:
            return None
        space["minutes"] = clamp_minutes(minutes)
        self.save()
        return space

    def set_allowed_apps(self, space_id: str, apps: list[str]) -> bool:
        space = self.get(space_id) or self.get_by_mode(str(space_id))
        if space is None or fixed_name(space["mode"]):
            # 深清空间不设置白名单：忽略写入
            return False
        space["allowed_apps"] = _clean_apps(apps)
        self.save()
        return True

    def toggle_allowed_app(self, space_id: str, exe: str, enabled: bool) -> bool:
        space = self.get(space_id) or self.get_by_mode(str(space_id))
        if space is None or fixed_name(space["mode"]):
            # 深清空间不设置白名单
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
