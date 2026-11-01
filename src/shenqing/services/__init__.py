"""系统集成：开机自启、托盘、日志。"""

from .autostart import AutostartManager
from .logging_setup import setup_logging
from .tray import TrayController

__all__ = ["AutostartManager", "TrayController", "setup_logging"]
