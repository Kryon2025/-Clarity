"""常量与产品级默认值。"""

from __future__ import annotations

from enum import Enum

APP_NAME = "深清"
#: 英文名（v0.4 起对外统一用 Clarity；「身轻」不再展示）
APP_ALIAS = "Clarity"
APP_ID = "ShenQing"
APP_VERSION = "0.7.0"

#: GitHub 仓库（自动更新与反馈入口用）
GITHUB_REPO = "Kryon2025/Clarity"

#: 唯一空间的名字（不可改名）
SPACE_NAME = "清空间"

#: 三档强度（界面文案；枚举值仍是 light/medium/heavy）
MODE_LABELS = {"light": "浅清", "medium": "覆清", "heavy": "深清"}

#: 主题：纯色（默认）/ 清空间浅色 / 液态玻璃（实验性）
THEMES = [
    {"value": "solid", "label": "纯色", "desc": "平面纯色，无需 GPU 特效", "experimental": False},
    {
        "value": "light",
        "label": "清空间浅色",
        "desc": "浅色底的清空间主题",
        "experimental": False,
    },
    {
        "value": "glass",
        "label": "液态玻璃",
        "desc": "折射玻璃与拖拽高光（实验性）",
        "experimental": True,
    },
]
DEFAULT_THEME = "solid"

#: 更新日志（最新在前；en 为空时用中文兜底）
CHANGELOG = [
    {
        "version": "0.7.0",
        "date": "2025-11-05",
        "tag": "",
        "items": [
            "新增进入前的 10 秒「水滴凝聚」倒计时：水滴凭空出现、向圆心汇聚并凝结为发光圆环，进入时圆环扩散至全屏；期间可随时取消，取消时水滴向外散开",
            "深清空间默认时长改为 1 分钟（旧数据自动迁移），时长滑块最短 1 分钟",
            "支持从 GitHub 自动更新：启动后自动检查新版本，关于页可手动检查 / 下载 / 安装",
            "关于页新增「许可证」「第三方组件」入口；仓库新增 LICENSE.txt、THIRD_PARTY_NOTICES.md、CHANGELOG.md",
            "新增发布流程：推送 v* 标签自动运行测试、打包绿色版与安装包，并把更新日志作为 Release 正文",
        ],
        "items_en": [
            "New 10-second droplet countdown before focus: droplets appear from nothing, converge and condense into a glowing ring, which expands to fullscreen on entry; cancel anytime and the droplets scatter outward",
            "Deep space now defaults to 1 minute (existing data migrates automatically); the duration slider minimum is 1 minute",
            "GitHub auto-update: checks for new releases after startup, with manual check / download / install on the About page",
            "About page gained License and Third-party buttons; the repo now ships LICENSE.txt, THIRD_PARTY_NOTICES.md and CHANGELOG.md",
            "New release pipeline: pushing a v* tag runs tests, packages the portable zip and installer, and uses the changelog as the release body",
        ],
    },
    {
        "version": "0.6.0",
        "date": "2025-11-03",
        "tag": "beta",
        "items": [
            "空间页改为浅清 / 覆清 / 深清三个标签页，卡片两列列表式布局，支持新增 / 删除 / 就地改名空间",
            "深清固定一个空间：不可增删改名，只能改时长与白名单，专注时只显示倒计时",
            "全局搜索：窗口右上角常驻，支持空间 / 主题 / 模式 / 插件 / 设置（Ctrl+K）",
            "保活看门狗：进程被杀约 2 秒后自动拉起；新安装默认最高权限运行",
            "新增反馈入口：功能请求 / Bug 反馈 / 参与讨论跳转 GitHub",
            "完善全局动画：页面切换、标签指示器、卡片增删、浮层、遮罩与主题切换过渡",
        ],
        "items_en": [
            "Spaces page now uses three tabs (Light / Veil / Deep) with a two-column card list; add, delete and rename spaces inline",
            "Deep has one fixed space: no add/remove/rename, only duration and allowlist; focus mode shows only the countdown",
            "Global search in the top-right corner on every page (Ctrl+K): spaces, themes, modes, plugins and settings",
            "Keeper watchdog relaunches the app about 2s after the process is killed; new installs run with highest privileges",
            "Feedback entry: feature request / bug report / discussions link to GitHub",
            "Polished global animations: page transitions, tab indicator, card add/remove, overlays, lock screen and theme switch",
        ],
    },
    {
        "version": "0.5.0",
        "date": "2025-11-03",
        "tag": "",
        "items": [
            "三档空间模型：浅清 / 覆清 / 深清各一个空间",
            "移除预览 / 体验按钮，时长滑块最短 1 分钟即体验",
            "导航分组：上组 空间 / 数据 / 插件 / 主题，下组 设置 / 关于",
            "新增关于页；移除番茄插件导航入口",
            "液态玻璃高亮块超出菜单项，长按可拖拽",
        ],
        "items_en": [
            "Three-tier space model: one space per Light / Veil / Deep tier",
            "Removed preview/trial buttons; the 1-minute minimum on the slider is the quick trial",
            "Navigation split into two groups: spaces/stats/plugins/themes and settings/about",
            "New About page; removed the TomaToDo plugin nav entry",
            "Liquid glass highlight is larger than the nav item and can be dragged on long press",
        ],
    },
    {
        "version": "0.4.0",
        "date": "2025-11-01",
        "tag": "",
        "items": [
            "品牌英文名改为 Clarity，界面不再显示「身轻」",
            "主题体系：纯色（默认）/ 清空间浅色 / 液态玻璃（实验性）",
            "顶部菜单栏 + 全局搜索；单空间「清空间」，时长就地设置",
            "深清不可提前结束；覆清全屏 dock 软件栏",
            "插件 SDK：schema、模板、validate 命令，插件可注册导航入口与遮罩组件",
        ],
        "items_en": [
            "English brand name is now Clarity; the old alias is no longer shown",
            "Themes: Solid (default) / Clarity Light / Liquid Glass (experimental)",
            "Top menu bar + global search; single space with inline duration",
            "Deep cannot end early; Veil shows a full-screen app dock",
            "Plugin SDK: schema, templates, validate command; plugins can register nav entries and overlay widgets",
        ],
    },
    {
        "version": "0.3.0",
        "date": "2025-10-28",
        "tag": "",
        "items": [
            "插件系统与插件页；内置番茄同步、专注统计",
            "防退出加固：锁定期间隐藏任务栏、屏蔽系统快捷键",
            "以管理员身份运行与最高权限开机自启",
            "英文界面（i18n）与 GitHub Actions 自动翻译",
        ],
        "items_en": [
            "Plugin system and plugins page; built-in TomaToDo sync and focus stats",
            "Lock hardening: hides the taskbar and blocks system shortcuts during focus",
            "Run as administrator and elevated autostart",
            "English UI (i18n) with automatic translation via GitHub Actions",
        ],
    },
    {
        "version": "0.2.0",
        "date": "2025-10-20",
        "tag": "",
        "items": [
            "多空间模型与全屏专注遮罩",
            "液态玻璃渲染管线（GLSL / qsb）",
            "托盘速启面板、灵动岛、SMTC 媒体控制",
            "专注统计与通知",
        ],
        "items_en": [
            "Multi-space model and full-screen focus overlay",
            "Liquid glass rendering pipeline (GLSL / qsb)",
            "Tray quick panel, dynamic island, SMTC media controls",
            "Focus stats and notifications",
        ],
    },
]

