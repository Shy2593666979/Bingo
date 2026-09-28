"""Human-readable, timezone-aware time formatting for prompts and logs."""

from datetime import datetime
from zoneinfo import ZoneInfo

WEEKDAYS = ("一", "二", "三", "四", "五", "六", "日")


def time_period(hour: int) -> str:
    """Return the Chinese day-period label for a 24-hour clock hour."""
    if 6 <= hour < 8:
        return "早上"
    if 8 <= hour < 11:
        return "上午"
    if 11 <= hour < 13:
        return "中午"
    if 13 <= hour < 18:
        return "下午"
    if 18 <= hour < 23:
        return "晚上"
    if hour >= 23 or hour < 2:
        return "深夜"
    return "凌晨"


def format_current_time(timezone: str, now: datetime | None = None) -> str:
    """Format the current time as date, Chinese weekday, period, and clock time."""
    zone = ZoneInfo(timezone)
    current = now or datetime.now(zone)
    if current.tzinfo is None:
        current = current.replace(tzinfo=zone)
    else:
        current = current.astimezone(zone)
    return (
        f"{current.year}年{current.month}月{current.day}日"
        f"（周{WEEKDAYS[current.weekday()]}{time_period(current.hour)}）"
        f" {current:%H:%M:%S}"
    )
