"""覆清（medium）dock 应用显示控制（v0.8）。

需求：白名单应用在前台时，直接 hide() 全屏遮罩（会话与计时继续），
让应用完全可见；前台切回非白名单/桌面后 300ms 内 show() 遮罩并恢复置顶；
2 秒防抖避免 Alt+Tab 闪烁。任务栏由防退出加固保持隐藏，本模块不碰。

- bridge.appLaunched → 激活应用窗口 → hide 遮罩；
- 300ms 轮询前台进程：属于当前空间白名单 → 保持隐藏；否则防抖 2s 后恢复；
- 会话结束/退出 → 停止轮询并恢复遮罩状态（会话已结束时不再强行 show）。
"""

from __future__ import annotations

import ctypes
import logging
import os
import sys
import time
from pathlib import Path

from PySide6.QtCore import QObject, QTimer

logger = logging.getLogger("shenqing.dock_reveal")

GWL_EXSTYLE = -20
WS_EX_TOPMOST = 0x00000008
SWP_NOSIZE = 0x0001
SWP_NOMOVE = 0x0002
SWP_NOACTIVATE = 0x0010
SW_RESTORE = 9
PROCESS_QUERY_LIMITED_INFORMATION = 0x1000
OVERLAY_OBJECT_NAME = "LockOverlay"
ACTIVATE_POLL_MS = 200
ACTIVATE_MAX_ATTEMPTS = 50  # 约 10s 等应用主窗口出现
WATCH_INTERVAL_MS = 300
SHOW_DEBOUNCE_SECONDS = 2.0
FOCUS_GRACE_SECONDS = 8.0

_WIN = os.name == "nt"
if _WIN:
    from ctypes import wintypes

    _user32 = ctypes.WinDLL("user32", use_last_error=True)
    _kernel32 = ctypes.WinDLL("kernel32", use_last_error=True)

    _WNDENUMPROC = ctypes.WINFUNCTYPE(wintypes.BOOL, wintypes.HWND, wintypes.LPARAM)

    _user32.GetWindowLongPtrW.restype = ctypes.c_ssize_t
    _user32.GetWindowLongPtrW.argtypes = [wintypes.HWND, ctypes.c_int]
    _user32.SetWindowPos.restype = wintypes.BOOL
    _user32.SetWindowPos.argtypes = [
        wintypes.HWND,
        wintypes.HWND,
        ctypes.c_int,
        ctypes.c_int,
        ctypes.c_int,
        ctypes.c_int,
        wintypes.UINT,
    ]
    _user32.GetForegroundWindow.restype = wintypes.HWND
    _user32.EnumWindows.restype = wintypes.BOOL
    _user32.EnumWindows.argtypes = [_WNDENUMPROC, wintypes.LPARAM]
    _user32.IsWindowVisible.restype = wintypes.BOOL
    _user32.IsWindowVisible.argtypes = [wintypes.HWND]
    _user32.ShowWindow.restype = wintypes.BOOL
    _user32.ShowWindow.argtypes = [wintypes.HWND, ctypes.c_int]
    _user32.BringWindowToTop.restype = wintypes.BOOL
    _user32.BringWindowToTop.argtypes = [wintypes.HWND]
    _user32.SetForegroundWindow.restype = wintypes.BOOL
    _user32.SetForegroundWindow.argtypes = [wintypes.HWND]
    _user32.GetWindowThreadProcessId.restype = wintypes.DWORD
    _user32.GetWindowThreadProcessId.argtypes = [wintypes.HWND, ctypes.POINTER(wintypes.DWORD)]
    _user32.AttachThreadInput.restype = wintypes.BOOL
    _user32.AttachThreadInput.argtypes = [wintypes.DWORD, wintypes.DWORD, wintypes.BOOL]
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
    _HWND_TOPMOST = wintypes.HWND(-1)


def exe_basename(exe: object) -> str:
    text = str(exe or "").strip().strip('"')
    if not text:
        return ""
    return Path(text).name.lower()


def _exe_of_pid(pid: int) -> str:
    if not _WIN or pid <= 0:
        return ""
    handle = _kernel32.OpenProcess(PROCESS_QUERY_LIMITED_INFORMATION, False, int(pid))
    if not handle:
        return ""
    try:
        size = wintypes.DWORD(1024)
        buffer = ctypes.create_unicode_buffer(1024)
        if _kernel32.QueryFullProcessImageNameW(handle, 0, buffer, ctypes.byref(size)):
            return Path(buffer.value).name.lower()
        return ""
    finally:
        _kernel32.CloseHandle(handle)