#: 项目仓库与反馈地址
GITHUB_URL = "https://github.com/Kryon2025/Clarity"
FEEDBACK_URLS = {
    "request": f"{GITHUB_URL}/issues/new?labels=enhancement",
    "bug": f"{GITHUB_URL}/issues/new?labels=bug",
    "discuss": f"{GITHUB_URL}/discussions",
}

#: 专注时长预设（分钟）
PRESET_MINUTES = (25, 45, 90)
MIN_MINUTES = 1
MAX_MINUTES = 240

#: 空间（Space）时长范围（分钟）——单空间固定，仅可调时长
SPACE_MIN_MINUTES = 1
SPACE_MAX_MINUTES = 240
SPACE_MINUTE_STEP = 1

#: 空间名长度上限
SPACE_NAME_LIMIT = 20

#: 体验模式的最短时长（分钟）
TRIAL_MINUTES = 1


class Atmosphere:
    """氛围 preset：v0.2 只影响视觉色调，音效留给 v0.3。"""

    VALUE = "value"
    LABEL = "label"
    COLOR = "color"
    DESC = "desc"


#: 空间氛围列表（QML 直接消费）
ATMOSPHERES: list[dict] = [
    {"value": "静谧", "label": "静谧", "color": "#4F7CFF", "desc": "深蓝夜色，适合睡眠与长时段专注"},
    {"value": "秩序", "label": "秩序", "color": "#22D3EE", "desc": "冷青网格，适合工作学习"},
    {"value": "探索", "label": "探索", "color": "#A78BFA", "desc": "紫调光雾，适合阅读与灵感"},
    {"value": "专注", "label": "专注", "color": "#34D399", "desc": "墨绿聚焦，适合刷题与写作"},
]

ATMOSPHERE_VALUES = [item["value"] for item in ATMOSPHERES]


def atmosphere_color(value: str) -> str:
    for item in ATMOSPHERES:
        if item["value"] == value:
            return item["color"]
    return ATMOSPHERES[0]["color"]


class LockLevel(str, Enum):
    """锁机强度。"""

    LIGHT = "light"    # 轻度：只结束黑名单进程
    MEDIUM = "medium"  # 中度：进程 + 网站域名屏蔽（需管理员才真正生效）
    HEAVY = "heavy"    # 重度：进程 + 全屏遮罩 + 屏蔽退出手段

    @property
    def label(self) -> str:
        return {"light": "轻度", "medium": "中度", "heavy": "重度"}[self.value]

    @property
    def description(self) -> str:
        return {
            "light": "只结束黑名单进程，可以正常暂停与退出",
            "medium": "结束后台干扰进程，并屏蔽黑名单网站（需管理员权限）",
            "heavy": "全屏遮罩锁机，屏蔽退出手段，必须等计时结束",
        }[self.value]


#: QML 中展示用的锁机强度列表
LOCK_LEVEL_CHOICES = [
    {"value": level.value, "label": level.label, "description": level.description}
    for level in LockLevel
]

#: 会话状态（与 core/session.py 的 SessionState 对应，避免 QML 侧引用 Python 枚举）
STATE_IDLE = "idle"
STATE_RUNNING = "running"
STATE_PAUSED = "paused"
