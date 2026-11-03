"""防退出加固：全屏遮罩盖住任务栏 / 屏蔽系统快捷键 / 反复置顶。

Windows 的任务栏（Shell_TrayWnd / Shell_SecondaryTrayWnd）本身就是 TOPMOST，
普通全屏窗口盖不住它；这里用三件事组合解决：

1. 锁定期间 **隐藏任务栏**（含副屏任务栏），结束后恢复；
2. **WH_KEYBOARD_LL 低级键盘钩子** 屏蔽 Win 键、Alt+Tab、Alt+Esc、Ctrl+Esc、Alt+F4、
   Ctrl+Shift+Esc（任务管理器）；
3. 定时把遮罩窗口重新拉到 HWND_TOPMOST，防止被别的置顶程序顶掉。

管理员模式下钩子与隐藏任务栏更可靠；非管理员也能用，但某些系统级窗口仍可能抢焦点。
"""

from __future__ import annotations

import ctypes
import sys
from ctypes import wintypes

from PySide6.QtCore import QObject, QTimer, Signal

user32 = ctypes.WinDLL("user32", use_last_error=True) if sys.platform == "win32" else None
kernel32 = ctypes.WinDLL("kernel32", use_last_error=True) if sys.platform == "win32" else None

SW_HIDE = 0
SW_SHOW = 5
HWND_TOPMOST = wintypes.HWND(-1)
SWP_NOMOVE = 0x0002
SWP_NOSIZE = 0x0001
SWP_NOACTIVATE = 0x0010
WH_KEYBOARD_LL = 13
WM_KEYDOWN = 0x0100
WM_SYSKEYDOWN = 0x0104
LLKHF_ALTDOWN = 0x20

VK_TAB = 0x09
VK_ESCAPE = 0x1B
VK_F4 = 0x73
VK_LWIN = 0x5B
VK_RWIN = 0x5C
VK_CONTROL = 0x11
VK_SHIFT = 0x10
VK_MENU = 0x12

TASKBAR_CLASSES = ("Shell_TrayWnd", "Shell_SecondaryTrayWnd")


class KBDLLHOOKSTRUCT(ctypes.Structure):
    _fields_ = [
        ("vkCode", wintypes.DWORD),
        ("scanCode", wintypes.DWORD),
        ("flags", wintypes.DWORD),
        ("time", wintypes.DWORD),
        ("dwExtraInfo", ctypes.c_void_p),
    ]


HOOKPROC = ctypes.WINFUNCTYPE(
    ctypes.c_ssize_t, ctypes.c_int, wintypes.WPARAM, wintypes.LPARAM
)


def restore_taskbars() -> None:
    """安全网：无论加固器状态如何，把任务栏恢复出来（退出/异常时调用）。"""
    if user32 is None:
        return
    for hwnd in _find_taskbars():
        try:
            user32.ShowWindow(hwnd, SW_SHOW)
        except Exception:  # noqa: BLE001
            continue


def _find_taskbars() -> list[int]:
    if user32 is None:
        return []
    handles: list[int] = []
    for cls in TASKBAR_CLASSES:
        hwnd = user32.FindWindowW(cls, None)
        while hwnd:
            handles.append(int(hwnd))
            hwnd = user32.FindWindowExW(None, hwnd, cls, None)
    return handles


