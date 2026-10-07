import asyncio
import logging
from collections.abc import AsyncIterator
from contextlib import suppress
from dataclasses import dataclass, field
from typing import Any

from sqlalchemy.ext.asyncio import async_sessionmaker
from sqlmodel.ext.asyncio.session import AsyncSession

from bingo.agent.runtime import AgentRuntime
from bingo.db.repositories import UserRepository
from bingo.schemas.maps import LocationInput
from bingo.services.logging import log_event

logger = logging.getLogger(__name__)


@dataclass(eq=False, slots=True)
class _Subscriber:
    queue: asyncio.Queue[dict[str, Any] | None] = field(default_factory=asyncio.Queue)


@dataclass(slots=True)
class _RunState:
    user_id: str
    run_id: str
    subscribers: set[_Subscriber] = field(default_factory=set)
    task: asyncio.Task[None] | None = None


class ChatRunSubscription:
    def __init__(
        self,
        service: "ChatRunService",
        state: _RunState,
        subscriber: _Subscriber,
    ) -> None:
        self._service = service
        self._state = state
        self._subscriber = subscriber
        self._closed = False

    async def events(self) -> AsyncIterator[dict[str, Any]]:
        while True:
            event = await self._subscriber.queue.get()
            if event is None:
                return
            yield event

    async def close(self) -> None:
        if self._closed:
            return
        self._closed = True
        await self._service.unsubscribe(self._state, self._subscriber)


class ChatRunService:
    """Own chat generation independently from any individual HTTP connection."""

    def __init__(
        self,
        session_factory: async_sessionmaker[AsyncSession],
        runtime: AgentRuntime,
    ) -> None:
        self._session_factory = session_factory
        self._runtime = runtime
        self._runs: dict[tuple[str, str], _RunState] = {}
        self._lock = asyncio.Lock()

    async def subscribe(
        self,
        *,
        user_id: str,
        run_id: str,
        supersedes_run_id: str | None,
        content: str,
        conversation_id: str | None,
        image_data_urls: tuple[str, ...] = (),
        image_id: str | None = None,
        image_mime_type: str | None = None,
        location: LocationInput | None = None,
        include_text_deltas: bool = False,
    ) -> ChatRunSubscription:
        key = (user_id, run_id)
        async with self._lock:
            state = self._runs.get(key)
            if state is None:
                run_handle = await self._runtime.begin_run(
                    user_id,
                    run_id,
                    supersedes_run_id,
                )
                state = _RunState(user_id=user_id, run_id=run_id)
                self._runs[key] = state
                state.task = asyncio.create_task(
                    self._execute(
                        state,
                        run_handle=run_handle,
                        content=content,
                        conversation_id=conversation_id,
                        image_data_urls=image_data_urls,
                        image_id=image_id,
                        image_mime_type=image_mime_type,
                        location=location,
                        include_text_deltas=include_text_deltas,
                    ),
                    name=f"chat-run-{run_id}",
                )
            subscriber = _Subscriber()
            state.subscribers.add(subscriber)
        return ChatRunSubscription(self, state, subscriber)

    async def unsubscribe(self, state: _RunState, subscriber: _Subscriber) -> None:
        async with self._lock:
            state.subscribers.discard(subscriber)

    async def close(self) -> None:
        async with self._lock:
            tasks = [state.task for state in self._runs.values() if state.task is not None]
        for task in tasks:
            task.cancel()
        for task in tasks:
            with suppress(asyncio.CancelledError):
                await task

    async def _execute(
        self,
        state: _RunState,
        *,
        run_handle,
        content: str,
        conversation_id: str | None,
        image_data_urls: tuple[str, ...],
        image_id: str | None,
        image_mime_type: str | None,
        location: LocationInput | None,
        include_text_deltas: bool = False,
    ) -> None:
        try:
            async with self._session_factory() as session:
                user = await UserRepository(session).get(state.user_id)
                if user is None:
                    raise ValueError("用户不存在或登录状态已失效")
                async for event in self._runtime.stream_segments(
                    session,
                    user,
                    content,
                    conversation_id,
                    run_handle=run_handle,
                    image_data_urls=image_data_urls,
                    image_id=image_id,
                    image_mime_type=image_mime_type,
                    location=location,
                    **({"include_text_deltas": True} if include_text_deltas else {}),
                ):
                    await self._publish(state, event)
        except asyncio.CancelledError:
            raise
        except Exception as error:
            log_event(
                logger,
                logging.ERROR,
                "chat_run.failed",
                user_id=state.user_id,
                run_id=state.run_id,
                error_type=type(error).__name__,
            )
            await self._publish(
                state,
                {"type": "error", "message": f"回复生成失败：{error}"},
            )
        finally:
            await self._finish(state)

    async def _publish(self, state: _RunState, event: dict[str, Any]) -> None:
        async with self._lock:
            subscribers = tuple(state.subscribers)
        for subscriber in subscribers:
            subscriber.queue.put_nowait(event)

    async def _finish(self, state: _RunState) -> None:
        key = (state.user_id, state.run_id)
        async with self._lock:
            subscribers = tuple(state.subscribers)
            if self._runs.get(key) is state:
                self._runs.pop(key, None)
        for subscriber in subscribers:
            subscriber.queue.put_nowait(None)
