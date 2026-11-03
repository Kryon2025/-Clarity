"""应用引导：QApplication + RinUIWindow + AppBridge。"""

from __future__ import annotations

import argparse
import os
import sys
import time
from pathlib import Path

from PySide6.QtCore import (
    QCoreApplication,
    QLockFile,
    QTimer,
    QtMsgType,
    QUrl,
    qInstallMessageHandler,
)
from PySide6.QtQml import QQmlComponent
from PySide6.QtGui import QIcon
from PySide6.QtWidgets import QApplication
from RinUI import RinUIWindow
from RinUI.core.config import Theme

from .bridge.app_bridge import AppBridge
from .i18n import Translator
from .consts import APP_ALIAS, APP_ID, APP_NAME, APP_VERSION
from .paths import app_data_dir, qml_dir, qml_file
from .services import elevation, keeper
from .services.dock_reveal import DockRevealController
from .services.lock_hardening import restore_taskbars
from .services.logging_setup import setup_logging
from .services.tray import TrayController, app_icon_path
from .settings import Settings

_LOG: list[str] = []
_QML_PROBLEMS: list[str] = []
_SMOKE_DONE = False

#: 已知无害的 Qt / RinUI 噪音（不参与冒烟判定）
_BENIGN_MARKERS = (
    "overrides a member of the base object",
    "QFontDatabase: Cannot find font directory",
    "ScrollBar attached property must be attached",
    "DPI Scale Factor",
    "HiDPI note",
    "Font Source:",
    "Font Family:",
)


def _is_problem(message: str, mode) -> bool:  # noqa: ANN001
    if any(marker in message for marker in _BENIGN_MARKERS):
        return False
    lowered = message.lower()
    if "qml:" in lowered or "typeerror" in lowered or "referenceerror" in lowered:
        return True
    return mode in (QtMsgType.QtCriticalMsg, QtMsgType.QtFatalMsg)


def _message_handler(mode, context, message: str) -> None:  # noqa: ANN001
    text = str(message)
    if _SMOKE_DONE:
        return
    _LOG.append(text)
    if _is_problem(text, mode):
        _QML_PROBLEMS.append(text)
    print(text, file=sys.stderr)


def _parse_args(argv: list[str]) -> tuple[argparse.Namespace, list[str]]:
    parser = argparse.ArgumentParser(prog=APP_NAME, description=f"{APP_NAME}（{APP_ALIAS}）专注锁机工具")
    parser.add_argument("--smoke", action="store_true", help="离屏冒烟测试：加载界面、截图后退出")
    parser.add_argument("--restarted", action="store_true", help="由保活看门狗重新拉起")
    parser.add_argument("--autostart", action="store_true", help="由计划任务/开机自启拉起")
    parser.add_argument("--theme", choices=["Auto", "Light", "Dark"], default=None)
    return parser.parse_known_args(argv[1:] if argv else [])


def _single_instance_lock(
    retries: int = 12,
    interval_ms: int = 400,
    restarted: bool = False,
) -> QLockFile | None:
    """拿单实例锁；提权重启时旧进程还在退出，所以重试几秒。

    --restarted 表示本进程由看门狗拉起，旧进程是被强杀的，锁文件大概率已失效：
    首次失败时主动清理一次陈旧锁，避免保活变成「反复拉起又退出」。
    """
    lock = QLockFile(str(app_data_dir() / "shenqing.lock"))
    lock.setStaleLockTime(0)
    for attempt in range(max(1, retries)):
        if lock.tryLock(100):
            return lock
        if restarted and attempt == 0:
            try:
                lock.removeStaleLockFile()
            except Exception:  # noqa: BLE001
                pass
        time.sleep(interval_ms / 1000.0)
    return None