class LockHardening(QObject):
    """锁定期间的加固器；activate(hwnd) / deactivate() 成对调用。"""

    blockedKey = Signal(str)

    def __init__(self, parent: QObject | None = None) -> None:
        super().__init__(parent)
        self._active = False
        self._hwnd = 0
        self._hidden_taskbars: list[int] = []
        self._hook = None
        self._hook_proc = None
        # v0.6：覆清 dock 拉起白名单应用时临时暂停「反复置顶」，否则遮罩每 500ms
        # 会把应用重新压到下面；任务栏隐藏与键盘钩子保持不变。
        self._topmost_enabled = True
        self._topmost_timer = QTimer(self)
        self._topmost_timer.setInterval(500)
        self._topmost_timer.timeout.connect(self._reassert_topmost)

    @property
    def active(self) -> bool:
        return self._active

    # ---------- 生命周期 ----------
    def activate(self, hwnd: int, *, hide_taskbar: bool = True, block_keys: bool = True) -> None:
        if self._active:
            self.deactivate()
        self._hwnd = int(hwnd or 0)
        self._active = True
        if hide_taskbar:
            self._hide_taskbars()
        if block_keys:
            self._install_hook()
        self._topmost_timer.start()
        self._reassert_topmost()

    def set_topmost_enabled(self, enabled: bool) -> None:
        """暂停/恢复「定时把遮罩拉回最前」。不影响隐藏任务栏与键盘钩子。"""
        self._topmost_enabled = bool(enabled)
        if self._topmost_enabled:
            self._reassert_topmost()

    def deactivate(self) -> None:
        if not self._active:
            return
        self._active = False
        self._topmost_timer.stop()
        self._uninstall_hook()
        self._restore_taskbars()
        self._hwnd = 0

    # ---------- 任务栏 ----------
    def _hide_taskbars(self) -> None:
        self._hidden_taskbars = []
        for hwnd in _find_taskbars():
            try:
                if user32.ShowWindow(hwnd, SW_HIDE):
                    self._hidden_taskbars.append(hwnd)
            except Exception:  # noqa: BLE001
                continue

    def _restore_taskbars(self) -> None:
        for hwnd in self._hidden_taskbars:
            try:
                user32.ShowWindow(hwnd, SW_SHOW)
            except Exception:  # noqa: BLE001
                continue
        self._hidden_taskbars = []

    # ---------- 置顶 ----------
    def _reassert_topmost(self) -> None:
        if not self._active or not self._hwnd or user32 is None:
            return
        if not self._topmost_enabled:
            return
        try:
            user32.SetWindowPos(
                wintypes.HWND(self._hwnd),
                HWND_TOPMOST,
                0,
                0,
                0,
                0,
                SWP_NOMOVE | SWP_NOSIZE | SWP_NOACTIVATE,
            )
        except Exception:  # noqa: BLE001
            pass

    # ---------- 键盘钩子 ----------
    def _install_hook(self) -> None:
        if user32 is None or self._hook:
            return
        try:
            self._hook_proc = HOOKPROC(self._keyboard_proc)
            self._hook = user32.SetWindowsHookExW(WH_KEYBOARD_LL, self._hook_proc, None, 0)
        except Exception:  # noqa: BLE001
            self._hook = None
            self._hook_proc = None

    def _uninstall_hook(self) -> None:
        if user32 is None or not self._hook:
            return
        try:
            user32.UnhookWindowsHookEx(self._hook)
        except Exception:  # noqa: BLE001
            pass
        self._hook = None
        self._hook_proc = None

    def _keyboard_proc(self, n_code, w_param, l_param):  # noqa: ANN001
        try:
            if n_code == 0 and self._active and w_param in (WM_KEYDOWN, WM_SYSKEYDOWN):
                info = ctypes.cast(l_param, ctypes.POINTER(KBDLLHOOKSTRUCT)).contents
                if self._is_blocked(info):
                    try:
                        self.blockedKey.emit(str(info.vkCode))
                    except Exception:  # noqa: BLE001
                        pass
                    return 1  # 吞掉按键
        except Exception:  # noqa: BLE001
            pass
        return user32.CallNextHookEx(None, n_code, w_param, l_param)

    @staticmethod
    def _is_blocked(info: KBDLLHOOKSTRUCT) -> bool:
        if user32 is None:
            return False
        vk = int(info.vkCode)
        alt = bool(info.flags & LLKHF_ALTDOWN) or bool(user32.GetAsyncKeyState(VK_MENU) & 0x8000)
        ctrl = bool(user32.GetAsyncKeyState(VK_CONTROL) & 0x8000)
        shift = bool(user32.GetAsyncKeyState(VK_SHIFT) & 0x8000)
        if vk in (VK_LWIN, VK_RWIN):
            return True
        if vk == VK_TAB and alt:
            return True
        if vk == VK_ESCAPE and (alt or ctrl):
            return True
        if vk == VK_F4 and alt:
            return True
        if vk == VK_ESCAPE and ctrl and shift:
            return True
        return False
