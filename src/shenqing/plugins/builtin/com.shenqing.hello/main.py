"""最小示例插件：加载时打招呼，专注结束时记一条记录。

这个插件同时也是 docs/插件开发.md 里的参考实现：
只覆写 on_load / on_session_end / on_unload 三个钩子，其余用 PluginBase 默认实现。
"""

from __future__ import annotations

from datetime import datetime

from shenqing.plugins.api import PluginAPI, PluginBase

#: 最多保留多少条记录，避免 settings.json 无限增长
MAX_RECORDS = 100


class Plugin(PluginBase):
    """深清插件入口类，必须叫 Plugin。"""

    def __init__(self) -> None:
        self._api: PluginAPI | None = None

    def on_load(self, api: PluginAPI) -> None:
        self._api = api
        count = int(api.get_setting("load_count", 0)) + 1
        api.set_setting("load_count", count)
        api.log(f"你好插件已加载（第 {count} 次）")
        api.notify("深清插件", "你好插件已加载：专注结束时我会记一条记录。")

    def on_unload(self) -> None:
        if self._api is not None:
            self._api.log("你好插件已卸载")

    def on_session_end(self, summary: dict) -> None:
        api = self._api
        if api is None:
            return
        records = api.get_setting("records", [])
        if not isinstance(records, list):
            records = []
        records = [item for item in records if isinstance(item, dict)]
        space_name = summary.get("space_name") or summary.get("space") or "空间"
        records.append(
            {
                "at": datetime.now().isoformat(timespec="seconds"),
                "space": str(space_name),
                "minutes": float(summary.get("minutes", 0.0)),
                "completed": bool(summary.get("completed", False)),
            }
        )
        api.set_setting("records", records[-MAX_RECORDS:])
        api.log(f"记录一条专注：{space_name} {summary.get('minutes', 0)} 分钟")
