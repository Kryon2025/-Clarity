# 你好，深清（com.shenqing.hello）

内置最小示例插件，演示深清插件系统的最小闭环：加载时打招呼 → 专注结束时记录一条数据 → 卸载时收尾。

## 它做了什么

| 钩子 | 行为 |
| --- | --- |
| on_load | api.log + api.notify；加载次数累加进 load_count |
| on_session_end | 把每次专注的「空间 / 分钟数 / 是否完成」追加到 records（最多保留 100 条） |
| on_unload | 记一条卸载日志 |

## 数据位置

`%APPDATA%\ShenQing\plugin_data\com.shenqing.hello\settings.json`

## 怎么停用

设置 → 插件 → 关闭「你好，深清」；或直接把它写进宿主
`%APPDATA%\ShenQing\settings.json` 的 `disabled_plugins` 数组。

## 适合拿来抄的地方

- 入口类固定叫 `Plugin`，放在 `main.py` 顶层；
- `on_load` 里保存 `api`，后续钩子通过它读写设置；
- 钩子里抛出的异常会被 manager 捕获并写日志，不会拖垮主程序。
