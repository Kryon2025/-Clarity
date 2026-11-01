"""系统托盘：关闭主窗口后仍能继续运行。"""

from __future__ import annotations

from pathlib import Path

from PySide6.QtCore import QCoreApplication, QObject, Signal
from PySide6.QtGui import QAction, QCursor, QIcon
from PySide6.QtWidgets import QMenu, QSystemTrayIcon

from ..consts import APP_ALIAS, APP_NAME


def app_icon_path() -> Path | None:
    """优先用项目 assets 图标，其次回退到 RinUI 自带图标。"""
    bundled = getattr(__import__("sys"), "_MEIPASS", None)
    candidates: list[Path] = []
    if bundled:
        candidates.append(Path(bundled) / "assets" / "icon.png")
    project_icon = Path(__file__).resolve().parents[3] / "assets" / "icon.png"
    candidates.append(project_icon)
    try:
        import RinUI

        candidates.append(Path(RinUI.__file__).resolve().parent / "assets" / "img" / "default_app_icon.png")
    except ImportError:  # pragma: no cover
        pass
    for path in candidates:
        if path.exists():
            return path
    return None


class TrayController(QObject):
    showRequested = Signal()
    startRequested = Signal()
    quickPanelRequested = Signal()
    quitRequested = Signal()

    def __init__(self, parent: QObject | None = None) -> None:
        super().__init__(parent)
        self._tray = QSystemTrayIcon(self)
        icon_path = app_icon_path()
        self._tray.setIcon(QIcon(str(icon_path)) if icon_path else QIcon())
        self._tray.setToolTip(f"{APP_NAME}（{APP_ALIAS}）")

        menu = QMenu()
        show_action = QAction(QCoreApplication.translate("ShenQing", "显示主窗口"), menu)
        show_action.triggered.connect(self.showRequested)
        start_action = QAction(QCoreApplication.translate("ShenQing", "开始专注"), menu)
        start_action.triggered.connect(self.startRequested)
        quick_action = QAction(QCoreApplication.translate("ShenQing", "速启面板…"), menu)
        quick_action.triggered.connect(self.quickPanelRequested)
        quit_action = QAction(QCoreApplication.translate("ShenQing", "退出深清"), menu)
        quit_action.triggered.connect(self.quitRequested)
        menu.addAction(show_action)
        menu.addAction(start_action)
        menu.addAction(quick_action)
        menu.addSeparator()
        menu.addAction(quit_action)
        self._menu = menu
        # 注意：不调用 setContextMenu，右键改由 activated(Context) 打开速启面板
        self._tray.activated.connect(self._on_activated)

    def show(self) -> None:
        self._tray.show()

    def set_tooltip_text(self, app_name: str) -> None:
        self._tray.setToolTip(app_name)

    def show_menu(self) -> None:
        """兜底：面板加载失败时仍能用右键菜单。"""
        self._menu.popup(QCursor.pos())

    def tray_geometry(self):  # noqa: ANN201 - QRect | None
        try:
            rect = self._tray.geometry()
            return rect if rect.isValid() else None
        except Exception:  # noqa: BLE001
            return None

    def hide(self) -> None:
        self._tray.hide()

    def message(self, title: str, body: str) -> None:
        if QSystemTrayIcon.supportsMessages():
            self._tray.showMessage(title, body, QSystemTrayIcon.MessageIcon.Information, 4000)

    def _on_activated(self, reason: QSystemTrayIcon.ActivationReason) -> None:
        if reason == QSystemTrayIcon.ActivationReason.Context:
            # 右键：RinUI/CW2 风格的速启面板
            self.quickPanelRequested.emit()
            return
        if reason in (
            QSystemTrayIcon.ActivationReason.Trigger,
            QSystemTrayIcon.ActivationReason.DoubleClick,
        ):
            self.showRequested.emit()
