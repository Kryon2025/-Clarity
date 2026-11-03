"""保活看门狗（v0.6）：主进程被杀后自动重新拉起。

工作方式：
1. 主程序启动时 start_keeper()：
   - 写 %APPDATA%/ShenQing/keeper.json（当前 PID / 拉起命令 / 工作目录 / 时间 / 是否提权 / 看门狗 PID）；
   - 用 pythonw 起一个独立子进程跑 keeper_worker.py（DETACHED_PROCESS + CREATE_BREAKAWAY_FROM_JOB，
     不随主进程退出）；若已有看门狗在跑则复用，不重复起。
2. 看门狗每 2s 用 Win32 API 检查主进程 PID：消失就按 keeper.json 重新拉起（带 --restarted），
   新主进程会重写 keeper.json 并复用同一个看门狗。
3. 主程序正常退出时 stop_keeper()：杀掉看门狗并删除 keeper.json / keeper.lock，避免误拉起。

边界：若用户先杀看门狗、再杀主程序，则不会被拉起（可接受）。
"""

from __future__ import annotations

import json
import logging
import os
import subprocess
import sys
import time
from pathlib import Path

from ..keeper_worker import is_process_alive, read_pid, read_state
from ..paths import app_data_dir
from . import elevation

logger = logging.getLogger("shenqing.keeper")

KEEPER_STATE_NAME = "keeper.json"
KEEPER_LOCK_NAME = "keeper.lock"
DEFAULT_POLL_SECONDS = 2.0
RESTART_FLAG = "--restarted"
#: 测试 / 冒烟时跳过保活
DISABLE_ENV = "SHENQING_NO_KEEPER"

_DETACHED = getattr(subprocess, "DETACHED_PROCESS", 0x00000008)
_NEW_GROUP = getattr(subprocess, "CREATE_NEW_PROCESS_GROUP", 0x00000200)
_BREAKAWAY = 0x01000000


# ---------------------------------------------------------------- 路径 / 命令
def keeper_state_path() -> Path:
    return app_data_dir() / KEEPER_STATE_NAME


def keeper_lock_path() -> Path:
    return app_data_dir() / KEEPER_LOCK_NAME


def enabled() -> bool:
    return os.name == "nt" and os.environ.get(DISABLE_ENV) != "1"


def _pythonw() -> str:
    exe = Path(sys.executable)
    for name in ("pythonw.exe", "pythonw"):
        candidate = exe.with_name(name)
        if candidate.exists():
            return str(candidate)
    return str(exe)


def main_command() -> list[str]:
    """重新拉起主程序用的命令行（不含 --restarted）。"""
    if getattr(sys, "frozen", False):
        return [str(sys.executable)]
    root = Path(__file__).resolve().parents[3]
    run_py = root / "run.py"
    if run_py.exists():
        return [_pythonw(), str(run_py)]
    return [str(sys.executable), "-m", "shenqing"]  # 兜底：包已安装


def working_directory() -> str:
    if getattr(sys, "frozen", False):
        return str(Path(sys.executable).resolve().parent)
    return str(Path(__file__).resolve().parents[3])


def worker_command(state_path: Path, poll: float) -> list[str]:
    state = str(state_path)
    if getattr(sys, "frozen", False):
        return [
            str(sys.executable),
            "--keeper-worker",
            "--state",
            state,
            "--poll",
            str(poll),
        ]
    script = Path(__file__).resolve().parents[1] / "keeper_worker.py"
    return [_pythonw(), str(script), "--state", state, "--poll", str(poll)]


# ---------------------------------------------------------------- 状态文件
def _write_state(path: Path, payload: dict) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(json.dumps(payload, ensure_ascii=False, indent=2), encoding="utf-8")


def _remove_file(path: Path) -> None:
    try:
        path.unlink()
    except OSError:
        pass


