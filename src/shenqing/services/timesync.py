"""网络时间校准（v0.8）：HTTP Date 头 → 本机时钟偏移。

- 启动时 sync_now() 请求 https://www.bing.com / api.github.com 的 Date 头；
- 偏移 = 服务器时间 - 本机 time.time()，持久化到 time_sync.json（供下次启动兜底）；
- now() 返回网络校准后的本地时间；会话计时仍用 time.monotonic() 锚点，避免休眠/改表影响。
"""

from __future__ import annotations

import json
import logging
import threading
import time
import urllib.request
from datetime import datetime
from email.utils import parsedate_to_datetime

from ..paths import app_data_dir

logger = logging.getLogger("shenqing.timesync")

CACHE_NAME = "time_sync.json"
URLS = ("https://api.github.com", "https://www.bing.com")
TIMEOUT_SECONDS = 6
USER_AGENT = "ShenQing-TimeSync"

_lock = threading.Lock()
_offset_seconds = 0.0
_synced_at = 0.0
_source = ""
_synced = False


def _parse_http_date(value: str) -> float | None:
    try:
        parsed = parsedate_to_datetime(str(value or ""))
    except (TypeError, ValueError):
        return None
    if parsed is None:
        return None
    if parsed.tzinfo is None:
        parsed = parsed.replace(tzinfo=datetime.now().astimezone().tzinfo)
    return parsed.timestamp()


def _fetch_offset(timeout: float = TIMEOUT_SECONDS) -> tuple[float, str] | None:
    for url in URLS:
        try:
            request = urllib.request.Request(
                url, headers={"User-Agent": USER_AGENT, "Cache-Control": "no-cache"}
            )
            with urllib.request.urlopen(request, timeout=timeout) as response:  # noqa: S310
                header = response.headers.get("Date")
            server = _parse_http_date(header or "")
            if server is None:
                continue
            return server - time.time(), url
        except Exception as exc:  # noqa: BLE001 - 网络失败换下一个源
            logger.debug("网络时间源失败 %s：%s", url, exc)
    return None


def _cache_path():
    return app_data_dir() / CACHE_NAME


def _save_cache(offset: float, source: str) -> None:
    try:
        payload = {
            "offset": round(float(offset), 3),
            "syncedAt": int(time.time()),
            "source": str(source),
        }
        _cache_path().write_text(
            json.dumps(payload, ensure_ascii=False, indent=2), encoding="utf-8"
        )
    except OSError:
        pass


def load_cache() -> None:
    """读取上次的偏移（即使本次联网失败也能用近似值）。"""
    global _offset_seconds, _synced_at, _source, _synced
    try:
        data = json.loads(_cache_path().read_text(encoding="utf-8"))
    except (OSError, json.JSONDecodeError, ValueError):
        return
    if not isinstance(data, dict):
        return
    try:
        offset = float(data.get("offset", 0.0))
        synced_at = float(data.get("syncedAt", 0.0))
    except (TypeError, ValueError):
        return
    if not synced_at:
        return
    with _lock:
        _offset_seconds = offset
        _synced_at = synced_at
        _source = str(data.get("source") or "")
        _synced = True


def sync_now(timeout: float = TIMEOUT_SECONDS) -> bool:
    """联网取一次 Date 头并更新偏移；成功返回 True。"""
    global _offset_seconds, _synced_at, _source, _synced
    result = _fetch_offset(timeout)
    if result is None:
        logger.info("网络时间同步失败，沿用本地时钟/缓存偏移")
        return False
    offset, source = result
    with _lock:
        _offset_seconds = offset
        _synced_at = time.time()
        _source = source
        _synced = True
    _save_cache(offset, source)
    logger.info("网络时间已校准：偏移 %.3fs（%s）", offset, source)
    return True


def offset_seconds() -> float:
    with _lock:
        return _offset_seconds


def synced() -> bool:
    with _lock:
        return _synced


def synced_at() -> float:
    with _lock:
        return _synced_at


def source() -> str:
    with _lock:
        return _source


def now() -> datetime:
    """网络校准后的本地时间（未同步时等于本地时间）。"""
    return datetime.fromtimestamp(time.time() + offset_seconds()).astimezone()


def today():
    return now().date()
