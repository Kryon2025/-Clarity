<div align="right">
简体中文 | <a href="/docs/readme/README.en_US.md">English</a>
</div>

<p align="center">
  <img width="16%" align="center" src="docs/images/logo.png" alt="logo">
</p>
<h1 align="center">
  深清
</h1>
<p align="center">
  Clarity · 把这件事做完，再抬头
</p>

<div align="center">

[![星标](https://img.shields.io/github/stars/Kryon2025/Clarity?style=for-the-badge&color=orange&label=%E6%98%9F%E6%A0%87)](https://github.com/Kryon2025/Clarity)
[![当前版本](https://img.shields.io/github/v/release/Kryon2025/Clarity?style=for-the-badge&color=purple&label=%E5%BD%93%E5%89%8D%E7%89%88%E6%9C%AC)](https://github.com/Kryon2025/Clarity/releases/latest)
[![下载量](https://img.shields.io/github/downloads/Kryon2025/Clarity/total.svg?label=%E4%B8%8B%E8%BD%BD%E9%87%8F&color=green&style=for-the-badge)](https://github.com/Kryon2025/Clarity/releases)
[![License: GPLv3](https://img.shields.io/badge/License-GPLv3-blue.svg?style=for-the-badge&label=%E8%AE%B8%E5%8F%AF)](./LICENSE)
[![平台](https://img.shields.io/badge/%E5%B9%B3%E5%8F%B0-Windows%2010%2F11-0078D4?style=for-the-badge&logo=windows)](https://github.com/Kryon2025/Clarity/releases)
[![Python](https://img.shields.io/badge/Python-3.13-3776AB?style=for-the-badge&logo=python&logoColor=white)](https://www.python.org/)

</div>

> [!TIP]
> 深清只有一个空间「**清空间**」，分三档强度：**浅清 / 覆清 / 深清**。选好时长开始专注，时间没到不开门。
> 支持纯色 / 清空间浅色 / 液态玻璃三套主题，插件系统可以把番茄ToDo、CW2 组件等接进来。

![空间页](docs/images/v06_spaces_light.png)

## 特性

- **进入前 10 秒水滴倒计时**：水滴凭空出现、向圆心汇聚并凝结成发光圆环，进入时圆环扩散全屏；期间可随时取消（取消则水滴散开）；
- **Patina 式应用使用时长**：前台应用每 5 秒采样（自动跳过空闲/锁屏/休眠），分类与颜色可自定义，数据页看今日 / 本周 / 历史；
- **AI 助手**：支持免配置「免费直连」（无需 Key 直接聊天）、DeepSeek、小米 MiMo、ChatGPT、Groq、智谱 GLM、硅基流动与自定义接口；可自动获取模型列表、开启深度思考/联网搜索、保留对话历史并估算用量费用，异步问答、设置语义搜索，Key 只保存在本机；
- **进入动画 v2**：1200 个发光水光点从四周出现、持续向中心滚动汇聚，结束瞬间一道光波扩散变暗后进入专注；
- **今日专注卡片**：结束后水滴汇成光点展开卡片（Bing 壁纸背景、头像、每日一言、分享 / 保存 / 延长 20 分钟）；
- **睡眠模式「还清」**：多段锁定时间、提前 1h/30m/1m 提醒、每月解锁次数、点击时钟 10 次解锁；
- **联网校时 + 专注期间禁止熄屏/休眠**；覆清白名单应用前台时自动隐藏遮罩，任务栏全程隐藏；
- **新手引导**、dock 设置面板（音量 / 关机重启二次确认）、数据页 Patina 风格结构；
- **法语 / 日语**界面（AI 机器人自动翻译）；
- **GitHub 自动更新**：启动后自动检查新版本，关于页可手动检查 / 下载 / 安装；
- **三档空间**：浅清（屏蔽黑名单窗口与声音）/ 覆清（额外显示白名单应用 dock）/ 深清（白名单外全部屏蔽、不可提前结束、只显示倒计时）；
- **多空间**：浅清 / 覆清可新增多个空间，各自保存名称、锁定时长与白名单；深清固定一个空间，只能改时长；
- **浏览器式标签页**：空间页顶部三标签切换档位，下面两列卡片列表，卡片上直接改名 / 改时长 / 开始；
- **全屏专注遮罩**：左侧倒计时、右上灵动岛（SMTC 媒体控制）、覆清档右侧 dock；
- **主题系统**：纯色（默认）/ 清空间浅色 / 液态玻璃（实验性，长按拖拽高光）；
- **全局搜索**：窗口右上角常驻，搜空间 / 主题 / 模式 / 插件 / 设置（Ctrl+K）；
- **防退出加固**：锁定期间隐藏任务栏、屏蔽系统快捷键、每 500ms 重新置顶；结束自动恢复；
- **保活**：独立看门狗监控主进程，被杀约 2 秒自动拉起；新安装默认最高权限运行并登记最高权限开机自启；
- **不杀进程**：默认把干扰应用的窗口藏起来 + 静音，保留未保存的工作；
- **插件系统**：目录即装，插件可注册导航入口与全屏遮罩组件；内置「番茄同步」（番茄ToDo 数据互通）与默认停用的「CW2 全屏组件」；
- **国际化**：简体中文 / English / 日本語 / Français，GitHub Actions 自动抽取，并可用 AI 机器人自动翻译缺漏条目。

## 软件截图

| 覆清 · 空间卡片 | 深清 · 纯倒计时 |
| --- | --- |
| ![覆清](docs/images/v06_spaces_light.png) | ![深清](docs/images/v06_spaces_heavy.png) |

| 关于 · 更新日志 | 液态玻璃拖拽高光 |
| --- | --- |
| ![关于](docs/images/v06_about_cw2.png) | ![玻璃](docs/images/v04_glass_drag.png) |

| 进入前水滴凝聚成环 | 关于 · 检查更新 |
| --- | --- |
| ![水滴](docs/images/v06_enter_ring_complete.png) | ![更新](docs/images/v07_update_card.png) |

## 安装 & 使用

> [!IMPORTANT]
> 请到 [**Releases**](https://github.com/Kryon2025/Clarity/releases) 页面下载最新版本。

- **安装包**：下载 `ShenQing-Setup-x.y.z.exe`，双击安装（会请求管理员权限），安装完自动创建桌面 / 开始菜单快捷方式；安装时可勾选「最高权限开机自启」；
- **绿色版**：下载 `ShenQing-Portable-vx.y.z.zip`，解压后双击 `深清.exe` 即用，无需安装。

使用要点：

- 空间页选好档位与时长 → 点卡片右侧白色「**开始**」胶囊；深清卡为「开始深清」；
- 专注中按 **Ctrl+K** 全局搜索；深清档不可提前结束；
- 关闭主窗口只会收进托盘，真正退出请用托盘菜单「退出深清」或速启面板；
- 数据保存在 `%APPDATA%\ShenQing\`（空间、设置、插件、专注统计），不上传云端；
- 许可证：[LICENSE](./LICENSE)（GPL-3.0）；第三方组件与素材资源：[NOTICE](./NOTICE)。

## AI 助手

在 左侧导航「AI」页中：

1. 想零配置体验：选 **「免费直连（免配置）」**，不用 Key、选好模型即可对话；
2. 想用正式服务：选择 **DeepSeek**（deepseek-flash / deepseek-v4-pro）/ **小米 MiMo** / **ChatGPT** / **Groq** / **智谱 GLM** / **硅基流动** / **自定义**，点「刷新」自动获取该服务商的最新模型列表；
2. 填入对应平台的 API Key（Key 只保存在 `%APPDATA%\ShenQing\settings.json`，不会上传）；
3. 点「测试连接」确认可用；之后点右上角的 AI 图标即可提问。

AI 请求在后台线程执行，不阻塞界面；失败会自动提示并回退到本地设置模糊搜索。

## 更新日志

见 [CHANGELOG.md](./CHANGELOG.md)（应用内「关于」页也可查看完整更新日志）。

## 开发

```powershell
python -m pip install -r requirements.txt
python run.py                              # 从源码启动
python -m unittest discover -s tests -v    # 单元 / 集成测试
$env:QT_QPA_PLATFORM="offscreen"; $env:QT_QUICK_BACKEND="software"; python run.py --smoke
python scripts/i18n.py extract             # 抽取翻译（compile / check 同理）
```

打包：

```powershell
python -m PyInstaller --noconfirm --clean packaging/ShenQing.spec
iscc /DAppVersion=0.7.0 packaging/installer.iss   # 需要 Inno Setup 6，产出 dist\installer\*Setup*.exe
Compress-Archive -Path "dist/深清/*" -DestinationPath "dist/ShenQing-Portable-v0.7.0.zip" -Force
```

推送 `v*` 标签时，[release.yml](.github/workflows/release.yml) 会自动跑测试、打包绿色版与安装包，并把更新日志作为 Release 正文与附件发布。

## 插件开发

- SDK 说明：[sdk/README.md](./sdk/README.md)，清单 Schema：[sdk/plugin.schema.json](./sdk/plugin.schema.json)
- 文档：[docs/插件开发.md](./docs/插件开发.md)
- 模板：[`templates/basic-plugin`](./templates/basic-plugin)（注册导航入口）、[`templates/widget-plugin`](./templates/widget-plugin)（注册全屏组件）
- 校验：`python -m shenqing.plugins.validate <插件目录>`
- 安装：把插件目录 / zip 放到 `%APPDATA%\ShenQing\plugins\`，在「插件」页重新扫描即可。

## 反馈 & 贡献

- Bug 反馈 / 功能请求：[Issues](https://github.com/Kryon2025/Clarity/issues)（应用内「关于」页有直达按钮）
- 讨论：[Discussions](https://github.com/Kryon2025/Clarity/discussions)
- 欢迎提交 PR；提交前请跑通单元测试与冒烟。

## 协议

本项目（深清 / Clarity）以 **GNU General Public License v3.0（GPL-3.0-only）** 授权发布，详情见 [LICENSE](./LICENSE)。
第三方开源组件、素材与设计参考的许可证与说明见 [NOTICE](./NOTICE)。

Copyright © 2025 Kryon.

## 致谢

### 第三方库和框架

- [Qt](https://www.qt.io/) / [PySide6](https://doc.qt.io/qtforpython/)（LGPLv3）
- [RinUI](https://github.com/RinLit-233-shiroko/RinUI)（MIT）
- [pywin32](https://github.com/mhammond/pywin32)（PSF-2.0）
- [pycaw](https://github.com/AndreMiras/pycaw)（MIT）
- [pyinstaller](https://pyinstaller.org/)（打包工具）
- [Inno Setup](https://jrsoftware.org/isinfo.php)（安装包制作）

### 设计参考

- 空间卡片与关于页的交互参考 [Class Widgets 2](https://github.com/RinLit-233-shiroko/Class-Widgets-2)
