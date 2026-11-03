"""基础插件模板：注册一个导航入口，并在会话开始时上报插件状态。

复制这个目录到 %APPDATA%\ShenQing\plugins\ 下，改 plugin.json 的 id / name，
再按自己的需求改 qml/Main.qml 即可。
"""

from __future__ import annotations

from shenqing.plugins.api import PluginAPI, PluginBase


class Plugin(PluginBase):
    """插件入口类（必须叫 Plugin，并继承 PluginBase）。"""

    def on_load(self, api: PluginAPI) -> None:
        self.api = api
        ok = api.register_nav_item(
            "home",
            "基础插件",
            icon_name="ic_fluent_apps_24_regular",
            qml_relative_path="qml/Main.qml",
        )
        api.log(f"基础插件已加载，导航入口注册{'成功' if ok else '失败'}")

    def on_session_start(self, space: dict) -> None:
        self.api.set_ui_state(
            {
                "summary": f"正在专注：{space.get('name', '')}",
                "space": space.get("name", ""),
            }
        )

    def on_session_end(self, summary: dict) -> None:
        self.api.set_ui_state(
            {
                "summary": f"最近一次：{summary.get('minutes', 0)} 分钟",
                "minutes": summary.get("minutes", 0),
            }
        )
