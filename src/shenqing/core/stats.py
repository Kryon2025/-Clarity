"""专注数据统计：本地 JSON 存储 + CSV 导出。"""

from __future__ import annotations

import csv
import json
from datetime import date, datetime, timedelta
from pathlib import Path
from typing import Any

from ..paths import app_data_dir


class StatsStore:
    """```json
    {"sessions": [{"date": "2026-11-01", "minutes": 25.0, "level": "medium",
                   "completed": true, "interruptions": 0, "ts": "2026-11-01T10:00:00"}]}
    ```"""

    def __init__(self, path: Path | None = None) -> None:
        self.path = path or (app_data_dir() / "stats.json")
        self._sessions: list[dict[str, Any]] = []
        self.load()

    # ---- 存储 ----
    def load(self) -> None:
        try:
            if self.path.exists():
                data = json.loads(self.path.read_text(encoding="utf-8"))
                sessions = data.get("sessions") if isinstance(data, dict) else None
                if isinstance(sessions, list):
                    self._sessions = [s for s in sessions if isinstance(s, dict)]
        except (OSError, json.JSONDecodeError):
            self._sessions = []

    def save(self) -> None:
        try:
            self.path.parent.mkdir(parents=True, exist_ok=True)
            self.path.write_text(
                json.dumps({"sessions": self._sessions}, ensure_ascii=False, indent=2),
                encoding="utf-8",
            )
        except OSError:
            pass

    # ---- 写入 ----
    def record(
        self,
        minutes: float,
        level: str,
        completed: bool,
        interruptions: int = 0,
        space: str = "",
        *,
        when: datetime | None = None,
        started_at: datetime | None = None,
    ) -> None:
        now = when or datetime.now()
        start = started_at or now
        self._sessions.append(
            {
                "date": now.date().isoformat(),
                "ts": now.isoformat(timespec="seconds"),
                "start": start.isoformat(timespec="seconds"),
                "minutes": round(float(minutes), 1),
                "level": level,
                "completed": bool(completed),
                "interruptions": int(interruptions),
                "space": str(space or ""),
            }
        )
        self.save()

    # ---- 查询 ----
    @property
    def sessions(self) -> list[dict[str, Any]]:
        return list(self._sessions)

    def minutes_on(self, day: date) -> float:
        key = day.isoformat()
        return round(sum(float(s.get("minutes", 0)) for s in self._sessions if s.get("date") == key), 1)

    def sessions_on(self, day: date | None = None) -> list[dict[str, Any]]:
        key = (day or date.today()).isoformat()
        return [dict(s) for s in self._sessions if s.get("date") == key]

    def today_sessions(self, today: date | None = None) -> int:
        """今天完成的专注次数（供 UI 今日专注卡片/连续打卡）。"""
        return len(self.sessions_on(today))

    def today_minutes(self, today: date | None = None) -> float:
        return self.minutes_on(today or date.today())

    def week_minutes(self, today: date | None = None) -> float:
        today = today or date.today()
        monday = today - timedelta(days=today.weekday())
        days = {monday + timedelta(days=i) for i in range(7)}
        return round(
            sum(float(s.get("minutes", 0)) for s in self._sessions if s.get("date") in {d.isoformat() for d in days}),
            1,
        )

    def total_sessions(self) -> int:
        return len(self._sessions)

    def streak_days(self, today: date | None = None) -> int:
        """连续专注天数（今天还没专注时从昨天往前算，保留昨天的成绩）。"""
        days = {s.get("date") for s in self._sessions if float(s.get("minutes", 0)) >= 1}
        today = today or date.today()
        cursor = today if today.isoformat() in days else today - timedelta(days=1)
        streak = 0
        while cursor.isoformat() in days:
            streak += 1
            cursor -= timedelta(days=1)
        return streak

    def last_7_days(self, today: date | None = None) -> list[dict[str, Any]]:
        """近 7 天（含今天）每天分钟数，供热图使用。"""
        today = today or date.today()
        result = []
        for offset in range(6, -1, -1):
            day = today - timedelta(days=offset)
            result.append({"date": day.isoformat(), "minutes": self.minutes_on(day)})
        return result

    # ---- 导出 ----
    def export_csv(self, dest: Path | None = None) -> Path:
        target = dest or (app_data_dir() / "exports" / f"深清_专注记录_{date.today().isoformat()}.csv")
        target.parent.mkdir(parents=True, exist_ok=True)
        with target.open("w", encoding="utf-8-sig", newline="") as fp:
            writer = csv.writer(fp)
            writer.writerow(["日期", "开始时间", "时长(分钟)", "强度", "是否完成", "暂停次数"])
            for s in self._sessions:
                writer.writerow(
                    [
                        s.get("date", ""),
                        s.get("ts", ""),
                        s.get("minutes", 0),
                        s.get("level", ""),
                        "是" if s.get("completed") else "否",
                        s.get("interruptions", 0),
                    ]
                )
        return target
