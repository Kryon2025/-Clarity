"""系统电源与音量（v0.8，供 dock 设置面板调用）。

- get_volume()/set_volume()：pycaw 读写默认输出设备主音量（0-100）；
- power_action("shutdown"/"restart")：shutdown /s /t 0 或 shutdown /r /t 0。
pycaw 缺失或调用失败时安全降级（音量返回 -1 / 设置返回 False）。
"""

from __future__ import annotations

import logging
import os
import subprocess

logger = logging.getLogger("shenqing.system_control")

CREATE_NO_WINDOW = getattr(subprocess, "CREATE_NO_WINDOW", 0)


class _DeviceVolumeAdapter:
    """适配新版 pycaw（AudioDevice.volume_percent），保持旧接口方法名。"""

    def __init__(self, device) -> None:  # noqa: ANN001
        self._device = device

    def GetMasterVolumeLevelScalar(self) -> float:  # noqa: N802 - 兼容旧接口
        return max(0.0, min(1.0, float(self._device.volume_percent) / 100.0))

    def SetMasterVolumeLevelScalar(self, value, context=None) -> None:  # noqa: N802,ANN001
        level = max(0.0, min(100.0, float(value) * 100.0))
        self._device.volume_percent = level


def _volume_interface():  # noqa: ANN202
    """返回可读写的音量接口（兼容新旧 pycaw；测试可 mock 本函数）。"""
    from pycaw.utils import AudioUtilities

    device = AudioUtilities.GetSpeakers()
    # 新版 pycaw：AudioDevice.volume_percent / EndpointVolume
    if hasattr(device, "volume_percent") and hasattr(device, "EndpointVolume"):
        return _DeviceVolumeAdapter(device)
    # 旧版 pycaw：Activate 出 IAudioEndpointVolume
    from ctypes import POINTER, cast

    from comtypes import CLSCTX_ALL
    from pycaw.pycaw import IAudioEndpointVolume

    interface = device.Activate(IAudioEndpointVolume._iid_, CLSCTX_ALL, None)
    return cast(interface, POINTER(IAudioEndpointVolume))


def get_volume() -> int:
    """默认输出设备主音量 0-100；不可用返回 -1。"""
    if os.name != "nt":
        return -1
    try:
        scalar = float(_volume_interface().GetMasterVolumeLevelScalar())
        return max(0, min(100, int(round(scalar * 100))))
    except Exception as exc:  # noqa: BLE001 - 没有音频设备/未装 pycaw
        logger.info("读取系统音量失败：%s", exc)
        return -1


def set_volume(value: int) -> bool:
    """设置默认输出设备主音量（0-100）。"""
    if os.name != "nt":
        return False
    try:
        level = max(0, min(100, int(value)))
    except (TypeError, ValueError):
        return False
    try:
        _volume_interface().SetMasterVolumeLevelScalar(level / 100.0, None)
        return True
    except Exception as exc:  # noqa: BLE001
        logger.info("设置系统音量失败：%s", exc)
        return False


def power_action(action: str) -> bool:
    """关机 / 重启（QML 已二次确认）。"""
    command = {"shutdown": "s", "restart": "r"}.get(str(action or "").lower())
    if command is None:
        return False
    if os.name != "nt":
        return False
    try:
        subprocess.run(
            ["shutdown", f"/{command}", "/t", "0"],
            capture_output=True,
            creationflags=CREATE_NO_WINDOW,
            timeout=10,
        )
        return True
    except (OSError, subprocess.SubprocessError) as exc:
        logger.warning("执行 %s 失败：%s", action, exc)
        return False
