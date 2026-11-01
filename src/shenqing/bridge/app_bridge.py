"""暴露给 QML 的应用桥（上下文对象名：App）。

v0.2：数据模型改为「空间（Space）」，会话围绕空间展开：
开始某空间 → 守卫按「全局黑名单 + 空间白名单」工作 → 结束写统计并通知插件。
"""

from __future__ import annotations

import logging

from PySide6.QtCore import (
    QCoreApplication,
    Property,
    QObject,
    QRunnable,
    QThreadPool,
    QTimer,
    Signal,
    Slot,
)

from ..consts import (
    APP_ALIAS,
    APP_NAME,
    APP_VERSION,
    ATMOSPHERES,
    MAX_MINUTES,
    MIN_MINUTES,
    PRESET_MINUTES,
    SPACE_MAX_MINUTES,
    SPACE_MIN_MINUTES,
    SPACE_MINUTE_STEP,
    LockLevel,
)
from ..core.app_catalog import load_cached, load_catalog
from ..core.blocklist import Blocklist
from ..core.guard import ProcessGuard
from ..core.session import SessionController, SessionState
from ..core.spaces import SpaceManager
from ..core.stats import StatsStore
from ..services import elevation
from ..services.autostart import AutostartManager
from ..services.lock_hardening import LockHardening
from ..services.media_smtc import MediaSmtcService
from ..services.notifications import NotificationService
from ..settings import Settings

logger = logging.getLogger("shenqing.bridge")

try:  # 插件系统由独立模块提供，缺失时降级为空实现
    from ..plugins.manager import PluginManager
except Exception:  # noqa: BLE001 - 插件模块可能尚未就绪
    PluginManager = None  # type: ignore[assignment,misc]


class _CatalogScan(QRunnable):
    """后台线程扫描本机应用清单，完成后通过信号回主线程。"""

    def __init__(self, bridge: "AppBridge") -> None:
        super().__init__()
        self._bridge = bridge

    def run(self) -> None:  # noqa: D401 - QRunnable 接口
        try:
            items = load_catalog(force=True)
        except Exception as exc:  # noqa: BLE001
            logger.warning("扫描应用清单失败：%s", exc)
            items = []
        try:
            self._bridge._catalogScanned.emit(items)
        except RuntimeError:  # 宿主已销毁
            pass


