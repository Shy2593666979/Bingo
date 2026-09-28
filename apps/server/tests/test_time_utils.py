from datetime import datetime
from zoneinfo import ZoneInfo

import pytest

from bingo.utils.time import format_current_time, time_period


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
