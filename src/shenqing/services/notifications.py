"""Windows 系统通知：注册 AppUserModelID + Toast 通知，失败回退托盘气泡。"""

from __future__ import annotations

import os
from pathlib import Path
from typing import Any, Callable

from PySide6.QtCore import QObject

try:
    import winreg
except ImportError:  # pragma: no cover
    winreg = None  # type: ignore[assignment]

APP_ID = "ShenQing.ShenQing"
APP_DISPLAY_NAME = "深清"


class NotificationService(QObject):
    """优先用 Windows Toast（会进通知中心），不可用时用托盘气泡。"""

    def __init__(
        self,
        app_id: str = APP_ID,
        display_name: str = APP_DISPLAY_NAME,
        icon_path: Path | str | None = None,
        fallback: Callable[[str, str], None] | None = None,
        parent: QObject | None = None,
    ) -> None:
        super().__init__(parent)
        self.app_id = app_id
        self.display_name = display_name
        self.icon_path = str(icon_path) if icon_path else ""
        self._fallback = fallback
        self._registered = False
        self._toast_ok = False
        try:
            from winrt.windows.ui.notifications import ToastNotificationManager  # noqa: F401

            self._toast_ok = True
        except Exception:  # noqa: BLE001
            self._toast_ok = False

    # ---------- 注册 ----------
    def register(self) -> bool:
        """在 HKCU\\Software\\Classes\\AppUserModelId 下注册，Toast 才能显示应用名与图标。"""
        if winreg is None:
            return False
        try:
            with winreg.CreateKey(winreg.HKEY_CURRENT_USER, rf"Software\\Classes\\AppUserModelId\\{self.app_id}") as key:
                winreg.SetValueEx(key, "DisplayName", 0, winreg.REG_SZ, self.display_name)
                if self.icon_path:
                    winreg.SetValueEx(key, "IconUri", 0, winreg.REG_SZ, self.icon_path)
                winreg.SetValueEx(key, "ShowInSettings", 0, winreg.REG_DWORD, 1)
            self._registered = True
            return True
        except OSError:
            return False

    @property
    def available(self) -> bool:
        return self._toast_ok

    # ---------- 发送 ----------
    def notify(self, title: str, body: str) -> bool:
        if not self._registered:
            self.register()
        if self._toast_ok and self._toast_ok:
            try:
                if self._show_toast(title, body):
                    return True
            except Exception:  # noqa: BLE001
                pass
        if self._fallback is not None:
            self._fallback(title, body)
            return False
        return False

    def _show_toast(self, title: str, body: str) -> bool:
        from winrt.windows.data.xml.dom import XmlDocument
        from winrt.windows.ui.notifications import (
            ToastNotification,
            ToastNotificationManager,
        )

        def esc(text: str) -> str:
            return (
                str(text)
                .replace("&", "&amp;")
                .replace("<", "&lt;")
                .replace(">", "&gt;")
            )

        xml = (
            '<toast activationType="foreground" scenario="default">'
            "<visual><binding template=\"ToastGeneric\">"
            f"<text>{esc(title)}</text><text>{esc(body)}</text>"
            "</binding></visual>"
            '<audio silent="true"/>'
            "</toast>"
        )
        doc = XmlDocument()
        doc.load_xml(xml)
        notifier = ToastNotificationManager.create_toast_notifier(self.app_id)
        notifier.show(ToastNotification(doc))
        return True
