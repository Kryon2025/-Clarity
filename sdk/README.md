# 深清插件 SDK

> 适用：深清 0.1.x ｜ 插件 API 版本 **0.1**
>
> 本文从零讲清楚怎么写一个深清插件：目录、清单、生命周期钩子、PluginAPI、
> 导航入口与遮罩组件、打包安装、调试与安全边界。配套文件：
> [plugin.schema.json](plugin.schema.json)、[templates/basic-plugin](../templates/basic-plugin/)、
> [templates/widget-plugin](../templates/widget-plugin/)。

插件就是**一个目录 + 一份 plugin.json + 一个入口 Python 文件**。宿主扫描到目录后，
按 manifest 的 entry 加载入口文件，实例化里面名为 `Plugin` 的类，然后按事件调用钩子。
插件与宿主同进程运行，安装插件 = 信任这份本地代码（见「安全边界」）。

## 0. 快速开始（2 分钟）

1. 复制模板：`templates/basic-plugin` → `%APPDATA%\ShenQing\plugins\com.example.basic`
   （开发期也可以放到仓库根的 `plugins/` 下，免安装）；
2. 改 `plugin.json` 的 `id` 与 `name`（id 必须全局唯一，建议反向域名）；
3. 校验：

   ```powershell
   cd 深清
   $env:PYTHONPATH = "src"
   python -m shenqing.plugins.validate "$env:APPDATA\ShenQing\plugins\com.example.basic"
   ```

4. 重启深清，或在「设置 → 插件」点「重新加载插件」；插件默认启用。

## 1. 目录结构

```text
com.example.myplugin/
├─ plugin.json          # 清单（必须，见第 2 节）
├─ main.py              # 入口（默认；可在 entry 里改）
├─ icon.png             # 可选：插件图标（manifest.icon）
├─ qml/
│  ├─ Main.qml          # 可选：导航入口页面
│  └─ Widget.qml        # 可选：全屏遮罩组件
└─ README.md            # 可选：给用户看的说明
```

规则：

- 只有「直接包含 `plugin.json` 的子目录」才会被扫描，嵌套目录不算插件；
- 入口文件和 QML 图标等资源都必须在插件目录内，**禁止** `..`、绝对路径、盘符路径；
- 插件数据不写在代码目录里，而在 `%APPDATA%\ShenQing\plugin_data\<插件 id>\settings.json`，
  升级 / 重装 / 删除插件代码都不会丢数据；
- 入口文件可以 import 同目录的其它 `.py`（加载时插件目录会临时加入 `sys.path`）。

## 2. plugin.json 字段

完整 JSON Schema 见 [plugin.schema.json](plugin.schema.json)。

| 字段 | 必填 | 类型 | 说明 |
| --- | --- | --- | --- |
| `id` | 是 | string | 唯一 id，建议反向域名；字母/数字/点/下划线/短横线，最长 128，含 `..` 不合法 |
| `name` | 是 | string | 显示名 |
| `version` | 是 | string | 插件版本，如 `1.0.0` |
| `api_version` | 是 | string | 依赖的插件 API 版本，如 `0.1`；主版本必须与宿主一致 |
| `entry` | 是 | string | 入口相对路径，必须是插件目录内的 `.py`，通常 `main.py` |
| `author` | 否 | string | 作者 |
| `description` | 否 | string | 一句话说明，显示在插件页 |
| `homepage` | 否 | string | 主页 / 仓库地址 |
| `icon` | 否 | string | 图标相对路径，如 `icon.png`（建议 PNG/SVG，64-256 边长） |
| `default_enabled` | 否 | bool | 默认 `true`；`false` 表示**安装后默认停用**，用户在插件页手动启用，且之后不会被自动关掉 |

最小示例：

```json
{
  "id": "com.example.hello",
  "name": "你好",
  "version": "1.0.0",
  "api_version": "0.1",
  "entry": "main.py"
}
```

## 3. 入口类与 7 个生命周期钩子

入口模块顶层必须定义名为 `Plugin`、继承 `PluginBase` 的类：

```python
from shenqing.plugins.api import PluginAPI, PluginBase


class Plugin(PluginBase):
    ...
```

