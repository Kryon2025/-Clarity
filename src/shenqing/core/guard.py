"""后台进程守护：轮询枚举进程，按黑名单强制结束。

只用 ctypes 调 Win32，不额外依赖 psutil；所有操作都在主线程的 QTimer 里做，
单次轮询量级是几百个进程，开销可以忽略。正式版若采样更频繁应移到 QThread。
"""

from __future__ import annotations

import ctypes
import sys
from ctypes import wintypes

from PySide6.QtCore import QObject, QTimer, Signal

TH32CS_SNAPPROCESS = 0x00000002
INVALID_HANDLE_VALUE = ctypes.c_void_p(-1).value
PROCESS_TERMINATE = 0x0001

#: 永不结束的系统 / 输入法 / 自身进程
DEFAULT_WHITELIST: frozenset[str] = frozenset(
    {
        "explorer.exe",
        "dwm.exe",
        "csrss.exe",
        "winlogon.exe",
        "services.exe",
        "lsass.exe",
        "svchost.exe",
        "ctfmon.exe",
        "shenqing.exe",
        "python.exe",
        "pythonw.exe",
    }
)


class PROCESSENTRY32W(ctypes.Structure):
    _fields_ = [
        ("dwSize", wintypes.DWORD),
        ("cntUsage", wintypes.DWORD),
        ("th32ProcessID", wintypes.DWORD),
        ("th32DefaultHeapID", ctypes.c_void_p),
        ("th32ModuleID", wintypes.DWORD),
        ("cntThreads", wintypes.DWORD),
        ("th32ParentProcessID", wintypes.DWORD),
        ("pcPriClassBase", ctypes.c_long),
        ("dwFlags", wintypes.DWORD),
        ("szExeFile", wintypes.WCHAR * 260),
    ]


if sys.platform == "win32":
    _kernel32 = ctypes.WinDLL("kernel32", use_last_error=True)
    _kernel32.CreateToolhelp32Snapshot.argtypes = [wintypes.DWORD, wintypes.DWORD]
    _kernel32.CreateToolhelp32Snapshot.restype = wintypes.HANDLE
    _kernel32.Process32FirstW.argtypes = [wintypes.HANDLE, ctypes.POINTER(PROCESSENTRY32W)]
    _kernel32.Process32FirstW.restype = wintypes.BOOL
    _kernel32.Process32NextW.argtypes = [wintypes.HANDLE, ctypes.POINTER(PROCESSENTRY32W)]
    _kernel32.Process32NextW.restype = wintypes.BOOL
    _kernel32.OpenProcess.argtypes = [wintypes.DWORD, wintypes.BOOL, wintypes.DWORD]
    _kernel32.OpenProcess.restype = wintypes.HANDLE
    _kernel32.TerminateProcess.argtypes = [wintypes.HANDLE, wintypes.UINT]
    _kernel32.TerminateProcess.restype = wintypes.BOOL
    _kernel32.CloseHandle.argtypes = [wintypes.HANDLE]
    _kernel32.CloseHandle.restype = wintypes.BOOL
else:  # pragma: no cover - 仅 Windows 目标
    _kernel32 = None


def iter_processes() -> list[tuple[int, str]]:
    """返回 [(pid, exe_name)]；非 Windows 环境返回空列表。"""
    if _kernel32 is None:
        return []
    snapshot = _kernel32.CreateToolhelp32Snapshot(TH32CS_SNAPPROCESS, 0)
    if not snapshot or snapshot == INVALID_HANDLE_VALUE:
        return []
    entry = PROCESSENTRY32W()
    entry.dwSize = ctypes.sizeof(PROCESSENTRY32W)
    processes: list[tuple[int, str]] = []
    try:
        if not _kernel32.Process32FirstW(snapshot, ctypes.byref(entry)):
            return []
        while True:
            processes.append((int(entry.th32ProcessID), str(entry.szExeFile)))
            if not _kernel32.Process32NextW(snapshot, ctypes.byref(entry)):
                break
    finally:
        _kernel32.CloseHandle(snapshot)
    return processes


def kill_process(pid: int) -> bool:
    """强制结束进程（不需要管理员权限即可结束同用户进程）。"""
    if _kernel32 is None:
        return False
    handle = _kernel32.OpenProcess(PROCESS_TERMINATE, False, pid)
    if not handle:
        return False
    try:
        return bool(_kernel32.TerminateProcess(handle, 1))
    finally:
        _kernel32.CloseHandle(handle)


class ProcessGuard(QObject):
    """按黑名单轮询并结束进程。"""

    processKilled = Signal(str)  # exe 名

    def __init__(self, parent: QObject | None = None) -> None:
        super().__init__(parent)
        self._timer = QTimer(self)
        self._timer.setInterval(1000)
        self._timer.timeout.connect(self.poll)
        self._blacklist: set[str] = set()
        self._whitelist: set[str] = set(DEFAULT_WHITELIST)
        self._active = False
        self.killed_total = 0

    @property
    def active(self) -> bool:
        return self._active

    def set_interval(self, milliseconds: int) -> None:
        self._timer.setInterval(max(200, int(milliseconds)))

    def set_blacklist(self, names: list[str]) -> None:
        self._blacklist = {n.strip().lower() for n in names if n.strip()}

    def set_whitelist(self, names: list[str]) -> None:
        self._whitelist = set(DEFAULT_WHITELIST) | {n.strip().lower() for n in names if n.strip()}

    def start(self) -> None:
        self._active = True
        self._timer.start()

    def stop(self) -> None:
        self._active = False
        self._timer.stop()

    def poll(self) -> None:
        if not self._active or not self._blacklist:
            return
        for pid, exe_name in iter_processes():
            exe = exe_name.lower()
            if exe in self._whitelist or exe not in self._blacklist:
                continue
            if kill_process(pid):
                self.killed_total += 1
                self.processKilled.emit(exe_name)
