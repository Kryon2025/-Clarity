"""用户设置持久化（%APPDATA%\\ShenQing\\settings.json）。"""

from __future__ import annotations

import json
from pathlib import Path
from typing import Any

from .consts import LockLevel
from .paths import app_data_dir

DEFAULTS: dict[str, Any] = {
    "theme": "Auto",            # Auto / Light / Dark
    "language": "auto",  # auto / zh_CN / en_US
    "autostart": False,
    "hardening": True,      # 防退出加固：隐藏任务栏 + 屏蔽系统快捷键
    "admin_mode": False,    # 以管理员身份运行（启动时 UAC 提权）
    "default_minutes": 25,
    "lock_level": LockLevel.MEDIUM.value,
    "guard_interval_ms": 1000,
    "pause_limit": 2,           # 一次会话允许的暂停次数
    "cooldown_minutes": 5,      # 提前结束后再次开始前的冷却
    "pin_enabled": False,
    "pin": "",                  # 明文仅作占位，正式版改哈希
    "hosts_block_enabled": False,  # 网站屏蔽（写 hosts，需要管理员权限）
}


class Settings:
    """极简 JSON 设置容器（读写都在主线程，够用且好调试）。"""

    def __init__(self, path: Path | None = None) -> None:
        self.path = path or (app_data_dir() / "settings.json")
        self._data: dict[str, Any] = dict(DEFAULTS)
        self.load()

    def load(self) -> None:
        try:
            if self.path.exists():
                loaded = json.loads(self.path.read_text(encoding="utf-8"))
                if isinstance(loaded, dict):
                    self._data.update(loaded)
        except (OSError, json.JSONDecodeError):
            # 配置坏了就用默认值，不让启动失败
            self._data = dict(DEFAULTS)

    def save(self) -> None:
        try:
            self.path.parent.mkdir(parents=True, exist_ok=True)
            self.path.write_text(
                json.dumps(self._data, ensure_ascii=False, indent=2),
                encoding="utf-8",
            )
        except OSError:
            pass

    def get(self, key: str, default: Any = None) -> Any:
        return self._data.get(key, DEFAULTS.get(key, default))

    def set(self, key: str, value: Any, *, save: bool = True) -> None:
        self._data[key] = value
        if save:
            self.save()
