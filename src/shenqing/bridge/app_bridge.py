"""暴露给 QML 的应用桥（上下文对象名：App）。

v0.2：数据模型改为「空间（Space）」，会话围绕空间展开：
开始某空间 → 守卫按「全局黑名单 + 空间白名单」工作 → 结束写统计并通知插件。
"""

from __future__ import annotations

import json
import logging
import os
import threading
import time
from collections import deque
from datetime import datetime, timedelta
from pathlib import Path

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
    CHANGELOG,
    APP_NAME,
    APP_VERSION,
    ATMOSPHERES,
    DEFAULT_THEME,
    FEEDBACK_URLS,
    MAX_MINUTES,
    MIN_MINUTES,
    MODE_LABELS,
    PRESET_MINUTES,
    QUOTES,
    SPACE_MAX_MINUTES,
    SPACE_MIN_MINUTES,
    SPACE_MINUTE_STEP,
    THEMES,
    TRIAL_MINUTES,
    LockLevel,
)
from ..core.app_catalog import load_cached, load_catalog
from ..core.blocklist import Blocklist
from ..core.guard import ProcessGuard
from ..core.session import SessionController, SessionState
from ..core.spaces import SpaceManager
from ..core.stats import StatsStore
from ..services import elevation, power, timesync, updater
from ..services import ai as ai_service
from ..services import app_usage
from ..services import sleep_mode, system_control, wallpaper
from ..services.autostart import AutostartManager
from ..services.lock_hardening import LockHardening
from ..services.media_smtc import MediaSmtcService
from ..services.notifications import NotificationService
from ..paths import app_data_dir, license_file, notice_file
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