def _install_crash_safety() -> None:
    """兜底：进程退出/未捕获异常时把任务栏恢复出来（防退出加固期间任务栏是隐藏的）。"""
    import atexit

    atexit.register(restore_taskbars)
    previous_hook = sys.excepthook

    def _excepthook(exc_type, exc, tb):  # noqa: ANN001
        try:
            restore_taskbars()
        finally:
            previous_hook(exc_type, exc, tb)

    sys.excepthook = _excepthook


def main(argv: list[str] | None = None) -> int:
    # Windows 控制台默认 GBK，RinUI 会打印 emoji，先切到 UTF-8 避免 UnicodeEncodeError
    for stream in (sys.stdout, sys.stderr):
        try:
            stream.reconfigure(encoding="utf-8", errors="replace")  # type: ignore[union-attr]
        except (AttributeError, ValueError):
            pass

    logging = setup_logging()
    _install_crash_safety()
    args, qt_args = _parse_args(list(sys.argv if argv is None else argv))

    app = QApplication([sys.argv[0], *qt_args])
    app.setApplicationName(APP_NAME)
    app.setApplicationDisplayName(f"{APP_NAME}（{APP_ALIAS}）")
    app.setApplicationVersion(APP_VERSION)
    app.setOrganizationName(APP_ID)
    # 关窗只收托盘，不退出后台
    app.setQuitOnLastWindowClosed(False)

    icon = app_icon_path()
    if icon is not None:
        app.setWindowIcon(QIcon(str(icon)))

    qInstallMessageHandler(_message_handler)

    lock = _single_instance_lock(restarted=args.restarted)
    if lock is None and not args.smoke:
        print("深清已经在运行了（单实例模式）", file=sys.stderr)
        return 0

    settings = Settings()
    if args.smoke:
        os.environ.setdefault("SHENQING_NO_SCAN", "1")
    else:
        _apply_first_run_defaults(settings)

    # 管理员模式：以最高权限启动（UAC 确认一次），失败则按普通权限继续
    if bool(settings.get("admin_mode", False)) and not elevation.is_admin() and not args.smoke:
        logging.info("管理员模式已开启，正在以管理员身份重启…")
        if elevation.relaunch_as_admin():
            return 0

    # 翻译必须在加载 QML 之前装好（QML 里的 qsTr 在加载时求值）
    translator = Translator(app, str(settings.get("language", "auto")))
    bridge = AppBridge(translator=translator)
    window = RinUIWindow()  # 先建引擎，绑定上下文对象后再加载 QML
    window.engine.rootContext().setContextProperty("App", bridge)

    theme_mode = str(settings.get("theme_mode", "solid"))
    theme_name = args.theme or ("Light" if theme_mode == "light" else "Dark")
    try:
        window.setTheme(Theme(theme_name))
    except (ValueError, KeyError):
        logging.warning("未知主题：%s", theme_name)

    try:
        window.load(qml_file("Main.qml"))
    except (RuntimeError, FileNotFoundError) as exc:
        print(f"界面加载失败：{exc}", file=sys.stderr)
        if _QML_PROBLEMS:
            for problem in _QML_PROBLEMS[-5:]:
                print(f"  {problem}", file=sys.stderr)
        return 2

    bridge.themeChanged.connect(lambda name: window.setTheme(Theme(name)))

    def _retranslate(locale: str) -> None:
        engine = window.engine
        try:
            retranslate = getattr(engine, "retranslate", None)
            if callable(retranslate):
                retranslate()
        except Exception as exc:  # noqa: BLE001
            logging.warning("QML 重译失败：%s", exc)
        tray_ref = panel_holder.get("tray")
        if tray_ref is not None:
            tray_ref.set_tooltip_text(APP_NAME)

    bridge.languageChanged.connect(_retranslate)

    panel_holder: dict = {"panel": None}

    def hide_panel() -> None:
        panel = panel_holder["panel"]
        if panel is not None:
            panel.setProperty("visible", False)

    def toggle_quick_panel() -> None:
        panel = panel_holder["panel"]
        if panel is None:
            component = QQmlComponent(
                window.engine, QUrl.fromLocalFile(str(qml_file("QuickPanel.qml")))
            )
            panel = component.create()
            if component.isError() or panel is None:
                logging.warning("速启面板加载失败：%s", component.errorString())
                return
            panel_holder["panel"] = panel
        # 位置：托盘图标/光标附近；面板内部会做边界翻转
        # 通过 requestTick 触发面板的 toggleAt(x, y)（幂等显示，不会把自己关掉）
        from PySide6.QtGui import QCursor

        rect = tray.tray_geometry() if tray is not None else None
        if rect is not None:
            anchor_x = rect.center().x()
            anchor_y = rect.top()
        else:
            cursor = QCursor.pos()
            anchor_x, anchor_y = cursor.x(), cursor.y()
        panel.setProperty("requestX", anchor_x)
        panel.setProperty("requestY", anchor_y)
        panel.setProperty("requestTick", int(panel.property("requestTick") or 0) + 1)

    tray: TrayController | None = None
    if not args.smoke:
        tray = TrayController(app)
        tray.showRequested.connect(lambda: _show_window(window))
        tray.startRequested.connect(lambda: bridge.startLevel(bridge.lockLevel))
        tray.quickPanelRequested.connect(toggle_quick_panel)
        tray.quitRequested.connect(app.quit)
        tray.show()
        # 速启面板里的「打开主界面 / 设置 / 退出」按钮
        bridge.showMainRequested.connect(lambda: (_show_window(window), hide_panel()))
        bridge.settingsRequested.connect(
            lambda: (_show_window(window), _goto_settings(window), hide_panel())
        )
        bridge.quitRequested.connect(app.quit)
        bridge.toast.connect(lambda text: tray.message(APP_NAME, text))
        # 开始专注后自动收起速启面板
        bridge.stateChanged.connect(
            lambda: panel_holder["panel"] is not None
            and bridge.busy
            and panel_holder["panel"].setProperty("visible", False)
        )

    if not args.smoke:
        # 保活：写 keeper.json 并起独立看门狗；正常退出时结束看门狗
        if keeper.start_keeper():
            logging.info("保活看门狗已启动")
        else:
            logging.info("保活看门狗未启动")
        app.aboutToQuit.connect(keeper.stop_keeper)
        # 覆清 dock：白名单应用启动后要显示在 always-on-top 遮罩之上（不退出专注）
        dock_reveal = setup_dock_reveal(app, bridge)
        logging.info("覆清 dock 显示控制器已就绪：%s", dock_reveal is not None)
        # 首次运行提示：默认最高权限 + 最高权限自启
        if settings.get("elevated_bootstrap"):
            _bootstrap_elevated(settings, bridge)
        # 自动更新：启动 6 秒后检查一次 GitHub Releases（auto_update 可关）
        if bool(settings.get("auto_update", True)):
            QTimer.singleShot(6000, bridge.checkUpdate)

    if args.smoke:
        QTimer.singleShot(3000, lambda: _smoke_finish(app, window))
    else:
        logging.info("深清启动完成，数据目录：%s", app_data_dir())

    app.aboutToQuit.connect(bridge.overlayClosed)

    code = app.exec()
    return int(code) if not args.smoke else (1 if _QML_PROBLEMS else 0)


