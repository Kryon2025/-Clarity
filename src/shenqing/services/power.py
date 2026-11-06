"""专注期间禁止熄屏/休眠（v0.8）。

SetThreadExecutionState(ES_CONTINUOUS | ES_SYSTEM_REQUIRED | ES_DISPLAY_REQUIRED)
非 Windows 环境安全降级为空操作。
"""

from __future__ import annotations

import ctypes
import logging
import os

logger = logging.getLogger("shenqing.power")

ES_CONTINUOUS = 0x80000000
ES_SYSTEM_REQUIRED = 0x00000001
ES_DISPLAY_REQUIRED = 0x00000002

_active = False


def keep_awake() -> bool:
    """会话开始：阻止系统休眠与显示器关闭。"""
    global _active
    if os.name != "nt":
        return False
    try:
        ctypes.windll.kernel32.SetThreadExecutionState(
            ES_CONTINUOUS | ES_SYSTEM_REQUIRED | ES_DISPLAY_REQUIRED
        )
        _active = True
        logger.info("已开启专注防休眠（禁止熄屏/休眠）")
        return True
    except Exception as exc:  # noqa: BLE001
        logger.warning("设置防休眠失败：%s", exc)
        return False


def allow_sleep() -> bool:
    """会话结束：恢复正常息屏/休眠策略。"""
    global _active
    if os.name != "nt":
        return False
    try:
        ctypes.windll.kernel32.SetThreadExecutionState(ES_CONTINUOUS)
        _active = False
        logger.info("已恢复系统休眠策略")
        return True
    except Exception as exc:  # noqa: BLE001
        logger.warning("恢复休眠策略失败：%s", exc)
        return False


def active() -> bool:
    return _active
