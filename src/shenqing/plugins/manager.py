"""插件管理器：扫描、加载、启用 / 停用、事件分发与热重载。

插件目录按优先级从高到低扫描：

1. 用户目录：环境变量 SHENQING_PLUGINS_DIR 覆盖，否则 %APPDATA%\\ShenQing\\plugins；
2. 开发目录：仓库根目录下的 plugins/（存在时）；
3. 内置目录：shenqing/plugins/builtin（示例插件，始终可用）。

同一 id 只保留优先级最高的那一份；每个插件都独立 try/except，坏插件只影响自己。
所有公开方法都由 threading.RLock 保护，可在宿主主线程直接调用。
"""

from __future__ import annotations

import importlib.util
import logging
import os
import re
import sys
import threading
from collections.abc import Callable, Sequence
from dataclasses import dataclass, field
from pathlib import Path
from types import ModuleType
from typing import Any, Protocol

from ..consts import APP_VERSION
from ..paths import app_data_dir
from ..settings import Settings
from .api import (
    PLUGIN_API_VERSION,
    ManifestError,
    PluginAPI,
    PluginBase,
    PluginManifest,
    SignalEmitter,
    tray_notify,
)

#: 覆盖用户插件目录的环境变量；可用 os.pathsep（Windows 为 ;）分隔多个目录。
PLUGINS_DIR_ENV = "SHENQING_PLUGINS_DIR"

#: 宿主 settings.json 里记录「被停用插件 id」的键。
DISABLED_PLUGINS_KEY = "disabled_plugins"

#: 宿主事件名 -> 插件钩子方法名。bridge 只认这几个事件。
EVENT_HOOKS: dict[str, str] = {
    "session_start": "on_session_start",
    "session_end": "on_session_end",
    "process_blocked": "on_process_blocked",
    "tick": "on_tick",
    "settings_changed": "on_settings_changed",
}


class SettingsLike(Protocol):
    """manager 只依赖宿主 Settings 的两个方法，方便测试时替换。"""

    def get(self, key: str, default: Any = None) -> Any: ...

    def set(self, key: str, value: Any, *, save: bool = True) -> None: ...


def _safe_resolve(path: Path) -> Path:
    try:
        return path.resolve()
    except OSError:  # pragma: no cover - 极端文件系统错误
        return path


def default_plugins_dirs() -> list[Path]:
    """用户插件目录：SHENQING_PLUGINS_DIR 优先，否则 %APPDATA%\\ShenQing\\plugins。"""
    raw = os.environ.get(PLUGINS_DIR_ENV, "").strip()
    if raw:
        return [Path(item) for item in raw.split(os.pathsep) if item.strip()]
    return [app_data_dir() / "plugins"]


def project_plugins_dirs() -> list[Path]:
    """项目内开发用插件目录：<仓库根>/plugins（不存在时返回空列表）。"""
    root = Path(__file__).resolve().parents[3]
    candidate = root / "plugins"
    return [candidate] if candidate.is_dir() else []


def default_builtin_dir() -> Path:
    """内置示例插件目录：shenqing/plugins/builtin。"""
    return Path(__file__).resolve().parent / "builtin"


@dataclass
class PluginRecord:
    """一个被扫描到的插件（有效清单或坏清单都记一条）。"""

    key: str
    manifest: PluginManifest | None
    path: Path
    source: str
    enabled: bool = False
    error: str | None = None
    instance: PluginBase | None = None
    api: PluginAPI | None = None
    module_name: str | None = None
    loaded: bool = False
    ui_state: dict = field(default_factory=dict)

    @property
    def plugin_id(self) -> str:
        """清单 id；清单无效时退回目录名，保证 UI 有东西可显示。"""
        return self.manifest.id if self.manifest is not None else self.path.name


class PluginLoadError(RuntimeError):
    """插件加载过程中的可预期错误（入口缺失、没有 Plugin 类等）。"""


