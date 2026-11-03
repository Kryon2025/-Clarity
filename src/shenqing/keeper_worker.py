"""保活看门狗进程（v0.6）。

职责：主程序启动时写 %APPDATA%/ShenQing/keeper.json；本进程每 2 秒检查主进程 PID，
发现主进程消失就按 keeper.json 里的命令行 + 工作目录重新拉起它（带 --restarted），
并在宽限期内等待新主进程写入自己的 PID，避免重复拉起。

- 可独立运行：pythonw src/shenqing/keeper_worker.py --state <keeper.json>
- 打包后由主 exe 以 --keeper-worker 入口运行（run.py 里分发），逻辑相同。
- 本文件只用标准库，不 import shenqing，保证 pythonw 直接运行即可。
"""

from __future__ import annotations

import argparse
import json
import os
import subprocess
import sys
import time
from pathlib import Path

RESTART_FLAG = "--restarted"
DEFAULT_POLL_SECONDS = 2.0
#: 拉起主程序后的宽限期：等新主进程启动并写回 keeper.json
GRACE_SECONDS = 10.0
#: 拉起失败后的重试间隔
RETRY_SECONDS = 6.0
#: 连续多次拉起后新主进程仍未接管（比如界面加载直接失败）就放弃，避免无限循环
MAX_RELAUNCH_ATTEMPTS = 6

STILL_ACTIVE = 259
PROCESS_QUERY_LIMITED_INFORMATION = 0x1000
PROCESS_TERMINATE = 0x0001

DETACHED_PROCESS = getattr(subprocess, "DETACHED_PROCESS", 0x00000008)
CREATE_NEW_PROCESS_GROUP = getattr(subprocess, "CREATE_NEW_PROCESS_GROUP", 0x00000200)
CREATE_BREAKAWAY_FROM_JOB = 0x01000000


# ---------------------------------------------------------------- 进程检查
def is_process_alive(pid: int) -> bool:
    """Win32 API 判断 PID 是否仍存活（非 Windows 退化为 os.kill）。"""
    try:
        pid = int(pid)
    except (TypeError, ValueError):
        return False
    if pid <= 0:
        return False
    if os.name != "nt":
        try:
            os.kill(pid, 0)
            return True
        except OSError:
            return False
    import ctypes
    from ctypes import wintypes

    kernel32 = ctypes.WinDLL("kernel32", use_last_error=True)
    handle = kernel32.OpenProcess(PROCESS_QUERY_LIMITED_INFORMATION, False, pid)
    if not handle:
        return False
    try:
        code = wintypes.DWORD(0)
        if kernel32.GetExitCodeProcess(handle, ctypes.byref(code)):
            return int(code.value) == STILL_ACTIVE
        return False
    finally:
        kernel32.CloseHandle(handle)


def is_admin() -> bool:
    try:
        import ctypes

        return bool(ctypes.windll.shell32.IsUserAnAdmin())
    except Exception:  # noqa: BLE001
        return False


# ---------------------------------------------------------------- 状态 / 锁文件
def read_state(path: Path) -> dict | None:
    try:
        data = json.loads(path.read_text(encoding="utf-8"))
    except (OSError, json.JSONDecodeError, ValueError):
        return None
    if not isinstance(data, dict):
        return None
    try:
        int(data.get("pid") or 0)
    except (TypeError, ValueError):
        return None
    return data


def read_pid(path: Path) -> int:
    try:
        return int(path.read_text(encoding="utf-8").strip())
    except (OSError, ValueError):
        return 0


def try_acquire_lock(lock_path: Path) -> bool:
    """同一时刻只允许一个看门狗（lock 里记录看门狗自己的 PID）。"""
    existing = read_pid(lock_path)
    if existing and existing != os.getpid() and is_process_alive(existing):
        return False
    try:
        lock_path.parent.mkdir(parents=True, exist_ok=True)
        lock_path.write_text(str(os.getpid()), encoding="utf-8")
        return True
    except OSError:
        return False


def release_lock(lock_path: Path) -> None:
    try:
        if read_pid(lock_path) == os.getpid():
            lock_path.unlink()
    except OSError:
        pass


