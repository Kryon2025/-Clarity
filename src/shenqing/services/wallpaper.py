"""Bing 每日壁纸 + Windows 用户头像（v0.8）。

- bing_wallpaper_url(): 抓 HPImageArchive，下载到 %APPDATA%/ShenQing/cache/bing.jpg，返回 file:// URL；
- user_avatar_url(): 找 %APPDATA%/Microsoft/AccountPictures 下最新的头像图片，返回 file:// URL；
失败均返回空串，不阻塞 UI（由 bridge 后台线程调用）。
"""

from __future__ import annotations

import json
import logging
import os
import urllib.request
from datetime import date
from pathlib import Path

from ..paths import app_data_dir

logger = logging.getLogger("shenqing.wallpaper")

BING_API = "https://www.bing.com/HPImageArchive.aspx?format=js&idx=0&n=1"
BING_BASE = "https://www.bing.com"
USER_AGENT = "ShenQing-Wallpaper"
TIMEOUT_SECONDS = 15
IMAGE_SUFFIXES = (".png", ".jpg", ".jpeg", ".bmp", ".webp")


def cache_dir() -> Path:
    path = app_data_dir() / "cache"
    path.mkdir(parents=True, exist_ok=True)
    return path


def bing_cache_path() -> Path:
    return cache_dir() / "bing.jpg"


def _to_url(path: Path) -> str:
    try:
        return path.resolve().as_uri()
    except (OSError, ValueError):
        return ""


def cached_bing_url() -> str:
    path = bing_cache_path()
    if path.exists() and path.stat().st_size > 0:
        return _to_url(path)
    return ""


def _fetch_bing_image_url() -> str:
    request = urllib.request.Request(
        BING_API, headers={"User-Agent": USER_AGENT, "Cache-Control": "no-cache"}
    )
    with urllib.request.urlopen(request, timeout=TIMEOUT_SECONDS) as response:  # noqa: S310
        data = json.loads(response.read().decode("utf-8", errors="replace"))
    images = data.get("images") if isinstance(data, dict) else None
    if not isinstance(images, list) or not images:
        return ""
    url = str(images[0].get("url") or "")
    if not url:
        return ""
    if url.startswith("http"):
        return url
    if url.startswith("/"):
        return BING_BASE + url
    return BING_BASE + "/" + url


def refresh_bing_wallpaper(force: bool = False) -> str:
    """下载今天的 Bing 壁纸（当天已缓存则只校验文件）；返回 file:// URL 或空串。"""
    cached = bing_cache_path()
    try:
        if not force and cached.exists() and cached.stat().st_size > 0:
            if date.fromtimestamp(cached.stat().st_mtime) == date.today():
                return _to_url(cached)
    except OSError:
        pass
    try:
        image_url = _fetch_bing_image_url()
        if not image_url:
            return cached_bing_url()
        request = urllib.request.Request(image_url, headers={"User-Agent": USER_AGENT})
        with urllib.request.urlopen(request, timeout=TIMEOUT_SECONDS) as response:  # noqa: S310
            content = response.read()
        if not content:
            return cached_bing_url()
        cached.parent.mkdir(parents=True, exist_ok=True)
        cached.write_bytes(content)
        logger.info("Bing 壁纸已缓存：%s", cached)
        return _to_url(cached)
    except Exception as exc:  # noqa: BLE001 - 壁纸失败不能影响主程序
        logger.info("获取 Bing 壁纸失败：%s", exc)
        return cached_bing_url()


def avatar_dirs() -> list[Path]:
    result: list[Path] = []
    appdata = os.environ.get("APPDATA")
    if appdata:
        result.append(Path(appdata) / "Microsoft" / "AccountPictures")
    try:
        result.append(Path.home() / "AppData" / "Roaming" / "Microsoft" / "AccountPictures")
    except RuntimeError:  # pragma: no cover
        pass
    return result


def user_avatar_url() -> str:
    """Windows 当前用户头像（最新一张）；找不到返回空串。"""
    candidates: list[Path] = []
    for folder in avatar_dirs():
        try:
            if not folder.exists():
                continue
            for item in folder.iterdir():
                if item.is_file() and item.suffix.lower() in IMAGE_SUFFIXES:
                    candidates.append(item)
        except OSError:
            continue
    if not candidates:
        return ""
    try:
        newest = max(candidates, key=lambda p: p.stat().st_mtime)
        return _to_url(newest)
    except OSError:
        return ""
