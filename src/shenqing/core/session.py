"""专注会话状态机。"""

from __future__ import annotations

from enum import Enum

from PySide6.QtCore import QObject, QTimer, Signal


class SessionState(str, Enum):
    IDLE = "idle"
    RUNNING = "running"
    PAUSED = "paused"


class SessionController(QObject):
    """倒计时会话。

    - 时长以分钟为单位传入，内部按秒倒计时；
    - 暂停有次数上限（默认 2 次），防止「暂停逃逸」；
    - 自然结束与提前结束走同一个 finished 信号，由上层决定是否记入统计。
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
        self._timer = QTimer(self)
        self._timer.setInterval(1000)
        self._timer.timeout.connect(self._on_timeout)

    # ---- 只读属性 ----
    @property
    def state(self) -> SessionState:
        return self._state

    @property
    def remaining(self) -> int:
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

    # ---- 控制 ----
    def start(self, minutes: int, pause_limit: int = 2) -> None:
        if self._state is not SessionState.IDLE:
            return
        self._total = max(1, int(minutes)) * 60
        self._remaining = self._total
        self._pauses = 0
        self._pause_limit = max(0, int(pause_limit))
        self._state = SessionState.RUNNING
        self._timer.start()
        self.stateChanged.emit()
        self.tick.emit(self._remaining)

    def pause(self) -> bool:
        if not self.can_pause:
            return False
        self._timer.stop()
        self._pauses += 1
        self._state = SessionState.PAUSED
        self.stateChanged.emit()
        return True

    def resume(self) -> bool:
        if self._state is not SessionState.PAUSED:
            return False
        self._state = SessionState.RUNNING
        self._timer.start()
        self.stateChanged.emit()
        return True

    def stop(self) -> None:
        """提前结束（外部已做过冷却 / PIN 校验）。"""
        if self._state is SessionState.IDLE:
            return
        self._timer.stop()
        elapsed = self._total - self._remaining
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

    def _on_timeout(self) -> None:
        if self._remaining > 0:
            self._remaining -= 1
        self.tick.emit(self._remaining)
        if self._remaining <= 0:
            self._timer.stop()
            elapsed, pauses = self._total, self._pauses
            self._reset()
            self.stateChanged.emit()
            self.finished.emit(elapsed, True, pauses)
