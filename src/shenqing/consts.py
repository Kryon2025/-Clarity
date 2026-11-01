"""常量与产品级默认值。"""

from __future__ import annotations

from enum import Enum

APP_NAME = "深清"
APP_ALIAS = "身轻"
APP_ID = "ShenQing"
APP_VERSION = "0.3.0"

#: 专注时长预设（分钟）
PRESET_MINUTES = (25, 45, 90)
MIN_MINUTES = 1
MAX_MINUTES = 240

#: 空间（Space）时长范围（分钟）
SPACE_MIN_MINUTES = 15
SPACE_MAX_MINUTES = 240
SPACE_MINUTE_STEP = 5

#: 空间名长度上限
SPACE_NAME_LIMIT = 20


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
