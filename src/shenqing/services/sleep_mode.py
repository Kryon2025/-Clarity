"""睡眠模式（v0.8）：多段锁定时间 + 提醒 + 每月解锁机会。

数据文件：%APPDATA%/ShenQing/settings/sleep.json
{
  "schedules": [{"id": "sl_xxx", "time": "23:30", "enabled": true}],
  "reminders": true,
  "unlockChances": 3,
  "unlockUsed": 0,
  "unlockMonth": "2026-11",
  "fired": {"2026-11-06": ["23:30|lock", "23:30|60"]}
}
"""

from __future__ import annotations

import json
import logging
import re
import uuid
from datetime import datetime, timedelta
from pathlib import Path

from ..paths import app_data_dir

logger = logging.getLogger("shenqing.sleep")

TIME_RE = re.compile(r"^(\d{1,2}):(\d{2})$")
DEFAULT_UNLOCK_CHANCES = 3
REMINDER_MINUTES = (60, 30, 1)
LOCK_KIND = "lock"


def normalize_time(value: object) -> str:
    """'9:05' → '09:05'；非法返回空串。"""
    match = TIME_RE.match(str(value or "").strip())
    if not match:
        return ""
    hour = int(match.group(1))
    minute = int(match.group(2))
    if hour > 23 or minute > 59:
        return ""
    return f"{hour:02d}:{minute:02d}"


def _new_id() -> str:
    return "sl_" + uuid.uuid4().hex[:8]


def _month_key(now: datetime | None = None) -> str:
    return (now or datetime.now()).strftime("%Y-%m")


