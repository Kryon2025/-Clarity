"""开机自启：写 HKCU\\Software\\Microsoft\\Windows\\CurrentVersion\\Run。"""

from __future__ import annotations

import sys
from pathlib import Path

try:  # 仅 Windows 有 winreg
    import winreg
except ImportError:  # pragma: no cover
    winreg = None  # type: ignore[assignment]

RUN_KEY = r"Software\Microsoft\Windows\CurrentVersion\Run"


class AutostartManager:
    """注册表 Run 项管理：不需要管理员权限（当前用户 HKCU）。"""

    def __init__(self, name: str = "深清") -> None:
        self.name = name

    @staticmethod
    def launch_command() -> str:
        exe = sys.executable
        if getattr(sys, "frozen", False):  # PyInstaller 打包后
            return f'"{exe}"'
        run_py = Path(__file__).resolve().parents[3] / "run.py"
        return f'"{exe}" "{run_py}"'

    def is_enabled(self) -> bool:
        if winreg is None:
            return False
        try:
            with winreg.OpenKey(winreg.HKEY_CURRENT_USER, RUN_KEY, 0, winreg.KEY_READ) as key:
                value, _ = winreg.QueryValueEx(key, self.name)
                return bool(value)
        except OSError:
            return False

    def enable(self) -> bool:
        if winreg is None:
            return False
        try:
            with winreg.CreateKey(winreg.HKEY_CURRENT_USER, RUN_KEY) as key:
                winreg.SetValueEx(key, self.name, 0, winreg.REG_SZ, self.launch_command())
            return True
        except OSError:
            return False

    def disable(self) -> bool:
        if winreg is None:
            return False
        try:
            with winreg.OpenKey(winreg.HKEY_CURRENT_USER, RUN_KEY, 0, winreg.KEY_SET_VALUE) as key:
                winreg.DeleteValue(key, self.name)
            return True
        except OSError:
            return False

    def set(self, enabled: bool) -> bool:
        return self.enable() if enabled else self.disable()
