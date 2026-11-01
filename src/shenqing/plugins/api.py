"""插件 API：插件基类、宿主 API、清单（plugin.json）解析与校验。

插件作者只需要关心三件事：

1. 插件目录里的 plugin.json（清单，见 PluginManifest）；
2. main.py 里名为 Plugin 的类，继承 PluginBase；
3. on_load 收到的 PluginAPI，用它读写插件自己的设置、发通知、记日志。

设计原则：

- 插件与宿主同进程运行，所有入口都自行吞异常，插件出错不会冒泡到宿主；
- 所有公开方法都能在主线程 / 插件线程调用，内部用 RLock 与原子写保护；
- 设置文件放在 %APPDATA%\\ShenQing\\plugin_data\\<插件 id>\\settings.json，
  与插件代码目录分离，插件升级 / 重装不会丢数据。
"""

from __future__ import annotations

import copy
import json
import logging
import os
import re
import threading
from collections.abc import Callable, Mapping
from dataclasses import dataclass, field
from pathlib import Path
from typing import Any

from ..consts import APP_VERSION

#: 宿主插件 API 版本；plugin.json 的 api_version 主版本一致才兼容。
PLUGIN_API_VERSION = "0.1"

#: 插件清单里的必填字段
_REQUIRED_FIELDS = ("id", "name", "version", "api_version", "entry")
#: 插件清单里的可选文本字段
_OPTIONAL_FIELDS = ("author", "description", "homepage")
#: 全部已知字段（其余字段原样保留在 extra 里）
_KNOWN_FIELDS = frozenset(_REQUIRED_FIELDS + _OPTIONAL_FIELDS)

_ID_PATTERN = re.compile(r"^[A-Za-z0-9][A-Za-z0-9._-]{0,127}$")
_MAJOR_PATTERN = re.compile(r"^(\d+)")
_DRIVE_PATTERN = re.compile(r"^[A-Za-z]:")

#: 通知回调签名：(标题, 正文) -> None
Notifier = Callable[[str, str], None]
#: 插件信号回调签名：(插件 id, 信号名, 负载) -> None
SignalEmitter = Callable[[str, str, Any], None]
#: 插件 UI 状态回调签名：(插件 id, 状态字典) -> None
StateSetter = Callable[[str, dict[str, Any]], None]

logger = logging.getLogger("shenqing.plugins")

_tray_lock = threading.Lock()
_tray_icon: Any = None


class ManifestError(ValueError):
    """plugin.json 缺失、格式错误或字段不合法。"""


def _api_major(version: str) -> int | None:
    """取版本号的主版本（"0.1" -> 0），格式不对返回 None。"""
    match = _MAJOR_PATTERN.match(str(version).strip())
    return int(match.group(1)) if match else None


def _normalize_entry(raw: str) -> str:
    """把 entry 规范成插件目录内的相对 POSIX 路径，并挡住越界写法。"""
    entry = raw.replace("\\", "/").strip()
    if entry.startswith("/") or _DRIVE_PATTERN.match(entry):
        raise ManifestError("entry 必须是插件目录内的相对路径")
    parts = [part for part in entry.split("/") if part not in ("", ".")]
    if not parts or ".." in parts:
        raise ManifestError("entry 不能为空，也不能包含 ..")
    if not parts[-1].lower().endswith(".py"):
        raise ManifestError("entry 必须指向 .py 文件")
    return "/".join(parts)


def _as_text(value: Any, field_name: str) -> str:
    """把清单里的文本字段转成非空字符串。"""
    if isinstance(value, bool) or not isinstance(value, (str, int, float)):
        raise ManifestError(f"plugin.json 字段 {field_name} 必须是字符串")
    text = str(value).strip()
    if not text:
        raise ManifestError(f"plugin.json 字段 {field_name} 不能为空")
    return text


