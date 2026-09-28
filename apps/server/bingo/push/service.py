import asyncio
import json
import logging
import time
from contextlib import suppress
from datetime import timedelta

from sqlalchemy.ext.asyncio import async_sessionmaker
from sqlmodel.ext.asyncio.session import AsyncSession

from bingo.db.models import ProactiveMessage
from bingo.db.repositories import PushOutboxRepository
from bingo.db.time import beijing_now
from bingo.push.provider import PushDelivery, PushProvider
from bingo.services.logging import log_event

logger = logging.getLogger(__name__)

RETRY_DELAYS_SECONDS = (30, 300, 1800, 7200, 21600)


class PushService:
    def __init__(
        self,
        session_factory: async_sessionmaker[AsyncSession],
        provider: PushProvider,
        *,
        poll_seconds: float,
    ) -> None:
        self._session_factory = session_factory
        self._provider = provider
        self._poll_seconds = poll_seconds
        self._worker: asyncio.Task[None] | None = None

    @property
    def enabled(self) -> bool:
        return self._provider.enabled

    async def start(self) -> None:
        if self.enabled:
            self._worker = asyncio.create_task(self._run_worker(), name="bingo-push-worker")

    async def close(self) -> None:
        if self._worker is not None:
            self._worker.cancel()
            with suppress(asyncio.CancelledError):
                await self._worker
        await self._provider.close()

    async def enqueue(self, proactive: ProactiveMessage, title: str, body: str) -> int:
        if not self.enabled:
            return 0
        payload = {
            "type": "proactive_message",
            "proactive_id": proactive.id,
            "message_id": proactive.message_id,
            "conversation_id": proactive.conversation_id,
            "sent_at": proactive.created_at.isoformat(),
        }
        async with self._session_factory() as session:
            count = await PushOutboxRepository(session).enqueue_for_user(
                user_id=proactive.user_id,
                proactive_message_id=proactive.id,
                title=title,
                body=body,
                payload_json=json.dumps(payload, ensure_ascii=False),
            )
        log_event(
            logger,
            logging.INFO,
            "push.enqueued",
            user_id=proactive.user_id,
            message_id=proactive.message_id,
            count=count,
        )
        return count

    async def _run_worker(self) -> None:
        while True:
            try:
                processed = await self._deliver_one()
                if not processed:
                    await asyncio.sleep(self._poll_seconds)
            except asyncio.CancelledError:
                raise
            except Exception as error:
                log_event(
                    logger,
                    logging.ERROR,
                    "push.failed",
                    error_type=type(error).__name__,
                )
                await asyncio.sleep(self._poll_seconds)

    async def _deliver_one(self) -> bool:
        async with self._session_factory() as session:
            repository = PushOutboxRepository(session)
            row = await repository.next_due()
            if row is None:
                return False
            outbox, device = row
            started_at = time.perf_counter()
            try:
                provider_id = await self._provider.send(
                    PushDelivery(
                        request_id=outbox.id,
                        client_id=device.client_id,
                        title=outbox.title,
                        body=outbox.body,
                        payload=json.loads(outbox.payload_json),
                    )
                )
            except Exception as error:
                attempts = outbox.attempts + 1
                if attempts >= len(RETRY_DELAYS_SECONDS):
                    await repository.mark_failed(outbox, attempts, str(error))
                else:
                    await repository.reschedule(
                        outbox,
                        attempts,
                        beijing_now() + timedelta(seconds=RETRY_DELAYS_SECONDS[attempts - 1]),
                        str(error),
                    )
                log_event(
                    logger,
                    logging.ERROR,
                    "push.failed",
                    user_id=outbox.user_id,
                    message_id=outbox.proactive_message_id,
                    provider=device.provider,
                    attempt=attempts,
                    duration_ms=round((time.perf_counter() - started_at) * 1000),
                    error_type=type(error).__name__,
                )
                return True
            await repository.mark_sent(outbox, provider_id)
            log_event(
                logger,
                logging.INFO,
                "push.sent",
                user_id=outbox.user_id,
                message_id=outbox.proactive_message_id,
                provider=device.provider,
                attempt=outbox.attempts + 1,
                duration_ms=round((time.perf_counter() - started_at) * 1000),
            )
            return True
