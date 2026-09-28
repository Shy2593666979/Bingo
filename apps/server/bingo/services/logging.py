import logging
import sys
from contextvars import ContextVar, Token
from datetime import datetime
from logging.handlers import TimedRotatingFileHandler
from pathlib import Path
from typing import Any
from zoneinfo import ZoneInfo

from bingo.config import LoggingSettings

BEIJING_TIMEZONE = ZoneInfo("Asia/Shanghai")
SERVER_DIRECTORY = Path(__file__).resolve().parents[2]
REQUEST_ID: ContextVar[str | None] = ContextVar("request_id", default=None)

SAFE_FIELDS = frozenset(
    {
        "request_id",
        "run_id",
        "user_id",
        "conversation_id",
        "message_id",
        "tool",
        "method",
        "path",
        "status_code",
        "duration_ms",
        "error_type",
        "job",
        "stage",
        "count",
        "attempt",
        "provider",
        "audio_bytes",
        "outcome",
    }
)


class BeijingFormatter(logging.Formatter):
    def formatTime(self, record: logging.LogRecord, datefmt: str | None = None) -> str:
        moment = datetime.fromtimestamp(record.created, BEIJING_TIMEZONE)
        if datefmt:
            return moment.strftime(datefmt)
        return moment.strftime("%Y-%m-%d %H:%M:%S.") + f"{int(record.msecs):03d}"

    def format(self, record: logging.LogRecord) -> str:
        rendered = super().format(record)
        fields = getattr(record, "event_fields", {})
        if not isinstance(fields, dict):
            return rendered
        values = dict(fields)
        values.setdefault("request_id", REQUEST_ID.get())
        suffix = " ".join(
            f"{key}={_format_value(value)}"
            for key, value in values.items()
            if key in SAFE_FIELDS and value is not None
        )
        return f"{rendered} | {suffix}" if suffix else rendered


class ExcludeAccessFilter(logging.Filter):
    def filter(self, record: logging.LogRecord) -> bool:
        return not record.name.startswith("bingo.access")


def configure_logging(settings: LoggingSettings) -> None:
    level = getattr(logging, settings.level)
    formatter = BeijingFormatter("%(asctime)s | %(levelname)s | %(name)s | %(message)s")
    root = logging.getLogger()
    _close_handlers(root)
    root.setLevel(level)

    if settings.console:
        console = logging.StreamHandler(sys.stdout)
        console.setFormatter(formatter)
        console.setLevel(level)
        root.addHandler(console)

    directory = Path(settings.directory)
    if not directory.is_absolute():
        directory = SERVER_DIRECTORY / directory

    if settings.application_file or settings.access_file:
        directory.mkdir(parents=True, exist_ok=True)

    if settings.application_file:
        application = _file_handler(directory / settings.application_file, settings, formatter)
        application.addFilter(ExcludeAccessFilter())
        root.addHandler(application)

    access_logger = logging.getLogger("bingo.access")
    _close_handlers(access_logger)
    access_logger.setLevel(level)
    access_logger.propagate = True
    if settings.access_file:
        access_logger.addHandler(
            _file_handler(directory / settings.access_file, settings, formatter)
        )

    for logger_name in ("uvicorn", "uvicorn.error", "uvicorn.access"):
        uvicorn_logger = logging.getLogger(logger_name)
        uvicorn_logger.handlers.clear()
        uvicorn_logger.propagate = True


def log_event(
    logger: logging.Logger,
    level: int,
    event: str,
    **fields: Any,
) -> None:
    safe_fields = {key: value for key, value in fields.items() if key in SAFE_FIELDS}
    logger.log(level, event, extra={"event_fields": safe_fields})


def set_request_id(request_id: str) -> Token[str | None]:
    return REQUEST_ID.set(request_id)


def reset_request_id(token: Token[str | None]) -> None:
    REQUEST_ID.reset(token)


def _file_handler(
    path: Path,
    settings: LoggingSettings,
    formatter: logging.Formatter,
) -> TimedRotatingFileHandler:
    handler = TimedRotatingFileHandler(
        path,
        when="midnight",
        interval=1,
        backupCount=settings.retention_days,
        encoding="utf-8",
    )
    handler.setLevel(getattr(logging, settings.level))
    handler.setFormatter(formatter)
    return handler


def _close_handlers(logger: logging.Logger) -> None:
    for handler in logger.handlers[:]:
        logger.removeHandler(handler)
        handler.close()


def _format_value(value: Any) -> str:
    text = str(value).replace("\r", " ").replace("\n", " ")
    return text if text and not any(character.isspace() for character in text) else repr(text)
