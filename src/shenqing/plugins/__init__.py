"""深清插件系统。

对外只需要从这里导入：:

    from shenqing.plugins import PluginManager, PluginBase, PluginAPI

- PluginBase：插件入口基类（钩子全为空实现）；
- PluginAPI：on_load 里拿到的宿主 API（设置 / 通知 / 日志 / 信号 /
  导航入口 / 遮罩组件 / UI 状态）；
- PluginManager：扫描、加载、启用 / 停用、事件分发与热重载；
- PluginManifest：plugin.json 的解析与校验。
"""

from __future__ import annotations

from .api import (
    PLUGIN_API_VERSION,
    WIDGET_ANCHORS,
    ManifestError,
    PluginAPI,
    PluginBase,
    PluginManifest,
    tray_notify,
)
from .manager import (
    DEFAULTS_APPLIED_KEY,
    DISABLED_PLUGINS_KEY,
    EVENT_HOOKS,
    PLUGINS_DIR_ENV,
    PluginManager,
    resolve_relative_path,
)

__all__ = [
    "DEFAULTS_APPLIED_KEY",
    "DISABLED_PLUGINS_KEY",
    "EVENT_HOOKS",
    "PLUGIN_API_VERSION",
    "PLUGINS_DIR_ENV",
    "WIDGET_ANCHORS",
    "ManifestError",
    "PluginAPI",
    "PluginBase",
    "PluginManager",
    "PluginManifest",
    "resolve_relative_path",
    "tray_notify",
]
