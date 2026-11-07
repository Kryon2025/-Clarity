"""用户设置持久化（%APPDATA%\\ShenQing\\settings.json）。"""

from __future__ import annotations

import json
import os
from pathlib import Path
from typing import Any

from .consts import LockLevel
from .paths import app_data_dir

DEFAULTS: dict[str, Any] = {
    "theme": "Auto",            # 窗口 chrome：Auto / Light / Dark
    "theme_mode": "solid",      # 应用主题：solid / light / glass
    "default_mode": "medium",   # 默认强度：light / medium / heavy
    "language": "auto",  # auto / zh_CN / en_US
    "autostart": False,
    "hardening": True,      # 防退出加固：隐藏任务栏 + 屏蔽系统快捷键
    "keep_alive": True,     # 不杀进程：只隐藏窗口 + 静音（保留未保存工作）
    "admin_mode": False,    # 以管理员身份运行（启动时 UAC 提权）
    "auto_update": True,    # 启动后自动检查 GitHub Releases 更新
    "ai_enabled": False,    # AI 集成（v0.9 真实接入，云端免费 API）
    "ai_provider": "groq",  # groq / glm / siliconflow / custom
    "ai_api_base": "",
    "ai_api_key": "",
    "ai_model": "",
    "ai_models_cache": {},  # provider -> {models:[...], fetchedAt}（24h 过期）
    "ai_reasoning_enabled": True,   # 思考模式（DeepSeek thinking / OpenAI reasoning_effort）
    "ai_web_search_enabled": False,  # 联网检索（DeepSeek / GLM）
    "ai_reasoning_effort": "",       # 可选：low / medium / high（OpenAI/DeepSeek）
    "ui_font_family": "",            # 界面字体（空 = 内置默认字体）
    "ui_font_scale": 1.0,            # 界面字号缩放 0.8-1.4（步进 0.05）
    "nav_mode": "expanded",          # 导航模式：auto / expanded / icons / custom
    "app_usage_heatmap_days": 90,    # 应用热力图天数：30 / 90 / 180
    "volume_panel": 50,     # dock 设置面板上次的系统音量（0-100）
    "onboarding_done": False,  # 首次使用引导是否完成
    "countdown_date": "",      # 倒数日目标日期 YYYY-MM-DD（空=不显示）
    "overlay_widget_order": [],  # 全屏遮罩自定义组件顺序 ["pluginId:itemId"]
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
        #: 首次运行（配置文件尚不存在）——app.py 用它决定默认最高权限
        self.is_new = not self.path.exists()
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
        """原子写：先写 .tmp 再 os.replace，避免断电/并发写坏 settings.json。"""
        try:
            self.path.parent.mkdir(parents=True, exist_ok=True)
            temp = self.path.with_name(self.path.name + ".tmp")
            temp.write_text(
                json.dumps(self._data, ensure_ascii=False, indent=2),
                encoding="utf-8",
            )
            os.replace(temp, self.path)
        except OSError:
            pass

    def get(self, key: str, default: Any = None) -> Any:
        return self._data.get(key, DEFAULTS.get(key, default))

    def set(self, key: str, value: Any, *, save: bool = True) -> None:
        self._data[key] = value
        if save:
            self.save()
