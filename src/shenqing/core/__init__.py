"""核心领域逻辑：空间、会话、守护、统计、黑名单、应用清单。"""

from .app_catalog import CATEGORIES, load_cached, load_catalog
from .blocklist import Blocklist
from .guard import ProcessGuard, iter_processes, kill_process
from .session import SessionController, SessionState
from .spaces import SpaceManager
from .stats import StatsStore

__all__ = [
    "CATEGORIES",
    "Blocklist",
    "ProcessGuard",
    "SessionController",
    "SessionState",
    "SpaceManager",
    "StatsStore",
    "iter_processes",
    "kill_process",
    "load_cached",
    "load_catalog",
]
