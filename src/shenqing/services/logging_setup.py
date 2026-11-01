"""日志：写入 %APPDATA%\\ShenQing\\logs\\app.log。"""

from __future__ import annotations

import logging
from logging.handlers import RotatingFileHandler

from ..paths import logs_dir


def setup_logging(level: int = logging.INFO) -> logging.Logger:
    logger = logging.getLogger("shenqing")
    if logger.handlers:
        return logger
    logger.setLevel(level)
    handler = RotatingFileHandler(
        logs_dir() / "app.log",
        maxBytes=1_000_000,
        backupCount=3,
        encoding="utf-8",
    )
    handler.setFormatter(logging.Formatter("%(asctime)s [%(levelname)s] %(name)s: %(message)s"))
    logger.addHandler(handler)
    stream = logging.StreamHandler()
    stream.setFormatter(logging.Formatter("[%(levelname)s] %(message)s"))
    logger.addHandler(stream)
    return logger