def window_pid(hwnd: int) -> int:
    if not _WIN or not hwnd:
        return 0
    pid = wintypes.DWORD(0)
    _user32.GetWindowThreadProcessId(int(hwnd), ctypes.byref(pid))
    return int(pid.value)


def window_exe(hwnd: int) -> str:
    return _exe_of_pid(window_pid(hwnd))


def foreground_exe() -> str:
    if not _WIN:
        return ""
    return window_exe(int(_user32.GetForegroundWindow() or 0))


def window_ids_for_exe(exe: object) -> list[int]:
    target = exe_basename(exe)
    if not _WIN or not target:
        return []
    found: list[int] = []

    def _callback(hwnd, _lparam):  # noqa: ANN001
        if not _user32.IsWindowVisible(hwnd):
            return True
        if window_exe(hwnd) == target:
            found.append(int(hwnd))
        return True

    try:
        _user32.EnumWindows(_WNDENUMPROC(_callback), 0)
    except (OSError, ValueError):  # pragma: no cover
        return []
    return found


def overlay_hwnd(window) -> int:  # noqa: ANN001
    if window is None:
        return 0
    try:
        return int(window.winId() or 0)
    except (RuntimeError, ValueError, TypeError):
        return 0


def is_topmost(hwnd: int) -> bool:
    if not _WIN or not hwnd:
        return False
    style = _user32.GetWindowLongPtrW(int(hwnd), GWL_EXSTYLE)
    return bool(style & WS_EX_TOPMOST)


def set_topmost(hwnd: int, enabled: bool) -> bool:
    if not _WIN or not hwnd:
        return False
    insert_after = _HWND_TOPMOST if enabled else wintypes.HWND(-2)
    return bool(
        _user32.SetWindowPos(
            int(hwnd), insert_after, 0, 0, 0, 0, SWP_NOMOVE | SWP_NOSIZE | SWP_NOACTIVATE
        )
    )


def activate_window(hwnd: int) -> bool:
    if not _WIN or not hwnd:
        return False
    try:
        _user32.ShowWindow(int(hwnd), SW_RESTORE)
        _user32.BringWindowToTop(int(hwnd))
        _user32.SetForegroundWindow(int(hwnd))
        if int(_user32.GetForegroundWindow() or 0) == int(hwnd):
            return True
        foreground = int(_user32.GetForegroundWindow() or 0)
        fg_thread = int(_user32.GetWindowThreadProcessId(foreground, None))
        target_thread = int(_user32.GetWindowThreadProcessId(int(hwnd), None))
        if fg_thread and target_thread and fg_thread != target_thread:
            _user32.AttachThreadInput(fg_thread, target_thread, True)
            try:
                _user32.SetForegroundWindow(int(hwnd))
            finally:
                _user32.AttachThreadInput(fg_thread, target_thread, False)
        return int(_user32.GetForegroundWindow() or 0) == int(hwnd)
    except (OSError, ValueError):  # pragma: no cover
        return False


