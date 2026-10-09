from datetime import datetime
from zoneinfo import ZoneInfo

import pytest

from bingo.utils.time import format_current_time, format_message_time, time_period


@pytest.mark.parametrize(
    ("hour", "period"),
    [
        (0, "深夜"),
        (1, "深夜"),
        (2, "凌晨"),
        (5, "凌晨"),
        (6, "早上"),
        (7, "早上"),
        (8, "上午"),
        (10, "上午"),
        (11, "中午"),
        (12, "中午"),
        (13, "下午"),
        (17, "下午"),
        (18, "晚上"),
        (22, "晚上"),
        (23, "深夜"),
    ],
)
def test_time_period_boundaries(hour: int, period: str) -> None:
    assert time_period(hour) == period


def test_format_current_time_includes_date_weekday_period_and_clock() -> None:
    now = datetime(2026, 9, 28, 6, 7, 8, tzinfo=ZoneInfo("Asia/Shanghai"))
    assert format_current_time("Asia/Shanghai", now) == "2026年9月28日（周一早上） 06:07:08"


@pytest.mark.parametrize(
    ("sent_at", "expected"),
    [
        ("2026-09-30T21:30:00+08:00", "[2026年9月30日 晚上 21:30]"),
        ("2026-10-02T15:20:00+08:00", "[2026年10月2日 下午 15:20]"),
        ("2026-10-03T09:10:00+08:00", "[10月3日 上周六 上午 09:10]"),
        ("2026-10-04T06:30:00+08:00", "[10月4日 上周日 早上 06:30]"),
        ("2026-10-05T20:30:00+08:00", "[10月5日 周一 晚上 20:30]"),
        ("2026-10-08T22:15:00+08:00", "[10月8日 昨天 晚上 22:15]"),
        ("2026-10-09T10:05:00+08:00", "[10月9日 今天 上午 10:05]"),
        ("2026-10-09T02:05:00+00:00", "[10月9日 今天 上午 10:05]"),
        ("2026-10-09T11:05:00", "[10月9日 今天 中午 11:05]"),
        ("2026-10-10T01:05:00+08:00", "[2026年10月10日 深夜 01:05]"),
    ],
)
def test_message_time_uses_seven_calendar_days(sent_at: str, expected: str) -> None:
    now = datetime.fromisoformat("2026-10-09T10:10:00+08:00")
    assert format_message_time(datetime.fromisoformat(sent_at), "Asia/Shanghai", now) == expected


def test_message_time_recalculates_relative_day_and_handles_year_boundary() -> None:
    sent_at = datetime.fromisoformat("2026-12-31T21:30:00+08:00")
    assert (
        format_message_time(
            sent_at, "Asia/Shanghai", datetime.fromisoformat("2027-01-01T10:00:00+08:00")
        )
        == "[12月31日 昨天 晚上 21:30]"
    )
    assert (
        format_message_time(
            sent_at, "Asia/Shanghai", datetime.fromisoformat("2027-01-07T10:00:00+08:00")
        )
        == "[2026年12月31日 晚上 21:30]"
    )
