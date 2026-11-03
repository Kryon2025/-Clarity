"""CW2 全屏组件插件：向深清的全屏遮罩注册小组件。

组件注册通过 api.register_widget(...)，宿主把 QML 按 anchor 放到遮罩角落。
默认不启用（manifest 的 default_enabled=false），用户可在「插件」页打开。
"""

from __future__ import annotations

from typing import Any

from shenqing.plugins.api import PluginAPI, PluginBase

WIDGETS = [
    {
        "id": "clock",
        "title": "时钟",
        "qml": "widgets/clock.qml",
        "anchor": "topLeft",
        "width": 240,
        "height": 108,
    },
    {
        "id": "quote",
        "title": "专注提示牌",
        "qml": "widgets/quote.qml",
        "anchor": "bottomLeft",
        "width": 360,
        "height": 96,
    },
]


class Plugin(PluginBase):
    def on_load(self, api: PluginAPI) -> None:
        self.api = api
        registered = 0
        for widget in WIDGETS:
            try:
                try:
                    ok = api.register_widget(
                        widget["id"],
                        widget["title"],
                        widget["qml"],
                        anchor=widget["anchor"],
                        width=widget["width"],
                        height=widget["height"],
                    )
                except TypeError:
                    ok = api.register_widget(widget["id"], widget["title"], widget["qml"])
            except Exception as exc:  # noqa: BLE001
                api.log(f"注册组件 {widget['id']} 失败：{exc}")
                ok = False
            registered += int(bool(ok))
        api.log(f"CW2 组件插件已加载，注册 {registered}/{len(WIDGETS)} 个组件")

    def on_unload(self) -> None:
        pass
