"""GitHub Releases 自动更新（v0.6）。

- 仓库：Kryon2025/Clarity（consts.GITHUB_REPO）
- check_latest(): GET /releases/latest，只在远端版本 > 当前 APP_VERSION 时返回信息
- download(): 分块下载安装包，可回调进度、可取消
- version_tuple()/is_newer()：宽松版本比较（忽略 v 前缀与非数字段，长度不同按 0 补齐）

全部为纯函数/阻塞 IO，供 bridge 在后台线程调用，不直接依赖 Qt。
"""

from __future__ import annotations

import json
import logging
import re
import threading
import urllib.error
import urllib.request
from pathlib import Path
from typing import Any, Callable

from ..consts import APP_VERSION, GITHUB_REPO

logger = logging.getLogger("shenqing.updater")

API_LATEST = f"https://api.github.com/repos/{GITHUB_REPO}/releases/latest"
RELEASES_PAGE = f"https://github.com/{GITHUB_REPO}/releases"
USER_AGENT = "ShenQing-Updater"
ACCEPT = "application/vnd.github+json"
TIMEOUT_SECONDS = 20
CHUNK_SIZE = 64 * 1024


class CancelToken:
    """下载取消令牌（线程安全）。"""

    def __init__(self) -> None:
        self._event = threading.Event()

    def cancel(self) -> None:
        self._event.set()

    @property
    def cancelled(self) -> bool:
        return self._event.is_set()

    def is_set(self) -> bool:
        return self._event.is_set()


def version_tuple(version: object) -> tuple[int, ...]:
    """'v0.6.10' → (0, 6, 10)；非数字段丢弃，至少返回一个元素。"""
    text = str(version or "").strip().lower()
    if text.startswith("v"):
        text = text[1:]
    parts = re.findall(r"\d+", text)
    if not parts:
        return (0,)
    return tuple(int(part) for part in parts)


def is_newer(remote: object, current: object = APP_VERSION) -> bool:
    """远端版本是否严格大于当前版本（长度不同按 0 补齐）。"""
    left = version_tuple(remote)
    right = version_tuple(current)
    length = max(len(left), len(right))
    left = left + (0,) * (length - len(left))
    right = right + (0,) * (length - len(right))
    return left > right


def select_asset(assets: list[dict] | None) -> dict | None:
    """只挑安装包：优先文件名含 Setup 的 .exe，其次第一个 .exe。"""
    exes: list[dict] = []
    for asset in assets or []:
        if not isinstance(asset, dict):
            continue
        name = str(asset.get("name") or "")
        if name.lower().endswith(".exe"):
            exes.append(asset)
    if not exes:
        return None
    for asset in exes:
        if "setup" in str(asset.get("name") or "").lower():
            return asset
    return exes[0]


def _fetch_release() -> dict | None:
    """请求 GitHub latest release；失败返回 None（调用方决定是否报错）。"""
    request = urllib.request.Request(
        API_LATEST,
        headers={"Accept": ACCEPT, "User-Agent": USER_AGENT},
    )
    with urllib.request.urlopen(request, timeout=TIMEOUT_SECONDS) as response:  # noqa: S310
        payload = response.read().decode("utf-8", errors="replace")
    data = json.loads(payload)
    return data if isinstance(data, dict) else None


def check_latest(current_version: str | None = None) -> dict | None:
    """检查最新版本；有更新返回信息 dict，否则/失败返回 None。"""
    current = current_version or APP_VERSION
    try:
        release = _fetch_release()
    except (urllib.error.URLError, OSError, ValueError, json.JSONDecodeError) as exc:
        logger.warning("检查更新失败：%s", exc)
        return None
    if not release:
        return None
    tag = str(release.get("tag_name") or "").strip()
    version = tag[1:] if tag.lower().startswith("v") else tag
    if not version or not is_newer(version, current):
        return None
    asset = select_asset(release.get("assets"))
    return {
        "version": version,
        "tag": tag,
        "notes": str(release.get("body") or ""),
        "pageUrl": str(release.get("html_url") or RELEASES_PAGE),
        "assetName": str(asset.get("name") or "") if asset else "",
        "assetUrl": str(asset.get("browser_download_url") or "") if asset else "",
        "assetSize": int(asset.get("size") or 0) if asset else 0,
    }


def download(
    asset_url: str,
    dest_path: str | Path,
    on_progress: Callable[[int], None] | None = None,
    cancel: CancelToken | None = None,
) -> bool:
    """分块下载安装包到 dest_path；成功返回 True。可被 cancel 中途取消。"""
    url = str(asset_url or "").strip()
    if not url:
        return False
    dest = Path(dest_path)
    part = dest.with_name(dest.name + ".part")
    notified = -1

    def _progress(value: int) -> None:
        nonlocal notified
        if on_progress is None:
            return
        value = max(0, min(100, int(value)))
        if value == notified:
            return
        notified = value
        try:
            on_progress(value)
        except Exception as exc:  # noqa: BLE001 - 进度回调不能影响下载
            logger.warning("下载进度回调失败：%s", exc)

    try:
        dest.parent.mkdir(parents=True, exist_ok=True)
        request = urllib.request.Request(url, headers={"User-Agent": USER_AGENT})
        with urllib.request.urlopen(request, timeout=TIMEOUT_SECONDS) as response:  # noqa: S310
            total = int(response.headers.get("Content-Length") or 0)
            received = 0
            _progress(0)
            with part.open("wb") as handle:
                while True:
                    if cancel is not None and cancel.cancelled:
                        handle.close()
                        _remove(part)
                        logger.info("更新下载已取消")
                        return False
                    chunk = response.read(CHUNK_SIZE)
                    if not chunk:
                        break
                    handle.write(chunk)
                    received += len(chunk)
                    if total > 0:
                        _progress(received * 100 // total)
        if part.exists() and part.stat().st_size <= 0:
            _remove(part)
            return False
        part.replace(dest)
        _progress(100)
        return True
    except (urllib.error.URLError, OSError, ValueError) as exc:
        logger.warning("下载更新失败：%s", exc)
        _remove(part)
        return False


def _remove(path: Path) -> None:
    try:
        path.unlink()
    except OSError:
        pass


def release_page_url(fallback: str = "") -> str:
    return fallback or RELEASES_PAGE


def format_notes(notes: object, limit: int = 4000) -> str:
    text = str(notes or "").strip()
    return text[:limit]