@dataclass(frozen=True)
class PluginManifest:
    """插件清单（plugin.json）的解析结果。

    必填：id / name / version / api_version / entry；
    可选：author / description / homepage；其余字段原样保存在 extra。
    """

    id: str
    name: str
    version: str
    api_version: str
    entry: str = "main.py"
    author: str = ""
    description: str = ""
    homepage: str = ""
    extra: dict[str, Any] = field(default_factory=dict)

    @classmethod
    def from_dict(cls, data: Mapping[str, Any]) -> PluginManifest:
        """校验一个已解析的 JSON 对象并返回清单；不合法抛 ManifestError。"""
        if not isinstance(data, Mapping):
            raise ManifestError("plugin.json 顶层必须是 JSON 对象")
        values: dict[str, str] = {}
        for key in _REQUIRED_FIELDS:
            if key not in data:
                raise ManifestError(f"plugin.json 缺少必填字段：{key}")
            values[key] = _as_text(data[key], key)

        plugin_id = values["id"]
        if not _ID_PATTERN.fullmatch(plugin_id) or ".." in plugin_id:
            raise ManifestError(
                f"插件 id 不合法：{plugin_id!r}（只允许字母、数字、点、下划线、短横线）"
            )
        if _api_major(values["api_version"]) is None:
            raise ManifestError('api_version 必须形如 "0.1"（以数字主版本开头）')

        optional: dict[str, str] = {}
        for key in _OPTIONAL_FIELDS:
            raw = data.get(key, "")
            if raw is None:
                raw = ""
            if not isinstance(raw, str):
                raise ManifestError(f"plugin.json 字段 {key} 必须是字符串")
            optional[key] = raw.strip()

        extra = {key: value for key, value in data.items() if key not in _KNOWN_FIELDS}
        return cls(
            id=plugin_id,
            name=values["name"],
            version=values["version"],
            api_version=values["api_version"],
            entry=_normalize_entry(values["entry"]),
            extra=extra,
            **optional,
        )

    @classmethod
    def from_file(cls, path: Path | str) -> PluginManifest:
        """读取并校验 plugin.json；读不到或格式错误抛 ManifestError。"""
        manifest_path = Path(path)
        try:
            text = manifest_path.read_text(encoding="utf-8-sig")
        except OSError as exc:
            raise ManifestError(f"读取 {manifest_path.name} 失败：{exc}") from exc
        try:
            data = json.loads(text)
        except json.JSONDecodeError as exc:
            raise ManifestError(
                f"{manifest_path.name} 不是合法 JSON：第 {exc.lineno} 行 {exc.msg}"
            ) from exc
        return cls.from_dict(data)

    def is_api_compatible(self, host_api_version: str = PLUGIN_API_VERSION) -> bool:
        """主版本一致即兼容（宿主 0.1 接受 0.x 插件，拒绝 1.x 插件）。"""
        mine = _api_major(self.api_version)
        host = _api_major(host_api_version)
        return mine is not None and host is not None and mine == host

    def to_dict(self) -> dict[str, Any]:
        """还原成可写回磁盘的字典。"""
        data: dict[str, Any] = dict(self.extra)
        data.update(
            {
                "id": self.id,
                "name": self.name,
                "version": self.version,
                "api_version": self.api_version,
                "entry": self.entry,
                "author": self.author,
                "description": self.description,
                "homepage": self.homepage,
            }
        )
        return data


class PluginBase:
    """插件入口基类：按需覆写钩子，全部默认空实现。

    子类必须命名为 Plugin，并且在插件入口模块（默认 main.py）的顶层定义。
    插件实例由 PluginManager 创建，不要自己 new。
    """

    def on_load(self, api: PluginAPI) -> None:
        """插件被启用后立即调用一次。适合保存 api、读设置、初始化状态。"""

    def on_unload(self) -> None:
        """插件被停用或重载前调用一次。适合保存状态、关闭资源。"""

    def on_session_start(self, space: dict) -> None:
        """开始一段专注时调用。space 为空间字典（id/name/minutes/...）。"""

    def on_session_end(self, summary: dict) -> None:
        """一段专注结束时调用。summary 含 space_name/minutes/completed 等字段。"""

    def on_process_blocked(self, exe: str) -> None:
        """守护进程结束了一个干扰程序时调用，exe 为进程名（如 game.exe）。"""

    def on_tick(self, remaining_seconds: int) -> None:
        """专注中每秒调用一次，remaining_seconds 为剩余秒数。"""

    def on_settings_changed(self, key: str, value: Any) -> None:
        """宿主设置项变化时调用，key / value 为设置键与值。"""


