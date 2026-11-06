"""专注会话状态机（v0.8：monotonic 计时，休眠/改系统时间不跑偏）。"""

from __future__ import annotations

import time
from enum import Enum

from PySide6.QtCore import QObject, QTimer, Signal


class SessionState(str, Enum):
    IDLE = "idle"
    RUNNING = "running"
    PAUSED = "paused"


class SessionController(QObject):
    """倒计时会话。

    - 时长以分钟传入，内部用 time.monotonic() 计算每次 tick 真实经过的秒数：
      电脑休眠醒来后 QTimer 可能一次补很多 tick，剩余时间按真实经过秒数一次性扣减，
      到点立即结束，不按墙钟多算、也不会卡在锁定。
    - 普通 tick 每次至少扣 1 秒（兼容测试里手动驱动 _on_timeout）。
    - 暂停次数上限（默认 2），防止「暂停逃逸」。
    """

    stateChanged = Signal()
    tick = Signal(int)  # 剩余秒数
    finished = Signal(int, bool, int)  # (专注秒数, 是否自然完成, 暂停次数)

    def __init__(self, parent: QObject | None = None) -> None:
        super().__init__(parent)
        self._state = SessionState.IDLE
        self._total = 0
        self._remaining = 0
        self._pauses = 0
        self._pause_limit = 2
        self._last_tick_at = 0.0  # time.monotonic()
        self._timer = QTimer(self)
        self._timer.setInterval(1000)
        self._timer.timeout.connect(self._on_timeout)

    # ---- 只读属性 ----
    @property
    def state(self) -> SessionState:
        return self._state

    @property
    def remaining(self) -> int:
        if self._state is SessionState.RUNNING:
            drift = int(max(0.0, time.monotonic() - self._last_tick_at))
            return max(0, self._remaining - drift)
        return self._remaining

    @property
    def total(self) -> int:
        return self._total

    @property
    def pauses(self) -> int:
        return self._pauses

    @property
    def pause_limit(self) -> int:
        return self._pause_limit

    @property
    def can_pause(self) -> bool:
        return self._state is SessionState.RUNNING and self._pauses < self._pause_limit

    # ---- 内部计时 ----
    def _consume_elapsed(self) -> int:
        """按 monotonic 真实经过秒数扣减剩余时间（至少 0 秒）。"""
        now = time.monotonic()
        elapsed = int(max(0.0, now - self._last_tick_at))
        self._last_tick_at = now
        if elapsed:
            self._remaining = max(0, self._remaining - elapsed)
        return elapsed

    # ---- 控制 ----
    def start(self, minutes: int, pause_limit: int = 2) -> None:
        if self._state is not SessionState.IDLE:
            return
        self._total = max(1, int(minutes)) * 60
        self._remaining = self._total
        self._pauses = 0
        self._pause_limit = max(0, int(pause_limit))
        self._state = SessionState.RUNNING
        self._last_tick_at = time.monotonic()
        self._timer.start()
        self.stateChanged.emit()
        self.tick.emit(self._remaining)

    def pause(self) -> bool:
        if self.can_pause:
            self._timer.stop()
            self._consume_elapsed()
            if self._remaining <= 0:
                self._finish(completed=False)
                return True
            self._pauses += 1
            self._state = SessionState.PAUSED
            self.stateChanged.emit()
            return True
        return False

    def resume(self) -> bool:
        if self._state is not SessionState.PAUSED:
            return False
        self._state = SessionState.RUNNING
        self._last_tick_at = time.monotonic()
        self._timer.start()
        self.stateChanged.emit()
        return True

    def extend(self, minutes: int) -> bool:
        """延长当前会话（运行/暂停中有效），并立即刷新显示。"""
        try:
            extra = max(1, int(minutes)) * 60
        except (TypeError, ValueError):
            return False
        if self._state is SessionState.IDLE:
            return False
        self._total += extra
        self._remaining += extra
        self.tick.emit(self._remaining)
        self.stateChanged.emit()
        return True

    def stop(self) -> None:
        """提前结束（外部已做过冷却 / PIN 校验）。"""
        if self._state is SessionState.IDLE:
            return
        if self._state is SessionState.RUNNING:
            self._consume_elapsed()
        self._timer.stop()
        elapsed = max(0, self._total - self._remaining)
        self._reset()
        self.finished.emit(elapsed, False, self._pauses)

    def reset(self) -> None:
        self._timer.stop()
        self._reset()
        self.stateChanged.emit()

    # ---- 内部 ----
    def _reset(self) -> None:
        self._state = SessionState.IDLE
        self._total = 0
        self._remaining = 0
        self._pauses = 0
        self._last_tick_at = 0.0

    def _finish(self, *, completed: bool) -> None:
        elapsed, pauses = self._total, self._pauses
        self._timer.stop()
        self._reset()
        self.stateChanged.emit()
        self.finished.emit(elapsed, completed, pauses)

    def _on_timeout(self) -> None:
        if self._state is not SessionState.RUNNING:
            return
        now = time.monotonic()
        elapsed = int(round(max(0.0, now - self._last_tick_at)))
        # 手动驱动/定时器抖动时也至少扣 1 秒
        steps = max(1, elapsed)
        self._last_tick_at = now
        self._remaining = max(0, self._remaining - steps)
        self.tick.emit(self._remaining)
        if self._remaining <= 0:
            self._finish(completed=True)
