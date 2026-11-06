"""Patina 式「应用使用时长」统计（v0.9）。

- 每 5 秒取前台窗口进程（GetForegroundWindow + GetWindowThreadProcessId +
  QueryFullProcessImageNameW），按真实经过时间累计分钟数；
- GetLastInputInfo 判断空闲：空闲 ≥5 分钟暂停累计；
- 用 time.monotonic 计算采样间隔：休眠/锁屏/时钟跳变的大间隔直接丢弃，不重复计算；
- 数据：%APPDATA%/ShenQing/app_usage.json
  {"YYYY-MM-DD": {"chrome.exe": {"minutes": 123.4, "name": "Chrome"}}}
  每 60 秒落盘 + 退出时 flush()；
- 分类与颜色有内置映射，用户覆盖持久化到 app_usage_overrides.json；
- 不计入深清自身进程。
"""

from __future__ import annotations

import ctypes
import json
import logging
import os
import sys
import time
from datetime import date, datetime, timedelta
from pathlib import Path
from typing import Callable

from PySide6.QtCore import QObject, QTimer, Signal

from ..paths import app_data_dir

logger = logging.getLogger("shenqing.app_usage")

DATA_NAME = "app_usage.json"
OVERRIDES_NAME = "app_usage_overrides.json"
SAMPLE_INTERVAL_MS = 5000
FLUSH_INTERVAL_MS = 60000
IDLE_LIMIT_MS = 5 * 60 * 1000
#: 单次采样间隔超过该秒数视为休眠/锁屏/时钟跳变，直接丢弃
MAX_SAMPLE_GAP_SECONDS = 15.0
#: 保留最近多少天数据
KEEP_DAYS = 180

CATEGORIES: list[dict[str, str]] = [
    {"value": "browser", "label": "浏览器", "color": "#3B82F6"},
    {"value": "dev", "label": "开发", "color": "#8B5CF6"},
    {"value": "office", "label": "办公", "color": "#F59E0B"},
    {"value": "study", "label": "学习", "color": "#10B981"},
    {"value": "entertainment", "label": "娱乐", "color": "#EC4899"},
    {"value": "communication", "label": "通讯", "color": "#06B6D4"},
    {"value": "other", "label": "其他", "color": "#94A3B8"},
]
CATEGORY_COLORS = {item["value"]: item["color"] for item in CATEGORIES}
CATEGORY_LABELS = {item["value"]: item["label"] for item in CATEGORIES}
DEFAULT_CATEGORY = "other"

#: 内置 应用 → 分类 映射（可被用户覆盖）
BUILTIN_CATEGORY: dict[str, str] = {
    "chrome.exe": "browser",
    "msedge.exe": "browser",
    "firefox.exe": "browser",
    "brave.exe": "browser",
    "opera.exe": "browser",
    "code.exe": "dev",
    "code - insiders.exe": "dev",
    "pycharm64.exe": "dev",
    "idea64.exe": "dev",
    "devenv.exe": "dev",
    "sublime_text.exe": "dev",
    "windowsterminal.exe": "dev",
    "powershell.exe": "dev",
    "pwsh.exe": "dev",
    "cmd.exe": "dev",
    "git-bash.exe": "dev",
    "winword.exe": "office",
    "excel.exe": "office",
    "powerpnt.exe": "office",
    "wps.exe": "office",
    "et.exe": "office",
    "wpp.exe": "office",
    "notion.exe": "office",
    "obsidian.exe": "study",
    "acrobat.exe": "study",
    "acrord32.exe": "study",
    "zotero.exe": "study",
    "anki.exe": "study",
    "steam.exe": "entertainment",
    "spotify.exe": "entertainment",
    "bilibili.exe": "entertainment",
    "qqmusic.exe": "entertainment",
    "neteasemusic.exe": "entertainment",
    "wechat.exe": "communication",
    "weixin.exe": "communication",
    "qq.exe": "communication",
    "telegram.exe": "communication",
    "discord.exe": "communication",
    "slack.exe": "communication",
    "dingtalk.exe": "communication",
    "feishu.exe": "communication",
    "lark.exe": "communication",
}

