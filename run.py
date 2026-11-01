"""开发期启动入口：python run.py [--smoke]"""

from __future__ import annotations

import sys
from pathlib import Path

SRC = Path(__file__).resolve().parent / "src"
if str(SRC) not in sys.path:
    sys.path.insert(0, str(SRC))

from shenqing.app import main  # noqa: E402

if __name__ == "__main__":
    raise SystemExit(main(sys.argv))