class SleepManager:
    def __init__(self, path: Path | None = None) -> None:
        default = app_data_dir() / "settings" / "sleep.json"
        self.path = Path(path) if path is not None else default
        self._schedules: list[dict] = []
        self._reminders = True
        self._unlock_chances = DEFAULT_UNLOCK_CHANCES
        self._unlock_used = 0
        self._unlock_month = _month_key()
        self._fired: dict[str, list[str]] = {}
        self.load()

    # ---------- 持久化 ----------
    def _defaults(self) -> None:
        self._schedules = []
        self._reminders = True
        self._unlock_chances = DEFAULT_UNLOCK_CHANCES
        self._unlock_used = 0
        self._unlock_month = _month_key()
        self._fired = {}

    def load(self) -> None:
        self._defaults()
        try:
            data = json.loads(self.path.read_text(encoding="utf-8")) if self.path.exists() else None
        except (OSError, json.JSONDecodeError, ValueError):
            data = None
        if not isinstance(data, dict):
            self.save()
            return
        schedules = data.get("schedules")
        if isinstance(schedules, list):
            for item in schedules:
                if not isinstance(item, dict):
                    continue
                text = normalize_time(item.get("time"))
                if not text:
                    continue
                if any(s["time"] == text for s in self._schedules):
                    continue
                self._schedules.append(
                    {
                        "id": str(item.get("id") or _new_id()),
                        "time": text,
                        "enabled": bool(item.get("enabled", True)),
                    }
                )
        self._reminders = bool(data.get("reminders", True))
        try:
            self._unlock_chances = max(0, int(data.get("unlockChances", DEFAULT_UNLOCK_CHANCES)))
            self._unlock_used = max(0, int(data.get("unlockUsed", 0)))
        except (TypeError, ValueError):
            self._unlock_chances = DEFAULT_UNLOCK_CHANCES
            self._unlock_used = 0
        self._unlock_month = str(data.get("unlockMonth") or _month_key())
        fired = data.get("fired")
        if isinstance(fired, dict):
            self._fired = {
                str(key): [str(v) for v in values]
                for key, values in fired.items()
                if isinstance(values, list)
            }
        self._reset_month_if_needed()
        self.save()

    def save(self) -> None:
        try:
            self.path.parent.mkdir(parents=True, exist_ok=True)
            payload = {
                "schedules": [dict(item) for item in self._schedules],
                "reminders": bool(self._reminders),
                "unlockChances": int(self._unlock_chances),
                "unlockUsed": int(self._unlock_used),
                "unlockMonth": str(self._unlock_month),
                "fired": {key: list(values) for key, values in self._fired.items()},
            }
            self.path.write_text(
                json.dumps(payload, ensure_ascii=False, indent=2), encoding="utf-8"
            )
        except OSError:
            pass

    # ---------- 时间表 ----------
    def schedules(self) -> list[dict]:
        return [
            {"id": item["id"], "time": item["time"], "enabled": bool(item["enabled"])}
            for item in sorted(self._schedules, key=lambda s: s["time"])
        ]

    def schedule_times(self) -> list[str]:
        return [item["time"] for item in self.schedules() if item["enabled"]]

    def add_schedule(self, value: object) -> str:
        text = normalize_time(value)
        if not text:
            return ""
        if any(item["time"] == text for item in self._schedules):
            return ""
        item = {"id": _new_id(), "time": text, "enabled": True}
        self._schedules.append(item)
        self.save()
        return item["id"]

    def remove_schedule(self, key: object) -> bool:
        target = str(key or "").strip()
        if not target:
            return False
        for item in list(self._schedules):
            if item["id"] == target or item["time"] == normalize_time(target):
                self._schedules.remove(item)
                self.save()
                return True
        return False

    # ---------- 提醒 ----------
    @property
    def reminders_enabled(self) -> bool:
        return bool(self._reminders)

    @property
    def reminders(self) -> list[int]:
        return list(REMINDER_MINUTES) if self._reminders else []

    def set_reminders(self, enabled: bool) -> None:
        self._reminders = bool(enabled)
        self.save()

    # ---------- 解锁机会 ----------
    def _reset_month_if_needed(self, now: datetime | None = None) -> bool:
        key = _month_key(now)
        if self._unlock_month != key:
            self._unlock_month = key
            self._unlock_used = 0
            return True
        return False

    @property
    def unlock_chances(self) -> int:
        self._reset_month_if_needed()
        return max(0, int(self._unlock_chances) - int(self._unlock_used))

    @property
    def unlock_total(self) -> int:
        return max(0, int(self._unlock_chances))

    @property
    def unlock_chance_label(self) -> str:
        return f"本月剩余 {self.unlock_chances}/{self.unlock_total} 次"

    def try_unlock(self) -> bool:
        self._reset_month_if_needed()
        if self.unlock_chances <= 0:
            return False
        self._unlock_used += 1
        self.save()
        return True

    # ---------- 触发记录 ----------
    def _fired_for(self, day: str) -> list[str]:
        return self._fired.get(day, [])

    def is_fired(self, day: str, time_text: str, kind: object) -> bool:
        return f"{time_text}|{kind}" in self._fired_for(day)

    def mark_fired(self, day: str, time_text: str, kind: object) -> None:
        key = f"{time_text}|{kind}"
        values = self._fired_for(day)
        if key not in values:
            values.append(key)
        self._fired[day] = values
        # 只保留最近 14 天
        keep = sorted(self._fired.keys())[-14:]
        self._fired = {k: self._fired[k] for k in keep}
        self.save()

    def due_lock(self, now: datetime) -> dict | None:
        """当前分钟是否该自动进入深清锁定。"""
        clock = now.strftime("%H:%M")
        day = now.strftime("%Y-%m-%d")
        for item in self._schedules:
            if not item["enabled"] or item["time"] != clock:
                continue
            if self.is_fired(day, item["time"], LOCK_KIND):
                continue
            return item
        return None

    def due_reminders(self, now: datetime) -> list[dict]:
        """当前分钟是否该发「提前 60/30/1 分钟」提醒。"""
        if not self._reminders:
            return []
        result: list[dict] = []
        for item in self._schedules:
            if not item["enabled"]:
                continue
            for offset in REMINDER_MINUTES:
                # 锁定时刻可能在明/后一天，往前推 offset 分钟后与 now 同分钟即触发
                for day_delta in (0, 1):
                    day = now.date() + timedelta(days=day_delta)
                    hour, minute = item["time"].split(":")
                    scheduled = datetime(
                        day.year, day.month, day.day, int(hour), int(minute)
                    )
                    target = scheduled - timedelta(minutes=offset)
                    if target.strftime("%Y-%m-%d %H:%M") != now.strftime("%Y-%m-%d %H:%M"):
                        continue
                    if self.is_fired(now.strftime("%Y-%m-%d"), item["time"], offset):
                        continue
                    result.append({"schedule": item, "offset": offset})
        return result
