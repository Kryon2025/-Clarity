"""应用屏蔽（不杀进程）：把非白名单应用「藏起来 + 静音」，保留未保存的工作。

- 窗口：EnumWindows 找到目标进程的可见顶层窗口 → ShowWindow(SW_HIDE)，结束时 SW_SHOW 恢复；
- 声音：Core Audio（pycaw）按进程找到音频会话 → ISimpleAudioVolume.SetMute(True)，
  结束时恢复为「屏蔽前的静音状态」，不会把用户本来就静音的应用打开声音。

pycaw 不可用时只做窗口隐藏（静音降级为不处理），不影响主流程。
"""

from __future__ import annotations

import ctypes
import sys
from ctypes import wintypes
from typing import Any

SW_HIDE = 0
SW_SHOW = 5
GWL_EXSTYLE = -20
WS_EX_TOOLWINDOW = 0x00000080

#: 永远不隐藏的窗口类（桌面/任务栏/输入法/系统壳）
SKIP_CLASSES = {
    "Progman",
    "WorkerW",
    "Shell_TrayWnd",
    "Shell_SecondaryTrayWnd",
    "Windows.UI.Core.CoreWindow",
    "ApplicationFrameWindow",  # UWP 壳，隐藏会连累整个应用，保守跳过
    "IME",
    "MSCTFIME UI",
    "Default IME",
}

user32 = ctypes.WinDLL("user32", use_last_error=True) if sys.platform == "win32" else None

try:  # 可选依赖：只用于静音
    from pycaw.pycaw import AudioUtilities  # type: ignore
except Exception:  # noqa: BLE001
    AudioUtilities = None  # type: ignore[assignment]


def _enum_windows() -> list[tuple[int, int]]:
    """返回 [(hwnd, pid)]：所有可见、有标题、非工具窗口的顶层窗口。"""
    if user32 is None:
        return []
    result: list[tuple[int, int]] = []

    @ctypes.WINFUNCTYPE(wintypes.BOOL, wintypes.HWND, wintypes.LPARAM)
    def callback(hwnd, _lparam):  # noqa: ANN001
        try:
            if not user32.IsWindowVisible(hwnd):
                return True
            length = user32.GetWindowTextLengthW(hwnd)
            if length <= 0:
                return True
            pid = wintypes.DWORD()
            user32.GetWindowThreadProcessId(hwnd, ctypes.byref(pid))
            class_name = ctypes.create_unicode_buffer(256)
            user32.GetClassNameW(hwnd, class_name, 256)
            if class_name.value in SKIP_CLASSES:
                return True
            ex_style = user32.GetWindowLongW(hwnd, GWL_EXSTYLE)
            if ex_style & WS_EX_TOOLWINDOW:
                return True
            result.append((int(hwnd), int(pid.value)))
        except Exception:  # noqa: BLE001
            pass
        return True

    try:
        user32.EnumWindows(callback, 0)
    except Exception:  # noqa: BLE001
        return result
    return result


class AppShield:
    """把目标进程的窗口藏起来、声音静音，并记住原状态以便恢复。"""

    def __init__(self) -> None:
        self._hidden: list[int] = []
        self._muted: list[tuple[Any, int]] = []  # (ISimpleAudioVolume, 原静音状态)
        self._sessions: list[Any] = []

    @property
    def audio_available(self) -> bool:
        return AudioUtilities is not None

    # ---------- 窗口 ----------
    def hide_process_windows(self, pid: int) -> int:
        if user32 is None:
            return 0
        count = 0
        for hwnd, owner in _enum_windows():
            if owner != pid or hwnd in self._hidden:
                continue
            try:
                user32.ShowWindow(hwnd, SW_HIDE)
                self._hidden.append(hwnd)
                count += 1
            except Exception:  # noqa: BLE001
                continue
        return count

    # ---------- 声音 ----------
    def _load_sessions(self) -> None:
        if AudioUtilities is None:
            return
        if not self._sessions:
            try:
                self._sessions = list(AudioUtilities.GetAllSessions())
            except Exception:  # noqa: BLE001
                self._sessions = []

    def mute_process(self, pid: int) -> bool:
        self._load_sessions()
        muted = False
        for session in self._sessions:
            try:
                if int(getattr(session, "ProcessId", -1)) != pid:
                    continue
                volume = session.SimpleAudioVolume
                if volume is None:
                    continue
                if any(item[0] is volume for item in self._muted):
                    muted = True
                    continue
                previous = int(volume.GetMute())
                volume.SetMute(1, None)
                self._muted.append((volume, previous))
                muted = True
            except Exception:  # noqa: BLE001
                continue
        return muted

    # ---------- 组合 ----------
    def shield(self, pid: int) -> tuple[int, bool]:
        hidden = self.hide_process_windows(pid)
        muted = self.mute_process(pid)
        return hidden, muted

    def restore(self) -> None:
        if user32 is not None:
            for hwnd in self._hidden:
                try:
                    user32.ShowWindow(hwnd, SW_SHOW)
                except Exception:  # noqa: BLE001
                    continue
        self._hidden.clear()
        for volume, previous in self._muted:
            try:
                volume.SetMute(previous, None)
            except Exception:  # noqa: BLE001
                continue
        self._muted.clear()
        self._sessions = []
