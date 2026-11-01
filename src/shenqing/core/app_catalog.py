"""本机应用清单：扫描开始菜单快捷方式，解析目标 exe、抓图标、粗分类。

用于「允许使用的应用」白名单页。结果缓存到 %APPDATA%\\ShenQing\\apps.json，
暴露 `refresh` 时重扫（扫描约 1–5 秒，取决于开始菜单规模）。
"""

from __future__ import annotations

import json
import os
import time
from pathlib import Path
from typing import Any

from ..paths import app_data_dir

#: 分类关键词（按顺序匹配，先命中先用）
CATEGORY_RULES: list[tuple[str, tuple[str, ...]]] = [
    (
        "办公软件",
        (
            "office", "word", "excel", "powerpoint", "wps", "notion", "onenote",
            "acrobat", "pdf", "xmind", "typora", "obsidian", "飞书", "钉钉", "石墨",
            "outlook", "foxmail", "onenote", "印象笔记", "语雀",
        ),
    ),
    (
        "教育学习",
        (
            "学习", "作业", "课堂", "课程", "题库", "考试", "单词", "词典", "翻译",
            "anki", "geogebra", "desmos", "智学", "网课", "学堂", "刷题", "笔记",
            "math", "英语", "数学", "物理", "化学", "生物", "语文", "历史", "地理",
        ),
    ),
    (
        "实用工具",
        (
            "计算器", "截图", "压缩", "7-zip", "bandizip", "winrar", "命令行", "终端",
            "记事本", "画图", "资源管理器", "控制面板", "设置", "cmd", "powershell",
            "terminal", "notepad", "snipaste", "calculator", "paint", "任务管理器",
            "taskmgr", "everything", "quicklook", "utools",
        ),
    ),
]

DEFAULT_CATEGORY = "其他"
CATEGORIES = ["全部应用", "办公软件", "教育学习", "实用工具", "其他"]

#: 明显不是「给人用的应用」的目标，扫到就丢
_SKIP_EXE = {
    "unins000.exe", "uninstall.exe", "uninst.exe", "setup.exe", "update.exe",
    "updater.exe", "crashpad_handler.exe", "elevate.exe",
}
_SKIP_NAME_KEYWORDS = ("卸载", "uninstall", "readme", "帮助", "帮助文档", "license", "许可")

_CACHE_TTL_SECONDS = 12 * 3600


def _start_menu_dirs() -> list[Path]:
    dirs: list[Path] = []
    program_data = os.environ.get("ProgramData")
    if program_data:
        dirs.append(Path(program_data) / "Microsoft" / "Windows" / "Start Menu" / "Programs")
    appdata = os.environ.get("APPDATA")
    if appdata:
        dirs.append(Path(appdata) / "Microsoft" / "Windows" / "Start Menu" / "Programs")
    return [d for d in dirs if d.is_dir()]


def _resolve_shortcut(shell: Any, lnk: Path) -> str:
    """用 WScript.Shell 解析 .lnk 目标路径。"""
    try:
        shortcut = shell.CreateShortcut(str(lnk))
        return str(shortcut.Targetpath or "")
    except Exception:  # noqa: BLE001 - COM 对各种坏快捷方式都会抛
        return ""


def _iter_shortcuts(limit: int = 600) -> list[Path]:
    found: list[Path] = []
    for base in _start_menu_dirs():
        for path in base.rglob("*.lnk"):
            found.append(path)
            if len(found) >= limit:
                return found
    return found


def _classify(name: str, path: str) -> str:
    haystack = f"{name} {path}".lower()
    for category, keywords in CATEGORY_RULES:
        if any(keyword.lower() in haystack for keyword in keywords):
            return category
    return DEFAULT_CATEGORY


def _icon_url(exe_path: Path, icons_dir: Path, key: str) -> str:
    """用 Qt 的 QFileIconProvider 抓 exe 图标并缓存为 png，返回 file:// URL。"""
    try:
        from PySide6.QtGui import QGuiApplication
    except ImportError:  # pragma: no cover
        return ""
    if QGuiApplication.instance() is None:
        return ""
    target = icons_dir / f"{key}.png"
    if target.exists():
        return target.resolve().as_uri()
    try:
        from PySide6.QtCore import QFileInfo, QSize
        from PySide6.QtWidgets import QFileIconProvider

        provider = QFileIconProvider()
        icon = provider.icon(QFileInfo(str(exe_path)))
        if icon.isNull():
            return ""
        pixmap = icon.pixmap(QSize(64, 64))
        if pixmap.isNull():
            return ""
        icons_dir.mkdir(parents=True, exist_ok=True)
        if not pixmap.save(str(target), "PNG"):
            return ""
        return target.resolve().as_uri()
    except Exception:  # noqa: BLE001 - 图标失败不影响清单
        return ""


def _scan() -> list[dict]:
    import hashlib

    shortcuts = _iter_shortcuts()
    if not shortcuts:
        return []

    try:
        import pythoncom
        import win32com.client

        pythoncom.CoInitialize()
    except Exception:  # noqa: BLE001 - 没有 pywin32 就退化为空清单
        return []

    try:
        shell = win32com.client.Dispatch("WScript.Shell")
    except Exception:  # noqa: BLE001
        return []

    icons_dir = app_data_dir() / "icons"
    catalog: dict[str, dict] = {}
    for shortcut in shortcuts:
        raw_name = shortcut.stem
        if any(keyword in raw_name.lower() for keyword in _SKIP_NAME_KEYWORDS):
            continue
        target = _resolve_shortcut(shell, shortcut)
        if not target:
            continue
        exe_path = Path(target)
        if exe_path.suffix.lower() != ".exe" or not exe_path.exists():
            continue
        exe = exe_path.name.lower()
        if exe in _SKIP_EXE or exe in catalog:
            continue
        stem = exe_path.stem.lower()
        if "unins" in stem or "uninstall" in stem:
            continue
        key = hashlib.md5(f"{exe}|{exe_path}".encode()).hexdigest()[:16]
        catalog[exe] = {
            "exe": exe,
            "name": raw_name.strip() or exe_path.stem,
            "path": str(exe_path),
            "iconUrl": _icon_url(exe_path, icons_dir, key),
            "category": _classify(raw_name, str(exe_path)),
        }
    items = list(catalog.values())
    items.sort(key=lambda item: (item["category"], item["name"].lower()))
    return items


def load_cached() -> list[dict]:
    """只读缓存，不做扫描；没有缓存返回空列表（供启动时快速取用）。"""
    cache_path = app_data_dir() / "apps.json"
    try:
        data: Any = json.loads(cache_path.read_text(encoding="utf-8"))
        items = data.get("apps")
        if isinstance(items, list):
            return items
    except (OSError, json.JSONDecodeError):
        pass
    return []


def load_catalog(force: bool = False) -> list[dict]:
    """读取应用清单（默认 12 小时缓存，force=True 重扫）。"""
    cache_path = app_data_dir() / "apps.json"
    if not force and cache_path.exists():
        try:
            data: Any = json.loads(cache_path.read_text(encoding="utf-8"))
            built = float(data.get("built", 0))
            items = data.get("apps")
            if isinstance(items, list) and items and time.time() - built < _CACHE_TTL_SECONDS:
                return items
        except (OSError, json.JSONDecodeError, TypeError, ValueError):
            pass

    items = _scan()
    try:
        cache_path.parent.mkdir(parents=True, exist_ok=True)
        cache_path.write_text(
            json.dumps({"built": int(time.time()), "apps": items}, ensure_ascii=False, indent=2),
            encoding="utf-8",
        )
    except OSError:
        pass
    return items
