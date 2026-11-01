"""Windows SMTC（System Media Transport Controls）媒体信息服务。

后台线程跑 asyncio 轮询当前媒体会话（标题/艺术家/播放状态/进度），
通过 Qt 信号把数据交给主线程；提供播放/暂停、上一首、下一首控制。
不依赖第三方包以外的 GUI，WinRT 不可用时整体降级为 available=False。
"""

from __future__ import annotations

import asyncio
import threading
from typing import Any

from PySide6.QtCore import QObject, Signal

#: 常见播放器 AUMID/进程名 -> 友好名
_APP_NAMES: dict[str, str] = {
    "spotify": "Spotify",
    "cloudmusic": "网易云音乐",
    "netease": "网易云音乐",
    "qqmusic": "QQ 音乐",
    "kugou": "酷狗音乐",
    "kuwo": "酷我音乐",
    "bilibili": "哔哩哔哩",
    "potplayer": "PotPlayer",
    "vlc": "VLC",
    "music.ui": "Groove 音乐",
    "zunemusic": "Groove 音乐",
    "foobar": "foobar2000",
    "chrome": "Chrome",
    "msedge": "Edge",
    "firefox": "Firefox",
}


def _friendly_app(app_id: str) -> str:
    lowered = (app_id or "").lower()
    for key, name in _APP_NAMES.items():
        if key in lowered:
            return name
    if "!" in app_id:
        tail = app_id.split("!")[0].split(".")[-1]
        return tail.capitalize() or "媒体"
    return app_id or "媒体"


class MediaSmtcService(QObject):
    """轮询 SMTC 会话；数据以 dict 形式发 changed 信号。"""

    changed = Signal(dict)

    def __init__(self, parent: QObject | None = None, interval: float = 1.0) -> None:
        super().__init__(parent)
        self._interval = max(0.4, interval)
        self._loop: asyncio.AbstractEventLoop | None = None
        self._thread: threading.Thread | None = None
        self._stop = threading.Event()
        self._available = False
        self._last: dict[str, Any] = {}
        self._lock = threading.Lock()

    # ---------- 生命周期 ----------
    @property
    def available(self) -> bool:
        return self._available

    def start(self) -> None:
        if self._thread is not None and self._thread.is_alive():
            return
        try:  # 预热导入，让 available 尽早反映真实情况
            from winrt.windows.media.control import (  # noqa: F401
                GlobalSystemMediaTransportControlsSessionManager,
            )

            self._available = True
        except Exception:  # noqa: BLE001 - 没装 WinRT 就降级
            self._available = False
            return
        self._stop.clear()
        self._thread = threading.Thread(target=self._run, name="shenqing-smtc", daemon=True)
        self._thread.start()

    def stop(self) -> None:
        self._stop.set()
        loop = self._loop
        if loop is not None and loop.is_running():
            try:
                loop.call_soon_threadsafe(loop.stop)
            except RuntimeError:
                pass

    # ---------- 后台线程 ----------
    def _run(self) -> None:
        loop = asyncio.new_event_loop()
        self._loop = loop
        asyncio.set_event_loop(loop)
        try:
            loop.run_until_complete(self._poll())
        except Exception:  # noqa: BLE001
            pass
        finally:
            try:
                loop.close()
            except Exception:  # noqa: BLE001
                pass
            self._loop = None

    async def _poll(self) -> None:
        from winrt.windows.media.control import (
            GlobalSystemMediaTransportControlsSessionManager as Manager,
        )

        last_emit = 0.0
        try:
            manager = await Manager.request_async()
        except Exception:  # noqa: BLE001
            self._available = False
            return

        while not self._stop.is_set():
            try:
                payload = await self._read(manager)
            except Exception:  # noqa: BLE001
                payload = self._empty()
            # 只在有变化或每 2 秒兜底刷新时发信号，避免刷爆 UI
            if payload != self._last:
                self._last = payload
                try:
                    self.changed.emit(payload)
                except RuntimeError:
                    return
            await asyncio.sleep(self._interval)

    async def _read(self, manager: Any) -> dict[str, Any]:
        session = manager.get_current_session()
        if session is None:
            return self._empty()
        props = await session.try_get_media_properties_async()
        info = session.get_playback_info()
        timeline = session.get_timeline_properties()
        playing = False
        if info is not None:
            try:
                from winrt.windows.media.control import (
                    GlobalSystemMediaTransportControlsSessionPlaybackStatus as Status,
                )

                playing = info.playback_status == Status.PLAYING
            except Exception:  # noqa: BLE001
                playing = False
        position = 0.0
        duration = 0.0
        if timeline is not None:
            try:
                position = float(timeline.position.total_seconds())
                duration = float(timeline.end_time.total_seconds())
            except Exception:  # noqa: BLE001
                position = duration = 0.0
        title = getattr(props, "title", "") or ""
        app_id = session.source_app_user_model_id or ""
        if not title:
            return self._empty()
        return {
            "has": True,
            "title": title,
            "artist": getattr(props, "artist", "") or "",
            "album": getattr(props, "album_title", "") or "",
            "app": _friendly_app(app_id),
            "appId": app_id,
            "playing": playing,
            "position": round(position, 1),
            "duration": round(duration, 1),
        }

    @staticmethod
    def _empty() -> dict[str, Any]:
        return {
            "has": False,
            "title": "",
            "artist": "",
            "album": "",
            "app": "",
            "appId": "",
            "playing": False,
            "position": 0.0,
            "duration": 0.0,
        }

    # ---------- 控制 ----------
    def _run_coroutine(self, factory) -> None:  # noqa: ANN001
        loop = self._loop
        if loop is None or not loop.is_running():
            return
        try:
            asyncio.run_coroutine_threadsafe(factory(), loop)
        except Exception:  # noqa: BLE001
            pass

    def toggle(self) -> None:
        self._run_coroutine(self._toggle)

    def next(self) -> None:
        self._run_coroutine(self._next)

    def previous(self) -> None:
        self._run_coroutine(self._previous)

    async def _toggle(self) -> None:
        from winrt.windows.media.control import (
            GlobalSystemMediaTransportControlsSessionManager as Manager,
        )

        manager = await Manager.request_async()
        session = manager.get_current_session()
        if session is not None:
            await session.try_toggle_play_pause_async()

    async def _next(self) -> None:
        from winrt.windows.media.control import (
            GlobalSystemMediaTransportControlsSessionManager as Manager,
        )

        manager = await Manager.request_async()
        session = manager.get_current_session()
        if session is not None:
            await session.try_skip_next_async()

    async def _previous(self) -> None:
        from winrt.windows.media.control import (
            GlobalSystemMediaTransportControlsSessionManager as Manager,
        )

        manager = await Manager.request_async()
        session = manager.get_current_session()
        if session is not None:
            await session.try_skip_previous_async()
