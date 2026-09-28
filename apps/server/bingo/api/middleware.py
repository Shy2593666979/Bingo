import logging
import re
import time
import uuid
from collections.abc import Awaitable, Callable
from typing import Any

from bingo.services.logging import log_event, reset_request_id, set_request_id

logger = logging.getLogger("bingo.access")
REQUEST_ID_PATTERN = re.compile(r"^[A-Za-z0-9._-]{1,64}$")

Message = dict[str, Any]
Receive = Callable[[], Awaitable[Message]]
Send = Callable[[Message], Awaitable[None]]


class RequestLoggingMiddleware:
    def __init__(self, app: Any) -> None:
        self.app = app

    async def __call__(self, scope: Message, receive: Receive, send: Send) -> None:
        if scope["type"] != "http":
            await self.app(scope, receive, send)
            return

        request_id = _request_id(scope)
        request_token = set_request_id(request_id)
        started_at = time.perf_counter()
        status_code = 500

        async def send_with_request_id(message: Message) -> None:
            nonlocal status_code
            if message["type"] == "http.response.start":
                status_code = int(message["status"])
                headers = list(message.get("headers", []))
                headers.append((b"x-request-id", request_id.encode("ascii")))
                message["headers"] = headers
            await send(message)

        try:
            await self.app(scope, receive, send_with_request_id)
        except Exception as error:
            log_event(
                logger,
                logging.ERROR,
                "request.failed",
                method=scope["method"],
                path=scope["path"],
                status_code=500,
                duration_ms=_duration_ms(started_at),
                error_type=type(error).__name__,
            )
            raise
        else:
            log_event(
                logger,
                logging.INFO,
                "request.completed",
                method=scope["method"],
                path=scope["path"],
                status_code=status_code,
                duration_ms=_duration_ms(started_at),
            )
        finally:
            reset_request_id(request_token)


def _request_id(scope: Message) -> str:
    for raw_name, raw_value in scope.get("headers", []):
        if raw_name.lower() == b"x-request-id":
            candidate = raw_value.decode("ascii", errors="ignore")
            if REQUEST_ID_PATTERN.fullmatch(candidate):
                return candidate
    return uuid.uuid4().hex


def _duration_ms(started_at: float) -> int:
    return round((time.perf_counter() - started_at) * 1000)