class PluginAPI:
    """宿主提供给单个插件的 API。

    不要自己构造；PluginManager 会在 on_load 之前创建并传入。
    所有方法都保证不抛异常（失败时记日志 / 返回默认值），可安全地在
    插件线程或宿主主线程调用。
    """

    def __init__(
        self,
        plugin_id: str,
        data_dir: Path | str,
        *,
        logger: logging.Logger | None = None,
        notifier: Notifier | None = None,
        signal_emitter: SignalEmitter | None = None,
        state_setter: StateSetter | None = None,
        host_version: str = APP_VERSION,
    ) -> None:
        self._plugin_id = str(plugin_id)
        self._logger = logger or logging.getLogger(f"shenqing.plugins.{self._plugin_id}")
        self._notifier = notifier
        self._signal_emitter = signal_emitter
        self._state_setter = state_setter
        self._host_version = str(host_version)
        self._lock = threading.RLock()
        self._data_dir = Path(data_dir)
        self._settings_path = self._data_dir / "settings.json"
        self._settings: dict[str, Any] = {}
        try:
            self._data_dir.mkdir(parents=True, exist_ok=True)
        except OSError as exc:
            self._logger.warning("插件数据目录不可写 %s：%s", self._data_dir, exc)
        self._load_settings()

    # ---------- 只读信息 ----------
    @property
    def plugin_id(self) -> str:
        """当前插件 id。"""
        return self._plugin_id

    @property
    def data_dir(self) -> Path:
        """当前插件的数据目录（settings.json 所在目录）。"""
        return self._data_dir

    @property
    def settings_path(self) -> Path:
        """当前插件 settings.json 的绝对路径，调试时可直接打开。"""
        return self._settings_path

    # ---------- 日志 ----------
    def log(self, message: str) -> None:
        """写一条插件日志（logger 名为 shenqing.plugins.<插件 id>）。"""
        try:
            self._logger.info("[%s] %s", self._plugin_id, message)
        except Exception:
            pass

    # ---------- 设置 ----------
    def get_setting(self, key: str, default: Any = None) -> Any:
        """读插件自己的设置；key 不存在或读取失败时返回 default。"""
        try:
            if not isinstance(key, str) or not key:
                return default
            with self._lock:
                return copy.deepcopy(self._settings.get(key, default))
        except Exception:
            self._logger.exception("读取插件设置 %s 失败", key)
            return default

    def set_setting(self, key: str, value: Any) -> bool:
        """写插件自己的设置并落盘；value 必须可 JSON 序列化，成功返回 True。"""
        try:
            if not isinstance(key, str) or not key:
                self._logger.warning("插件设置键必须是非空字符串")
                return False
            try:
                encoded = json.dumps(value, ensure_ascii=False, allow_nan=False)
            except (TypeError, ValueError) as exc:
                self._logger.warning("插件设置 %s 不是合法 JSON：%s", key, exc)
                return False
            with self._lock:
                self._settings[key] = json.loads(encoded)
                return self._save_settings()
        except Exception:
            self._logger.exception("写入插件设置 %s 失败", key)
            return False

    # ---------- 通知 / 信号 ----------
    def notify(self, title: str, body: str) -> None:
        """弹一条系统通知（托盘不可用时只记日志）。"""
        try:
            text_title = str(title)[:80]
            text_body = str(body)[:400]
            if self._notifier is not None:
                self._notifier(text_title, text_body)
                return
            if not tray_notify(text_title, text_body):
                self._logger.info("通知（当前无托盘可用）：%s - %s", text_title, text_body)
        except Exception:
            self._logger.exception("插件通知失败")

    def emit_signal(self, name: str, payload: Any = None) -> None:
        """向宿主发一个插件信号，由宿主监听者决定怎么呈现（例如 toast）。"""
        try:
            if not isinstance(name, str) or not name:
                self._logger.warning("插件信号名必须是非空字符串")
                return
            if self._signal_emitter is None:
                self._logger.debug("插件信号 %s（宿主未订阅）：%r", name, payload)
                return
            self._signal_emitter(self._plugin_id, name, payload)
        except Exception:
            self._logger.exception("插件发送信号 %s 失败", name)

    def set_ui_state(self, state: Mapping[str, Any] | None) -> bool:
        """把插件想让宿主展示的状态交给宿主（设置页插件行会显示 state.summary）。

        要求 JSON 可序列化；宿主只做展示，不会回传。成功返回 True。
        """
        try:
            if state is None:
                state = {}
            if not isinstance(state, Mapping):
                self._logger.warning("插件 UI 状态必须是字典")
                return False
            encoded = json.dumps(dict(state), ensure_ascii=False, allow_nan=False)
            payload = json.loads(encoded)
            if self._state_setter is None:
                self._logger.debug("宿主未接收插件 UI 状态：%r", payload)
                return False
            self._state_setter(self._plugin_id, payload)
            return True
        except (TypeError, ValueError) as exc:
            self._logger.warning("插件 UI 状态不是合法 JSON：%s", exc)
            return False
        except Exception:
            self._logger.exception("提交插件 UI 状态失败")
            return False

    # ---------- 宿主信息 ----------
    def host_version(self) -> str:
        """宿主版本号，例如 0.1.0（与插件 API 版本不是一回事）。"""
        return self._host_version

    def register_nav_page(self, title: str, qml_relative_path: str) -> bool:
        """预留：贡献导航页。0.1 尚未开放，调用只会记警告并返回 False。"""
        self._logger.warning(
            "register_nav_page 在插件 API 0.1 中尚未开放，已忽略：%s (%s)",
            title,
            qml_relative_path,
        )
        return False

    # ---------- 内部实现 ----------
    def _load_settings(self) -> None:
        try:
            if not self._settings_path.exists():
                return
            data = json.loads(self._settings_path.read_text(encoding="utf-8"))
            if isinstance(data, dict):
                self._settings = data
            else:
                self._logger.warning("插件设置文件顶层不是对象，已忽略：%s", self._settings_path)
        except (OSError, json.JSONDecodeError) as exc:
            self._logger.warning("读取插件设置失败，使用默认值：%s", exc)
            self._settings = {}

    def _save_settings(self) -> bool:
        try:
            self._data_dir.mkdir(parents=True, exist_ok=True)
            payload = json.dumps(
                self._settings, ensure_ascii=False, indent=2, sort_keys=True
            )
            tmp_path = self._settings_path.with_name(self._settings_path.name + ".tmp")
            tmp_path.write_text(payload + "\n", encoding="utf-8")
            os.replace(tmp_path, self._settings_path)
            return True
        except (OSError, TypeError, ValueError) as exc:
            self._logger.warning("保存插件设置失败：%s", exc)
            return False