#: 常见 exe 的展示名
DISPLAY_NAMES: dict[str, str] = {
    "chrome.exe": "Chrome",
    "msedge.exe": "Edge",
    "firefox.exe": "Firefox",
    "code.exe": "VS Code",
    "pycharm64.exe": "PyCharm",
    "idea64.exe": "IntelliJ IDEA",
    "devenv.exe": "Visual Studio",
    "sublime_text.exe": "Sublime Text",
    "windowsterminal.exe": "Terminal",
    "powershell.exe": "PowerShell",
    "winword.exe": "Word",
    "excel.exe": "Excel",
    "powerpnt.exe": "PowerPoint",
    "wps.exe": "WPS",
    "notion.exe": "Notion",
    "obsidian.exe": "Obsidian",
    "steam.exe": "Steam",
    "spotify.exe": "Spotify",
    "wechat.exe": "WeChat",
    "weixin.exe": "WeChat",
    "qq.exe": "QQ",
    "telegram.exe": "Telegram",
    "discord.exe": "Discord",
    "slack.exe": "Slack",
    "dingtalk.exe": "钉钉",
    "feishu.exe": "飞书",
    "lark.exe": "Lark",
}

LOCK_EXES = {"lockapp.exe", "logonui.exe", "winlogon.exe"}
_PROCESS_QUERY_LIMITED_INFORMATION = 0x1000
_WIN = os.name == "nt"
if _WIN:
    from ctypes import wintypes

    _user32 = ctypes.WinDLL("user32", use_last_error=True)
    _kernel32 = ctypes.WinDLL("kernel32", use_last_error=True)
    _user32.GetForegroundWindow.restype = wintypes.HWND
    _user32.GetWindowThreadProcessId.restype = wintypes.DWORD
    _user32.GetWindowThreadProcessId.argtypes = [
        wintypes.HWND,
        ctypes.POINTER(wintypes.DWORD),
    ]
    _user32.GetLastInputInfo.restype = wintypes.BOOL
    _user32.OpenInputDesktop.restype = wintypes.HANDLE
    _kernel32.OpenProcess.restype = wintypes.HANDLE
    _kernel32.OpenProcess.argtypes = [wintypes.DWORD, wintypes.BOOL, wintypes.DWORD]
    _kernel32.QueryFullProcessImageNameW.restype = wintypes.BOOL
    _kernel32.QueryFullProcessImageNameW.argtypes = [
        wintypes.HANDLE,
        wintypes.DWORD,
        wintypes.LPWSTR,
        ctypes.POINTER(wintypes.DWORD),
    ]
    _kernel32.CloseHandle.argtypes = [wintypes.HANDLE]
    _kernel32.GetTickCount.restype = wintypes.DWORD
    _user32.CloseDesktop.argtypes = [wintypes.HANDLE]

    class _LASTINPUTINFO(ctypes.Structure):
        _fields_ = [("cbSize", wintypes.UINT), ("dwTime", wintypes.DWORD)]


def own_process_names() -> set[str]:
    names = {"shenqing.exe", "深清.exe"}
    try:
        names.add(Path(sys.executable).name.lower())
    except (TypeError, ValueError, AttributeError):
        pass
    return names


def foreground_process() -> tuple[int, str] | None:
    """返回 (pid, exe 小写)；无前台窗口/受限时返回 None。"""
    if not _WIN:
        return None
    hwnd = int(_user32.GetForegroundWindow() or 0)
    if not hwnd:
        return None
    pid = wintypes.DWORD(0)
    _user32.GetWindowThreadProcessId(hwnd, ctypes.byref(pid))
    pid_value = int(pid.value)
    if pid_value <= 0:
        return None
    handle = _kernel32.OpenProcess(_PROCESS_QUERY_LIMITED_INFORMATION, False, pid_value)
    if not handle:
        return None
    try:
        size = wintypes.DWORD(1024)
        buffer = ctypes.create_unicode_buffer(1024)
        if not _kernel32.QueryFullProcessImageNameW(handle, 0, buffer, ctypes.byref(size)):
            return None
        return pid_value, Path(buffer.value).name.lower()
    finally:
        _kernel32.CloseHandle(handle)


