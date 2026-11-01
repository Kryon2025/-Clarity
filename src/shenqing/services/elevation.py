"""权限相关：是否管理员、提权重启、最高权限开机自启（计划任务）。

- 普通自启：HKCU\\...\\Run（不需要管理员，见 autostart.py）
- 最高权限自启：Windows 计划任务 ONLOGON + RunLevel HIGHEST（登录即提权启动，不弹 UAC）
"""

from __future__ import annotations

import ctypes
import subprocess
import sys
from pathlib import Path

TASK_NAME = "ShenQing.ElevatedAutostart"
SW_SHOWNORMAL = 1


def is_admin() -> bool:
    """当前进程是否管理员。"""
    try:
        return bool(ctypes.windll.shell32.IsUserAnAdmin())
    except Exception:  # noqa: BLE001
        return False


def _launch_command() -> tuple[str, str]:
    """返回 (可执行文件, 参数)。打包后直接用 exe，开发环境用 python + run.py。"""
    if getattr(sys, "frozen", False):
        return sys.executable, ""
    run_py = Path(__file__).resolve().parents[2] / "run.py"
    return sys.executable, f'"{run_py}"'


def relaunch_as_admin(extra_args: str = "") -> bool:
    """用「以管理员身份运行」重新拉起自己；调用方随后应退出。"""
    exe, params = _launch_command()
    params = (params + " " + extra_args).strip()
    try:
        result = ctypes.windll.shell32.ShellExecuteW(
            None, "runas", exe, params or None, None, SW_SHOWNORMAL
        )
        return int(result) > 32  # >32 表示成功
    except Exception:  # noqa: BLE001
        return False


def _run_schtasks(args: list[str]) -> tuple[bool, str]:
    creationflags = getattr(subprocess, "CREATE_NO_WINDOW", 0)
    try:
        completed = subprocess.run(
            ["schtasks", *args],
            capture_output=True,
            text=True,
            encoding="gbk",
            errors="replace",
            creationflags=creationflags,
            timeout=20,
        )
    except (OSError, subprocess.SubprocessError) as exc:
        return False, str(exc)
    output = (completed.stdout or completed.stderr or "").strip()
    return completed.returncode == 0, output


def elevated_autostart_enabled() -> bool:
    ok, _ = _run_schtasks(["/Query", "/TN", TASK_NAME])
    return ok


def set_elevated_autostart(enabled: bool) -> tuple[bool, str]:
    """创建/删除「最高权限开机自启」计划任务（需要管理员）。"""
    if enabled:
        exe, params = _launch_command()
        command = f'"{exe}" {params} --autostart'.strip()
        ok, output = _run_schtasks(
            [
                "/Create",
                "/TN",
                TASK_NAME,
                "/TR",
                command,
                "/SC",
                "ONLOGON",
                "/RL",
                "HIGHEST",
                "/F",
            ]
        )
        return ok, output
    ok, output = _run_schtasks(["/Delete", "/TN", TASK_NAME, "/F"])
    # 任务本来就不存在也算成功
    return ok or "不存在" in output or "cannot find" in output.lower(), output