def _path_to_url(path: object) -> str:
    if not path:
        return ""
    try:
        return Path(str(path)).as_uri()
    except Exception:  # noqa: BLE001
        return str(path)


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
    themeChanged = Signal(str)
    toast = Signal(str)
    guardEvent = Signal(str)
    #: v0.6：从覆清 dock 启动白名单应用成功（携带 exe 名/路径），供主程序把应用窗口提到遮罩之上
    appLaunched = Signal(str)
    mediaChanged = Signal()
    showMainRequested = Signal()
    spacesPageRequested = Signal(str)
    settingsRequested = Signal()
    quitRequested = Signal()
    wallpaperChanged = Signal()
    sleepChanged = Signal()
    appUsageChanged = Signal()
    aiChanged = Signal()
    aiModelsChanged = Signal()
    aiChatsChanged = Signal()
    aiUsageChanged = Signal()
    languageChanged = Signal(str)
    _catalogScanned = Signal(list)
    #: 自动更新：后台线程 → 主线程
    _updateChecked = Signal(object, str)
    _updateProgress = Signal(int)
    _updateDownloaded = Signal(bool, str)
    #: v0.9 AI：线程池回调 → 主线程（token 防止旧回答覆盖新问题）
    _aiAsyncResult = Signal(int, object)
    #: v0.10 模型列表拉取结果：provider, models, error
    _aiModelsFetched = Signal(str, object, str)

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
        self._session_started_at = timesync.now()
        self._trial_active = False
        self._trial_times: list[float] = []
        self._preview_active = False
        self._preview_level = ""
        # 进入前的 10 秒倒计时（水滴凝聚）
        self._prepare_active = False
        self._prepare_remaining = 0
        self._prepare_space_id = ""
        self._prepare_mode = ""
        self._prepare_minutes: int | None = None
        self._prepare_timer = QTimer(self)
        self._prepare_timer.setInterval(1000)
        self._prepare_timer.timeout.connect(self._tick_prepare)
        # 自动更新状态（idle/checking/available/downloading/ready/error）
        self._update_state = "idle"
        self._update_info: dict | None = None
        self._update_progress = 0
        self._update_error = ""
        self._update_download_path: Path | None = None
        self._update_cancel: updater.CancelToken | None = None
        # v0.8：睡眠模式 / 系统控制 / 壁纸 / AI 骨架
        self._sleep = sleep_mode.SleepManager()
        self._ai = ai_service.AIService(self._settings)
        # v0.9 AI 异步状态
        self._ai_state = "idle"
        self._ai_answer = ""
        self._ai_error = ""
        self._ai_token = 0
        self._ai_mode = ""
        # v0.10：当前服务商模型列表（fetch /models）
        self._ai_models: list[str] = []
        self._ai_models_state = "idle"
        self._ai_models_error = ""
        # v0.11：费用用量 + 对话历史
        self._ai_chats_path = app_data_dir() / "ai_chats.json"
        self._ai_usage_path = app_data_dir() / "ai_usage.json"
        self._ai_chats: dict = {"currentId": "", "conversations": []}
        self._ai_usage: dict = {}
        self._ai_last_usage: dict = {}
        self._ai_usage_currency = ""
        self._ai_pending_conv = ""
        self._load_ai_chats()
        self._load_ai_usage()
        # v0.9 应用使用时长统计（前台应用 5s 采样）
        self._app_usage = app_usage.AppUsageTracker(
            now_provider=timesync.now, parent=self
        )
        self._app_usage_date = ""
        self._app_usage_hourly_range = "today"
        self._volume = -1
        self._sleep_lock_active = False
        self._clock_clicks: deque[float] = deque()
        self._bing_url = wallpaper.cached_bing_url()
        self._avatar_url = ""
        self._sleep_timer = QTimer(self)
        self._sleep_timer.setInterval(20000)
        self._sleep_timer.timeout.connect(self._tick_sleep)
        self._media_info: dict = {}
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
        if os.environ.get("SHENQING_NO_SCAN") != "1":
            self._media.start()
        self._notifications = NotificationService(parent=self)
        self._notifications.register()
        # v0.8：清理已移除的 CW2 组件插件；启动睡眠模式轮询 + 壁纸预取（测试/冒烟跳过）
        self._purge_legacy_plugins()
        if os.environ.get("SHENQING_NO_SCAN") != "1":
            self._sleep_timer.start()
            self._app_usage.start()
            threading.Thread(
                target=self._load_wallpaper_assets,
                name="shenqing-wallpaper",
                daemon=True,
            ).start()
        application = QCoreApplication.instance()
        if application is not None:
            application.aboutToQuit.connect(self._shutdown_services)

        self._catalogScanned.connect(self._apply_catalog)
        self._updateChecked.connect(self._on_update_checked)
        self._updateProgress.connect(self._on_update_progress)
        self._updateDownloaded.connect(self._on_update_downloaded)
        self._aiAsyncResult.connect(self._on_ai_result)
        self._aiModelsFetched.connect(self._on_ai_models_fetched)
        self._app_usage.changed.connect(self._on_app_usage_changed)
        self._session.stateChanged.connect(self.stateChanged)
        self._session.stateChanged.connect(self.lockedChanged)
        self._session.tick.connect(self._on_tick)
        self._session.finished.connect(self._on_finished)
        self._guard.processKilled.connect(self._on_process_killed)

        # 没有缓存时后台补一次扫描，避免启动被 1–5 秒的扫描拖住；
        # 冒烟模式（SHENQING_NO_SCAN=1）跳过，保证离屏测试快速稳定
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

    @Property(list, notify=pluginsChanged)
    def pluginNavItems(self) -> list[dict]:
        """插件注册的导航入口（导航「插件」展开后的子项）。"""
        if self._plugins is None:
            return []
        getter = getattr(self._plugins, "list_nav_items", None)
        if getter is None:
            return []
        try:
            items = list(getter())
        except Exception:  # noqa: BLE001
            return []
        return [
            {
                "id": str(item.get("itemId") or item.get("id") or ""),
                "title": str(item.get("title") or ""),
                "icon": str(item.get("icon") or "grid"),
                "qmlPath": _path_to_url(item.get("qmlPath")),
                "pluginId": str(item.get("pluginId") or ""),
            }
            for item in items
        ]

    @Property(list, notify=pluginsChanged)
    def pluginWidgets(self) -> list[dict]:
        """插件注册的全屏遮罩组件。"""
        if self._plugins is None:
            return []
        getter = getattr(self._plugins, "list_widgets", None)
        if getter is None:
            return []
        try:
            widgets = list(getter())
        except Exception:  # noqa: BLE001
            return []
        return [
            {
                "id": str(item.get("itemId") or item.get("id") or ""),
                "title": str(item.get("title") or ""),
                "qmlPath": _path_to_url(item.get("qmlPath")),
                "anchor": str(item.get("anchor") or "topRight"),
                "width": int(item.get("width") or 240),
                "height": int(item.get("height") or 120),
                "pluginId": str(item.get("pluginId") or ""),
            }
            for item in widgets
        ]

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
        mode = str(space.get("mode", ""))
        view["mode"] = mode
        view["fixedName"] = mode == "heavy"
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

    @Property(list, notify=stateChanged)
    def sessionWhitelist(self) -> list[str]:
        """当前专注空间的白名单（小写 exe 名）；主程序判断前台窗口是否属于 dock 白名单。"""
        space = self._spaces.get(self._active_space_id)
        if space is None:
            return []
        return [str(item).lower() for item in space.get("allowed_apps", [])]

    # ---------- v0.6 多空间 API ----------
    @Slot(str, result=str)
    def addSpaceFor(self, mode: str) -> str:
        """新增一张空间（浅清/覆清）；深清固定一张，失败返回空串。"""
        space = self._spaces.add(mode)
        if space is None:
            self.toast.emit(
                QCoreApplication.translate("ShenQing", "深清只有一张固定空间，不能新增")
                if str(mode) == "heavy"
                else QCoreApplication.translate("ShenQing", "无法新增空间")
            )
            return ""
        self.spacesChanged.emit()
        self.toast.emit(QCoreApplication.translate("ShenQing", "已新增空间"))
        return str(space["id"])

    @Slot(str, str, result=bool)
    def deleteSpaceFor(self, mode: str, space_id: str) -> bool:
        """删除一张空间；深清 / 每档最后一张 / 专注中的空间不可删。"""
        space = self._spaces.get(space_id)
        if space is None or str(space.get("mode")) != str(mode):
            return False
        if str(mode) == "heavy":
            self.toast.emit(QCoreApplication.translate("ShenQing", "深清空间不可删除"))
            return False
        if self._busy_space(space_id):
            self.toast.emit(QCoreApplication.translate("ShenQing", "专注中不能删除当前空间"))
            return False
        if len(self._spaces.by_mode(mode)) <= 1:
            self.toast.emit(QCoreApplication.translate("ShenQing", "每档至少保留一个空间"))
            return False
        if not self._spaces.delete(space_id):
            return False
        self.spacesChanged.emit()
        return True

    def _busy_space(self, space_id: str) -> bool:
        return bool(space_id) and self._active_space_id == space_id and self.busy

    @Slot(str, str, result=bool)
    def setSpaceName(self, space_id: str, name: str) -> bool:
        if not self._spaces.set_name(space_id, name):
            space = self._spaces.get(space_id)
            if space is not None and str(space.get("mode")) == "heavy":
                self.toast.emit(QCoreApplication.translate("ShenQing", "深清空间名不可修改"))
            return False
        self.spacesChanged.emit()
        return True

    @Slot(str, int, result=bool)
    def setSpaceMinutes(self, space_id: str, minutes: int) -> bool:
        if self._spaces.set_minutes(space_id, minutes) is None:
            return False
        self.spacesChanged.emit()
        return True

    @Slot(str, str, bool, result=bool)
    def toggleSpaceAllowedApp(self, space_id: str, exe: str, enabled: bool) -> bool:
        space = self._spaces.get(space_id) or self._spaces.get_by_mode(str(space_id))
        if space is not None and str(space.get("mode")) == "heavy":
            self.toast.emit(QCoreApplication.translate("ShenQing", "深清空间不设置白名单"))
            return False
        if not self._spaces.toggle_allowed_app(space_id, exe, bool(enabled)):
            return False
        self.spacesChanged.emit()
        self.catalogChanged.emit()
        return True

    @Slot(str, list, result=bool)
    def setSpaceAllowedApps(self, space_id: str, apps: list) -> bool:
        if not self._spaces.set_allowed_apps(space_id, [str(a) for a in apps]):
            return False
        self.spacesChanged.emit()
        return True

    # ---------- 旧 QML 浮层兼容（SpaceSettingsSheet 仍可能被加载） ----------
    @Property(list, constant=True)
    def atmospheres(self) -> list[dict]:
        return ATMOSPHERES

    @Property(dict, notify=spacesChanged)
    def draftSpace(self) -> dict:
        return {}

    @Slot(str)
    def beginEditSpace(self, space_id: str) -> None:
        self.spacesChanged.emit()

    @Slot(str, str, int, str)
    def updateSpace(self, space_id: str, name: str, minutes: int, atmosphere: str) -> None:
        space = self._spaces.get(space_id)
        if space is None:
            return
        if str(space.get("mode")) != "heavy":
            self._spaces.set_name(space_id, name)
        self._spaces.set_minutes(space_id, minutes)
        self.spacesChanged.emit()

    @Slot()
    def commitEditSpace(self) -> None:
        self.spacesChanged.emit()

    @Slot()
    def cancelEditSpace(self) -> None:
        self.spacesChanged.emit()

    @Slot(str)
    def deleteSpace(self, space_id: str) -> None:
        space = self._spaces.get(space_id)
        if space is None:
            return
        self.deleteSpaceFor(str(space.get("mode")), space_id)

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

    # ================= v0.8：时间 / 睡眠 / 系统 / 壁纸 / 结束卡片 =================
    @Property(int, notify=statsChanged)
    def todaySessions(self) -> int:
        return int(self._stats.today_sessions(timesync.today()))

    @Property(dict, notify=statsChanged)
    def todayFocusCard(self) -> dict:
        """结束卡片：{date, timeRange, spaceName, minutes, sessions, quote}。"""
        day = timesync.today()
        sessions = self._stats.sessions_on(day)
        starts: list = []
        ends: list = []
        for item in sessions:
            raw = str(item.get("start") or item.get("ts") or "")
            try:
                started = datetime.fromisoformat(raw)
            except (TypeError, ValueError):
                continue
            starts.append(started)
            ends.append(started + timedelta(minutes=float(item.get("minutes", 0) or 0)))
        time_range = ""
        if starts and ends:
            time_range = f"{min(starts):%H:%M} - {max(ends):%H:%M}"
        space_name = ""
        for item in reversed(sessions):
            if str(item.get("space") or ""):
                space_name = str(item.get("space"))
                break
        total_minutes = round(
            sum(float(item.get("minutes", 0) or 0) for item in sessions), 1
        )
        return {
            "date": day.isoformat(),
            "timeRange": time_range,
            "spaceName": space_name,
            "minutes": total_minutes,
            "sessions": len(sessions),
            "quote": QUOTES[day.toordinal() % len(QUOTES)] if QUOTES else "",
        }

    @Slot(int, result=bool)
    def extendSession(self, minutes: int) -> bool:
        if not self._session.extend(minutes):
            return False
        self.toast.emit(
            QCoreApplication.translate("ShenQing", "已延长 {0} 分钟").format(int(minutes))
        )
        return True

    # ---------- 速启面板 → 空间页 ----------
    @Slot(str)
    def openSpacesPage(self, mode: str) -> None:
        """速启面板点空间/档位：打开主界面并切到空间页（不开始专注）。"""
        value = str(mode or "")
        if value not in {item.value for item in LockLevel}:
            value = ""
        self.showMainRequested.emit()
        self.spacesPageRequested.emit(value)

    # ---------- 系统音量 / 关机重启 ----------
    @Property(int, notify=settingsChanged)
    def systemVolume(self) -> int:
        if self._volume < 0:
            self._volume = system_control.get_volume()
        return self._volume

    @Slot(int)
    def setSystemVolume(self, value: int) -> None:
        try:
            level = max(0, min(100, int(value)))
        except (TypeError, ValueError):
            return
        if system_control.set_volume(level):
            self._volume = level
            self._settings.set("volume_panel", level)
        self.settingsChanged.emit()

    @Slot(str)
    def systemPower(self, action: str) -> None:
        value = str(action or "").lower()
        if value not in ("shutdown", "restart"):
            return
        if system_control.power_action(value):
            self.toast.emit(
                QCoreApplication.translate("ShenQing", "系统将在 1 秒内{0}").format(
                    QCoreApplication.translate("ShenQing", "关机")
                    if value == "shutdown"
                    else QCoreApplication.translate("ShenQing", "重启")
                )
            )
        else:
            self.toast.emit(QCoreApplication.translate("ShenQing", "电源操作失败"))

    # ---------- 睡眠模式 ----------
    @Property(list, notify=sleepChanged)
    def sleepSchedules(self) -> list[str]:
        return self._sleep.schedule_times()

    @Property(list, notify=sleepChanged)
    def sleepScheduleItems(self) -> list[dict]:
        return self._sleep.schedules()

    @Slot(str, result=str)
    def addSleepSchedule(self, time_text: str) -> str:
        new_id = self._sleep.add_schedule(time_text)
        if new_id:
            self.sleepChanged.emit()
            self.toast.emit(QCoreApplication.translate("ShenQing", "已添加睡眠锁定时间"))
        else:
            self.toast.emit(QCoreApplication.translate("ShenQing", "时间格式不正确或已存在"))
        return new_id

    @Slot(str, result=bool)
    def removeSleepSchedule(self, key: str) -> bool:
        ok = self._sleep.remove_schedule(key)
        if ok:
            self.sleepChanged.emit()
        return ok

    @Property(bool, notify=sleepChanged)
    def sleepRemindersEnabled(self) -> bool:
        return self._sleep.reminders_enabled

    @Slot(bool)
    def setSleepReminders(self, enabled: bool) -> None:
        self._sleep.set_reminders(bool(enabled))
        self.sleepChanged.emit()

    @Property(int, notify=sleepChanged)
    def unlockChances(self) -> int:
        return self._sleep.unlock_chances

    @Property(str, notify=sleepChanged)
    def unlockChanceLabel(self) -> str:
        return self._sleep.unlock_chance_label

    @Slot(result=bool)
    def clickClockForUnlock(self) -> bool:
        """连续点时钟 10 次（5 秒内）→ 消耗一次本月机会解锁睡眠锁定。"""
        now = time.monotonic()
        while self._clock_clicks and now - self._clock_clicks[0] > 5.0:
            self._clock_clicks.popleft()
        self._clock_clicks.append(now)
        if len(self._clock_clicks) < 10:
            remain = 10 - len(self._clock_clicks)
            self.toast.emit(
                QCoreApplication.translate("ShenQing", "再点 {0} 次可解锁").format(remain)
            )
            return False
        self._clock_clicks.clear()
        if not self._sleep_lock_active:
            self.toast.emit(QCoreApplication.translate("ShenQing", "当前没有睡眠锁定"))
            return False
        if not self._sleep.try_unlock():
            self.sleepChanged.emit()
            self.toast.emit(QCoreApplication.translate("ShenQing", "本月解锁机会已用完"))
            return False
        self._sleep_lock_active = False
        self.sleepChanged.emit()
        if self._session.state is not SessionState.IDLE:
            self._session.stop()
        self.toast.emit(QCoreApplication.translate("ShenQing", "已解锁，提前结束本次睡眠锁定"))
        return True

    def _tick_sleep(self) -> None:
        try:
            now = timesync.now()
            for due in self._sleep.due_reminders(now):
                schedule = due["schedule"]
                offset = int(due["offset"])
                self._sleep.mark_fired(
                    now.strftime("%Y-%m-%d"), schedule["time"], offset
                )
                self.notify(
                    QCoreApplication.translate("ShenQing", "睡眠提醒"),
                    QCoreApplication.translate(
                        "ShenQing", "{0} 分钟后将进入深清锁定（{1}）"
                    ).format(offset, schedule["time"]),
                )
            if self._session.state is not SessionState.IDLE or self._prepare_active:
                return
            due_lock = self._sleep.due_lock(now)
            if due_lock is None:
                return
            heavy = self._spaces.get_by_mode("heavy")
            minutes = int(heavy.get("minutes", 180)) if heavy else 180
            self._sleep.mark_fired(
                now.strftime("%Y-%m-%d"), due_lock["time"], sleep_mode.LOCK_KIND
            )
            self._sleep_lock_active = True
            self._begin_space_session(heavy, "heavy", minutes)
            self.toast.emit(
                QCoreApplication.translate("ShenQing", "睡眠模式：已自动进入深清锁定")
            )
        except Exception as exc:  # noqa: BLE001 - 睡眠调度失败不能拖垮主程序
            logger.warning("睡眠模式调度失败：%s", exc)

    # ---------- Bing 壁纸 / 用户头像 ----------
    @Property(str, notify=wallpaperChanged)
    def bingWallpaperUrl(self) -> str:
        if self._bing_url:
            return self._bing_url
        return wallpaper.cached_bing_url()

    @Property(str, notify=wallpaperChanged)
    def userAvatarUrl(self) -> str:
        return self._avatar_url

    def _load_wallpaper_assets(self) -> None:
        try:
            url = wallpaper.refresh_bing_wallpaper()
            avatar = wallpaper.user_avatar_url()
            changed = False
            if url and url != self._bing_url:
                self._bing_url = url
                changed = True
            if avatar != self._avatar_url:
                self._avatar_url = avatar
                changed = True
            if changed:
                self.wallpaperChanged.emit()
        except Exception as exc:  # noqa: BLE001
            logger.info("壁纸/头像加载失败：%s", exc)

    # ================= v0.9 AI 集成 =================
    @Property(bool, notify=settingsChanged)
    def aiConfigured(self) -> bool:
        return self._ai.configured()

    @Property(bool, notify=settingsChanged)
    def aiEnabled(self) -> bool:
        return self._ai.enabled()

    @Slot(bool)
    def setAIEnabled(self, enabled: bool) -> None:
        self._settings.set("ai_enabled", bool(enabled))
        self.settingsChanged.emit()

    @Property(bool, notify=settingsChanged)
    def aiNeedsKey(self) -> bool:
        return self._ai.needs_key()

    @Property(bool, notify=settingsChanged)
    def aiSupportsReasoning(self) -> bool:
        return self._ai.supports_reasoning()

    @Property(bool, notify=settingsChanged)
    def aiSupportsWebSearch(self) -> bool:
        return self._ai.supports_web_search()

    @Property(bool, notify=settingsChanged)
    def aiReasoningEnabled(self) -> bool:
        return self._ai.reasoning_enabled()

    @Slot(bool)
    def setAIReasoningEnabled(self, enabled: bool) -> None:
        self._settings.set("ai_reasoning_enabled", bool(enabled))
        self.settingsChanged.emit()

    @Property(bool, notify=settingsChanged)
    def aiWebSearchEnabled(self) -> bool:
        return self._ai.web_search_enabled()

    @Slot(bool)
    def setAIWebSearchEnabled(self, enabled: bool) -> None:
        self._settings.set("ai_web_search_enabled", bool(enabled))
        self.settingsChanged.emit()

    @Property(str, notify=settingsChanged)
    def aiReasoningEffort(self) -> str:
        return self._ai.reasoning_effort()

    @Slot(str)
    def setAIReasoningEffort(self, effort: str) -> None:
        self._settings.set("ai_reasoning_effort", str(effort or "").strip())
        self.settingsChanged.emit()

    @Property(list, constant=True)
    def aiProviders(self) -> list[dict]:
        providers = ai_service.provider_list()
        for item in providers:
            if item.get("value") == "custom":
                # 自定义服务商的思考/联网能力由用户开关决定
                item["supports_reasoning"] = bool(
                    self._settings.get("ai_reasoning_enabled", True)
                )
                item["supports_web_search"] = bool(
                    self._settings.get("ai_web_search_enabled", False)
                )
        return providers

    @Property(str, notify=settingsChanged)
    def aiProvider(self) -> str:
        return self._ai.provider()

    @Slot(str)
    def setAIProvider(self, value: str) -> None:
        old_provider = self._ai.provider()
        if not self._ai.set_provider(str(value or "")):
            return
        if self._ai.provider() == old_provider:
            self.settingsChanged.emit()
            return
        # 切换服务商：清空旧模型列表，带出默认 base/model；有 Key 则自动拉取新列表
        self._ai_models = []
        self._ai_models_state = "idle"
        self._ai_models_error = ""
        self.aiModelsChanged.emit()
        self.settingsChanged.emit()
        if (not self._ai.needs_key()) or self._ai.has_key():
            QTimer.singleShot(0, self.fetchAIModels)

    # ---------- 模型列表（/models） ----------
    def _models_cache(self) -> dict:
        raw = self._settings.get("ai_models_cache", {})
        return dict(raw) if isinstance(raw, dict) else {}

    @Property(list, notify=aiModelsChanged)
    def aiModels(self) -> list[str]:
        if self._ai_models:
            return list(self._ai_models)
        cached = ai_service.cached_models(
            self._models_cache(), self._ai.provider()
        )
        if cached:
            return cached
        return list(self._ai.preset().get("models") or [])

    @Property(str, notify=aiModelsChanged)
    def aiModelsState(self) -> str:
        return self._ai_models_state

    @Property(str, notify=aiModelsChanged)
    def aiModelsError(self) -> str:
        return self._ai_models_error

    @Slot()
    def fetchAIModels(self) -> None:
        if self._ai_models_state == "loading":
            return
        key = self._ai.api_key()
        base = self._ai.api_base()
        if not base or (self._ai.needs_key() and not key):
            self._ai_models = []
            self._ai_models_state = "error"
            self._ai_models_error = (
                "请先填写 API Key 与 API Base"
                if self._ai.needs_key()
                else "请先填写 API Base"
            )
            self.aiModelsChanged.emit()
            return
        provider = self._ai.provider()
        self._ai_models_state = "loading"
        self._ai_models_error = ""
        self.aiModelsChanged.emit()
        threading.Thread(
            target=self._fetch_models_worker,
            args=(provider, base, key),
            name="shenqing-ai-models",
            daemon=True,
        ).start()

    def _fetch_models_worker(self, provider: str, base: str, key: str) -> None:
        error = ""
        models: list[str] = []
        try:
            models = ai_service.fetch_models(base, key, provider)
        except Exception as exc:  # noqa: BLE001 - fetch_models 本身不抛异常，双保险
            error = self._ai.sanitize(exc)
        if not models and not error:
            error = "未获取到模型列表"
        try:
            self._aiModelsFetched.emit(provider, models, error)
        except RuntimeError:  # 宿主已销毁
            pass

    @Slot(str, object, str)
    def _on_ai_models_fetched(
        self, provider: str, models: object, error: str
    ) -> None:
        fetched = [str(item) for item in models] if isinstance(models, list) else []
        if fetched:
            cache = ai_service.cache_models(self._models_cache(), provider, fetched)
            self._settings.set("ai_models_cache", cache)
        if str(provider) != self._ai.provider():
            # 旧服务商的迟到结果：只更新缓存，不影响当前 UI
            return
        if fetched:
            self._ai_models = fetched
            self._ai_models_state = "ok"
            self._ai_models_error = ""
        else:
            self._ai_models = []
            self._ai_models_state = "error"
            self._ai_models_error = self._ai.sanitize(error or "未获取到模型列表")
        self.aiModelsChanged.emit()

    @Property(str, notify=settingsChanged)
    def aiBase(self) -> str:
        return self._ai.api_base()

    @Slot(str)
    def setAIBase(self, url: str) -> None:
        self._settings.set("ai_api_base", str(url or "").strip())
        self.settingsChanged.emit()

    @Property(str, notify=settingsChanged)
    def aiModel(self) -> str:
        return self._ai.model()

    @Slot(str)
    def setAIModel(self, model: str) -> None:
        self._settings.set("ai_model", str(model or "").strip())
        self.settingsChanged.emit()

    @Property(bool, notify=settingsChanged)
    def aiHasKey(self) -> bool:
        return self._ai.has_key()

    @Slot(str)
    def setAIKey(self, key: str) -> None:
        self._settings.set("ai_api_key", str(key or "").strip())
        self.settingsChanged.emit()

    @Property(str, notify=aiChanged)
    def aiState(self) -> str:
        return self._ai_state

    @Property(str, notify=aiChanged)
    def aiAnswer(self) -> str:
        return self._ai_answer

    @Property(str, notify=aiChanged)
    def aiError(self) -> str:
        return self._ai_error

    def _ai_settings_items(self) -> list[dict]:
        return [
            {"key": "theme_mode", "title": "主题", "hint": "纯色 / 浅色 / 液态玻璃"},
            {"key": "theme", "title": "窗口外观", "hint": "Auto / Light / Dark"},
            {"key": "language", "title": "语言", "hint": "跟随系统 / 中文 / English"},
            {"key": "autostart", "title": "开机自启", "hint": "登录时启动深清"},
            {"key": "hardening", "title": "防退出加固", "hint": "隐藏任务栏、屏蔽系统快捷键"},
            {"key": "keep_alive", "title": "保留进程", "hint": "不结束进程，只隐藏窗口与静音"},
            {"key": "admin_mode", "title": "管理员权限", "hint": "以最高权限运行 / UAC"},
            {"key": "auto_update", "title": "自动更新", "hint": "启动后检查 GitHub Releases"},
            {"key": "default_mode", "title": "默认强度", "hint": "浅清 / 覆清 / 深清"},
            {"key": "default_minutes", "title": "默认时长", "hint": "速启默认分钟数"},
            {"key": "lock_level", "title": "锁定强度", "hint": "轻度 / 中度 / 重度"},
            {"key": "pause_limit", "title": "暂停次数", "hint": "一次会话允许的暂停上限"},
            {"key": "volume_panel", "title": "系统音量", "hint": "dock 设置面板音量"},
            {"key": "sleepRemindersEnabled", "title": "睡眠提醒", "hint": "提前 60/30/1 分钟提醒"},
            {"key": "countdown_date", "title": "倒数日", "hint": "目标日期 YYYY-MM-DD"},
            {"key": "ai_enabled", "title": "AI 助手", "hint": "启用 AI 问答与设置搜索"},
            {"key": "ai_provider", "title": "AI 服务商", "hint": "Groq / 智谱 / SiliconFlow"},
            {"key": "onboarding_done", "title": "新手引导", "hint": "首次使用欢迎页"},
            {"key": "guard_interval_ms", "title": "巡检间隔", "hint": "进程守护轮询毫秒数"},
            {"key": "hosts_block_enabled", "title": "网站屏蔽", "hint": "写 hosts 屏蔽网站"},
        ]

    @Slot(str)
    def askAI(self, prompt: str) -> None:
        text = str(prompt or "").strip()
        if not text:
            return
        if not self._ai.configured():
            self._ai_state = "error"
            self._ai_error = "AI 未启用或未配置"
            self._ai_answer = ""
            self.aiChanged.emit()
            return
        conversation = self._ensure_current_conversation()
        self._ai_pending_conv = str(conversation.get("id") or "")
        self._append_ai_message(conversation, "user", text)
        self._start_ai_job("ask", text)

    @Slot(str)
    def aiAsk(self, prompt: str) -> None:
        """UI 别名：与 askAI 相同。"""
        self.askAI(prompt)

    @Slot()
    def aiCancel(self) -> None:
        self._ai_token += 1
        self._ai_state = "idle"
        self._ai_answer = ""
        self._ai_error = ""
        self._ai_mode = ""
        self._ai_pending_conv = ""
        self.aiChanged.emit()

    @Slot()
    def testAIConnection(self) -> None:
        if not self._ai.configured():
            self._ai_state = "error"
            self._ai_error = "AI 未启用或未配置"
            self._ai_answer = ""
            self.aiChanged.emit()
            self.toast.emit(QCoreApplication.translate("ShenQing", "请先启用并填写 AI 配置"))
            return
        self._start_ai_job("test", "")

    def _start_ai_job(self, mode: str, prompt: str) -> None:
        self._ai_token += 1
        token = self._ai_token
        self._ai_mode = str(mode)
        self._ai_state = "loading"
        self._ai_answer = ""
        self._ai_error = ""
        self.aiChanged.emit()

        def _callback(result: object) -> None:
            try:
                self._aiAsyncResult.emit(token, result)
            except RuntimeError:  # 宿主已销毁
                pass

        if mode == "test":
            self._ai.submit_test(_callback)
        else:
            self._ai.submit_ask(prompt, _callback)

    @Slot(int, object)
    def _on_ai_result(self, token: int, result: object) -> None:
        if int(token) != self._ai_token:
            return
        data = result if isinstance(result, dict) else {}
        mode = self._ai_mode
        if data.get("ok"):
            self._ai_state = "ok"
            self._ai_answer = str(data.get("text") or "")
            self._ai_error = ""
            if mode == "test":
                self.toast.emit(QCoreApplication.translate("ShenQing", "AI 连接正常"))
        else:
            self._ai_state = "error"
            self._ai_answer = ""
            self._ai_error = self._ai.sanitize(data.get("error") or "AI 请求失败")
            if mode == "test":
                self.toast.emit(
                    QCoreApplication.translate("ShenQing", "AI 连接失败：{0}").format(
                        self._ai_error[:80]
                    )
                )
        usage = data.get("usage")
        if isinstance(usage, dict) and usage:
            self._record_ai_usage(usage)
        if mode == "ask":
            conversation = self._find_conversation(self._ai_pending_conv)
            self._ai_pending_conv = ""
            if conversation is not None and data.get("ok"):
                self._append_ai_message(
                    conversation,
                    "assistant",
                    self._ai_answer,
                    reasoning=str(data.get("reasoning") or ""),
                    tokens=int((usage or {}).get("total_tokens") or 0),
                )
        self.aiChanged.emit()

    @Slot(str, result=list)
    def aiSearchSettings(self, query: str) -> list[dict]:
        """设置语义搜索；未配置/失败时回退本地模糊匹配。"""
        text = str(query or "").strip()
        if not text:
            return []
        items = self._ai_settings_items()
        try:
            return self._ai.search_settings(text, items)
        except Exception as exc:  # noqa: BLE001
            logger.info("AI 设置搜索失败，回退本地匹配：%s", self._ai.sanitize(exc))
            return ai_service.local_search(text, items)

    # ================= v0.11 对话历史 / 费用用量 =================
    def _load_ai_chats(self) -> None:
        data = None
        try:
            if self._ai_chats_path.exists():
                data = json.loads(self._ai_chats_path.read_text(encoding="utf-8"))
        except (OSError, json.JSONDecodeError, ValueError):
            data = None
        conversations: list[dict] = []
        current_id = ""
        if isinstance(data, dict):
            raw = data.get("conversations")
            if isinstance(raw, list):
                for item in raw:
                    if not isinstance(item, dict):
                        continue
                    conversation_id = str(item.get("id") or "").strip()
                    if not conversation_id:
                        continue
                    messages = []
                    for message in item.get("messages") or []:
                        if not isinstance(message, dict):
                            continue
                        messages.append(
                            {
                                "role": str(message.get("role") or "user"),
                                "content": str(message.get("content") or ""),
                                "reasoning": str(message.get("reasoning") or ""),
                                "time": str(message.get("time") or ""),
                                "tokens": int(message.get("tokens") or 0),
                            }
                        )
                    conversations.append(
                        {
                            "id": conversation_id,
                            "title": str(item.get("title") or "新对话"),
                            "createdAt": str(item.get("createdAt") or ""),
                            "updatedAt": str(item.get("updatedAt") or ""),
                            "messages": messages,
                        }
                    )
            current_id = str(data.get("currentId") or "")
        if not any(conversation["id"] == current_id for conversation in conversations):
            current_id = conversations[0]["id"] if conversations else ""
        self._ai_chats = {"currentId": current_id, "conversations": conversations}

    def _save_ai_chats(self) -> None:
        try:
            self._ai_chats_path.parent.mkdir(parents=True, exist_ok=True)
            self._ai_chats_path.write_text(
                json.dumps(self._ai_chats, ensure_ascii=False, indent=2), encoding="utf-8"
            )
        except OSError as exc:
            logger.warning("保存 AI 对话历史失败：%s", exc)

    def _find_conversation(self, conversation_id: str) -> dict | None:
        target = str(conversation_id or "")
        if not target:
            return None
        for conversation in self._ai_chats.get("conversations", []):
            if str(conversation.get("id")) == target:
                return conversation
        return None

    def _current_conversation(self) -> dict | None:
        return self._find_conversation(self._ai_chats.get("currentId", ""))

    def _new_conversation(self, title: str = "新对话") -> dict:
        import uuid

        now = timesync.now().isoformat(timespec="seconds")
        conversation = {
            "id": "chat_" + uuid.uuid4().hex[:10],
            "title": str(title or "新对话")[:24],
            "createdAt": now,
            "updatedAt": now,
            "messages": [],
        }
        self._ai_chats.setdefault("conversations", []).append(conversation)
        return conversation

    def _ensure_current_conversation(self) -> dict:
        conversation = self._current_conversation()
        if conversation is not None:
            return conversation
        conversation = self._new_conversation()
        self._ai_chats["currentId"] = conversation["id"]
        self._save_ai_chats()
        self.aiChatsChanged.emit()
        return conversation

    def _append_ai_message(
        self,
        conversation: dict,
        role: str,
        content: str,
        *,
        reasoning: str = "",
        tokens: int = 0,
    ) -> None:
        now = timesync.now().isoformat(timespec="seconds")
        message = {
            "role": str(role),
            "content": str(content or ""),
            "reasoning": str(reasoning or ""),
            "time": now,
            "tokens": int(tokens or 0),
        }
        conversation.setdefault("messages", []).append(message)
        conversation["updatedAt"] = now
        if role == "user":
            if str(conversation.get("title") or "") in ("", "新对话"):
                title = str(content or "").strip().replace("\n", " ")[:24]
                conversation["title"] = title or "新对话"
        self._save_ai_chats()
        self.aiChatsChanged.emit()

    @Property(list, notify=aiChatsChanged)
    def aiConversations(self) -> list[dict]:
        items = []
        for conversation in self._ai_chats.get("conversations", []):
            items.append(
                {
                    "id": str(conversation.get("id") or ""),
                    "title": str(conversation.get("title") or "新对话"),
                    "updatedAt": str(conversation.get("updatedAt") or ""),
                    "count": len(conversation.get("messages") or []),
                }
            )
        items.sort(key=lambda item: item["updatedAt"], reverse=True)
        return items

    @Property(list, notify=aiChatsChanged)
    def aiMessages(self) -> list[dict]:
        conversation = self._current_conversation()
        if conversation is None:
            return []
        return [dict(message) for message in conversation.get("messages") or []]

    @Slot()
    def newAIConversation(self) -> None:
        conversation = self._new_conversation()
        self._ai_chats["currentId"] = conversation["id"]
        self._save_ai_chats()
        self.aiChatsChanged.emit()

    @Slot(str, result=bool)
    def selectAIConversation(self, conversation_id: str) -> bool:
        conversation = self._find_conversation(conversation_id)
        if conversation is None:
            return False
        self._ai_chats["currentId"] = conversation["id"]
        self._save_ai_chats()
        self.aiChatsChanged.emit()
        return True

    @Slot(str, result=bool)
    def deleteAIConversation(self, conversation_id: str) -> bool:
        conversation = self._find_conversation(conversation_id)
        if conversation is None:
            return False
        self._ai_chats["conversations"].remove(conversation)
        if str(self._ai_chats.get("currentId")) == str(conversation["id"]):
            remaining = self._ai_chats.get("conversations") or []
            self._ai_chats["currentId"] = str(remaining[0]["id"]) if remaining else ""
        self._save_ai_chats()
        self.aiChatsChanged.emit()
        return True

    # ---------- 费用 / 用量 ----------
    def _load_ai_usage(self) -> None:
        try:
            data = json.loads(self._ai_usage_path.read_text(encoding="utf-8")) if self._ai_usage_path.exists() else None
        except (OSError, json.JSONDecodeError, ValueError):
            data = None
        self._ai_usage = data if isinstance(data, dict) else {}
        self._ai_last_usage = {}
        self._ai_usage_currency = ""

    def _save_ai_usage(self) -> None:
        try:
            self._ai_usage_path.parent.mkdir(parents=True, exist_ok=True)
            self._ai_usage_path.write_text(
                json.dumps(self._ai_usage, ensure_ascii=False, indent=2), encoding="utf-8"
            )
        except OSError as exc:
            logger.warning("保存 AI 用量失败：%s", exc)

    def _record_ai_usage(self, usage: dict) -> None:
        model = str(usage.get("model") or self._ai.model())
        provider = str(usage.get("provider") or self._ai.provider())
        try:
            tokens_in = max(0, int(usage.get("prompt_tokens") or 0))
            tokens_out = max(0, int(usage.get("completion_tokens") or 0))
            cost = max(0.0, float(usage.get("cost") or 0.0))
        except (TypeError, ValueError):
            tokens_in = tokens_out = 0
            cost = 0.0
        currency = str(usage.get("currency") or "CNY")
        day = timesync.today().isoformat()
        entry = self._ai_usage.setdefault(
            day, {"tokens_in": 0, "tokens_out": 0, "cost": 0.0, "by_provider": {}}
        )
        entry["tokens_in"] = int(entry.get("tokens_in", 0)) + tokens_in
        entry["tokens_out"] = int(entry.get("tokens_out", 0)) + tokens_out
        entry["cost"] = round(float(entry.get("cost", 0.0)) + cost, 8)
        by_provider = entry.setdefault("by_provider", {})
        provider_entry = by_provider.setdefault(
            provider, {"tokens_in": 0, "tokens_out": 0, "cost": 0.0, "currency": currency}
        )
        provider_entry["tokens_in"] = int(provider_entry.get("tokens_in", 0)) + tokens_in
        provider_entry["tokens_out"] = int(provider_entry.get("tokens_out", 0)) + tokens_out
        provider_entry["cost"] = round(float(provider_entry.get("cost", 0.0)) + cost, 8)
        provider_entry["currency"] = currency
        self._ai_last_usage = {
            "model": model,
            "provider": provider,
            "prompt_tokens": tokens_in,
            "completion_tokens": tokens_out,
            "cost": round(cost, 6),
            "currency": currency,
        }
        self._ai_usage_currency = currency
        self._save_ai_usage()
        self.aiUsageChanged.emit()

    def _today_usage(self) -> dict:
        return self._ai_usage.get(timesync.today().isoformat(), {})

    @Property(int, notify=aiUsageChanged)
    def aiTodayTokens(self) -> int:
        entry = self._today_usage()
        return int(entry.get("tokens_in", 0)) + int(entry.get("tokens_out", 0))

    @Property(float, notify=aiUsageChanged)
    def aiTodayCost(self) -> float:
        return round(float(self._today_usage().get("cost", 0.0)), 6)

    @Property(str, notify=aiUsageChanged)
    def aiCurrency(self) -> str:
        if self._ai_usage_currency:
            return self._ai_usage_currency
        return str(
            ai_service.provider_pricing(self._ai.provider(), self._ai.model()).get("currency")
            or "CNY"
        )

    @Property(dict, notify=aiUsageChanged)
    def aiLastUsage(self) -> dict:
        return dict(self._ai_last_usage)

    @Slot()
    def resetAIUsage(self) -> None:
        self._ai_usage = {}
        self._ai_last_usage = {}
        self._ai_usage_currency = ""
        self._save_ai_usage()
        self.aiUsageChanged.emit()

    # ================= v0.9 应用使用时长 =================
    @Property(str, notify=statsChanged)
    def appUsageDate(self) -> str:
        return self._app_usage_date or timesync.today().isoformat()

    @Slot(str)
    def setAppUsageDate(self, date_text: str) -> None:
        text = str(date_text or "").strip()
        if text:
            try:
                datetime.strptime(text, "%Y-%m-%d")
            except ValueError:
                return
        self._app_usage_date = text
        self.statsChanged.emit()
        self.appUsageChanged.emit()

    def _usage_day(self) -> str:
        return self._app_usage_date or timesync.today().isoformat()

    @Property(list, notify=statsChanged)
    def appUsageToday(self) -> list[dict]:
        return self._app_usage.usage_for(self._usage_day())

    @Property(list, notify=statsChanged)
    def appUsageWeek(self) -> list[dict]:
        return self._app_usage.week_usage()

    @Property(int, notify=statsChanged)
    def appUsageTotalMinutes(self) -> int:
        return int(round(self._app_usage.total_minutes(self._usage_day())))

    @Property(int, notify=statsChanged)
    def appUsageTotalToday(self) -> int:
        return int(round(self._app_usage.total_minutes(self._usage_day())))

    @Property(int, notify=statsChanged)
    def appUsageTotalWeek(self) -> int:
        return int(round(sum(item["minutes"] for item in self._app_usage.week_usage(limit=1000))))

    @Property(list, notify=statsChanged)
    def appCategories(self) -> list[dict]:
        return [
            {
                "category": item["category"],
                "name": item.get("label", item["category"]),
                "label": item.get("label", item["category"]),
                "minutes": item["minutes"],
                "color": item["color"],
            }
            for item in self._app_usage.category_totals(self._usage_day())
        ]

    @Slot(str, str, result=bool)
    def setAppCategory(self, exe: str, category: str) -> bool:
        ok = self._app_usage.set_category(exe, category)
        if ok:
            self.statsChanged.emit()
            self.appUsageChanged.emit()
        return ok

    @Slot(str, str, result=bool)
    def setAppColor(self, exe: str, color: str) -> bool:
        ok = self._app_usage.set_color(exe, color)
        if ok:
            self.statsChanged.emit()
            self.appUsageChanged.emit()
        return ok

    def _on_app_usage_changed(self) -> None:
        self.statsChanged.emit()
        self.appUsageChanged.emit()

    # ---------- v0.13 热力图 / 小时分布 / 应用分类 ----------
    @Property(list, notify=appUsageChanged)
    def appUsageHeatmap(self) -> list[dict]:
        """最近 N 天每日总分钟（无记录补 0），画日历热力图。"""
        return self._app_usage.heatmap(self.appUsageHeatmapDays)

    @Property(list, notify=appUsageChanged)
    def appUsageHourly(self) -> list[dict]:
        return self._app_usage.hourly(self._app_usage_hourly_range)

    @Property(str, notify=appUsageChanged)
    def appUsageHourlyRange(self) -> str:
        return self._app_usage_hourly_range

    @Slot(str)
    def setAppUsageHourlyRange(self, value: str) -> None:
        text = str(value or "").strip().lower()
        if text not in ("today", "week"):
            return
        self._app_usage_hourly_range = text
        self.appUsageChanged.emit()

    @Property(int, notify=appUsageChanged)
    def appUsageHeatmapDays(self) -> int:
        value = self._settings.get("app_usage_heatmap_days", 90)
        try:
            days = int(value)
        except (TypeError, ValueError):
            days = 90
        return days if days in (30, 90, 180) else 90

    @Slot(int)
    def setAppUsageHeatmapDays(self, days: int) -> None:
        try:
            value = int(days)
        except (TypeError, ValueError):
            return
        if value not in (30, 90, 180):
            return
        self._settings.set("app_usage_heatmap_days", value)
        self.appUsageChanged.emit()

    @Property(list, notify=appUsageChanged)
    def appUsageApps(self) -> list[dict]:
        return self._app_usage.all_apps()

    @Slot(str, result=bool)
    def resetAppCategory(self, exe: str) -> bool:
        ok = self._app_usage.reset_category(exe)
        if ok:
            self.statsChanged.emit()
            self.appUsageChanged.emit()
        return ok

    @Property(list, constant=True)
    def appCategoryOptions(self) -> list[dict]:
        return [
            {"value": item["value"], "label": item["label"]}
            for item in app_usage.CATEGORIES
        ]

    # ================= 服务退出清理 =================
    def _shutdown_services(self) -> None:
        try:
            self._app_usage.shutdown()
        except Exception as exc:  # noqa: BLE001
            logger.warning("停止应用使用统计失败：%s", exc)
        try:
            self._save_ai_chats()
            self._save_ai_usage()
        except Exception as exc:  # noqa: BLE001
            logger.warning("保存 AI 历史/用量失败：%s", exc)
        try:
            self._ai.shutdown()
        except Exception as exc:  # noqa: BLE001
            logger.warning("停止 AI 线程池失败：%s", exc)


    def _purge_legacy_plugins(self) -> None:
        """移除已下线的内置组件插件（含已安装数据）。"""
        legacy = ("com.shenqing.cw2widgets",)
        try:
            import shutil

            for plugin_id in legacy:
                for folder in (
                    app_data_dir() / "plugins" / plugin_id,
                    app_data_dir() / "plugin_data" / plugin_id,
                ):
                    if folder.exists():
                        shutil.rmtree(folder, ignore_errors=True)
                        logger.info("已移除旧插件数据：%s", folder)
            disabled = self._settings.get("disabled_plugins", [])
            if isinstance(disabled, list) and any(item in legacy for item in disabled):
                self._settings.set(
                    "disabled_plugins", [item for item in disabled if item not in legacy]
                )
        except Exception as exc:  # noqa: BLE001
            logger.warning("清理旧插件失败：%s", exc)

    @Property(str, notify=statsChanged)
    def dailyQuote(self) -> str:
        day = timesync.today()
        return QUOTES[day.toordinal() % len(QUOTES)] if QUOTES else ""

    @Property(dict, notify=statsChanged)
    def lastSession(self) -> dict:
        """最近一次专注：{spaceName, level, minutes, startMs, endMs, quote, avatarUrl, wallpaperUrl}。"""
        sessions = self._stats.sessions
        if not sessions:
            return {}
        item = sessions[-1]
        start_raw = str(item.get("start") or item.get("ts") or "")
        end_raw = str(item.get("ts") or "")
        start_dt = None
        end_dt = None
        try:
            start_dt = datetime.fromisoformat(start_raw)
        except (TypeError, ValueError):
            pass
        try:
            end_dt = datetime.fromisoformat(end_raw)
        except (TypeError, ValueError):
            end_dt = None
        if start_dt is None and end_dt is not None:
            start_dt = end_dt - timedelta(minutes=float(item.get("minutes", 0) or 0))
        if end_dt is None and start_dt is not None:
            end_dt = start_dt + timedelta(minutes=float(item.get("minutes", 0) or 0))
        day = start_dt.date() if start_dt is not None else timesync.today()
        return {
            "spaceName": str(item.get("space") or ""),
            "level": str(item.get("level") or ""),
            "minutes": float(item.get("minutes", 0) or 0),
            "startMs": int(start_dt.timestamp() * 1000) if start_dt else 0,
            "endMs": int(end_dt.timestamp() * 1000) if end_dt else 0,
            "quote": QUOTES[day.toordinal() % len(QUOTES)] if QUOTES else "",
            "avatarUrl": self.userAvatarUrl,
            "wallpaperUrl": self.bingWallpaperUrl,
        }

    @Slot(result=str)
    def shareSummary(self) -> str:
        """结束卡片分享文本（复制到剪贴板用）。"""
        card = self.todayFocusCard
        quote = str(card.get("quote") or "")
        return (
            f"深清 · {card.get('date', '')}\n"
            f"{card.get('timeRange', '')}  {card.get('spaceName', '')}\n"
            f"专注 {card.get('minutes', 0)} 分钟 · {card.get('sessions', 0)} 次\n"
            f"{quote}"
        )

    @Property(str, constant=True)
    def dataDir(self) -> str:
        """用户数据目录（%APPDATA%/ShenQing），供 QML 保存图片等。"""
        return str(app_data_dir())

    @Slot(result=str)
    def newSummaryImagePath(self) -> str:
        """生成一个可写的「今日专注卡片」PNG 路径（QML grabToImage 用）。"""
        from datetime import datetime

        folder = app_data_dir() / "summary"
        try:
            folder.mkdir(parents=True, exist_ok=True)
        except OSError:
            return ""
        return str(folder / f"focus-{datetime.now():%Y%m%d-%H%M%S}.png")

    @Slot(result=str)
    def saveSummaryImage(self) -> str:
        """预留：结束卡片图片保存由 QML 的 grabToImage 完成，后端暂不渲染。"""
        return ""

    @Property(bool, notify=settingsChanged)
    def onboardingDone(self) -> bool:
        return bool(self._settings.get("onboarding_done", False))

    @Slot(bool)
    def setOnboardingDone(self, done: bool) -> None:
        self._settings.set("onboarding_done", bool(done))
        self.settingsChanged.emit()

    @Property(list, notify=pluginsChanged)
    def overlayWidgets(self) -> list[dict]:
        """全屏遮罩自定义组件；按 overlayWidgetOrder 排序（未排的排后面）。"""
        widgets = list(self.pluginWidgets)
        order = self.overlayWidgetOrder
        if not order:
            return widgets
        rank = {value: index for index, value in enumerate(order)}

        def _key(item: dict) -> int:
            key = f"{item.get('pluginId', '')}:{item.get('id', '')}"
            return rank.get(key, len(order))

        return sorted(widgets, key=_key)

    @Property(list, notify=statsChanged)
    def recentSessions(self) -> list[dict]:
        """最近会话明细（数据页列表用，最多 30 条，倒序）。"""
        items = self._stats.sessions[-30:]
        result: list[dict] = []
        for item in reversed(items):
            start_raw = str(item.get("start") or item.get("ts") or "")
            end_raw = str(item.get("ts") or "")
            start_dt = None
            end_dt = None
            try:
                start_dt = datetime.fromisoformat(start_raw)
            except (TypeError, ValueError):
                pass
            try:
                end_dt = datetime.fromisoformat(end_raw)
            except (TypeError, ValueError):
                end_dt = None
            result.append(
                {
                    "date": str(item.get("date") or ""),
                    "spaceName": str(item.get("space") or ""),
                    "level": str(item.get("level") or ""),
                    "minutes": float(item.get("minutes", 0) or 0),
                    "completed": bool(item.get("completed", False)),
                    "startMs": int(start_dt.timestamp() * 1000) if start_dt else 0,
                    "endMs": int(end_dt.timestamp() * 1000) if end_dt else 0,
                }
            )
        return result

    @Property(list, notify=settingsChanged)
    def overlayWidgetOrder(self) -> list[str]:
        raw = self._settings.get("overlay_widget_order", [])
        return [str(item) for item in raw] if isinstance(raw, list) else []

    @Slot(list)
    def setOverlayWidgetOrder(self, ids: list) -> None:
        self._settings.set("overlay_widget_order", [str(item) for item in ids])
        self.settingsChanged.emit()
        self.pluginsChanged.emit()

    @Property(int, notify=settingsChanged)
    def countdownDays(self) -> int:
        """倒数日剩余天数；未设置返回 -1。"""
        raw = str(self._settings.get("countdown_date", "") or "")
        if not raw:
            return -1
        try:
            target = datetime.strptime(raw, "%Y-%m-%d").date()
        except ValueError:
            return -1
        return (target - timesync.today()).days

    @Property(str, notify=settingsChanged)
    def countdownDate(self) -> str:
        return str(self._settings.get("countdown_date", "") or "")

    @Slot(str)
    def setCountdownDate(self, date_text: str) -> None:
        text = str(date_text or "").strip()
        if text:
            try:
                datetime.strptime(text, "%Y-%m-%d")
            except ValueError:
                self.toast.emit(QCoreApplication.translate("ShenQing", "日期格式应为 YYYY-MM-DD"))
                return
        self._settings.set("countdown_date", text)
        self.settingsChanged.emit()

    def _begin_space_session(
        self,
        space: dict | None,
        level: str,
        minutes: int,
        *,
        trial: bool = False,
    ) -> None:
        """以某张空间为载体开始一轮专注（时长/白名单取该空间，档位由调用方决定）。"""
        if self._session.state is not SessionState.IDLE:
            self.toast.emit(QCoreApplication.translate("ShenQing", "已经有正在进行的专注"))
            return
        if level not in {item.value for item in LockLevel}:
            return
        self._active_space_id = str(space.get("id") or "") if space else ""
        self._session_level = level
        self._trial_active = bool(trial)
        self._preview_active = False
        self._preview_level = ""
        # 深清空间不设置白名单：heavy 会话只保留系统进程（DEFAULT_WHITELIST），
        # 即使旧数据里残留 allowed_apps 也不加载。
        if level == LockLevel.HEAVY.value:
            whitelist: list[str] = []
        else:
            whitelist = [str(a) for a in (space.get("allowed_apps", []) if space else [])]
        self._guard.configure(
            blacklist=self._blocklist.processes,
            whitelist=whitelist,
            strict=level == LockLevel.HEAVY.value,
            keep_alive=bool(self._settings.get("keep_alive", True)),
        )
        self._guard.set_interval(int(self._settings.get("guard_interval_ms", 1000)))
        self._guard.start()
        self._session_started_at = timesync.now()
        power.keep_awake()
        self._session.start(int(minutes), int(self._settings.get("pause_limit", 2)))
        self.lockedChanged.emit()
        payload = (
            self._space_view(space)
            if space
            else {"name": QCoreApplication.translate("ShenQing", "速启")}
        )
        payload["level"] = level
        payload["trial"] = bool(trial)
        self._dispatch("session_start", payload)

    @Slot(str)
    def startSpace(self, space_id: str) -> None:
        """按该空间自己的时长 / 白名单 / 档位开始一轮专注。"""
        space = self._spaces.get(space_id)
        if space is None:
            self.toast.emit(QCoreApplication.translate("ShenQing", "空间不存在"))
            return
        if self._session.state is not SessionState.IDLE:
            self.toast.emit(QCoreApplication.translate("ShenQing", "已经有正在进行的专注"))
            return
        # 先进入 10 秒倒计时（水滴凝聚），期间可取消
        self._begin_prepare(space)

    @Slot(str)
    def startLevel(self, level: str) -> None:
        """速启面板：不选空间，直接按强度开始一轮专注。"""
        if level not in {item.value for item in LockLevel}:
            return
        minutes = int(self._settings.get("default_minutes", 45))
        # 速启用该档第一张空间做载体（白名单取它，时长仍按设置）
        space = self._spaces.get_by_mode(level) or self._spaces.get_by_mode("medium")
        if self._session.state is not SessionState.IDLE:
            self.toast.emit(QCoreApplication.translate("ShenQing", "已经有正在进行的专注"))
            return
        self._begin_prepare(space, minutes)

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
        if self._session_level == LockLevel.HEAVY.value and not self._trial_active:
            self.toast.emit(
                QCoreApplication.translate("ShenQing", "深清档不可提前结束，等计时走完")
            )
            return
        self._session.stop()

    # ================= 统计 / 设置 =================
    @Property(float, notify=statsChanged)
    def todayMinutes(self) -> float:
        return self._stats.today_minutes(timesync.today())

    @Property(float, notify=statsChanged)
    def weekMinutes(self) -> float:
        return self._stats.week_minutes(timesync.today())

    @Property(int, notify=statsChanged)
    def streakDays(self) -> int:
        return self._stats.streak_days(timesync.today())

    @Property(int, notify=statsChanged)
    def sessionCount(self) -> int:
        return self._stats.total_sessions()

    @Property(list, notify=statsChanged)
    def last7Days(self) -> list[dict]:
        return self._stats.last_7_days(timesync.today())

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
    def navExpanded(self) -> bool:
        return bool(self._settings.get("nav_expanded", False))

    @Slot(bool)
    def setNavExpanded(self, expanded: bool) -> None:
        self._settings.set("nav_expanded", bool(expanded))
        self.settingsChanged.emit()

    # ---------- v0.12 UI 字体 / 字号 / 导航模式 ----------
    @Property(str, notify=settingsChanged)
    def uiFontFamily(self) -> str:
        return str(self._settings.get("ui_font_family", "") or "")

    @Slot(str)
    def setUIFontFamily(self, family: str) -> None:
        self._settings.set("ui_font_family", str(family or "").strip())
        self.settingsChanged.emit()

    @Property(list, constant=True)
    def uiFontFamilies(self) -> list[str]:
        """系统可选中文字体（过滤 @ 开头的竖排字体，排序，最多 200）。"""
        try:
            from PySide6.QtGui import QFontDatabase

            families = {
                str(name)
                for name in QFontDatabase.families()
                if name and not str(name).startswith("@")
            }
            result = sorted(families)[:200]
            if result:
                return result
            # 离屏/无字体目录环境可能枚举为空：至少返回默认字体，避免下拉框空白
            fallback = str(self.defaultFontFamily or "Sans Serif")
            return [fallback]
        except Exception:  # noqa: BLE001 - 字体枚举失败不能影响界面
            return []

    @Property(str, constant=True)
    def defaultFontFamily(self) -> str:
        """内置默认字体（QML 在 ui_font_family 为空时使用）。"""
        try:
            from PySide6.QtGui import QFontDatabase
            from PySide6.QtWidgets import QApplication

            application = QApplication.instance()
            if application is not None:
                return str(application.font().family())
            return str(
                QFontDatabase.systemFont(QFontDatabase.SystemFont.GeneralFont).family()
            )
        except Exception:  # noqa: BLE001
            return ""

    @staticmethod
    def _normalized_font_scale(value: object) -> float:
        """夹紧到 0.8–1.4，并四舍五入到 0.05 步进。"""
        try:
            scale = float(value)
        except (TypeError, ValueError):
            scale = 1.0
        scale = max(0.8, min(1.4, scale))
        steps = round((scale - 0.8) / 0.05)
        return round(0.8 + steps * 0.05, 2)

    @Property(float, notify=settingsChanged)
    def uiFontScale(self) -> float:
        return self._normalized_font_scale(self._settings.get("ui_font_scale", 1.0))

    @Slot(float)
    def setUIFontScale(self, scale: float) -> None:
        self._settings.set("ui_font_scale", self._normalized_font_scale(scale))
        self.settingsChanged.emit()

    @Property(list, constant=True)
    def uiFontScaleOptions(self) -> list[float]:
        return [0.85, 1.0, 1.15, 1.3]

    NAV_MODES = ("auto", "expanded", "icons", "custom")

    @Property(str, notify=settingsChanged)
    def navMode(self) -> str:
        value = str(self._settings.get("nav_mode", "expanded") or "expanded")
        return value if value in self.NAV_MODES else "expanded"

    @Slot(str)
    def setNavMode(self, mode: str) -> None:
        value = str(mode or "")
        if value not in self.NAV_MODES:
            return
        self._settings.set("nav_mode", value)
        self.settingsChanged.emit()

    @Property(bool, notify=settingsChanged)
    def keepAlive(self) -> bool:
        """True = 不杀进程，只隐藏窗口 + 静音。"""
        return bool(self._settings.get("keep_alive", True))

    @Slot(bool)
    def setKeepAlive(self, enabled: bool) -> None:
        self._settings.set("keep_alive", bool(enabled))
        self.settingsChanged.emit()
        self.toast.emit(
            QCoreApplication.translate("ShenQing", "不再结束进程，只屏蔽界面与声音")
            if enabled
            else QCoreApplication.translate("ShenQing", "已改为直接结束进程")
        )

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
    @Slot(bool)
    def setOverlayTopmostEnabled(self, enabled: bool) -> None:
        """覆清 dock：拉起白名单应用时暂停/恢复遮罩的定时置顶（不影响防退出加固）。"""
        try:
            self._hardening.set_topmost_enabled(bool(enabled))
        except Exception as exc:  # noqa: BLE001
            logger.warning("切换遮罩置顶失败：%s", exc)

    @Slot()
    def overlayOpened(self) -> None:
        hwnd = 0
        instance = QCoreApplication.instance()
        if instance is not None:
            for window in instance.topLevelWindows():
                if window.objectName() == "LockOverlay":
                    hwnd = int(window.winId())
                    break
        if hwnd:
            # v0.8：任务栏在所有档位的专注期间都保持隐藏；
            # 键盘钩子仍受「防退出加固」设置控制。
            self._hardening.activate(
                hwnd, hide_taskbar=True, block_keys=self.hardeningEnabled
            )

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
        try:
            from ..i18n import supported_codes

            allowed = set(supported_codes()) | {"auto"}
        except Exception:  # noqa: BLE001
            allowed = {"auto", "zh_CN", "en_US"}
        if code not in allowed:
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

    # ================= v0.4：单空间 / 三档 / 主题 / 预览体验 / dock / 搜索 =================
    @Property(dict, notify=spacesChanged)
    def space(self) -> dict:
        return self._space_view(self._spaces.space)

    @Property(int, constant=True)
    def spaceMinMinutes(self) -> int:
        return SPACE_MIN_MINUTES

    @Property(int, constant=True)
    def spaceMaxMinutes(self) -> int:
        return SPACE_MAX_MINUTES

    @Property(int, constant=True)
    def spaceMinuteStep(self) -> int:
        return SPACE_MINUTE_STEP

    @Property(int, notify=spacesChanged)
    def spaceMinutes(self) -> int:
        return int(self._spaces.space.get("minutes", 45))

    @Slot(str, int)
    def setSpaceMinutesFor(self, mode: str, minutes: int) -> None:
        """v0.5 兼容：按档位改时长（映射到该档第一张空间）。"""
        self._spaces.set_minutes(mode, minutes)
        self.spacesChanged.emit()

    @Slot(str, str)
    def setSpaceNameFor(self, mode: str, name: str) -> None:
        """v0.5 兼容：按档位改名（映射到该档第一张空间）。"""
        if self._spaces.set_name(mode, name):
            self.spacesChanged.emit()
        elif str(mode) == "heavy":
            self.toast.emit(QCoreApplication.translate("ShenQing", "深清空间名不可修改"))

    @Slot(str, str, bool, result=bool)
    def toggleSpaceAllowedAppFor(self, mode: str, exe: str, enabled: bool) -> bool:
        """v0.5 兼容：按档位改白名单（映射到该档第一张空间）；深清拒绝。"""
        if str(mode) == "heavy":
            self.toast.emit(QCoreApplication.translate("ShenQing", "深清空间不设置白名单"))
            return False
        if self._spaces.toggle_allowed_app(mode, exe, bool(enabled)):
            self.spacesChanged.emit()
            self.catalogChanged.emit()
            return True
        return False

    @Property(list, constant=True)
    def modes(self) -> list[dict]:
        result = []
        for level in (LockLevel.LIGHT, LockLevel.MEDIUM, LockLevel.HEAVY):
            result.append(
                {
                    "value": level.value,
                    "label": QCoreApplication.translate("ShenQing", MODE_LABELS[level.value]),
                    "desc": self._mode_desc(level.value),
                }
            )
        return result

    @staticmethod
    def _mode_desc(value: str) -> str:
        if value == "light":
            return QCoreApplication.translate("ShenQing", "只屏蔽黑名单应用的窗口与声音")
        if value == "medium":
            return QCoreApplication.translate("ShenQing", "屏蔽干扰并显示允许使用的应用 dock")
        return QCoreApplication.translate("ShenQing", "白名单之外的应用全部屏蔽，不可提前结束")

    @Property(str, notify=settingsChanged)
    def defaultMode(self) -> str:
        return str(self._settings.get("default_mode", LockLevel.MEDIUM.value))

    @Slot(str)
    def setDefaultMode(self, mode: str) -> None:
        if mode not in {item.value for item in LockLevel}:
            return
        self._settings.set("default_mode", mode)
        self.settingsChanged.emit()

    @Property(str, notify=settingsChanged)
    def themeMode(self) -> str:
        return str(self._settings.get("theme_mode", DEFAULT_THEME))

    @Slot(str)
    def setThemeMode(self, theme: str) -> None:
        valid = {item["value"] for item in THEMES}
        if theme not in valid:
            return
        self._settings.set("theme_mode", theme)
        self.settingsChanged.emit()
        self.themeChanged.emit("Light" if theme == "light" else "Dark")

    @Property(str, constant=True)
    def licenseText(self) -> str:
        """LICENSE 全文（关于页本地弹窗用）。"""
        try:
            return license_file().read_text(encoding="utf-8", errors="replace")
        except OSError:
            return "GNU General Public License v3.0"


    @Property(str, constant=True)
    def noticeText(self) -> str:
        """NOTICE 全文（关于页本地弹窗用）。"""
        try:
            return notice_file().read_text(encoding="utf-8", errors="replace")
        except OSError:
            return "Third-party notices"

    @Property(list, notify=languageChanged)
    def changelog(self) -> list[dict]:
        """更新日志（按当前语言返回中文或英文条目）。"""
        language = str(self._settings.get("language", "auto"))
        if language == "auto":
            from PySide6.QtCore import QLocale

            english = not QLocale.system().name().lower().startswith("zh")
        else:
            english = language.startswith("en")
        result: list[dict] = []
        for entry in CHANGELOG:
            items = entry.get("items_en") if english else entry.get("items")
            result.append(
                {
                    "version": str(entry.get("version", "")),
                    "date": str(entry.get("date", "")),
                    "tag": str(entry.get("tag", "")),
                    "items": list(items or entry.get("items") or []),
                }
            )
        return result

    @Property(list, constant=True)
    def themes(self) -> list[dict]:
        return [
            {
                "value": item["value"],
                "label": QCoreApplication.translate("ShenQing", item["label"]),
                "desc": QCoreApplication.translate("ShenQing", item["desc"]),
                "experimental": bool(item.get("experimental")),
            }
            for item in THEMES
        ]

    # ================= 进入前 10 秒倒计时（水滴凝聚） =================
    PREPARE_SECONDS = 10

    @Property(bool, notify=stateChanged)
    def prepareActive(self) -> bool:
        return self._prepare_active

    @Property(int, notify=stateChanged)
    def prepareRemaining(self) -> int:
        return int(self._prepare_remaining)

    @Property(str, notify=stateChanged)
    def prepareLevel(self) -> str:
        return str(self._prepare_mode)

    @Property(str, notify=stateChanged)
    def prepareSpaceName(self) -> str:
        space = self._spaces.get(self._prepare_space_id) if self._prepare_space_id else None
        return str(space.get("name", "")) if space else ""

    @Slot(str)
    def prepareSpace(self, space_id: str) -> None:
        """开始 10 秒进入倒计时（可随时 cancelPrepare 取消）。"""
        space = self._spaces.get(str(space_id or ""))
        if space is None or self._session.state is not SessionState.IDLE:
            return
        self._begin_prepare(space)

    @Slot(str)
    def prepareMode(self, mode: str) -> None:
        spaces = [s for s in self._spaces.all() if str(s.get("mode")) == str(mode)]
        if not spaces:
            return
        self._begin_prepare(spaces[0])

    def _begin_prepare(self, space: dict, minutes: int | None = None) -> None:
        self._prepare_minutes = int(minutes) if minutes else None
        self._prepare_active = True
        self._prepare_remaining = int(self.PREPARE_SECONDS)
        self._prepare_space_id = str(space.get("id") or "")
        self._prepare_mode = str(space.get("mode") or "")
        self._prepare_timer.start()
        self.stateChanged.emit()

    @Slot()
    def cancelPrepare(self) -> None:
        if not self._prepare_active:
            return
        self._prepare_timer.stop()
        self._prepare_active = False
        self._prepare_remaining = 0
        self._prepare_space_id = ""
        self._prepare_mode = ""
        self.stateChanged.emit()

    def _tick_prepare(self) -> None:
        if not self._prepare_active:
            return
        self._prepare_remaining = max(0, self._prepare_remaining - 1)
        self.stateChanged.emit()
        if self._prepare_remaining <= 0:
            space = self._spaces.get(self._prepare_space_id)
            mode = self._prepare_mode or str((space or {}).get("mode", "medium"))
            minutes = int(self._prepare_minutes or (space or {}).get("minutes", 45))
            self._prepare_minutes = None
            self._prepare_timer.stop()
            self._prepare_active = False
            self._prepare_space_id = ""
            self._prepare_mode = ""
            self.stateChanged.emit()
            self._begin_space_session(space, mode, minutes, trial=False)

    @Property(bool, notify=stateChanged)
    def trialActive(self) -> bool:
        return self._trial_active

    @Property(bool, notify=stateChanged)
    def previewActive(self) -> bool:
        return self._preview_active

    @Property(str, notify=stateChanged)
    def previewLevel(self) -> str:
        return self._preview_level

    @Slot(str)
    def previewMode(self, mode: str) -> None:
        if mode not in {item.value for item in LockLevel}:
            return
        self._preview_active = True
        self._preview_level = mode
        self.stateChanged.emit()
        self.lockedChanged.emit()

    @Slot()
    def stopPreview(self) -> None:
        self._preview_active = False
        self._preview_level = ""
        self.stateChanged.emit()
        self.lockedChanged.emit()

    @Slot(str)
    def startMode(self, mode: str) -> None:
        """按档位开始：先进入 10 秒倒计时。"""
        space = self._spaces.get_by_mode(mode)
        if space is None:
            self.toast.emit(QCoreApplication.translate("ShenQing", "空间不存在"))
            return
        if self._session.state is not SessionState.IDLE:
            self.toast.emit(QCoreApplication.translate("ShenQing", "已经有正在进行的专注"))
            return
        self._begin_prepare(space)

    @Slot(str)
    def startTrial(self, mode: str) -> None:
        """体验模式：1 分钟真实专注；每小时最多 5 次。"""
        if mode not in {item.value for item in LockLevel}:
            return
        now = time.time()
        self._trial_times = [t for t in self._trial_times if now - t < 3600]
        if len(self._trial_times) >= 5:
            self.toast.emit(
                QCoreApplication.translate("ShenQing", "体验次数已用完（每小时最多 5 次）")
            )
            return
        self._trial_times.append(now)
        space = self._spaces.get_by_mode(mode)
        self._begin_space_session(space, mode, TRIAL_MINUTES, trial=True)

    @Property(list, notify=spacesChanged)
    def dockApps(self) -> list[dict]:
        catalog = {str(item.get("exe", "")).lower(): item for item in self._catalog}
        result: list[dict] = []
        medium = self._spaces.get_by_mode("medium") or self._spaces.space
        for exe in medium.get("allowed_apps", []):
            item = catalog.get(str(exe).lower())
            if item is not None:
                result.append(
                    {
                        "exe": exe,
                        "name": str(item.get("name") or exe),
                        "iconUrl": str(item.get("iconUrl") or ""),
                        "path": str(item.get("path") or ""),
                    }
                )
            else:
                result.append({"exe": exe, "name": exe, "iconUrl": "", "path": ""})
        return result

    @Slot(str)
    def launchApp(self, exe: str) -> None:
        try:
            catalog = {str(item.get("exe", "")).lower(): item for item in self._catalog}
            item = catalog.get(str(exe).lower())
            path = str(item.get("path") or "") if item else ""
            if path:
                os.startfile(path)  # noqa: S606 - 用户主动启动白名单应用
            else:
                os.startfile(str(exe))  # noqa: S606
        except Exception as exc:  # noqa: BLE001
            logger.warning("启动应用失败：%s", exc)
            self.toast.emit(QCoreApplication.translate("ShenQing", "启动应用失败"))
            return
        # 通知主程序：应用已拉起，覆清 dock 需要把它显示到遮罩之上
        self.appLaunched.emit(str(exe))

    # ================= 自动更新（GitHub Releases） =================
    def _set_update_state(self, state: str, error: str = "") -> None:
        self._update_state = str(state)
        self._update_error = str(error or "")
        self.stateChanged.emit()

    @Property(str, notify=stateChanged)
    def updateState(self) -> str:
        return self._update_state

    @Property(bool, notify=stateChanged)
    def updateAvailable(self) -> bool:
        return self._update_info is not None

    @Property(str, notify=stateChanged)
    def updateLatestVersion(self) -> str:
        return str((self._update_info or {}).get("version", ""))

    @Property(str, notify=stateChanged)
    def updateNotes(self) -> str:
        return updater.format_notes((self._update_info or {}).get("notes", ""))

    @Property(int, notify=stateChanged)
    def updateProgress(self) -> int:
        return int(self._update_progress)

    @Property(str, notify=stateChanged)
    def updateError(self) -> str:
        return self._update_error

    @Property(str, notify=stateChanged)
    def updateAssetName(self) -> str:
        return str((self._update_info or {}).get("assetName", ""))

    @Property(bool, notify=settingsChanged)
    def autoUpdate(self) -> bool:
        return bool(self._settings.get("auto_update", True))

    @Slot(bool)
    def setAutoUpdate(self, enabled: bool) -> None:
        self._settings.set("auto_update", bool(enabled))
        self.settingsChanged.emit()

    def _check_update_worker(self) -> None:
        info: dict | None = None
        error = ""
        try:
            info = updater.check_latest()
        except Exception as exc:  # noqa: BLE001 - 后台线程不能崩
            error = str(exc)
            logger.warning("检查更新异常：%s", exc)
        try:
            self._updateChecked.emit(info, error)
        except RuntimeError:  # 宿主已销毁
            pass

    @Slot()
    def checkUpdate(self) -> None:
        """手动/自动检查 GitHub 最新 Release（后台线程，不阻塞界面）。"""
        if self._update_state in ("checking", "downloading"):
            return
        self._set_update_state("checking")
        threading.Thread(
            target=self._check_update_worker,
            name="shenqing-update-check",
            daemon=True,
        ).start()

    @Slot(object, str)
    def _on_update_checked(self, info: object, error: str) -> None:
        if error:
            self._update_info = None
            self._set_update_state("error", str(error))
            self.toast.emit(QCoreApplication.translate("ShenQing", "检查更新失败"))
            return
        if not isinstance(info, dict) or not info:
            self._update_info = None
            self._set_update_state("idle")
            return
        self._update_info = dict(info)
        self._set_update_state("available")
        self.toast.emit(
            QCoreApplication.translate("ShenQing", "发现新版本 {0}，可在关于页更新").format(
                str(info.get("version", ""))
            )
        )

    def _download_update_worker(
        self, url: str, dest: Path, cancel: updater.CancelToken
    ) -> None:
        ok = False
        try:
            ok = updater.download(
                url,
                dest,
                on_progress=lambda value: self._updateProgress.emit(int(value)),
                cancel=cancel,
            )
        except Exception as exc:  # noqa: BLE001
            logger.warning("下载更新异常：%s", exc)
        try:
            self._updateDownloaded.emit(bool(ok), str(dest))
        except RuntimeError:  # 宿主已销毁
            pass

    @Slot()
    def downloadUpdate(self) -> None:
        """下载最新安装包（后台线程，可取消）。"""
        info = self._update_info or {}
        url = str(info.get("assetUrl") or "")
        if self._update_state == "downloading":
            return
        if not url:
            self._set_update_state("error", "没有可下载的安装包")
            self.toast.emit(QCoreApplication.translate("ShenQing", "没有可下载的安装包"))
            return
        name = Path(str(info.get("assetName") or "ShenQing-Setup.exe")).name
        dest = app_data_dir() / "updates" / name
        self._update_download_path = dest
        self._update_progress = 0
        self._update_cancel = updater.CancelToken()
        self._set_update_state("downloading")
        threading.Thread(
            target=self._download_update_worker,
            args=(url, dest, self._update_cancel),
            name="shenqing-update-download",
            daemon=True,
        ).start()

    @Slot()
    def cancelUpdateDownload(self) -> None:
        if self._update_cancel is not None:
            self._update_cancel.cancel()

    @Slot(int)
    def _on_update_progress(self, value: int) -> None:
        self._update_progress = max(0, min(100, int(value)))
        self.stateChanged.emit()

    @Slot(bool, str)
    def _on_update_downloaded(self, ok: bool, dest: str) -> None:
        path = Path(dest) if dest else None
        if ok and path is not None and path.exists() and path.stat().st_size > 0:
            self._update_download_path = path
            self._update_progress = 100
            self._set_update_state("ready")
            self.toast.emit(QCoreApplication.translate("ShenQing", "安装包已下载完成"))
        else:
            self._update_download_path = None
            self._set_update_state("error", "下载失败或被取消")
            self.toast.emit(QCoreApplication.translate("ShenQing", "下载失败或被取消"))

    @Slot()
    def installUpdate(self) -> None:
        """启动已下载的安装包；先停看门狗，避免安装期间被自动拉起。"""
        path = self._update_download_path
        if self._update_state != "ready" or path is None or not path.exists():
            self.toast.emit(QCoreApplication.translate("ShenQing", "安装包尚未下载完成"))
            return
        try:
            from ..services import keeper

            keeper.stop_keeper()
        except Exception as exc:  # noqa: BLE001
            logger.warning("安装前停止看门狗失败：%s", exc)
        try:
            os.startfile(str(path))  # noqa: S606 - 用户主动安装更新
        except Exception as exc:  # noqa: BLE001
            logger.warning("启动安装程序失败：%s", exc)
            self.toast.emit(QCoreApplication.translate("ShenQing", "无法启动安装程序"))
            return
        self.toast.emit(
            QCoreApplication.translate("ShenQing", "安装程序已启动，安装完成后请重新打开深清")
        )

    @Slot()
    def openReleasePage(self) -> None:
        from PySide6.QtCore import QUrl
        from PySide6.QtGui import QDesktopServices

        page = str((self._update_info or {}).get("pageUrl") or "")
        url = updater.release_page_url(page)
        try:
            QDesktopServices.openUrl(QUrl(url))
        except Exception as exc:  # noqa: BLE001
            logger.warning("打开更新页面失败：%s", exc)
            self.toast.emit(QCoreApplication.translate("ShenQing", "无法打开浏览器"))

    @Slot(str, result=list)
    def search(self, query: str) -> list[dict]:
        text = str(query or "").strip().casefold()
        if not text:
            return []
        results: list[dict] = []

        def add(title: str, sub: str, kind: str, payload: object) -> None:
            if text in title.casefold() or text in sub.casefold():
                results.append({"title": title, "sub": sub, "kind": kind, "payload": payload})

        add(QCoreApplication.translate("ShenQing", "空间"), QCoreApplication.translate("ShenQing", "清空间与专注设置"), "page", 0)
        add(QCoreApplication.translate("ShenQing", "数据"), QCoreApplication.translate("ShenQing", "专注统计"), "page", 1)
        add(QCoreApplication.translate("ShenQing", "插件"), QCoreApplication.translate("ShenQing", "插件管理"), "page", 2)
        add(QCoreApplication.translate("ShenQing", "设置"), QCoreApplication.translate("ShenQing", "偏好设置"), "page", 3)
        add(QCoreApplication.translate("ShenQing", "主题"), QCoreApplication.translate("ShenQing", "纯色 / 浅色 / 液态玻璃"), "theme", "")
        for mode in self.modes:
            add(mode["label"], mode["desc"], "mode", mode["value"])
        # v0.6：每张空间也是一条搜索结果（payload 带 id + mode，QML 可跳到空间页）
        for space in self.spaces:
            mode = str(space.get("mode") or "")
            label = QCoreApplication.translate("ShenQing", MODE_LABELS.get(mode, mode))
            add(
                str(space.get("name") or ""),
                label,
                "space",
                {"id": str(space.get("id") or ""), "mode": mode},
            )
        for theme in self.themes:
            add(theme["label"], theme["desc"], "theme", theme["value"])
        for plugin in self.plugins:
            add(str(plugin.get("name") or ""), str(plugin.get("description") or ""), "plugin", str(plugin.get("id") or ""))
        for action, label in (
            ("hardening", QCoreApplication.translate("ShenQing", "防退出加固")),
            ("admin", QCoreApplication.translate("ShenQing", "以管理员身份运行")),
            ("autostart", QCoreApplication.translate("ShenQing", "最高权限开机自启")),
            ("feedback", QCoreApplication.translate("ShenQing", "功能请求与 Bug 反馈")),
        ):
            add(label, QCoreApplication.translate("ShenQing", "设置"), "action", action)
        return results[:20]

    @Slot(str)
    def openFeedback(self, kind: str) -> None:
        url = FEEDBACK_URLS.get(str(kind or ""), FEEDBACK_URLS["request"])
        try:
            from PySide6.QtCore import QUrl
            from PySide6.QtGui import QDesktopServices

            QDesktopServices.openUrl(QUrl(url))
        except Exception as exc:  # noqa: BLE001
            logger.warning("打开反馈页面失败：%s", exc)
            self.toast.emit(QCoreApplication.translate("ShenQing", "无法打开浏览器"))

    # ================= 内部回调 =================
    def _on_tick(self, remaining: int) -> None:
        self.tickChanged.emit()
        self._dispatch("tick", int(remaining))

    def _on_finished(self, elapsed_seconds: int, completed: bool, pauses: int) -> None:
        self._guard.stop()
        power.allow_sleep()
        self._sleep_lock_active = False
        self._clock_clicks.clear()
        space = self._spaces.get(self._active_space_id)
        space_name = str(space["name"]) if space else ""
        minutes = elapsed_seconds / 60
        if self._trial_active:
            # 体验模式只做演示：不写统计、不影响连续天数
            self.toast.emit(QCoreApplication.translate("ShenQing", "体验结束"))
        elif completed or minutes >= 1:
            self._stats.record(
                minutes,
                self._session_level or self.lockLevel,
                completed,
                pauses,
                space=space_name,
                when=timesync.now(),
                started_at=self._session_started_at,
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
        self._trial_active = False
        self.stateChanged.emit()
        self.lockedChanged.emit()

    def _on_process_killed(self, exe_name: str) -> None:
        self.guardEvent.emit(exe_name)
        self._dispatch("process_blocked", str(exe_name))
