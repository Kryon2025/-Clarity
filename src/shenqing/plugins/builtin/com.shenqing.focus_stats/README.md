# 专注统计（com.shenqing.focus_stats）

内置示例插件：按空间累计专注次数与分钟数，数据只写在插件自己的 settings.json 里。

## 它做了什么

| 钩子 | 行为 |
| --- | --- |
| on_load | 读出现有统计，记一条「累计 N 次 / M 分钟」日志 |
| on_session_end | 按 space_id 累加 sessions / minutes，同时更新 totals 与 last_session |
| get_summary | 返回 `{totals, spaces, last_session}`，空间按分钟数降序，方便以后接统计 UI |

## 数据位置

`%APPDATA%\ShenQing\plugin_data\com.shenqing.focus_stats\settings.json`

## 给宿主 / UI 用

```python
manager = PluginManager(settings)
plugin = manager.get_plugin("com.shenqing.focus_stats")
if plugin is not None:
    summary = plugin.get_summary()
```

## 说明

- 宿主没有传 `space_id` 时会退回用空间名当键（`summary.get("space")`）；
- 只有启用状态下才会记录；停用只影响后续，历史数据保留；
- 卸载插件不会删除 `plugin_data` 里的数据。