class AppBridge(QObject):
    """QML 只能看到这个对象：属性负责状态，Slot 负责动作。"""

    spacesChanged = Signal()
    stateChanged = Signal()
    tickChanged = Signal()
    statsChanged = Signal()
    catalogChanged = Signal()
    pluginsChanged = Signal()
    lockedChanged = Signal()
    settingsChanged = Signal()
    themeChanged = Signal()
    toast = Signal(str)
    guardEvent = Signal(str)
    mediaChanged = Signal()
    showMainRequested = Signal()
    settingsRequested = Signal()
    quitRequested = Signal()
    languageChanged = Signal(str)
    _catalogScanned = Signal(list)

    def __init__(
        self,
        parent: QObject | None = None,
        translator: object | None = None,
    ) -> None:
        super().__init__(parent)
        self._translator = translator
        self._settings = Settings()
        self._stats = StatsStore()
        self._blocklist = Blocklist()
        self._spaces = SpaceManager()
        self._guard = ProcessGuard(self)
        self._session = SessionController(self)
        self._autostart = AutostartManager()
        self._hardening = LockHardening(self)
        self._active_space_id = ""
        self._session_level = ""
        self._media_info: dict = {}
        self._draft: dict = {}
        self._catalog: list[dict] = load_cached()
        self._catalog_scanning = False
        self._plugins = self._init_plugins()
        if self._plugins is not None and hasattr(self._plugins, "set_notifier"):
            try:
                self._plugins.set_notifier(
                    lambda title, body: self.toast.emit(f"{title} · {body}" if title else str(body))
                )
            except Exception as exc:  # noqa: BLE001
                logger.warning("插件通知通道挂接失败：%s", exc)

        self._media = MediaSmtcService(self)
        self._media.changed.connect(self._on_media_changed)
        # 冒烟/测试模式下不起 WinRT 轮询线程（离屏环境没有媒体会话，也没必要）
        import os as _os

        if _os.environ.get("SHENQING_NO_SCAN") != "1":
            self._media.start()
        self._notifications = NotificationService(parent=self)
        self._notifications.register()

        self._catalogScanned.connect(self._apply_catalog)
        self._session.stateChanged.connect(self.stateChanged)
        self._session.stateChanged.connect(self.lockedChanged)
        self._session.tick.connect(self._on_tick)
        self._session.finished.connect(self._on_finished)
        self._guard.processKilled.connect(self._on_process_killed)

        # 没有缓存时后台补一次扫描，避免启动被 1–5 秒的扫描拖住；
        # 冒烟模式（SHENQING_NO_SCAN=1）跳过，保证离屏测试快速稳定
        import os

        if not self._catalog and os.environ.get("SHENQING_NO_SCAN") != "1":
            QTimer.singleShot(1500, self.refreshAppCatalog)

    # ================= 插件 =================
    def _init_plugins(self):  # noqa: ANN202
        if PluginManager is None:
            return None
        try:
            try:
                manager = PluginManager(
                    self._settings,
                    state_listener=lambda plugin_id, state: self.pluginsChanged.emit(),
                )
            except TypeError:
                manager = PluginManager()  # type: ignore[call-arg]
            logger.info("插件系统已加载")
            return manager
        except Exception as exc:  # noqa: BLE001 - 插件系统失败不能拖垮主程序
            logger.warning("插件系统初始化失败：%s", exc)
            return None

    def _dispatch(self, event: str, *args: object) -> None:
        if self._plugins is None:
            return
        try:
            self._plugins.dispatch(event, *args)
        except Exception as exc:  # noqa: BLE001
            logger.warning("插件事件 %s 分发失败：%s", event, exc)

    @Property(list, notify=pluginsChanged)
    def plugins(self) -> list[dict]:
        if self._plugins is None:
            return []
        try:
            return list(self._plugins.list_plugins())
        except Exception:  # noqa: BLE001
            return []

    @Slot(str, bool)
    def setPluginEnabled(self, plugin_id: str, enabled: bool) -> None:
        if self._plugins is None:
            return
        try:
            self._plugins.set_enabled(plugin_id, bool(enabled))
        except Exception as exc:  # noqa: BLE001
            logger.warning("切换插件 %s 失败：%s", plugin_id, exc)
            self.toast.emit(QCoreApplication.translate("ShenQing", "插件操作失败"))
        self.pluginsChanged.emit()

    @Slot()
    def restartPlugins(self) -> None:
        if self._plugins is not None:
            try:
                self._plugins.reload()
            except Exception as exc:  # noqa: BLE001
                logger.warning("重载插件失败：%s", exc)
        self.pluginsChanged.emit()

    # ================= 空间 =================
    def _space_view(self, space: dict) -> dict:
        view = dict(space)
        view["allowedCount"] = len(space.get("allowed_apps", []))
        view["atmosphereLabel"] = str(space.get("atmosphere", ""))
        for item in ATMOSPHERES:
            if item["value"] == space.get("atmosphere"):
                view["atmosphereColor"] = item["color"]
                break
        else:
            view["atmosphereColor"] = ATMOSPHERES[0]["color"]
        return view

    @Property(list, notify=spacesChanged)
    def spaces(self) -> list[dict]:
        return [self._space_view(space) for space in self._spaces.all()]

    @Property(list, notify=spacesChanged)
    def spacesLight(self) -> list[dict]:
        return [self._space_view(space) for space in self._spaces.light()]

    @Property(str, notify=spacesChanged)
    def superSpaceId(self) -> str:
        return self._spaces.super_id

    @Property(str, notify=stateChanged)
    def activeSpaceId(self) -> str:
        return self._active_space_id

    @Property(str, notify=stateChanged)
    def activeSpaceName(self) -> str:
        space = self._spaces.get(self._active_space_id)
        return str(space["name"]) if space else ""

    @Property(dict, notify=spacesChanged)
    def draftSpace(self) -> dict:
        space = self._spaces.get(str(self._draft.get("id", "")))
        if space is None:
            return {}
        view = self._space_view(space)
        view.update(self._draft.get("fields", {}))
        return view

    @Property(list, constant=True)
    def atmospheres(self) -> list[dict]:
        return ATMOSPHERES

    @Property(int, constant=True)
    def spaceMinMinutes(self) -> int:
        return SPACE_MIN_MINUTES

    @Property(int, constant=True)
    def spaceMaxMinutes(self) -> int:
        return SPACE_MAX_MINUTES

    @Property(int, constant=True)
    def spaceMinuteStep(self) -> int:
        return SPACE_MINUTE_STEP

    @Slot(result=str)
    def spacesNew(self) -> str:
        space = self._spaces.create()
        if space is None:
            self.toast.emit(QCoreApplication.translate("ShenQing", "其他空间已达上限（12 个）"))
            return ""
        self.spacesChanged.emit()
        self.toast.emit(QCoreApplication.translate("ShenQing", "已新增空间"))
        return str(space["id"])

    @Slot(str, str, int, str)
    def updateSpace(self, space_id: str, name: str, minutes: int, atmosphere: str) -> None:
        updated = self._spaces.update(
            space_id, name=name, minutes=minutes, atmosphere=atmosphere
        )
        if updated is not None:
            self._draft = {"id": space_id, "fields": {}}
            self.spacesChanged.emit()

    @Slot(str)
    def deleteSpace(self, space_id: str) -> None:
        if self._spaces.get(space_id) is not None and self._spaces.get(space_id)["super"]:
            self.toast.emit(QCoreApplication.translate("ShenQing", "主空间不可删除"))
            return
        if self._spaces.delete(space_id):
            if self._active_space_id == space_id:
                self.stopSession()
            self._draft = {}
            self.spacesChanged.emit()

    @Slot(str, list)
    def setSpaceAllowedApps(self, space_id: str, apps: list) -> None:
        if self._spaces.set_allowed_apps(space_id, [str(a) for a in apps]):
            self.spacesChanged.emit()

    @Slot(str, str, bool)
    def toggleSpaceAllowedApp(self, space_id: str, exe: str, enabled: bool) -> None:
        if self._spaces.toggle_allowed_app(space_id, exe, bool(enabled)):
            self.spacesChanged.emit()

    @Slot(str)
    def beginEditSpace(self, space_id: str) -> None:
        if self._spaces.get(space_id) is not None:
            self._draft = {"id": space_id, "fields": {}}
            self.spacesChanged.emit()

    @Slot(str, str, int, str)
    def updateDraft(self, space_id: str, name: str, minutes: int, atmosphere: str) -> None:
        if space_id:
            self._draft = {
                "id": space_id,
                "fields": {"name": name, "minutes": minutes, "atmosphere": atmosphere},
            }
            self.spacesChanged.emit()

    @Slot()
    def commitEditSpace(self) -> None:
        space_id = str(self._draft.get("id", ""))
        if not space_id:
            return
        fields = self._draft.get("fields", {})
        space = self._spaces.get(space_id)
        if space is not None and fields:
            self._spaces.update(
                space_id,
                name=fields.get("name", space["name"]),
                minutes=fields.get("minutes", space["minutes"]),
                atmosphere=fields.get("atmosphere", space["atmosphere"]),
            )
        self._draft = {}
        self.spacesChanged.emit()

    @Slot()
    def cancelEditSpace(self) -> None:
        self._draft = {}
        self.spacesChanged.emit()

    # ================= 会话 =================
    @Property(str, notify=stateChanged)
    def state(self) -> str:
        return self._session.state.value

    @Property(int, notify=tickChanged)
    def remainingSeconds(self) -> int:
        return self._session.remaining

    @Property(int, notify=stateChanged)
    def totalSeconds(self) -> int:
        return self._session.total

    @Property(float, notify=tickChanged)
    def progress(self) -> float:
        total = self._session.total
        if total <= 0:
            return 0.0
        return max(0.0, min(1.0, 1.0 - self._session.remaining / total))

    @Property(str, notify=tickChanged)
    def remainingText(self) -> str:
        seconds = max(0, self._session.remaining)
        return f"{seconds // 60:02d}:{seconds % 60:02d}"

    @Property(bool, notify=stateChanged)
    def busy(self) -> bool:
        return self._session.state is not SessionState.IDLE

    @Property(bool, notify=lockedChanged)
    def locked(self) -> bool:
        """v0.3：任何专注会话都进全屏遮罩（不只是超禅）。"""
        return self.busy

    @Property(str, notify=stateChanged)
    def sessionLevel(self) -> str:
        return self._session_level

    @Property(int, notify=stateChanged)
    def pauseCount(self) -> int:
        return self._session.pauses

    @Property(int, notify=stateChanged)
    def pauseLimit(self) -> int:
        return self._session.pause_limit

    @Property(bool, notify=stateChanged)
    def canPause(self) -> bool:
        return self._session.can_pause and self._session_level != LockLevel.HEAVY.value

    # ================= 媒体（SMTC） =================
    @Property(str, notify=mediaChanged)
    def mediaTitle(self) -> str:
        return str(self._media_info.get("title", ""))

    @Property(str, notify=mediaChanged)
    def mediaArtist(self) -> str:
        return str(self._media_info.get("artist", ""))

    @Property(str, notify=mediaChanged)
    def mediaAlbum(self) -> str:
        return str(self._media_info.get("album", ""))

    @Property(str, notify=mediaChanged)
    def mediaApp(self) -> str:
        return str(self._media_info.get("app", ""))

    @Property(bool, notify=mediaChanged)
    def mediaPlaying(self) -> bool:
        return bool(self._media_info.get("playing", False))

    @Property(float, notify=mediaChanged)
    def mediaPosition(self) -> float:
        return float(self._media_info.get("position", 0.0))

    @Property(float, notify=mediaChanged)
    def mediaDuration(self) -> float:
        return float(self._media_info.get("duration", 0.0))

    @Property(bool, notify=mediaChanged)
    def mediaHasSession(self) -> bool:
        return bool(self._media_info.get("has", False))

    @Slot()
    def mediaToggle(self) -> None:
        self._media.toggle()

    @Slot()
    def mediaNext(self) -> None:
        self._media.next()

    @Slot()
    def mediaPrev(self) -> None:
        self._media.previous()

    def _on_media_changed(self, payload: dict) -> None:
        self._media_info = dict(payload or {})
        self.mediaChanged.emit()

    # ================= 主窗口 / 退出（速启面板用） =================
    @Slot()
    def showMainWindow(self) -> None:
        self.showMainRequested.emit()

    @Slot()
    def gotoSettings(self) -> None:
        self.settingsRequested.emit()

    @Slot()
    def quitApp(self) -> None:
        self.quitRequested.emit()

    @Slot(str, str)
    def notify(self, title: str, body: str) -> None:
        """发一条系统通知（失败回退托盘气泡）。"""
        try:
            self._notifications.notify(title, body)
        except Exception as exc:  # noqa: BLE001
            logger.warning("系统通知失败：%s", exc)
            self.toast.emit(f"{title} · {body}")

    @Slot(str)
    def startSpace(self, space_id: str) -> None:
        if self._session.state is not SessionState.IDLE:
            self.toast.emit(QCoreApplication.translate("ShenQing", "已经有正在进行的专注"))
            return
        space = self._spaces.get(space_id)
        if space is None:
            self.toast.emit(QCoreApplication.translate("ShenQing", "空间不存在"))
            return
        self._active_space_id = space_id
        self._session_level = (
            LockLevel.HEAVY.value if space.get("super") else self.lockLevel
        )
        self._guard.set_blacklist(self._blocklist.processes)
        self._guard.set_whitelist([str(a) for a in space.get("allowed_apps", [])])
        self._guard.set_interval(int(self._settings.get("guard_interval_ms", 1000)))
        self._guard.start()
        self._session.start(int(space["minutes"]), int(self._settings.get("pause_limit", 2)))
        self.lockedChanged.emit()
        self._dispatch("session_start", self._space_view(space))

    @Slot(str)
    def startLevel(self, level: str) -> None:
        """速启面板：不选空间，直接按强度开始一轮专注。"""
        if self._session.state is not SessionState.IDLE:
            self.toast.emit(QCoreApplication.translate("ShenQing", "已经有正在进行的专注"))
            return
        if level not in {item.value for item in LockLevel}:
            return
        minutes = int(self._settings.get("default_minutes", 45))
        # 速启用主空间做载体（白名单/时长仍取主空间）
        space = self._spaces.get(self._spaces.super_id) if self._spaces.super_id else None
        self._active_space_id = str(space["id"]) if space else ""
        self._session_level = level
        self._guard.set_blacklist(self._blocklist.processes)
        if space is not None:
            self._guard.set_whitelist([str(a) for a in space.get("allowed_apps", [])])
        self._guard.set_interval(int(self._settings.get("guard_interval_ms", 1000)))
        self._guard.start()
        self._session.start(minutes, int(self._settings.get("pause_limit", 2)))
        self.lockedChanged.emit()
        payload = self._space_view(space) if space else {"name": "速启"}
        payload["level"] = level
        self._dispatch("session_start", payload)

    @Slot()
    def pauseSession(self) -> None:
        if self._session_level == LockLevel.HEAVY.value:
            self.toast.emit(QCoreApplication.translate("ShenQing", "重度模式不可暂停"))
            return
        if not self._session.pause():
            self.toast.emit(QCoreApplication.translate("ShenQing", "暂停次数已用完"))

    @Slot()
    def resumeSession(self) -> None:
        self._session.resume()

    @Slot()
    def stopSession(self) -> None:
        if self._session.state is SessionState.IDLE:
            return
        if self._session_level == LockLevel.HEAVY.value:
            self.toast.emit(QCoreApplication.translate("ShenQing", "重度模式不可提前结束，等计时走完"))
            return
        self._session.stop()

    # ================= 统计 / 设置 =================
    @Property(float, notify=statsChanged)
    def todayMinutes(self) -> float:
        return self._stats.today_minutes()

    @Property(float, notify=statsChanged)
    def weekMinutes(self) -> float:
        return self._stats.week_minutes()

    @Property(int, notify=statsChanged)
    def streakDays(self) -> int:
        return self._stats.streak_days()

    @Property(int, notify=statsChanged)
    def sessionCount(self) -> int:
        return self._stats.total_sessions()

    @Property(list, notify=statsChanged)
    def last7Days(self) -> list[dict]:
        return self._stats.last_7_days()

    @Property(list, constant=True)
    def presetMinutes(self) -> list[int]:
        return list(PRESET_MINUTES)

    @Property(int, constant=True)
    def minMinutes(self) -> int:
        return MIN_MINUTES

    @Property(int, constant=True)
    def maxMinutes(self) -> int:
        return MAX_MINUTES

    @Property(str, notify=settingsChanged)
    def lockLevel(self) -> str:
        return str(self._settings.get("lock_level", LockLevel.MEDIUM.value))

    @Property(int, notify=settingsChanged)
    def defaultMinutes(self) -> int:
        return int(self._settings.get("default_minutes", 25))

    @Property(bool, notify=settingsChanged)
    def autostartEnabled(self) -> bool:
        return self._autostart.is_enabled()

    # ---------- 权限 / 防退出 ----------
    @Property(bool, notify=settingsChanged)
    def isAdmin(self) -> bool:
        return elevation.is_admin()

    @Property(bool, notify=settingsChanged)
    def hardeningEnabled(self) -> bool:
        return bool(self._settings.get("hardening", True))

    @Property(bool, notify=settingsChanged)
    def adminMode(self) -> bool:
        return bool(self._settings.get("admin_mode", False))

    @Property(bool, notify=settingsChanged)
    def elevatedAutostart(self) -> bool:
        try:
            return elevation.elevated_autostart_enabled()
        except Exception:  # noqa: BLE001
            return False

    @Slot(bool)
    def setHardeningEnabled(self, enabled: bool) -> None:
        self._settings.set("hardening", bool(enabled))
        self.settingsChanged.emit()
        self.toast.emit(
            QCoreApplication.translate("ShenQing", "防退出加固已开启")
            if enabled
            else QCoreApplication.translate("ShenQing", "防退出加固已关闭")
        )

    @Slot(bool)
    def setAdminMode(self, enabled: bool) -> None:
        """开启时以管理员身份重启（UAC 确认一次）。"""
        self._settings.set("admin_mode", bool(enabled))
        if not enabled:
            self.settingsChanged.emit()
            return
        if elevation.is_admin():
            self.settingsChanged.emit()
            self.toast.emit(QCoreApplication.translate("ShenQing", "当前已是管理员权限"))
            return
        self.toast.emit(QCoreApplication.translate("ShenQing", "正在请求管理员权限…"))
        if elevation.relaunch_as_admin():
            self.quitRequested.emit()
        else:
            self.toast.emit(
                QCoreApplication.translate("ShenQing", "提权失败：用户取消了 UAC 或策略禁止")
            )

    @Slot(bool)
    def setElevatedAutostart(self, enabled: bool) -> None:
        if enabled and not elevation.is_admin():
            self.toast.emit(
                QCoreApplication.translate("ShenQing", "最高权限自启需要先以管理员身份运行")
            )
            self.settingsChanged.emit()
            return
        ok, message = elevation.set_elevated_autostart(bool(enabled))
        if not ok:
            logger.warning("计划任务操作失败：%s", message)
            self.toast.emit(QCoreApplication.translate("ShenQing", "设置失败，请检查权限"))
        else:
            if enabled:
                # 两者互斥：开了最高权限自启就关掉普通自启
                try:
                    self._autostart.disable()
                    self._settings.set("autostart", False)
                except Exception as exc:  # noqa: BLE001
                    logger.warning("关闭普通自启失败：%s", exc)
            self.toast.emit(
                QCoreApplication.translate("ShenQing", "已开启最高权限自启")
                if enabled
                else QCoreApplication.translate("ShenQing", "已关闭最高权限自启")
            )
        self.settingsChanged.emit()

    # ---------- 遮罩加固（QML 调用） ----------
    @Slot()
    def overlayOpened(self) -> None:
        if not self.hardeningEnabled:
            return
        hwnd = 0
        instance = QCoreApplication.instance()
        if instance is not None:
            for window in instance.topLevelWindows():
                if window.objectName() == "LockOverlay":
                    hwnd = int(window.winId())
                    break
        if hwnd:
            self._hardening.activate(hwnd, hide_taskbar=True, block_keys=True)

    @Slot()
    def overlayClosed(self) -> None:
        self._hardening.deactivate()

    @Property(str, notify=settingsChanged)
    def language(self) -> str:
        """设置里的语言：auto / zh_CN / en_US。"""
        return str(self._settings.get("language", "auto"))

    @Property(list, constant=True)
    def languages(self) -> list[dict]:
        from ..i18n import LOCALES

        result = [{"code": "auto", "label": QCoreApplication.translate("ShenQing", "跟随系统")}]
        for item in LOCALES:
            result.append({"code": item["code"], "label": item["label"]})
        return result

    @Slot(str)
    def setLanguage(self, code: str) -> None:
        if code not in ("auto", "zh_CN", "en_US"):
            return
        self._settings.set("language", code)
        if self._translator is not None:
            try:
                locale = self._translator.apply(code)  # type: ignore[attr-defined]
            except Exception as exc:  # noqa: BLE001
                logger.warning("切换语言失败：%s", exc)
                locale = ""
        else:
            locale = code
        self.languageChanged.emit(locale)
        self.settingsChanged.emit()

    @Property(str, notify=themeChanged)
    def theme(self) -> str:
        return str(self._settings.get("theme", "Auto"))

    @Property(str, constant=True)
    def appName(self) -> str:
        return APP_NAME

    @Property(str, constant=True)
    def appAlias(self) -> str:
        return APP_ALIAS

    @Property(str, constant=True)
    def version(self) -> str:
        return APP_VERSION

    @Property(list, notify=catalogChanged)
    def appCatalog(self) -> list[dict]:
        return self._catalog

    @Slot()
    def refreshAppCatalog(self) -> None:
        """异步扫描（1–6 秒），避免卡住界面；结果回主线程再 emit。"""
        if self._catalog_scanning:
            return
        self._catalog_scanning = True
        self.toast.emit(QCoreApplication.translate("ShenQing", "正在扫描本机应用…"))
        QThreadPool.globalInstance().start(_CatalogScan(self))

    def _apply_catalog(self, items: list) -> None:
        self._catalog_scanning = False
        if items:
            self._catalog = list(items)
        self.catalogChanged.emit()

    @Slot(int)
    def setDefaultMinutes(self, minutes: int) -> None:
        self._settings.set("default_minutes", max(MIN_MINUTES, min(MAX_MINUTES, int(minutes))))
        self.settingsChanged.emit()
        self._dispatch("settings_changed", "default_minutes", int(minutes))

    @Slot(str)
    def setLockLevel(self, level: str) -> None:
        if level not in {item.value for item in LockLevel}:
            return
        self._settings.set("lock_level", level)
        self.settingsChanged.emit()
        self.lockedChanged.emit()
        self._dispatch("settings_changed", "lock_level", level)

    @Slot(bool)
    def setAutostart(self, enabled: bool) -> None:
        if enabled and self.elevatedAutostart:
            if elevation.is_admin():
                elevation.set_elevated_autostart(False)
            else:
                self.toast.emit(
                    QCoreApplication.translate("ShenQing", "已开启最高权限自启，普通自启不再需要")
                )
                self.settingsChanged.emit()
                return
        if enabled and not self._autostart.is_enabled() and not elevation.is_admin():
            # 普通自启写 HKCU Run，不需要管理员
            pass
        self._autostart.set(bool(enabled))
        self._settings.set("autostart", bool(enabled))
        self.settingsChanged.emit()
        self._dispatch("settings_changed", "autostart", bool(enabled))

    @Slot(str)
    def setTheme(self, theme: str) -> None:
        if theme not in {"Auto", "Light", "Dark"}:
            return
        self._settings.set("theme", theme)
        self.themeChanged.emit()
        self.settingsChanged.emit()
        self._dispatch("settings_changed", "theme", theme)

    @Slot()
    def refreshStats(self) -> None:
        self.statsChanged.emit()

    @Slot(result=str)
    def exportStats(self) -> str:
        try:
            path = self._stats.export_csv()
        except OSError as exc:
            self.toast.emit(
                QCoreApplication.translate("ShenQing", "导出失败：{0}").format(exc)
            )
            return ""
        self.toast.emit(
            QCoreApplication.translate("ShenQing", "已导出：{0}").format(path.name)
        )
        return str(path)

    # ================= 内部回调 =================
    def _on_tick(self, remaining: int) -> None:
        self.tickChanged.emit()
        self._dispatch("tick", int(remaining))

    def _on_finished(self, elapsed_seconds: int, completed: bool, pauses: int) -> None:
        self._guard.stop()
        space = self._spaces.get(self._active_space_id)
        space_name = str(space["name"]) if space else ""
        minutes = elapsed_seconds / 60
        if completed or minutes >= 1:
            self._stats.record(
                minutes,
                self.lockLevel,
                completed,
                pauses,
                space=space_name,
            )
            self.statsChanged.emit()
            self.toast.emit(
                QCoreApplication.translate("ShenQing", "本轮专注完成，休息一下")
                if completed
                else QCoreApplication.translate("ShenQing", "本轮专注已结束")
            )
        else:
            self.toast.emit(QCoreApplication.translate("ShenQing", "专注时间太短，未计入统计"))
        summary = {
            "space": space_name,
            "space_id": self._active_space_id,
            "space_name": space_name,
            "minutes": round(minutes, 1),
            "completed": bool(completed),
            "pauses": int(pauses),
        }
        self._dispatch("session_end", summary)
        try:
            if completed:
                self._notifications.notify(
                    QCoreApplication.translate("ShenQing", "专注完成"),
                    "{} · {}".format(
                        space_name or QCoreApplication.translate("ShenQing", "专注"),
                        QCoreApplication.translate("ShenQing", "休息一下"),
                    ),
                )
            elif minutes >= 1:
                self._notifications.notify(
                    QCoreApplication.translate("ShenQing", "专注结束"),
                    "{} · {}".format(
                        space_name or QCoreApplication.translate("ShenQing", "专注"),
                        QCoreApplication.translate("ShenQing", "{0} 分钟").format(round(minutes)),
                    ),
                )
        except Exception as exc:  # noqa: BLE001
            logger.warning("结束通知失败：%s", exc)
        self._active_space_id = ""
        self._session_level = ""
        self.stateChanged.emit()
        self.lockedChanged.emit()

    def _on_process_killed(self, exe_name: str) -> None:
        self.guardEvent.emit(exe_name)
        self._dispatch("process_blocked", str(exe_name))
