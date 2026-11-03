# CW2 全屏组件（com.shenqing.cw2widgets）

把 Class Widgets 2 风格的桌面组件搬到深清「全屏专注遮罩」上。

- 默认状态：**安装但不启用**（plugin.json 的 `default_enabled: false`），在深清「插件」页打开即可。
- 当前组件：
  - 时钟（左上，HH:mm + 日期）
  - 专注提示牌（左下，可自行改文案）
- 注册方式：`api.register_widget(id, title, qml相对路径, anchor=topLeft|topRight|bottomLeft|bottomRight, width, height)`
- 想加组件：在 `widgets/` 放一个 QML 根 Item，然后在 `main.py` 的 `WIDGETS` 列表里加一项。
