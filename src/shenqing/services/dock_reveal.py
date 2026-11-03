"""覆清（medium）专注中，把 dock 启动的白名单应用显示到全屏遮罩之上（v0.6）。

背景：LockOverlay 是 always-on-top 全屏遮罩，白名单应用启动后窗口在遮罩下面，用户看不到。

做法（不重建窗口、不改 QML）：
1. bridge.launchApp 成功后发 appLaunched(exe)；
2. 本控制器临时去掉遮罩原生窗口的 WS_EX_TOPMOST（仍保持可见/全屏，不退出专注、计时照常）；
3. 轮询找到该 exe 的顶层窗口并 SetForegroundWindow 激活它；
4. 之后每秒检查前台窗口：仍属于当前空间白名单 → 保持遮罩非置顶；否则把遮罩重新置顶；
5. 会话结束/退出 → 恢复遮罩置顶、停止轮询。

只对 medium 生效（heavy 没有 dock，light 也没有 dock）。
非 Windows 环境全部安全降级为空操作。
"""

from __future__ import annotations

import ctypes
import logging
import os
from pathlib import Path

from PySide6.QtCore import QObject, Qt, QTimer

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
    _HWND_NOTOPMOST = wintypes.HWND(-2)


def exe_basename(exe: object) -> str:
    """'C:\\Windows\\notepad.exe' / 'notepad.exe' → 'notepad.exe'（小写）。"""
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
    """返回该 exe 的可见顶层窗口（按 Z 序，最上层在前）。"""
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
    except (OSError, ValueError):  # pragma: no cover - 极端环境
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
    """直接改原生窗口的置顶属性（不重建窗口、不打断 QML 遮罩）。"""
    if not _WIN or not hwnd:
        return False
    insert_after = _HWND_TOPMOST if enabled else _HWND_NOTOPMOST
    ok = _user32.SetWindowPos(
        int(hwnd),
        insert_after,
        0,
        0,
        0,
        0,
        SWP_NOMOVE | SWP_NOSIZE | SWP_NOACTIVATE,
    )
    return bool(ok)