| 钩子 | 触发时机 | 参数 |
| --- | --- | --- |
| `on_load(api)` | 插件加载 / 启用时一次（注册 UI 贡献放这里） | `PluginAPI` |
| `on_unload()` | 停用 / 热重载前 / 程序退出前 | — |
| `on_session_start(space)` | 开始专注 | `space` 空间字典 |
| `on_session_end(summary)` | 专注结束（自然结束或提前结束） | `summary` 会话摘要 |
| `on_process_blocked(exe)` | 守护进程结束一个干扰程序 | `exe` 进程名，如 `game.exe` |
| `on_tick(remaining_seconds)` | 专注中每秒一次 | 剩余秒数 |
| `on_settings_changed(key, value)` | 宿主设置项变化 | 设置键 / 值 |

参数结构：

```json
// space
{"id": "sp_xxx", "name": "工作学习", "minutes": 45, "atmosphere": "秩序",
 "allowed_apps": ["wechat.exe"], "super": false}

// summary（字段按宿主版本可能增减，插件要容忍缺失）
{"space_id": "sp_xxx", "space_name": "工作学习", "space": "工作学习",
 "minutes": 45.0, "completed": true, "pauses": 0}
```

约定：钩子都在宿主主线程按事件调用，**不要阻塞**（`on_tick` 每秒都来），也不要在插件里起
常驻线程 / while 循环。钩子抛异常只影响自己：宿主记日志并继续，但你的逻辑会中断。

## 4. PluginAPI 全表

`on_load(api)` 拿到的对象；所有方法都不会向插件抛异常（失败记日志并返回默认值）。

| 方法 | 返回 | 说明 |
| --- | --- | --- |
| `log(message)` | — | 写插件日志（logger `shenqing.plugins.<id>`，INFO） |
| `get_setting(key, default=None)` | Any | 读插件设置，返回深拷贝 |
| `set_setting(key, value)` | bool | 写插件设置并立即落盘；value 必须可 JSON 序列化 |
| `notify(title, body)` | — | 系统通知（宿主未接托盘时只写日志） |
| `emit_signal(name, payload)` | — | 向宿主发插件信号，签名 `(plugin_id, name, payload)` |
| `register_nav_item(item_id, title, icon_name="", qml_relative_path=None)` | bool | 注册导航入口 |
| `register_widget(widget_id, title, qml_relative_path, anchor="topRight", width=280, height=160)` | bool | 注册全屏遮罩组件 |
| `set_ui_state(state)` | bool | 上报插件展示状态（字典，JSON 可序列化，不落盘） |
| `host_version()` | str | 宿主版本号，如 `0.1.0` |
| `plugin_id` / `data_dir` / `settings_path` | str / Path | 只读信息 |

`register_nav_page` 是旧版预留名，0.1 请用 `register_nav_item`。

## 5. UI 贡献

### 5.1 导航入口 register_nav_item

```python
api.register_nav_item(
    "home",                          # 插件内唯一 id
    "我的插件",                       # 标题
    icon_name="ic_fluent_apps_24_regular",  # 可空
    qml_relative_path="qml/Main.qml",       # 可空：空则入口只跳到插件卡片
)
```

- `qml_relative_path` 必须是插件目录内的 `.qml`，越界 / 不存在 / 后缀不对都会返回 `False`；
- `icon_name` 还有兼容别名 `icon`（`api.register_nav_item("id", "标题", icon="tomato")`），
  两者都传时以 `icon_name` 为准；
- 同一插件内 `itemId` 不能重复，重复注册返回 `False`（不会覆盖）；
- 宿主通过 `manager.list_nav_items()` 拿到扁平列表：

  ```python
  [{"pluginId": "com.example.basic",
    "itemId": "home",
    "title": "基础插件",
    "icon": "ic_fluent_apps_24_regular",
    "qmlPath": "F:\\...\\com.example.basic\\qml\\Main.qml"}]
  ```

  `qmlPath` 是绝对路径；空字符串 `""` 表示该入口没有页面（只跳插件卡片）。

### 5.2 遮罩组件 register_widget

