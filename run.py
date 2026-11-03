"""开发期启动入口：python run.py [--smoke] [--restarted] [--keeper-worker]"""

from __future__ import annotations

import sys
from pathlib import Path

SRC = Path(__file__).resolve().parent / "src"
if str(SRC) not in sys.path:
    sys.path.insert(0, str(SRC))


def _run_keeper_worker() -> bool:
    """打包后由保活看门狗以「深清.exe --keeper-worker」拉起。"""
    if "--keeper-worker" not in sys.argv:
        return False
    from shenqing.keeper_worker import main as keeper_main

    raise SystemExit(keeper_main(sys.argv))


if __name__ == "__main__":
    _run_keeper_worker()
    from shenqing.app import main

    raise SystemExit(main(sys.argv))