class PluginManager:
    """插件生命周期与事件分发中心。

    典型用法（宿主主线程）::

        manager = PluginManager(settings)
        manager.dispatch("session_start", space_dict)
        manager.dispatch("session_end", summary_dict)
        manager.list_plugins()          # -> [{id, name, ...}]
        manager.set_enabled(plugin_id, False)
        manager.reload()
    """

    def __init__(
        self,
        settings: SettingsLike | None = None,
        *,
        plugin_dirs: Sequence[str | Path] | None = None,
        builtin_dir: str | Path | None = None,
        data_dir: str | Path | None = None,
        notifier: Callable[[str, str], None] | None = None,
        state_listener: Callable[[str, dict], None] | None = None,
        logger: logging.Logger | None = None,
    ) -> None:
        self._settings: SettingsLike = settings if settings is not None else Settings()
        self._logger = logger or logging.getLogger("shenqing.plugins")
        self._notifier = notifier
        self._state_listener = state_listener
        self._data_dir = (
            Path(data_dir) if data_dir is not None else (app_data_dir() / "plugin_data")
        )
        self._builtin_dir = (
            Path(builtin_dir) if builtin_dir is not None else default_builtin_dir()
        )
        self._roots: list[tuple[Path, str]] = self._resolve_roots(plugin_dirs)
        self._lock = threading.RLock()
        self._records: dict[str, PluginRecord] = {}
        self._signal_listeners: list[SignalEmitter] = []
        self._module_seq = 0

        with self._lock:
            self._records = self._scan()
            disabled = self._read_disabled()
            for record in self._records.values():
                manifest = record.manifest
                if manifest is None:
                    continue
                record.enabled = manifest.id not in disabled
                if record.enabled:
                    self._load(record)
        self._logger.info("插件系统就绪：%s", self._summary_text())

    # ================= 查询 =================
    def list_plugins(self) -> list[dict]:
        """返回插件列表（供 UI / bridge 直接转成 QML list）。"""
        with self._lock:
            result: list[dict] = []
            for record in self._records.values():
                manifest = record.manifest
                result.append(
                    {
                        "id": record.plugin_id,
                        "name": manifest.name if manifest else record.path.name,
                        "version": manifest.version if manifest else "",
                        "description": manifest.description if manifest else "",
                        "enabled": bool(record.enabled),
                        "error": record.error,
                        "path": str(record.path),
                        "state": dict(record.ui_state),
                    }
                )
            return result

    def get_plugin(self, plugin_id: str) -> PluginBase | None:
        """按 id 取已加载的插件实例（例如 focus_stats.get_summary()）。"""
        with self._lock:
            record = self._find(str(plugin_id))
            if record is None or not record.loaded:
                return None
            return record.instance

    def is_loaded(self, plugin_id: str) -> bool:
        """插件当前是否已成功加载。"""
        with self._lock:
            record = self._find(str(plugin_id))
            return bool(record is not None and record.loaded)

    # ================= 启用 / 停用 / 重载 =================
    def set_enabled(self, plugin_id: str, enabled: bool) -> bool:
        """启用或停用插件，并把状态写进宿主设置的 disabled_plugins。"""
        plugin_id = str(plugin_id)
        with self._lock:
            record = self._find(plugin_id)
            if record is None or record.manifest is None:
                self._logger.warning("插件不存在或清单无效：%s", plugin_id)
                return False
            wanted = bool(enabled)
            was_enabled = record.enabled
            record.enabled = wanted
            if wanted:
                if not record.loaded:
                    self._load(record)
            elif record.loaded:
                self._unload(record)
            if was_enabled != wanted:
                self._logger.info("插件 %s 已%s", plugin_id, "启用" if wanted else "停用")
            self._save_disabled()
            return True

    def reload(self) -> None:
        """重新扫描目录并重载全部插件（先逐个 on_unload，再重新 import）。"""
        with self._lock:
            self._logger.info("开始重载插件")
            for record in list(self._records.values()):
                if record.loaded:
                    self._unload(record)
            self._records = self._scan()
            disabled = self._read_disabled()
            for record in self._records.values():
                manifest = record.manifest
                if manifest is None:
                    continue
                record.enabled = manifest.id not in disabled
                if record.enabled:
                    self._load(record)
            self._save_disabled()
        self._logger.info("插件重载完成：%s", self._summary_text())

    # ================= 事件分发 =================
    def dispatch(self, event: str, *args: Any) -> None:
        """把宿主事件分发给所有已启用插件；单个插件抛异常只记日志。"""
        if not isinstance(event, str) or not event:
            return
        hook = EVENT_HOOKS.get(event)
        if hook is None:
            self._logger.warning("未知插件事件：%s", event)
            return
        with self._lock:
            targets = [
                record
                for record in self._records.values()
                if record.loaded and record.enabled and record.instance is not None
            ]
        for record in targets:
            self._invoke(record, hook, *args)

    # ================= 插件信号 / 通知 =================
    def add_signal_listener(self, listener: SignalEmitter) -> None:
        """订阅插件 api.emit_signal(name, payload)，回调签名 (id, name, payload)。"""
        if not callable(listener):
            return
        with self._lock:
            if listener not in self._signal_listeners:
                self._signal_listeners.append(listener)

    def remove_signal_listener(self, listener: SignalEmitter) -> None:
        """取消订阅插件信号。"""
        with self._lock:
            if listener in self._signal_listeners:
                self._signal_listeners.remove(listener)

    def set_notifier(self, notifier: Callable[[str, str], None] | None) -> None:
        """设置通知实现（例如托盘 controller 的 message 方法）。"""
        with self._lock:
            self._notifier = notifier

    # ================= 内部：扫描 =================
    def _resolve_roots(
        self, plugin_dirs: Sequence[str | Path] | None
    ) -> list[tuple[Path, str]]:
        if plugin_dirs is not None:
            roots = [(Path(path), "custom") for path in plugin_dirs]
        else:
            roots = [(path, "appdata") for path in default_plugins_dirs()]
            roots.extend((path, "project") for path in project_plugins_dirs())
        roots.append((self._builtin_dir, "builtin"))

        unique: list[tuple[Path, str]] = []
        seen: set[Path] = set()
        for path, source in roots:
            resolved = _safe_resolve(path)
            if resolved in seen:
                continue
            seen.add(resolved)
            unique.append((resolved, source))
        return unique

    def _scan(self) -> dict[str, PluginRecord]:
        records: dict[str, PluginRecord] = {}
        for root, source in self._roots:
            if not root.is_dir():
                continue
            try:
                children = sorted(root.iterdir(), key=lambda item: item.name.lower())
            except OSError as exc:  # pragma: no cover - 目录消失 / 无权限
                self._logger.warning("无法读取插件目录 %s：%s", root, exc)
                continue
            for child in children:
                if not child.is_dir():
                    continue
                manifest_path = child / "plugin.json"
                if not manifest_path.is_file():
                    continue
                try:
                    manifest = PluginManifest.from_file(manifest_path)
                except ManifestError as exc:
                    key = f"invalid::{child}"
                    records[key] = PluginRecord(
                        key=key,
                        manifest=None,
                        path=_safe_resolve(child),
                        source=source,
                        error=str(exc),
                    )
                    self._logger.warning("插件清单无效（%s）：%s", manifest_path, exc)
                    continue
                if manifest.id in records:
                    self._logger.debug(
                        "忽略被高优先级目录覆盖的插件：%s（%s）", manifest.id, child
                    )
                    continue
                records[manifest.id] = PluginRecord(
                    key=manifest.id,
                    manifest=manifest,
                    path=_safe_resolve(child),
                    source=source,
                )
        return records

    # ================= 内部：加载 / 卸载 =================
    def _load(self, record: PluginRecord) -> None:
        manifest = record.manifest
        if manifest is None:
            return
        record.error = None
        if not manifest.is_api_compatible(PLUGIN_API_VERSION):
            record.error = (
                f"API 版本不兼容：插件要求 {manifest.api_version}，"
                f"宿主为 {PLUGIN_API_VERSION}（主版本需一致）"
            )
            self._logger.warning("%s：%s", manifest.id, record.error)
            return
        entry = self._entry_path(record)
        if entry is None:
            return
        try:
            module = self._import_entry(record, entry)
            record.module_name = module.__name__
            plugin_class = getattr(module, "Plugin", None)
            if not isinstance(plugin_class, type):
                raise PluginLoadError("入口模块缺少 class Plugin")
            instance = plugin_class()
            if not isinstance(instance, PluginBase):
                self._logger.warning(
                    "插件 %s 的 Plugin 未继承 PluginBase，仅按鸭子类型调用钩子", manifest.id
                )
            on_load = getattr(instance, "on_load", None)
            if not callable(on_load):
                raise PluginLoadError("Plugin 缺少 on_load(api) 方法")
            record.instance = instance
            record.api = PluginAPI(
                plugin_id=manifest.id,
                data_dir=self._data_dir / manifest.id,
                logger=self._plugin_logger(manifest.id),
                notifier=self._deliver_notification,
                signal_emitter=self._emit_plugin_signal,
                state_setter=self._on_plugin_state,
                host_version=APP_VERSION,
            )
            on_load(record.api)
            record.loaded = True
            self._logger.info(
                "插件已加载：%s %s（%s）", manifest.id, manifest.version, record.path
            )
        except Exception as exc:
            record.error = f"加载失败：{type(exc).__name__}: {exc}"
            self._logger.exception("插件加载失败：%s", manifest.id)
            self._cleanup(record)

    def _unload(self, record: PluginRecord) -> None:
        if record.loaded and record.instance is not None:
            self._invoke(record, "on_unload")
        self._cleanup(record)

    def _cleanup(self, record: PluginRecord) -> None:
        record.loaded = False
        record.ui_state = {}
        record.instance = None
        record.api = None
        self._purge_modules(record)
        record.module_name = None

    def _entry_path(self, record: PluginRecord) -> Path | None:
        manifest = record.manifest
        if manifest is None:
            return None
        candidate = _safe_resolve(record.path / manifest.entry)
        if not candidate.is_relative_to(record.path):
            record.error = "入口文件不在插件目录内"
            self._logger.warning("%s：%s", manifest.id, record.error)
            return None
        if not candidate.is_file():
            record.error = f"入口文件不存在：{manifest.entry}"
            self._logger.warning("%s：%s", manifest.id, record.error)
            return None
        return candidate

    def _import_entry(self, record: PluginRecord, entry: Path) -> ModuleType:
        manifest = record.manifest
        plugin_id = manifest.id if manifest is not None else record.plugin_id
        self._module_seq += 1
        safe_id = re.sub(r"[^0-9A-Za-z_]", "_", plugin_id)
        module_name = f"_shenqing_plugin_{safe_id}_{self._module_seq}"
        spec = importlib.util.spec_from_file_location(module_name, entry)
        if spec is None or spec.loader is None:
            raise PluginLoadError(f"无法为 {entry} 创建 import spec")
        module = importlib.util.module_from_spec(spec)
        sys.modules[module_name] = module
        plugin_dir = str(record.path)
        inserted = plugin_dir not in sys.path
        if inserted:
            sys.path.insert(0, plugin_dir)
        try:
            spec.loader.exec_module(module)
        finally:
            if inserted:
                try:
                    sys.path.remove(plugin_dir)
                except ValueError:
                    pass
        return module

    def _purge_modules(self, record: PluginRecord) -> None:
        """清理插件主模块，以及插件目录里被 import 的同级模块。"""
        names: set[str] = set()
        if record.module_name:
            names.add(record.module_name)
        base = record.path
        for name, module in list(sys.modules.items()):
            file = getattr(module, "__file__", None)
            if not file:
                continue
            try:
                path = Path(file).resolve()
            except OSError:  # pragma: no cover - 极端文件系统错误
                continue
            if path == base or base in path.parents:
                names.add(name)
        for name in names:
            sys.modules.pop(name, None)

    # ================= 内部：钩子调用 =================
    def _invoke(self, record: PluginRecord, hook: str, *args: Any) -> bool:
        instance = record.instance
        if instance is None:
            return False
        func = getattr(instance, hook, None)
        if not callable(func):
            return False
        try:
            func(*args)
            return True
        except Exception:
            self._logger.exception(
                "插件 %s 的 %s 抛出异常（已忽略）", record.plugin_id, hook
            )
            return False

    # ================= 内部：设置 / 通知 / 信号 =================
    def _read_disabled(self) -> set[str]:
        try:
            raw = self._settings.get(DISABLED_PLUGINS_KEY, [])
        except Exception:
            self._logger.exception("读取 disabled_plugins 失败")
            return set()
        if not isinstance(raw, (list, tuple, set)):
            return set()
        return {str(item) for item in raw if isinstance(item, str) and item}

    def _save_disabled(self) -> None:
        disabled = self._read_disabled()
        for record in self._records.values():
            manifest = record.manifest
            if manifest is None:
                continue
            if record.enabled:
                disabled.discard(manifest.id)
            else:
                disabled.add(manifest.id)
        try:
            self._settings.set(DISABLED_PLUGINS_KEY, sorted(disabled))
        except Exception:
            self._logger.exception("保存插件启用状态失败")

    def _on_plugin_state(self, plugin_id: str, state: dict) -> None:
        """记录插件上报的 UI 状态，并通知宿主刷新（例如刷新插件列表 UI）。"""
        with self._lock:
            record = self._find(plugin_id)
            if record is None:
                return
            record.ui_state = dict(state)
        listener = self._state_listener
        if listener is not None:
            try:
                listener(plugin_id, dict(state))
            except Exception:  # noqa: BLE001 - 宿主回调失败不影响插件
                self._logger.exception("插件状态回调失败：%s", plugin_id)

    def _deliver_notification(self, title: str, body: str) -> None:
        with self._lock:
            notifier = self._notifier
        if notifier is not None:
            notifier(title, body)
        else:
            tray_notify(title, body)

    def _emit_plugin_signal(self, plugin_id: str, name: str, payload: Any) -> None:
        with self._lock:
            listeners = list(self._signal_listeners)
        self._logger.debug("插件信号 %s.%s = %r", plugin_id, name, payload)
        for listener in listeners:
            try:
                listener(plugin_id, name, payload)
            except Exception:
                self._logger.exception("插件信号监听器抛出异常（已忽略）")

    # ================= 内部：杂项 =================
    def _find(self, plugin_id: str) -> PluginRecord | None:
        for record in self._records.values():
            if record.plugin_id == plugin_id:
                return record
        return None

    def _plugin_logger(self, plugin_id: str) -> logging.Logger:
        return logging.getLogger(f"shenqing.plugins.{plugin_id}")

    def _summary_text(self) -> str:
        total = len(self._records)
        loaded = sum(1 for record in self._records.values() if record.loaded)
        failed = sum(1 for record in self._records.values() if record.error)
        return f"共 {total} 个，已加载 {loaded} 个，异常 {failed} 个"
