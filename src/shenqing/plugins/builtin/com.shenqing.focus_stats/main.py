r"""专注统计插件：按空间累计会话次数、分钟数，只写插件自己的 settings.json。

数据结构（%APPDATA%\ShenQing\plugin_data\com.shenqing.focus_stats\settings.json）::

    {
      "stats": {
        "spaces": {
          "sp_xxx": {"name": "工作学习", "sessions": 3, "minutes": 135.0}
        },
        "totals": {"sessions": 3, "minutes": 135.0},
        "last_session": {"space": "工作学习", "minutes": 45.0, "at": "..."}
      }
    }

以后接 UI 时，宿主用 manager.get_plugin("com.shenqing.focus_stats").get_summary()
就能拿到整理好的聚合数据，不必解析原始 JSON。
"""

from __future__ import annotations

from datetime import datetime
from typing import Any

from shenqing.plugins.api import PluginAPI, PluginBase


def _as_int(value: Any, fallback: int = 0) -> int:
    try:
        return int(value)
    except (TypeError, ValueError):
        return fallback


def _as_float(value: Any, fallback: float = 0.0) -> float:
    try:
        return float(value)
    except (TypeError, ValueError):
        return fallback


class Plugin(PluginBase):
    """专注统计插件：on_session_end 时累加，get_summary() 给 UI 用。"""

    def __init__(self) -> None:
        self._api: PluginAPI | None = None

    def on_load(self, api: PluginAPI) -> None:
        self._api = api
        totals = self.get_summary()["totals"]
        api.log(
            "专注统计插件已加载：累计 %d 次 / %.1f 分钟"
            % (_as_int(totals.get("sessions")), _as_float(totals.get("minutes")))
        )

    def on_session_end(self, summary: dict) -> None:
        api = self._api
        if api is None:
            return
        data = self._load_stats()
        space_id = str(summary.get("space_id") or summary.get("space") or "unknown")
        space_name = str(summary.get("space_name") or summary.get("space") or space_id)
        minutes = max(0.0, _as_float(summary.get("minutes")))
        entry = data["spaces"].setdefault(
            space_id, {"name": space_name, "sessions": 0, "minutes": 0.0}
        )
        if space_name:
            entry["name"] = space_name
        entry["sessions"] = _as_int(entry.get("sessions")) + 1
        entry["minutes"] = round(_as_float(entry.get("minutes")) + minutes, 1)
        data["totals"]["sessions"] = _as_int(data["totals"].get("sessions")) + 1
        data["totals"]["minutes"] = round(
            _as_float(data["totals"].get("minutes")) + minutes, 1
        )
        data["last_session"] = {
            "space": space_name,
            "space_id": space_id,
            "minutes": round(minutes, 1),
            "at": datetime.now().isoformat(timespec="seconds"),
        }
        api.set_setting("stats", data)
        api.log("已记录 %s：%.1f 分钟" % (space_name, minutes))

    def get_summary(self) -> dict:
        """供 UI 使用的聚合数据：总数 + 按分钟数降序的空间列表 + 最近一次会话。"""
        data = self._load_stats()
        spaces: list[dict] = []
        for space_id, entry in data["spaces"].items():
            spaces.append(
                {
                    "space_id": space_id,
                    "name": entry["name"],
                    "sessions": entry["sessions"],
                    "minutes": entry["minutes"],
                }
            )
        spaces.sort(key=lambda item: (-float(item["minutes"]), str(item["space_id"])))
        return {
            "totals": dict(data["totals"]),
            "spaces": spaces,
            "last_session": dict(data["last_session"]),
        }

    def _load_stats(self) -> dict:
        empty: dict = {
            "spaces": {},
            "totals": {"sessions": 0, "minutes": 0.0},
            "last_session": {},
        }
        api = self._api
        if api is None:
            return empty
        raw = api.get_setting("stats", {})
        if not isinstance(raw, dict):
            return empty
        spaces: dict[str, dict] = {}
        spaces_raw = raw.get("spaces")
        if isinstance(spaces_raw, dict):
            for space_id, item in spaces_raw.items():
                if not isinstance(item, dict):
                    continue
                spaces[str(space_id)] = {
                    "name": str(item.get("name", "")),
                    "sessions": _as_int(item.get("sessions")),
                    "minutes": round(_as_float(item.get("minutes")), 1),
                }
        totals_raw = raw.get("totals")
        totals = {"sessions": 0, "minutes": 0.0}
        if isinstance(totals_raw, dict):
            totals["sessions"] = _as_int(totals_raw.get("sessions"))
            totals["minutes"] = round(_as_float(totals_raw.get("minutes")), 1)
        last_raw = raw.get("last_session")
        last_session = last_raw if isinstance(last_raw, dict) else {}
        return {"spaces": spaces, "totals": totals, "last_session": last_session}
