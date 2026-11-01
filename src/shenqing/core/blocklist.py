"""黑名单：进程与网站域名，支持预设分组。"""

from __future__ import annotations

import json
from pathlib import Path
from typing import Any

from ..paths import app_data_dir

#: 预设进程分组（示例清单，用户可增删）
DEFAULT_GROUPS: dict[str, list[str]] = {
    "游戏": ["steam.exe", "wegame.exe", "epicgameslauncher.exe", "leagueclient.exe", "genshinimpact.exe"],
    "短视频": ["douyin.exe", "kuaishou.exe", "bilibili.exe"],
    "社交": ["wechat.exe", "qq.exe", "telegram.exe", "discord.exe"],
    "影音": ["potplayermini64.exe", "vlc.exe", "iqiyi.exe", "youku.exe"],
}

#: 预设网站分组（仅「中度」及以上使用；写 hosts 需要管理员权限）
DEFAULT_SITES: dict[str, list[str]] = {
    "短视频": ["douyin.com", "kuaishou.com", "bilibili.com"],
    "社交": ["weibo.com", "zhihu.com", "x.com"],
    "影音": ["iqiyi.com", "youku.com", "netflix.com"],
}


class Blocklist:
    """进程黑名单持久化（blocklist.json）。"""

    def __init__(self, path: Path | None = None) -> None:
        self.path = path or (app_data_dir() / "blocklist.json")
        self._processes: list[str] = []
        self.load()

    def load(self) -> None:
        try:
            if self.path.exists():
                data: Any = json.loads(self.path.read_text(encoding="utf-8"))
                if isinstance(data, dict) and isinstance(data.get("processes"), list):
                    self._processes = [str(p).strip() for p in data["processes"] if str(p).strip()]
        except (OSError, json.JSONDecodeError):
            self._processes = []

    def save(self) -> None:
        try:
            self.path.parent.mkdir(parents=True, exist_ok=True)
            self.path.write_text(
                json.dumps({"processes": self._processes}, ensure_ascii=False, indent=2),
                encoding="utf-8",
            )
        except OSError:
            pass

    @property
    def processes(self) -> list[str]:
        return list(self._processes)

    @property
    def groups(self) -> dict[str, list[str]]:
        return {name: list(items) for name, items in DEFAULT_GROUPS.items()}

    def add(self, name: str) -> bool:
        value = name.strip().lower()
        if not value or value in self._processes:
            return False
        self._processes.append(value)
        self.save()
        return True

    def add_many(self, names: list[str]) -> int:
        added = 0
        for name in names:
            value = name.strip().lower()
            if value and value not in self._processes:
                self._processes.append(value)
                added += 1
        if added:
            self.save()
        return added

    def remove(self, name: str) -> bool:
        value = name.strip().lower()
        if value not in self._processes:
            return False
        self._processes.remove(value)
        self.save()
        return True

    def add_group(self, group: str) -> int:
        return self.add_many(DEFAULT_GROUPS.get(group, []))
