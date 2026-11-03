# 基础插件模板（com.example.basic）

最小可跑插件：注册一个导航入口页，并在专注开始 / 结束时上报插件状态。

## 用法

1. 复制整个目录到 `%APPDATA%\ShenQing\plugins\`（或开发期的 `<仓库根>/plugins/`）；
2. 改 `plugin.json` 里的 `id` / `name`（id 全局唯一，建议反向域名）；
3. 校验：`python -m shenqing.plugins.validate <插件目录>`；
4. 重启深清，或在「设置 → 插件」点「重新加载插件」。

## 文件

| 文件 | 说明 |
| --- | --- |
| plugin.json | 清单（见 sdk/plugin.schema.json） |
| main.py | 入口，定义 class Plugin |
| qml/Main.qml | 导航入口页面（可换成任意 QML） |

## 说明

- 导航入口通过 `api.register_nav_item("home", "基础插件", qml_relative_path="qml/Main.qml")` 注册；
- qml 路径限制在插件目录内，不能写 `..` 或绝对路径；
- `api.set_ui_state({...})` 只影响宿主展示，不落盘，卸载即清空。