```python
api.register_widget(
    "countdown",            # 插件内唯一 id
    "专注倒计时",            # 标题
    "qml/Widget.qml",       # 插件目录内的 .qml（必填）
    anchor="topRight",      # 九宫格锚点
    width=280,              # 80-1920，超出吸附
    height=160,             # 40-1080，超出吸附
)
```

- anchor 可选：`topLeft` `topCenter` `topRight` `centerLeft` `center` `centerRight`
  `bottomLeft` `bottomCenter` `bottomRight`；
- 宿主只负责按 anchor / width / height 把 QML 放进全屏遮罩（重度锁机的遮罩层），
  组件 QML 的根元素必须是 `Item`，样式自己画；
- `manager.list_widgets()` 返回：

  ```python
  [{"pluginId": "com.shenqing.cw2widgets",
    "itemId": "clock",
    "title": "时钟",
    "icon": "",
    "qmlPath": "F:\\...\\com.shenqing.cw2widgets\\widgets\\clock.qml",
    "anchor": "topLeft",
    "width": 240,
    "height": 108}]
  ```

### 5.3 插件状态 set_ui_state

```python
api.set_ui_state({"summary": "专注中 12:34", "remaining": 754})
```

宿主把它原样挂在插件记录的 `state` 字段里（`manager.list_plugins()[i]["state"]`），
用于插件卡片 / 设置页展示。状态**不落盘**，插件卸载 / 重载时清空。
频繁调用会触发宿主刷新，`on_tick` 里建议限频（见组件模板）。

## 6. 完整示例：入口页 + 遮罩组件

目录：

```text
com.example.focus_toys/
├─ plugin.json
├─ main.py
└─ qml/
   ├─ Main.qml
   └─ Widget.qml
```

`plugin.json`：

```json
{
  "id": "com.example.focus_toys",
  "name": "专注小玩具",
  "version": "1.0.0",
  "api_version": "0.1",
  "entry": "main.py",
  "description": "带入口页和遮罩组件的完整示例"
}
```

`main.py`：

```python
from shenqing.plugins.api import PluginAPI, PluginBase


class Plugin(PluginBase):
    def __init__(self) -> None:
        self._last_bucket = -1

    def on_load(self, api: PluginAPI) -> None:
        self.api = api
        api.register_nav_item("home", "专注小玩具", qml_relative_path="qml/Main.qml")
        api.register_widget(
            "remaining",
            "剩余时间",
            "qml/Widget.qml",
            anchor="topRight",
            width=300,
            height=140,
        )

    def on_session_start(self, space: dict) -> None:
        self.api.set_ui_state({"summary": f"专注：{space.get('name', '')}"})

    def on_tick(self, remaining_seconds: int) -> None:
        bucket = remaining_seconds // 5
        if bucket == self._last_bucket:
            return
        self._last_bucket = bucket
        self.api.set_ui_state(
            {"summary": "剩余 %02d:%02d" % (remaining_seconds // 60, remaining_seconds % 60)}
        )

    def on_session_end(self, summary: dict) -> None:
        self._last_bucket = -1
        self.api.set_ui_state({"summary": f"完成 {summary.get('minutes', 0)} 分钟"})
```

`qml/Main.qml`（根元素 Item）：

```qml
import QtQuick

Item {
    Rectangle {
        anchors.fill: parent
        color: "#0B1220"
        radius: 18
        Text {
            anchors.centerIn: parent
            color: "#F2F6FF"
            font.pixelSize: 24
            text: "专注小玩具"
        }
    }
}
```

`qml/Widget.qml`（根元素 Item，宿主决定位置和尺寸）：

```qml
import QtQuick

Item {
    Rectangle {
        anchors.fill: parent
        color: "#14FFFFFF"
        radius: 16
        border.width: 1
        border.color: "#33FFFFFF"
    }
    Text {
        anchors.centerIn: parent
        color: "#F2FAFF"
        font.pixelSize: 20
        text: "专注中"
    }
}
```

QML 约定：只用 `QtQuick` 基础组件最稳；宿主内容区 / 遮罩的自定义 import（如 RinUI）
在插件里不保证长期可用。

