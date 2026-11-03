"""遮罩组件模板：注册一个专注倒计时小组件，并定期上报插件状态。

复制这个目录到 %APPDATA%\ShenQing\plugins\ 下，改 plugin.json 的 id / name，
再按自己的需求改 qml/Widget.qml 即可。
"""

from __future__ import annotations

from shenqing.plugins.api import PluginAPI, PluginBase


class Plugin(PluginBase):
    """插件入口类（必须叫 Plugin，并继承 PluginBase）。"""

    def __init__(self) -> None:
        self._last_bucket = -1

    def on_load(self, api: PluginAPI) -> None:
        self.api = api
        ok = api.register_widget(
            "countdown",
            "专注倒计时",
            "qml/Widget.qml",
            anchor="topRight",
            width=280,
            height=160,
        )
        api.log(f"组件模板已加载，遮罩组件注册{'成功' if ok else '失败'}")

    def on_session_start(self, space: dict) -> None:
        self.api.set_ui_state(
            {"summary": "专注中", "space": space.get("name", "")}
        )

    def on_tick(self, remaining_seconds: int) -> None:
        # 每秒都会回调；UI 状态限频到 5 秒一次，避免宿主频繁刷新
        bucket = int(remaining_seconds) // 5
        if bucket == self._last_bucket:
            return
        self._last_bucket = bucket
        self.api.set_ui_state(
            {
                "summary": "剩余 %02d:%02d"
                % (remaining_seconds // 60, remaining_seconds % 60),
                "remaining": int(remaining_seconds),
            }
        )

    def on_session_end(self, summary: dict) -> None:
        self._last_bucket = -1
        self.api.set_ui_state(
            {"summary": "已结束", "minutes": summary.get("minutes", 0)}
        )
