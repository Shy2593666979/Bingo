from datetime import datetime
from zoneinfo import ZoneInfo

from sqlalchemy import DateTime
from sqlalchemy.engine.interfaces import Dialect
from sqlalchemy.types import TypeDecorator

BEIJING_TIMEZONE = ZoneInfo("Asia/Shanghai")


def beijing_now() -> datetime:
    return datetime.now(BEIJING_TIMEZONE)


def as_beijing(value: datetime) -> datetime:
    if value.tzinfo is None:
        return value.replace(tzinfo=BEIJING_TIMEZONE)
    return value.astimezone(BEIJING_TIMEZONE)


class BeijingDateTime(TypeDecorator[datetime]):
    """Store Beijing wall-clock values and always return +08:00-aware datetimes."""

    impl = DateTime(timezone=True)
    cache_ok = True

    def process_bind_param(self, value: datetime | None, dialect: Dialect) -> datetime | None:
        if value is None:
            return None
        normalized = as_beijing(value)
        if dialect.name == "sqlite":
            return normalized.replace(tzinfo=None)
        return normalized

    def process_result_value(self, value: datetime | None, dialect: Dialect) -> datetime | None:
        if value is None:
            return None
        return as_beijing(value)