class DockRevealController(QObject):
    """覆清 dock：白名单应用在前台时隐藏遮罩，切走 2s 后恢复。"""

    def __init__(self, bridge, parent: QObject | None = None) -> None:
        super().__init__(parent)
        self._bridge = bridge
        self._overlay = None
        self._hidden = False
        self._last_whitelist_at = 0.0
        self._pending_exe = ""
        self._activate_attempts = 0
        self._app_hwnd = 0
        self._activated_at = 0.0
        self._watch_timer = QTimer(self)
        self._watch_timer.setInterval(WATCH_INTERVAL_MS)
        self._watch_timer.timeout.connect(self._on_watch_tick)
        self._activate_timer = QTimer(self)
        self._activate_timer.setInterval(ACTIVATE_POLL_MS)
        self._activate_timer.timeout.connect(self._on_activate_tick)

    # ---------- 判定 ----------
    def _eligible(self) -> bool:
        try:
            return bool(self._bridge.busy) and str(self._bridge.sessionLevel) == "medium"
        except (RuntimeError, AttributeError):
            return False

    def _whitelist(self) -> set[str]:
        try:
            return {exe_basename(item) for item in (self._bridge.sessionWhitelist or [])}
        except (RuntimeError, AttributeError):
            return set()

    # ---------- 遮罩 ----------
    def _overlay_window(self):  # noqa: ANN202
        if self._overlay is not None:
            try:
                if self._overlay.objectName() == OVERLAY_OBJECT_NAME:
                    return self._overlay
            except RuntimeError:
                pass
            self._overlay = None
        try:
            from PySide6.QtGui import QGuiApplication

            instance = QGuiApplication.instance()
            if instance is None:
                return None
            fallback = None
            for window in instance.topLevelWindows():
                if str(window.objectName()) != OVERLAY_OBJECT_NAME:
                    continue
                try:
                    if window.isVisible():
                        self._overlay = window
                        return window
                except RuntimeError:
                    continue
                if fallback is None:
                    fallback = window
            self._overlay = fallback
            return fallback
        except Exception:  # noqa: BLE001
            return None

    def _set_hardening_topmost(self, enabled: bool) -> None:
        try:
            setter = getattr(self._bridge, "setOverlayTopmostEnabled", None)
            if callable(setter):
                setter(bool(enabled))
        except Exception as exc:  # noqa: BLE001
            logger.warning("切换防退出加固置顶失败：%s", exc)

    def _hide_overlay(self) -> bool:
        window = self._overlay_window()
        if window is None or self._hidden:
            return False
        try:
            self._set_hardening_topmost(False)
            window.hide()
            self._hidden = True
            if not self._watch_timer.isActive():
                self._watch_timer.start()
            logger.info("覆清 dock：白名单应用在前台，隐藏遮罩（计时继续）")
            return True
        except (RuntimeError, TypeError) as exc:
            logger.warning("隐藏遮罩失败：%s", exc)
            return False

    def _show_overlay(self) -> bool:
        window = self._overlay_window()
        if window is None:
            return False
        try:
            window.showFullScreen()
            hwnd = overlay_hwnd(window)
            if hwnd:
                set_topmost(hwnd, True)
            self._set_hardening_topmost(True)
            self._hidden = False
            logger.info("覆清 dock：前台不是白名单应用，恢复遮罩")
            return True
        except (RuntimeError, TypeError) as exc:
            logger.warning("恢复遮罩失败：%s", exc)
            return False

    def restore(self) -> None:
        """会话结束/退出：停止轮询；会话仍在中却不再适用时把遮罩放回来。"""
        try:
            self._watch_timer.stop()
            self._activate_timer.stop()
            if self._hidden:
                if self._eligible():
                    self._show_overlay()
                else:
                    self._hidden = False
                    self._set_hardening_topmost(True)
            else:
                self._set_hardening_topmost(True)
        except Exception as exc:  # noqa: BLE001
            logger.warning("恢复遮罩状态失败：%s", exc)

    # ---------- 应用激活 ----------
    def _start_activate(self, exe: object) -> None:
        self._pending_exe = exe_basename(exe)
        self._activate_attempts = 0
        self._app_hwnd = 0
        self._activated_at = 0.0
        if self._pending_exe:
            self._activate_timer.start()
        else:
            self._hide_overlay()

    def _on_activate_tick(self) -> None:
        if not self._eligible():
            self._activate_timer.stop()
            self.restore()
            return
        self._activate_attempts += 1
        windows = window_ids_for_exe(self._pending_exe)
        if windows:
            activate_window(windows[0])
            self._app_hwnd = int(windows[0])
            self._activated_at = time.monotonic()
            self._hide_overlay()
            self._activate_timer.stop()
            return
        if self._activate_attempts >= ACTIVATE_MAX_ATTEMPTS:
            logger.info("覆清 dock：没等到 %s 的窗口，恢复遮罩", self._pending_exe)
            self._activate_timer.stop()
            self._show_overlay()

    def _on_watch_tick(self) -> None:
        if not self._eligible():
            self.restore()
            return
        if self._activate_timer.isActive():
            return
        current = foreground_exe()
        whitelist = self._whitelist()
        now = time.monotonic()
        if current and current in whitelist:
            self._last_whitelist_at = now
            if not self._hidden:
                self._hide_overlay()
            return
        own_names = {
            exe_basename(sys.executable),
            "python.exe",
            "pythonw.exe",
            "shenqing.exe",
        }
        if (
            current in own_names
            and self._app_hwnd
            and now - self._activated_at < FOCUS_GRACE_SECONDS
        ):
            if activate_window(self._app_hwnd):
                self._hide_overlay()
            return
        if not self._hidden:
            return
        # 切走 2 秒防抖：只有持续不在白名单应用上才把遮罩放回来
        if now - self._last_whitelist_at < SHOW_DEBOUNCE_SECONDS:
            return
        self._show_overlay()

    # ---------- 对外槽 ----------
    def handle_app_launched(self, exe: str) -> None:
        try:
            if not self._eligible():
                return
            self._start_activate(exe)
        except Exception as exc:  # noqa: BLE001
            logger.warning("覆清 dock 显示应用失败：%s", exc)

    def sync_session(self) -> None:
        try:
            if self._eligible():
                if not self._watch_timer.isActive():
                    self._watch_timer.start()
                return
            self.restore()
        except Exception as exc:  # noqa: BLE001
            logger.warning("同步会话状态失败：%s", exc)
