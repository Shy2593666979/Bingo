"""Human-readable, timezone-aware time formatting for prompts and logs."""

from datetime import datetime, timedelta
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


def format_message_time(sent_at: datetime, timezone: str, now: datetime) -> str:
    zone = ZoneInfo(timezone)
    sent = sent_at.replace(tzinfo=zone) if sent_at.tzinfo is None else sent_at.astimezone(zone)
    current = now.replace(tzinfo=zone) if now.tzinfo is None else now.astimezone(zone)
    days_ago = (current.date() - sent.date()).days
    if 0 <= days_ago < 7:
        if days_ago == 0:
            relative = "今天"
        elif days_ago == 1:
            relative = "昨天"
        else:
            week_start = current.date() - timedelta(days=current.weekday())
            prefix = "上周" if sent.date() < week_start else "周"
            relative = f"{prefix}{WEEKDAYS[sent.weekday()]}"
        date = f"{sent.month}月{sent.day}日 {relative}"
    else:
        date = f"{sent.year}年{sent.month}月{sent.day}日"
    return f"[{date} {time_period(sent.hour)} {sent:%H:%M}]"