## 7. 打包与安装

插件就是目录，直接压缩分发即可：

```text
com.example.focus_toys.zip
└─ com.example.focus_toys/
   ├─ plugin.json
   ├─ main.py
   └─ qml/...
```

安装步骤：

1. 解压到 `%APPDATA%\ShenQing\plugins\`，保证 `...\plugins\com.example.focus_toys\plugin.json` 存在；
2. （推荐）先跑校验：`python -m shenqing.plugins.validate <插件目录>`；
3. 重启深清，或在「设置 → 插件」点「重新加载插件」；
4. 在插件页启用 / 停用。`default_enabled=false` 的插件首次安装是停用状态，
   用户手动启用后会记住，不会每次启动又被关掉。

打包前删掉 `__pycache__`；不要把 `plugin_data`（在 appdata 里）打进压缩包。

## 8. 调试与日志

- 日志文件：`%APPDATA%\ShenQing\logs\app.log`（1 MB 轮转，保留 3 份，带 traceback）；
- 插件日志用 `api.log("...")`，logger 名 `shenqing.plugins.<插件 id>`；
- 不要在插件里用 `print` 调试（GUI 打包后没有控制台）；
- 插件列表的 `error` 字段是加载错误；会话事件里的异常只写日志，不会让宿主崩溃；
- 命令行校验：

  ```powershell
  cd 深清
  $env:PYTHONPATH = "src"
  python -m shenqing.plugins.validate "D:\my-plugins\com.example.focus_toys"
  python -m shenqing.plugins.validate "D:\my-plugins\com.example.focus_toys" --json
  ```

  退出码 0 = 通过；1 = 有错误（清单非法 / API 不兼容 / entry 不存在）。

## 9. 错误与版本兼容

| 情况 | 结果 |
| --- | --- |
| plugin.json 非法 / 缺字段 / id 不合法 | 插件列表显示 `error`，不加载，其它插件照常 |
| `api_version` 主版本 ≠ 宿主主版本 | `error`「API 版本不兼容」，不执行代码 |
| entry 不存在 / 越界 / 不是 .py | `error`「入口文件不存在 / 不在插件目录内」 |
| 入口没有 class Plugin / on_load 抛异常 | `error`「加载失败」，清理已导入模块，可修复后重新启用 |
| 事件钩子抛异常 | 写异常日志，跳过该插件本次事件 |
| 注册 QML 越界 / 不存在 / id 重复 | 返回 `False`，写警告日志，其它注册不受影响 |

版本规则：宿主 `PLUGIN_API_VERSION = "0.1"`；插件清单 `api_version` 的主版本一致即可
（宿主 0.1 接受 0.x）。新增 API 只加不改；主版本升级会拒绝旧插件并给出 `error`。
`api.host_version()` 只用于展示 / 日志，不要拿它做兼容判断。

## 10. 安全边界

- 插件是**本地 Python 代码**，与宿主同进程、同权限：能读写文件、访问网络、调 Win32 API；
- 宿主没有沙箱、没有签名校验，**安装插件 = 信任它**；只装可信来源，装前读一遍代码；
- 插件在宿主主线程跑，死循环 / 阻塞会卡住整个界面；
- 插件设置是明文 JSON（`plugin_data\<id>\settings.json`），不要存密码 / token；
- 插件只能注册 UI 贡献（导航入口 / 遮罩组件），不能改宿主窗口或其它插件的数据；
- 卸载插件不会删除 `plugin_data`，需要彻底清理请手动删目录。

## 11. 参考文件

| 位置 | 内容 |
| --- | --- |
| [plugin.schema.json](plugin.schema.json) | plugin.json 的 JSON Schema |
| [templates/basic-plugin](../templates/basic-plugin/) | 带导航入口的最小模板 |
| [templates/widget-plugin](../templates/widget-plugin/) | 带遮罩组件的最小模板 |
| `src/shenqing/plugins/builtin/` | 内置示例：hello / focus_stats / cw2widgets（默认停用） |
| `docs/插件开发.md` | 宿主侧说明（事件、接线、打包注意事项） |
