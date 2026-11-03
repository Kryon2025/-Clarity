# 遮罩组件模板（com.example.widget）

最小遮罩组件插件：在重度锁机全屏遮罩上放一个专注倒计时小组件。

## 用法

1. 复制整个目录到 `%APPDATA%\ShenQing\plugins\`（或开发期的 `<仓库根>/plugins/`）；
2. 改 `plugin.json` 里的 `id` / `name`；
3. 校验：`python -m shenqing.plugins.validate <插件目录>`；
4. 重启深清，在「设置 → 插件」启用「遮罩组件模板」，开始一段重度专注即可看到组件。

## 文件

| 文件 | 说明 |
| --- | --- |
| plugin.json | 清单（见 sdk/plugin.schema.json） |
| main.py | 入口，注册组件 + 上报状态 |
| qml/Widget.qml | 遮罩组件（根元素 Item） |

## 组件注册

```python
api.register_widget(
    "countdown",                 # 插件内唯一 id
    "专注倒计时",                 # 标题
    "qml/Widget.qml",            # 插件目录内的 .qml
    anchor="topRight",           # topLeft / topCenter / topRight / ...
    width=280,
    height=160,
)
```

- 尺寸范围：宽 80-1920、高 40-1080，超出会被吸附到边界；
- 路径限制在插件目录内，不能写 `..` 或绝对路径；
- `api.set_ui_state({...})` 用于让宿主展示插件状态（不落盘），示例里做了 5 秒限频。
