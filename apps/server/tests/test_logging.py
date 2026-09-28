import io
import logging
import re

from bingo.services.logging import BeijingFormatter, log_event, reset_request_id, set_request_id


def test_formatter_uses_beijing_time_milliseconds_and_request_id() -> None:
    stream = io.StringIO()
    handler = logging.StreamHandler(stream)
    handler.setFormatter(BeijingFormatter("%(asctime)s | %(levelname)s | %(name)s | %(message)s"))
    logger = logging.getLogger("test.logging.format")
    logger.handlers = [handler]
    logger.propagate = False
    logger.setLevel(logging.INFO)

    token = set_request_id("request-123")
    try:
        log_event(logger, logging.INFO, "agent.completed", user_id="user-1", duration_ms=12)
    finally:
        reset_request_id(token)

    output = stream.getvalue().strip()
    assert re.match(
        r"^\d{4}-\d{2}-\d{2} \d{2}:\d{2}:\d{2}\.\d{3} \| INFO \| "
        r"test\.logging\.format \| agent\.completed \| ",
        output,
    )
    assert "user_id=user-1" in output
    assert "duration_ms=12" in output
    assert "request_id=request-123" in output


def test_formatter_drops_sensitive_and_unknown_fields() -> None:
    stream = io.StringIO()
    handler = logging.StreamHandler(stream)
    handler.setFormatter(BeijingFormatter("%(message)s"))
    logger = logging.getLogger("test.logging.sensitive")
    logger.handlers = [handler]
    logger.propagate = False
    logger.setLevel(logging.INFO)

    log_event(
        logger,
        logging.INFO,
        "auth.login_failed",
        password="do-not-log",
        token="also-do-not-log",
        phone="13800138000",
        user_id="user-1",
    )

    output = stream.getvalue()
    assert "user_id=user-1" in output
    assert "do-not-log" not in output
    assert "also-do-not-log" not in output
    assert "13800138000" not in output