def idle_milliseconds() -> int:
    """距最后一次键鼠输入的毫秒数；失败返回 0。"""
    if not _WIN:
        return 0
    info = _LASTINPUTINFO()
    info.cbSize = ctypes.sizeof(_LASTINPUTINFO)
    if not _user32.GetLastInputInfo(ctypes.byref(info)):
        return 0
    now = int(_kernel32.GetTickCount()) & 0xFFFFFFFF
    return max(0, (now - int(info.dwTime)) & 0xFFFFFFFF)


def session_locked() -> bool:
    """锁屏/切换用户时 OpenInputDesktop 会失败。"""
    if not _WIN:
        return False
    try:
        desktop = _user32.OpenInputDesktop(0, False, 0x0100)  # DESKTOP_SWITCHDESKTOP
        if not desktop:
            return True
        _user32.CloseDesktop(desktop)
        return False
    except Exception:  # noqa: BLE001
        return False


def pretty_name(exe: str) -> str:
    name = DISPLAY_NAMES.get(exe)
    if name:
        return name
    stem = exe[:-4] if exe.lower().endswith(".exe") else exe
    return stem.replace("_", " ").replace("-", " ").title() or exe


class AppUsageTracker(QObject):
    """前台应用使用时长采样器（桥持有；测试可注入时钟/Win32 函数）。"""

    changed = Signal()

    def __init__(
        self,
        path: Path | None = None,
        *,
        parent: QObject | None = None,
        clock: Callable[[], float] | None = None,
        now_provider: Callable[[], datetime] | None = None,
        foreground_provider: Callable[[], tuple[int, str] | None] | None = None,
        idle_provider: Callable[[], int] | None = None,
        locked_provider: Callable[[], bool] | None = None,
        sample_interval_ms: int = SAMPLE_INTERVAL_MS,
    ) -> None:
        super().__init__(parent)
        self._path = Path(path) if path is not None else (app_data_dir() / DATA_NAME)
        self._overrides_path = self._path.with_name(OVERRIDES_NAME)
        self._clock = clock or time.monotonic
        self._now = now_provider or datetime.now
        self._foreground = foreground_provider or foreground_process
        self._idle = idle_provider or idle_milliseconds
        self._locked = locked_provider or session_locked
        self._days: dict[str, dict[str, dict]] = {}
        self._category_overrides: dict[str, str] = {}
        self._color_overrides: dict[str, str] = {}
        self._own_names = own_process_names()
        self._last_sample_at = self._clock()
        self._today = self._now().date().isoformat()
        self._dirty = False
        self._started = False
        self._sample_timer = QTimer(self)
        self._sample_timer.setInterval(max(1000, int(sample_interval_ms)))
        self._sample_timer.timeout.connect(self.sample)
        self._flush_timer = QTimer(self)
        self._flush_timer.setInterval(FLUSH_INTERVAL_MS)
        self._flush_timer.timeout.connect(self.flush)
        self.load()

    # ---------- 生命周期 ----------
    def start(self) -> None:
        if self._started:
            return
        self._started = True
        self._last_sample_at = self._clock()
        self._sample_timer.start()
        self._flush_timer.start()

    def shutdown(self) -> None:
        self._sample_timer.stop()
        self._flush_timer.stop()
        self.flush()
        self._started = False

    @property
    def started(self) -> bool:
        return self._started

    # ---------- 持久化 ----------
    def load(self) -> None:
        try:
            data = json.loads(self._path.read_text(encoding="utf-8"))
        except (OSError, json.JSONDecodeError, ValueError):
            data = None
        self._days = {}
        if isinstance(data, dict):
            for day, items in data.items():
                if not isinstance(items, dict):
                    continue
                bucket: dict[str, dict] = {}
                for exe, entry in items.items():
                    if not isinstance(entry, dict):
                        continue
                    try:
                        minutes = max(0.0, float(entry.get("minutes", 0)))
                    except (TypeError, ValueError):
                        continue
                    bucket[str(exe).lower()] = {
                        "minutes": round(minutes, 2),
                        "name": str(entry.get("name") or pretty_name(str(exe).lower())),
                    }
                self._days[str(day)] = bucket
        try:
            overrides = json.loads(self._overrides_path.read_text(encoding="utf-8"))
        except (OSError, json.JSONDecodeError, ValueError):
            overrides = None
        self._category_overrides = {}
        self._color_overrides = {}
        if isinstance(overrides, dict):
            categories = overrides.get("categories")
            if isinstance(categories, dict):
                self._category_overrides = {
                    str(exe).lower(): str(value)
                    for exe, value in categories.items()
                    if str(value) in CATEGORY_COLORS
                }
            colors = overrides.get("colors")
            if isinstance(colors, dict):
                self._color_overrides = {
                    str(exe).lower(): str(value)
                    for exe, value in colors.items()
                    if is_hex_color(str(value))
                }

    def flush(self) -> None:
        try:
            self._path.parent.mkdir(parents=True, exist_ok=True)
            trimmed = {
                day: self._days[day]
                for day in sorted(self._days.keys())[-KEEP_DAYS:]
            }
            self._days = trimmed
            payload = {
                day: {
                    exe: {"minutes": round(float(entry.get("minutes", 0)), 2),
                          "name": str(entry.get("name") or pretty_name(exe))}
                    for exe, entry in items.items()
                }
                for day, items in self._days.items()
            }
            self._path.write_text(
                json.dumps(payload, ensure_ascii=False, indent=2), encoding="utf-8"
            )
            self._overrides_path.write_text(
                json.dumps(
                    {
                        "categories": self._category_overrides,
                        "colors": self._color_overrides,
                    },
                    ensure_ascii=False,
                    indent=2,
                ),
                encoding="utf-8",
            )
            self._dirty = False
        except OSError as exc:
            logger.warning("保存应用使用数据失败：%s", exc)

    # ---------- 采样 ----------
    def sample(self) -> None:
        """采样一次（5 秒定时器 / 测试直接调用）。"""
        try:
            now_mono = self._clock()
            wall = self._now()
            day = wall.date().isoformat()
            if day != self._today:
                self.flush()
                self._today = day
            foreground = None if self._locked() else self._foreground()
            idle = self._idle()
            self._accumulate(foreground, idle, now_mono)
        except Exception as exc:  # noqa: BLE001 - 统计失败不能拖垮主程序
            logger.warning("应用使用采样失败：%s", exc)

    def _accumulate(
        self, foreground: tuple[int, str] | None, idle_ms: int, now_mono: float
    ) -> None:
        delta = now_mono - self._last_sample_at
        self._last_sample_at = now_mono
        if foreground is None:
            return
        pid, exe = foreground
        exe = str(exe or "").strip().lower()
        if not exe or pid == os.getpid() or exe in self._own_names:
            return
        if idle_ms >= IDLE_LIMIT_MS:
            return
        if delta <= 0 or delta > MAX_SAMPLE_GAP_SECONDS:
            return
        bucket = self._days.setdefault(self._today, {})
        entry = bucket.setdefault(exe, {"minutes": 0.0, "name": pretty_name(exe)})
        entry["minutes"] = round(float(entry.get("minutes", 0.0)) + delta / 60.0, 2)
        entry["name"] = pretty_name(exe)
        self._dirty = True

    # ---------- 分类 / 颜色 ----------
    def category_for(self, exe: str) -> str:
        value = str(exe or "").lower()
        override = self._category_overrides.get(value)
        if override in CATEGORY_COLORS:
            return override
        return BUILTIN_CATEGORY.get(value, DEFAULT_CATEGORY)

    def color_for(self, exe: str) -> str:
        value = str(exe or "").lower()
        override = self._color_overrides.get(value)
        if override:
            return override
        return CATEGORY_COLORS.get(self.category_for(value), CATEGORY_COLORS[DEFAULT_CATEGORY])

    def set_category(self, exe: str, category: str) -> bool:
        value = str(exe or "").strip().lower()
        key = str(category or "").strip()
        if not value:
            return False
        if key not in CATEGORY_COLORS:
            # 接受中文标签
            for item in CATEGORIES:
                if item["label"] == key:
                    key = item["value"]
                    break
        if key not in CATEGORY_COLORS:
            return False
        self._category_overrides[value] = key
        self._dirty = True
        self.flush()
        self.changed.emit()
        return True

    def set_color(self, exe: str, color: str) -> bool:
        value = str(exe or "").strip().lower()
        text = str(color or "").strip()
        if not value or not is_hex_color(text):
            return False
        self._color_overrides[value] = text.upper()
        self._dirty = True
        self.flush()
        self.changed.emit()
        return True

    # ---------- 查询 ----------
    def _bucket(self, day: str) -> dict[str, dict]:
        return self._days.get(str(day), {})

    def usage_for(self, day: str | None = None, limit: int = 20) -> list[dict]:
        key = str(day or self._now().date().isoformat())
        items = self._bucket(key)
        result = [
            {
                "exe": exe,
                "name": str(entry.get("name") or pretty_name(exe)),
                "minutes": round(float(entry.get("minutes", 0)), 1),
                "color": self.color_for(exe),
                "category": self.category_for(exe),
            }
            for exe, entry in items.items()
            if float(entry.get("minutes", 0)) > 0
        ]
        result.sort(key=lambda item: item["minutes"], reverse=True)
        return result[: max(0, int(limit))]

    def week_usage(self, limit: int = 20) -> list[dict]:
        """最近 7 天（含今天）按 exe 汇总。"""
        today = self._now().date()
        days = {(today - timedelta(days=offset)).isoformat() for offset in range(7)}
        totals: dict[str, dict] = {}
        for day in days:
            for exe, entry in self._bucket(day).items():
                minutes = float(entry.get("minutes", 0))
                if minutes <= 0:
                    continue
                target = totals.setdefault(
                    exe, {"minutes": 0.0, "name": str(entry.get("name") or pretty_name(exe))}
                )
                target["minutes"] = round(target["minutes"] + minutes, 2)
        result = [
            {
                "exe": exe,
                "name": str(entry["name"]),
                "minutes": round(float(entry["minutes"]), 1),
                "color": self.color_for(exe),
                "category": self.category_for(exe),
            }
            for exe, entry in totals.items()
            if float(entry["minutes"]) > 0
        ]
        result.sort(key=lambda item: item["minutes"], reverse=True)
        return result[: max(0, int(limit))]

    def total_minutes(self, day: str | None = None) -> float:
        key = str(day or self._now().date().isoformat())
        return round(
            sum(float(entry.get("minutes", 0)) for entry in self._bucket(key).values()), 1
        )

    def category_totals(self, day: str | None = None) -> list[dict]:
        key = str(day or self._now().date().isoformat())
        totals: dict[str, float] = {}
        for exe, entry in self._bucket(key).items():
            category = self.category_for(exe)
            totals[category] = totals.get(category, 0.0) + float(entry.get("minutes", 0))
        result = [
            {
                "category": category,
                "label": CATEGORY_LABELS.get(category, category),
                "name": CATEGORY_LABELS.get(category, category),
                "minutes": round(minutes, 1),
                "color": CATEGORY_COLORS.get(category, CATEGORY_COLORS[DEFAULT_CATEGORY]),
            }
            for category, minutes in totals.items()
            if minutes > 0
        ]
        result.sort(key=lambda item: item["minutes"], reverse=True)
        return result


def is_hex_color(value: str) -> bool:
    text = str(value or "").strip()
    if len(text) != 7 or not text.startswith("#"):
        return False
    try:
        int(text[1:], 16)
    except ValueError:
        return False
    return True