# ---------------------------------------------------------------- 重新拉起
def _shell_execute(verb: str, exe: str, args: list[str], cwd: str) -> bool:
    if os.name != "nt":
        return False
    import ctypes

    shell32 = ctypes.windll.shell32
    try:
        shell32.ShellExecuteW.restype = ctypes.c_void_p
        shell32.ShellExecuteW.argtypes = [
            ctypes.c_void_p,
            ctypes.c_wchar_p,
            ctypes.c_wchar_p,
            ctypes.c_wchar_p,
            ctypes.c_wchar_p,
            ctypes.c_int,
        ]
    except (AttributeError, TypeError):  # pragma: no cover - 老 Windows
        pass
    params = subprocess.list2cmdline(args) if args else None
    try:
        result = shell32.ShellExecuteW(None, verb, exe, params, cwd or None, 1)
        return int(result or 0) > 32
    except Exception:  # noqa: BLE001
        return False


def _popen_detached(command: list[str], cwd: str) -> bool:
    flags = DETACHED_PROCESS | CREATE_NEW_PROCESS_GROUP | CREATE_BREAKAWAY_FROM_JOB
    for attempt in (flags, flags & ~CREATE_BREAKAWAY_FROM_JOB):
        try:
            subprocess.Popen(
                command,
                cwd=cwd or None,
                creationflags=attempt,
                stdin=subprocess.DEVNULL,
                stdout=subprocess.DEVNULL,
                stderr=subprocess.DEVNULL,
                close_fds=True,
            )
            return True
        except OSError:
            continue
    return False


def relaunch_main(state: dict) -> bool:
    """按 keeper.json 重新拉起主程序；提权进程尽量用 runas。"""
    raw = state.get("command")
    if not isinstance(raw, list) or not raw:
        return False
    command = [str(item) for item in raw]
    exe = command[0]
    args = command[1:] + [RESTART_FLAG]
    cwd = str(state.get("cwd") or "")
    elevated = bool(state.get("elevated"))
    if os.name == "nt":
        if elevated and not is_admin() and _shell_execute("runas", exe, args, cwd):
            return True
        if _shell_execute("open", exe, args, cwd):
            return True
    return _popen_detached(command + [RESTART_FLAG], cwd)


# ---------------------------------------------------------------- 主循环
def run_worker(state_path: Path, poll: float = DEFAULT_POLL_SECONDS) -> int:
    state_path = Path(state_path)
    lock_path = state_path.with_name("keeper.lock")
    if not try_acquire_lock(lock_path):
        return 0
    grace_until = 0.0
    seen_pid = 0
    attempts = 0
    try:
        while True:
            state = read_state(state_path)
            if state is None:
                # 主程序正常退出时已删除 keeper.json → 看门狗跟着退出
                return 0
            pid = int(state.get("pid") or 0)
            if pid != seen_pid:
                # 新主进程接管（写入了自己的 PID）→ 重置失败计数
                seen_pid = pid
                attempts = 0
            if is_process_alive(pid):
                grace_until = 0.0
            else:
                now = time.monotonic()
                if now >= grace_until:
                    if attempts >= MAX_RELAUNCH_ATTEMPTS:
                        return 0
                    ok = relaunch_main(state)
                    attempts += 1
                    grace_until = time.monotonic() + (GRACE_SECONDS if ok else RETRY_SECONDS)
            time.sleep(max(0.2, float(poll)))
    finally:
        release_lock(lock_path)


def main(argv: list[str] | None = None) -> int:
    args_list = list(sys.argv[1:] if argv is None else argv)
    if args_list and str(args_list[0]).endswith((".py", ".exe")):
        # 直接用 python(w) keeper_worker.py 运行时去掉脚本路径
        args_list = args_list[1:]
    parser = argparse.ArgumentParser(prog="shenqing-keeper")
    parser.add_argument("--keeper-worker", action="store_true", help="打包 exe 的看门狗入口标记")
    parser.add_argument("--state", default="", help="keeper.json 路径")
    parser.add_argument("--poll", type=float, default=DEFAULT_POLL_SECONDS)
    args = parser.parse_args(args_list)
    state_path = Path(args.state) if args.state else default_state_path()
    return run_worker(state_path, args.poll)


def default_state_path() -> Path:
    base = os.environ.get("APPDATA")
    root = Path(base) if base else Path.home() / "AppData" / "Roaming"
    return root / "ShenQing" / "keeper.json"


if __name__ == "__main__":
    raise SystemExit(main(sys.argv))