def _goto_settings(window: RinUIWindow) -> None:
    """切到设置页（新版导航：空间/数据/插件/设置 → 设置是第 4 项，navIndex = 3）。"""
    root = window.root_window
    if root is not None:
        root.setProperty("navIndex", 3)


def _show_window(window: RinUIWindow) -> None:
    root = window.root_window
    if root is None:
        return
    root.show()
    root.requestActivate()


def setup_dock_reveal(app: QApplication, bridge: AppBridge) -> DockRevealController:
    """把「覆清 dock 应用显示到遮罩之上」的控制器接到桥上（lifecycle 挂在 app 下）。"""
    controller = DockRevealController(bridge, parent=app)
    bridge.appLaunched.connect(controller.handle_app_launched)
    bridge.stateChanged.connect(controller.sync_session)
    bridge.lockedChanged.connect(controller.sync_session)
    app.aboutToQuit.connect(controller.restore)
    return controller


def _apply_first_run_defaults(settings: Settings) -> bool:
    """v0.6：首次运行默认以最高权限运行，并标记待登记最高权限自启。

    返回是否首次运行。提权与登记计划任务都在主流程里做（失败静默）。
    """
    if not getattr(settings, "is_new", False):
        return False
    settings.set("admin_mode", True)
    settings.set("elevated_bootstrap", True)
    return True