def activate_window(hwnd: int) -> bool:
    """恢复并激活目标窗口；必要时附加前台线程输入队列绕过前台锁。"""
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
    """监听 appLaunched / 会话状态，把覆清白名单应用显示到遮罩之上。"""

    def __init__(self, bridge, parent: QObject | None = None) -> None:
        super().__init__(parent)
        self._bridge = bridge
        self._overlay = None
        self._pending_exe = ""
        self._activate_attempts = 0
        self._revealed = False
        self._saved_flags = None
        self._watch_timer = QTimer(self)
        self._watch_timer.setInterval(1000)
        self._watch_timer.timeout.connect(self._on_watch_tick)
        self._activate_timer = QTimer(self)
        self._activate_timer.setInterval(ACTIVATE_POLL_MS)
        self._activate_timer.timeout.connect(self._on_activate_tick)

    # ---------- 判定 ----------
    def _eligible(self) -> bool:
        try:
            return (
                bool(self._bridge.busy)
                and str(self._bridge.sessionLevel) == "medium"
            )
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
                if (
                    self._overlay.objectName() == OVERLAY_OBJECT_NAME
                    and self._overlay.isVisible()
                ):
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
        except Exception:  # noqa: BLE001 - 找不到遮罩就降级
            return None

    def _demote_overlay(self) -> bool:
        """去掉遮罩的 WindowStaysOnTopHint（通过 QML flags 属性，窗口不重建）。"""
        window = self._overlay_window()
        if window is None:
            return False
        try:
            flags = window.flags()
            if self._saved_flags is None:
                self._saved_flags = flags
            if not (flags & Qt.WindowStaysOnTopHint):
                return True
            ok = window.setProperty(
                "flags", int(flags & ~int(Qt.WindowStaysOnTopHint))
            )
            logger.info(
                "覆清 dock：降低遮罩 flags hwnd=%s before=%s setProperty=%s after=%s vis=%s",
                overlay_hwnd(window),
                int(flags),
                ok,
                int(window.flags()),
                window.isVisible(),
            )
            return True
        except (RuntimeError, ValueError, TypeError) as exc:
            logger.warning("取消遮罩置顶失败：%s", exc)
            return False

    def _restore_overlay_flags(self) -> None:
        """把遮罩恢复成原来的 always-on-top flags（隐藏状态下也不强制 show）。"""
        window = self._overlay_window()
        if window is None:
            return
        try:
            flags = window.flags()
            target = (
                self._saved_flags
                if self._saved_flags is not None
                else flags | Qt.WindowStaysOnTopHint
            )
            if not (flags & Qt.WindowStaysOnTopHint):
                window.setProperty("flags", int(target))
        except (RuntimeError, ValueError, TypeError) as exc:
            logger.warning("恢复遮罩置顶失败：%s", exc)

    def _ensure_topmost(self) -> None:
        if not self._revealed:
            self._restore_overlay_flags()

    def _reveal(self) -> bool:
        if not self._demote_overlay():
            logger.info("覆清 dock：没找到遮罩窗口，跳过置顶切换")
            return False
        self._revealed = True
        if not self._watch_timer.isActive():
            self._watch_timer.start()
        logger.info("覆清 dock：临时取消遮罩置顶，让白名单应用显示")
        return True

    def _raise_overlay(self) -> None:
        self._watch_timer.stop()
        self._restore_overlay_flags()
        self._revealed = False
        logger.info("覆清 dock：前台不是白名单应用，遮罩重新置顶")

    def restore(self) -> None:
        """恢复遮罩置顶并停止所有轮询（会话结束 / 退出时调用）。"""
        try:
            self._watch_timer.stop()
            self._activate_timer.stop()
            self._restore_overlay_flags()
            self._revealed = False
            self._saved_flags = None
        except Exception as exc:  # noqa: BLE001 - 恢复失败不能影响退出
            logger.warning("恢复遮罩置顶失败：%s", exc)

    # ---------- 应用激活 ----------
    def _start_activate(self, exe: object) -> None:
        self._pending_exe = exe_basename(exe)
        self._activate_attempts = 0
        if self._pending_exe:
            self._activate_timer.start()
        else:
            self._raise_overlay()

    def _on_activate_tick(self) -> None:
        if not self._eligible():
            self._activate_timer.stop()
            self.restore()
            return
        self._activate_attempts += 1
        windows = window_ids_for_exe(self._pending_exe)
        if windows:
            if activate_window(windows[0]):
                logger.info("覆清 dock：已激活 %s 的窗口", self._pending_exe)
            self._activate_timer.stop()
            return
        if self._activate_attempts >= ACTIVATE_MAX_ATTEMPTS:
            logger.info("覆清 dock：没等到 %s 的窗口，恢复遮罩", self._pending_exe)
            self._activate_timer.stop()
            self._raise_overlay()

    def _on_watch_tick(self) -> None:
        if not self._eligible():
            self.restore()
            return
        if self._activate_timer.isActive():
            # 应用还在启动/激活中（窗口可能 1-3s 才出来），这期间不要抢回置顶，
            # 否则会把刚拉起的应用再次压到遮罩下面。
            return
        current = foreground_exe()
        whitelist = self._whitelist()
        if logger.isEnabledFor(logging.DEBUG):
            logger.debug(
                "dock 轮询：前台=%s 白名单=%s 置顶=%s",
                current,
                sorted(whitelist),
                is_topmost(overlay_hwnd(self._overlay_window())),
            )
        if current and current in whitelist:
            return
        # 用户切回遮罩/桌面/其他应用：遮罩重新置顶
        self._raise_overlay()

    # ---------- 对外槽 ----------
    def handle_app_launched(self, exe: str) -> None:
        try:
            if not self._eligible():
                return
            if not self._reveal():
                return
            self._start_activate(exe)
        except Exception as exc:  # noqa: BLE001 - 不能让 dock 点击崩掉
            logger.warning("覆清 dock 显示应用失败：%s", exc)

    def sync_session(self) -> None:
        """桥的 stateChanged/lockedChanged 调用：会话结束恢复遮罩；会话中确保置顶。"""
        try:
            if self._eligible():
                self._ensure_topmost()
            else:
                self.restore()
        except Exception as exc:  # noqa: BLE001
            logger.warning("同步会话状态失败：%s", exc)