def tray_notify(title: str, body: str) -> bool:
    """兜底通知：借系统托盘弹一条消息，不可用或出错时返回 False。

    只在主线程、且 Qt 托盘可用时生效；这是一个「尽力而为」的函数，
    任何异常都会被吞掉，不影响调用方。
    """
    global _tray_icon
    try:
        if threading.current_thread() is not threading.main_thread():
            return False
        from PySide6.QtCore import QCoreApplication
        from PySide6.QtWidgets import QApplication, QSystemTrayIcon
    except Exception:
        return False
    try:
        app = QCoreApplication.instance()
        # 只有真正的 QApplication 才能碰 QtWidgets / 托盘：
        # 纯 QCoreApplication（无 GUI）下创建 QSystemTrayIcon 会直接段错误。
        if app is None or not isinstance(app, QApplication):
            return False
        if not QSystemTrayIcon.isSystemTrayAvailable():
            return False
        if not QSystemTrayIcon.supportsMessages():
            return False
        with _tray_lock:
            if _tray_icon is None:
                icon = QSystemTrayIcon(app.windowIcon(), app)
                icon.setToolTip("深清插件通知")
                icon.show()
                _tray_icon = icon
            tray = _tray_icon
        tray.showMessage(
            str(title)[:80],
            str(body)[:400],
            QSystemTrayIcon.MessageIcon.Information,
            4000,
        )
        # 兜底托盘图标只是临时用一下，避免和宿主自己的托盘图标长期并存
        try:
            from PySide6.QtCore import QTimer

            QTimer.singleShot(12_000, tray.hide)
        except Exception:
            pass
        return True
    except Exception:
        logger.exception("托盘通知失败")
        return False
