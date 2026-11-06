"""应用路径解析：区分开发环境与 PyInstaller 打包环境。"""

from __future__ import annotations

import os
import sys
from pathlib import Path

from .consts import APP_ID


def app_data_dir() -> Path:
    """用户数据目录：%APPDATA%\\ShenQing（可用 SHENQING_DATA_DIR 覆盖，便于测试）。"""
    override = os.environ.get("SHENQING_DATA_DIR")
    if override:
        path = Path(override)
        path.mkdir(parents=True, exist_ok=True)
        return path
    base = os.environ.get("APPDATA")
    root = Path(base) if base else Path.home() / "AppData" / "Roaming"
    path = root / APP_ID
    path.mkdir(parents=True, exist_ok=True)
    return path


def logs_dir() -> Path:
    path = app_data_dir() / "logs"
    path.mkdir(parents=True, exist_ok=True)
    return path


def resource_root() -> Path:
    """静态资源根：PyInstaller 解包目录，或 src/shenqing。"""
    bundled = getattr(sys, "_MEIPASS", None)
    if bundled:
        return Path(bundled)
    return Path(__file__).resolve().parent


def project_root() -> Path:
    """开发态仓库根目录（src 的上一级）。"""
    return Path(__file__).resolve().parents[2]


def _find_doc(name: str) -> Path:
    for candidate in (resource_root() / name, project_root() / name):
        if candidate.exists():
            return candidate
    return resource_root() / name


def license_file() -> Path:
    return _find_doc("LICENSE")


def notice_file() -> Path:
    return _find_doc("NOTICE")


def qml_dir() -> Path:
    return resource_root() / "qml"


def qml_file(*parts: str) -> Path:
    return qml_dir().joinpath(*parts)