def _bootstrap_elevated(settings: Settings, bridge: AppBridge) -> None:
    """首次运行：登记最高权限开机自启（失败静默），并 toast 说明默认最高权限。"""
    ok = False
    message = ""
    try:
        ok, message = elevation.set_elevated_autostart(True)
    except Exception as exc:  # noqa: BLE001
        message = str(exc)
    settings.set("elevated_bootstrap", False)
    if not ok:
        # 这里不在 main() 里，不能复用它的局部 logger，按需取配置好的 logger
        setup_logging().warning("最高权限自启登记失败（静默）：%s", message)
    admin = elevation.is_admin()
    if admin and ok:
        text = QCoreApplication.translate(
            "ShenQing", "已默认以最高权限运行，并开启最高权限开机自启"
        )
    elif admin:
        text = QCoreApplication.translate(
            "ShenQing", "已默认以最高权限运行（最高权限自启登记失败，可在设置里重试）"
        )
    elif ok:
        text = QCoreApplication.translate(
            "ShenQing", "已默认开启管理员模式，并登记最高权限开机自启"
        )
    else:
        text = QCoreApplication.translate(
            "ShenQing", "已默认开启管理员模式（下次启动会请求提权）"
        )
    bridge.toast.emit(text)


_SMOKE_PAGES = (
    "pages/SpacesPage.qml",
    "pages/WhitelistPage.qml",
    "pages/PluginsPage.qml",
    "pages/ThemesPage.qml",
    "pages/StatsPage.qml",
    "pages/SettingsPage.qml",
)


def _instantiate_pages(window: RinUIWindow) -> None:
    """逐页实例化，确保导航里每个页面在没有点击时也不是坏的。"""
    from PySide6.QtCore import QUrl
    from PySide6.QtQml import QQmlComponent

    qml_root = qml_dir()
    for relative in _SMOKE_PAGES:
        path = qml_root / relative
        component = QQmlComponent(window.engine, QUrl.fromLocalFile(str(path)))
        instance = component.create()
        if component.isError():
            message = component.errorString()
            _QML_PROBLEMS.append(f"{relative}: {message}")
            print(f"[smoke] {relative} 加载失败：{message}", file=sys.stderr)
        elif instance is not None:
            instance.deleteLater()
        else:
            print(f"[smoke] {relative} 未创建实例", file=sys.stderr)


def _smoke_finish(app: QApplication, window: RinUIWindow) -> None:
    """离屏冒烟：逐页实例化 + 抓一张窗口截图（失败不致命），然后退出。"""
    global _SMOKE_DONE
    _instantiate_pages(window)
    root = window.root_window
    if root is not None:
        try:
            image = root.grabWindow()
            out_dir = Path.cwd() / "build"
            out_dir.mkdir(parents=True, exist_ok=True)
            image.save(str(out_dir / "smoke.png"))
            print(f"[smoke] 截图已保存：{out_dir / 'smoke.png'}", file=sys.stderr)
        except (RuntimeError, AttributeError) as exc:  # pragma: no cover
            print(f"[smoke] 截图失败：{exc}", file=sys.stderr)
    for problem in _QML_PROBLEMS:
        print(f"[smoke] 问题：{problem}", file=sys.stderr)
    print(f"[smoke] QML 问题数：{len(_QML_PROBLEMS)}", file=sys.stderr)
    _SMOKE_DONE = True
    app.quit()
