"""速启面板控制器（v0.8）：确保托盘右键每次都能打开/重新定位面板。

QML（QuickPanel.qml）暴露 showAt(px, py) / toggleAt(px, py)。
Python 侧不再是「面板只在第一次创建、之后只 setProperty」，而是：
1. 面板对象失效（被销毁/隐藏异常）时重新创建；
2. 每次都直接 invokeMethod("showAt", x, y)，失败再退回 requestTick 机制；
3. 记录最近一次 toggle 结果，供自测脚本与日志排查。
"""

from __future__ import annotations

import logging

from PySide6.QtCore import Q_ARG, QMetaObject, QObject, Qt, QUrl, Signal
from PySide6.QtGui import QCursor

from ..paths import qml_file

logger = logging.getLogger("shenqing.quick_panel")


class QuickPanelController(QObject):
    """管理 QuickPanel.qml 实例与显示定位。"""

    shown = Signal()

    def __init__(self, window, tray=None, parent: QObject | None = None) -> None:  # noqa: ANN001
        super().__init__(parent)
        self._window = window
        self._tray = tray
        self._panel = None
        self._component = None
        self._last_ok = False
        self._last_point = (0, 0)
        self._toggle_count = 0

    # ---------- 面板对象 ----------
    def panel(self):  # noqa: ANN202
        return self._panel

    def ensure_panel(self):  # noqa: ANN202
        panel = self._panel
        if panel is not None:
            try:
                panel.objectName()
                return panel
            except (RuntimeError, ReferenceError):
                self._panel = None
                self._component = None
        if self._window is None:
            return None
        try:
            from PySide6.QtQml import QQmlComponent

            component = QQmlComponent(
                self._window.engine, QUrl.fromLocalFile(str(qml_file("QuickPanel.qml")))
            )
            panel = component.create()
            if component.isError() or panel is None:
                logger.warning("速启面板加载失败：%s", component.errorString())
                return None
            self._component = component
            self._panel = panel
            try:
                panel.destroyed.connect(lambda *_: self._on_destroyed())
            except (RuntimeError, TypeError):
                pass
            return panel
        except Exception as exc:  # noqa: BLE001 - 面板失败要有兜底菜单
            logger.warning("创建速启面板失败：%s", exc)
            return None

    def _on_destroyed(self) -> None:
        self._panel = None
        self._component = None

    # ---------- 定位 ----------
    def anchor(self) -> tuple[int, int]:
        rect = None
        if self._tray is not None:
            try:
                rect = self._tray.tray_geometry()
            except Exception:  # noqa: BLE001
                rect = None
        if rect is not None:
            return int(rect.center().x()), int(rect.top())
        cursor = QCursor.pos()
        return int(cursor.x()), int(cursor.y())

    def toggle(self) -> bool:
        """托盘右键：打开面板或重新定位（幂等）。"""
        self._toggle_count += 1
        panel = self.ensure_panel()
        if panel is None:
            return False
        x, y = self.anchor()
        self._last_point = (x, y)
        ok = False
        try:
            ok = bool(
                QMetaObject.invokeMethod(
                    panel,
                    "showAt",
                    Qt.ConnectionType.DirectConnection,
                    Q_ARG("QVariant", float(x)),
                    Q_ARG("QVariant", float(y)),
                )
            )
        except Exception as exc:  # noqa: BLE001 - 退回 requestTick 机制
            logger.info("invoke showAt 失败，退回 requestTick：%s", exc)
            ok = False
        if not ok:
            try:
                panel.setProperty("requestX", float(x))
                panel.setProperty("requestY", float(y))
                panel.setProperty("requestTick", int(panel.property("requestTick") or 0) + 1)
                ok = True
            except (RuntimeError, TypeError):
                ok = False
        try:
            visible = bool(panel.property("visible"))
            panel.setProperty("visible", True)
            if not visible and hasattr(panel, "raise_"):
                panel.raise_()
        except (RuntimeError, TypeError):
            pass
        self._last_ok = bool(ok)
        if self._last_ok:
            logger.info("速启面板已显示/重新定位：第 %s 次 (%s,%s)", self._toggle_count, x, y)
            self.shown.emit()
        return self._last_ok

    def hide(self) -> None:
        panel = self._panel
        if panel is None:
            return
        try:
            panel.setProperty("visible", False)
        except (RuntimeError, TypeError):
            self._panel = None

    def visible(self) -> bool:
        panel = self._panel
        if panel is None:
            return False
        try:
            return bool(panel.property("visible"))
        except (RuntimeError, TypeError):
            return False

    # ---------- 自测信息 ----------
    def stats(self) -> dict:
        panel = self._panel
        position = [0, 0]
        if panel is not None:
            try:
                position = [int(panel.property("x") or 0), int(panel.property("y") or 0)]
            except (RuntimeError, TypeError):
                pass
        return {
            "toggles": self._toggle_count,
            "lastOk": self._last_ok,
            "visible": self.visible(),
            "anchor": list(self._last_point),
            "position": position,
        }