# ---------------------------------------------------------------- 生命周期
def start_keeper(poll: float = DEFAULT_POLL_SECONDS) -> bool:
    """启动（或复用）看门狗；返回是否成功在跑。"""
    if not enabled():
        logger.debug("看门狗已禁用（%s=%s）", DISABLE_ENV, os.environ.get(DISABLE_ENV))
        return False
    try:
        state_path = keeper_state_path()
        previous = read_state(state_path)
        keeper_pid = 0
        if previous is not None:
            candidate = int(previous.get("keeper_pid") or 0)
            if candidate and is_process_alive(candidate):
                keeper_pid = candidate
        if not keeper_pid:
            lock_pid = read_pid(keeper_lock_path())
            if lock_pid and is_process_alive(lock_pid):
                keeper_pid = lock_pid
        state = {
            "pid": os.getpid(),
            "command": main_command(),
            "cwd": working_directory(),
            "started": int(time.time()),
            "elevated": bool(elevation.is_admin()),
            "keeper_pid": keeper_pid,
        }
        _write_state(state_path, state)
        if keeper_pid:
            logger.info("看门狗已在运行（pid=%s），复用", keeper_pid)
            return True
        process = _spawn_worker(state_path, poll)
        if process is None:
            _remove_file(state_path)
            return False
        state["keeper_pid"] = int(process.pid)
        _write_state(state_path, state)
        logger.info("看门狗已启动（pid=%s，监控主进程 %s）", process.pid, os.getpid())
        return True
    except Exception as exc:  # noqa: BLE001 - 保活失败不能拖垮主程序
        logger.warning("启动看门狗失败：%s", exc)
        return False


def _spawn_worker(state_path: Path, poll: float) -> subprocess.Popen | None:
    command = worker_command(state_path, poll)
    flags = _DETACHED | _NEW_GROUP | _BREAKAWAY
    for attempt in (flags, flags & ~_BREAKAWAY):
        try:
            return subprocess.Popen(
                command,
                cwd=working_directory(),
                creationflags=attempt,
                stdin=subprocess.DEVNULL,
                stdout=subprocess.DEVNULL,
                stderr=subprocess.DEVNULL,
                close_fds=True,
            )
        except OSError as exc:
            logger.warning("看门狗进程启动失败（flags=%s）：%s", attempt, exc)
    return None


def _terminate(pid: int) -> None:
    if pid <= 0:
        return
    if os.name == "nt":
        try:
            import ctypes

            kernel32 = ctypes.WinDLL("kernel32", use_last_error=True)
            handle = kernel32.OpenProcess(0x0001, False, int(pid))  # PROCESS_TERMINATE
            if handle:
                try:
                    kernel32.TerminateProcess(handle, 1)
                finally:
                    kernel32.CloseHandle(handle)
                return
        except Exception:  # noqa: BLE001
            pass
    try:
        subprocess.run(
            ["taskkill", "/F", "/PID", str(pid)],
            capture_output=True,
            creationflags=getattr(subprocess, "CREATE_NO_WINDOW", 0),
            timeout=10,
        )
    except (OSError, subprocess.SubprocessError):
        pass


def stop_keeper() -> None:
    """结束看门狗并删除状态/锁文件（主程序主动退出时调用）。"""
    if not enabled():
        return
    state_path = keeper_state_path()
    lock_path = keeper_lock_path()
    pids: set[int] = set()
    try:
        state = read_state(state_path)
        if state is not None:
            pids.add(int(state.get("keeper_pid") or 0))
        pids.add(read_pid(lock_path))
    except Exception as exc:  # noqa: BLE001
        logger.warning("读取看门狗状态失败：%s", exc)
    for pid in pids:
        if pid and pid != os.getpid() and is_process_alive(pid):
            _terminate(pid)
            logger.info("看门狗已结束（pid=%s）", pid)
    _remove_file(state_path)
    _remove_file(lock_path)
    logger.info("看门狗状态已清理")
