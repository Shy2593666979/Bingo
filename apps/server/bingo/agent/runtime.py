import asyncio
import logging
import time
from collections.abc import AsyncIterator
from contextlib import suppress
from dataclasses import dataclass
from typing import Any

from sqlmodel.ext.asyncio.session import AsyncSession

from bingo.agent.context import build_context
from bingo.agent.model_client import (
    ModelClient,
    ModelMessage,
    ModelTextDelta,
    ModelToolCall,
    ModelToolCalls,
)
from bingo.agent.runs import AgentRunCoordinator, AgentRunHandle
from bingo.agent.segments import split_complete_segments
from bingo.background import EngagementService
from bingo.db.models import Conversation, Memory, Message, User
from bingo.db.repositories import ConversationRepository, MemoryRepository, RoleRepository
from bingo.schemas.maps import LocationInput
from bingo.services.logging import log_event
from bingo.tools import ToolRegistry
from bingo.tools.base import ToolContext

MAX_TOOL_TURNS = 8
logger = logging.getLogger(__name__)


class AgentRunInterrupted(Exception):
    pass


@dataclass(frozen=True, slots=True)
class AgentResult:
    conversation_id: str
    message_id: str
    content: str


class AgentRuntime:
    def __init__(
        self,
        llm: ModelClient,
        tools: ToolRegistry,
        *,
        assistant_name: str,
        persona: str,
        timezone: str,
        engagement: EngagementService | None = None,
        location=None,
    ) -> None:
        self._llm = llm
        self._tools = tools
        self._assistant_name = assistant_name
        self._persona = persona
        self._timezone = timezone
        self._engagement = engagement
        self._location = location
        self._runs = AgentRunCoordinator()

    async def begin_run(
        self,
        user_id: str,
        run_id: str,
        supersedes_run_id: str | None = None,
    ) -> AgentRunHandle:
        return await self._runs.begin(user_id, run_id, supersedes_run_id)

    def stream_ephemeral(self, messages: list[ModelMessage]):
        return self._llm.stream(messages)

    async def complete_ephemeral(self, messages: list[ModelMessage]) -> str:
        return await self._llm.complete(messages)

    async def run(
        self,
        session: AsyncSession,
        user: User,
        content: str,
        conversation_id: str | None = None,
        *,
        image_data_urls: tuple[str, ...] = (),
        image_id: str | None = None,
        image_mime_type: str | None = None,
        location: LocationInput | None = None,
    ) -> AgentResult:
        started_at = time.perf_counter()
        log_event(logger, logging.INFO, "agent.started", user_id=user.id)
        try:
            repository = ConversationRepository(session, user.id)
            user = await repository.context_user(user, conversation_id)
            stored_content = content or (
                f"[位置] {location.name}：{location.address}" if location else "[图片]"
            )
            conversation, activity_version, user_message = await self._prepare_run(
                repository,
                session,
                user.id,
                stored_content,
                conversation_id,
                role_id=user.role_id,
            )
            user_message.image_id = image_id
            user_message.image_mime_type = image_mime_type
            user_message.location_json = location.model_dump_json() if location else None
            user_message.message_type = "location" if location else "chat"
            await repository.commit()
            history = await repository.list_messages(conversation.id)
            memories = await MemoryRepository(session, user.id).list(role_id=user.role_id)
            role = await RoleRepository(session).get(user.role_id)
            context = self._context(
                user,
                history,
                memories,
                role_prompt=role.context_prompt if role else "",
                current_location=await self._current_location(user.id),
            )
            if image_data_urls and context and context[-1].role == "user":
                context[-1] = ModelMessage(
                    role="user", content=content, image_data_urls=image_data_urls
                )
            reply = await self._llm.complete(context)
            assistant_message = await repository.add_message(
                conversation.id,
                "assistant",
                reply,
                assistant_role=user.role,
                role_id=user.role_id,
            )
            await repository.commit()
            await self._schedule_background(
                user.id,
                conversation.id,
                activity_version,
                assistant_message.id,
                role_id=user.role_id,
                role_name=user.role or "朋友",
            )
        except Exception as error:
            log_event(
                logger,
                logging.ERROR,
                "agent.failed",
                user_id=user.id,
                duration_ms=_duration_ms(started_at),
                error_type=type(error).__name__,
            )
            raise
        log_event(
            logger,
            logging.INFO,
            "agent.completed",
            user_id=user.id,
            conversation_id=conversation.id,
            message_id=assistant_message.id,
            duration_ms=_duration_ms(started_at),
        )
        return AgentResult(conversation.id, assistant_message.id, reply)

    async def stream_segments(
        self,
        session: AsyncSession,
        user: User,
        content: str,
        conversation_id: str | None = None,
        *,
        run_handle: AgentRunHandle,
        image_data_urls: tuple[str, ...] = (),
        image_id: str | None = None,
        image_mime_type: str | None = None,
        location: LocationInput | None = None,
        include_text_deltas: bool = False,
    ) -> AsyncIterator[dict[str, Any]]:
        started_at = time.perf_counter()
        log_event(
            logger,
            logging.INFO,
            "agent.started",
            user_id=user.id,
            run_id=run_handle.run_id,
        )
        try:
            await run_handle.wait_for_turn()
            async for event in self._stream_segments(
                session,
                user,
                content,
                conversation_id,
                run_handle=run_handle,
                image_data_urls=image_data_urls,
                image_id=image_id,
                image_mime_type=image_mime_type,
                location=location,
                include_text_deltas=include_text_deltas,
            ):
                yield event
        except AgentRunInterrupted:
            log_event(
                logger,
                logging.INFO,
                "agent.interrupted",
                user_id=user.id,
                run_id=run_handle.run_id,
                duration_ms=_duration_ms(started_at),
            )
        except Exception as error:
            log_event(
                logger,
                logging.ERROR,
                "agent.failed",
                user_id=user.id,
                duration_ms=_duration_ms(started_at),
                error_type=type(error).__name__,
            )
            raise
        finally:
            await self._runs.finish(run_handle)

    async def _stream_segments(
        self,
        session: AsyncSession,
        user: User,
        content: str,
        conversation_id: str | None = None,
        *,
        run_handle: AgentRunHandle,
        image_data_urls: tuple[str, ...] = (),
        image_id: str | None = None,
        image_mime_type: str | None = None,
        location: LocationInput | None = None,
        include_text_deltas: bool = False,
    ) -> AsyncIterator[dict[str, Any]]:
        started_at = time.perf_counter()
        repository = ConversationRepository(session, user.id)
        user = await repository.context_user(user, conversation_id)
        stored_content = content or (
            f"[位置] {location.name}：{location.address}" if location else "[图片]"
        )
        conversation, activity_version, user_message = await self._prepare_run(
            repository,
            session,
            user.id,
            stored_content,
            conversation_id,
            role_id=user.role_id,
            run_id=run_handle.run_id,
        )
        user_message.image_id = image_id
        user_message.image_mime_type = image_mime_type
        user_message.location_json = location.model_dump_json() if location else None
        user_message.message_type = "location" if location else "chat"
        await repository.commit()
        yield {
            "type": "start",
            "run_id": run_handle.run_id,
            "conversation_id": conversation.id,
            "user_message_id": user_message.id,
            "image_id": image_id,
            "created_at": user_message.created_at.isoformat(),
        }
        if run_handle.cancelled.is_set():
            yield {"type": "interrupted", "run_id": run_handle.run_id}
            raise AgentRunInterrupted

        messages = await repository.list_messages(conversation.id)
        memories = await MemoryRepository(session, user.id).list(role_id=user.role_id)
        role = await RoleRepository(session).get(user.role_id)
        history = self._context(
            user,
            messages,
            memories,
            role_prompt=role.context_prompt if role else "",
            current_location=await self._current_location(user.id),
        )
        if image_data_urls and history and history[-1].role == "user":
            history[-1] = ModelMessage(
                role="user", content=content, image_data_urls=image_data_urls
            )
        visible_reply: list[str] = []
        delivered_segments: list[str] = []
        pending = ""
        tool_context = ToolContext(
            session=session,
            user=user,
            timezone=self._timezone,
            conversation_id=conversation.id,
        )

        for _ in range(MAX_TOOL_TURNS):
            turn_text: list[str] = []
            tool_calls: tuple[ModelToolCall, ...] = ()
            try:
                async for event in _interruptible_stream(
                    self._llm.stream(history, self._tools.definitions()),
                    run_handle.cancelled,
                ):
                    if isinstance(event, ModelTextDelta):
                        if include_text_deltas:
                            yield {"type": "text_delta", "content": event.content}
                        turn_text.append(event.content)
                        visible_reply.append(event.content)
                        pending += event.content
                        segments, pending = split_complete_segments(pending)
                        for segment in segments:
                            delivered_segments.append(segment)
                            yield {"type": "segment", "content": segment}
                    elif isinstance(event, ModelToolCalls):
                        tool_calls = event.calls
            except AgentRunInterrupted:
                await self._save_interrupted_reply(
                    repository,
                    conversation.id,
                    run_handle.run_id,
                    delivered_segments,
                    user,
                )
                yield {"type": "interrupted", "run_id": run_handle.run_id}
                raise

            history.append(
                ModelMessage(
                    role="assistant",
                    content="".join(turn_text),
                    tool_calls=tool_calls,
                )
            )
            if not tool_calls:
                break

            if pending.strip():
                segments, _ = split_complete_segments(pending, final=True)
                for segment in segments:
                    delivered_segments.append(segment)
                    yield {"type": "segment", "content": segment}
                pending = ""

            for call in tool_calls:
                try:
                    result = await _interruptible_wait(
                        self._tools.execute(call.name, call.arguments, tool_context),
                        run_handle.cancelled,
                    )
                except AgentRunInterrupted:
                    await self._save_interrupted_reply(
                        repository,
                        conversation.id,
                        run_handle.run_id,
                        delivered_segments,
                        user,
                    )
                    yield {"type": "interrupted", "run_id": run_handle.run_id}
                    raise
                if result.client_event:
                    yield result.client_event
                history.append(
                    ModelMessage(
                        role="tool",
                        content=result.content,
                        tool_call_id=call.call_id,
                    )
                )
        else:
            log_event(
                logger,
                logging.ERROR,
                "agent.failed",
                user_id=user.id,
                conversation_id=conversation.id,
                duration_ms=_duration_ms(started_at),
                error_type="MaxToolTurnsExceeded",
            )
            yield {"type": "error", "message": "工具调用次数过多，本次任务已停止"}
            return

        if run_handle.cancelled.is_set():
            await self._save_interrupted_reply(
                repository,
                conversation.id,
                run_handle.run_id,
                delivered_segments,
                user,
            )
            yield {"type": "interrupted", "run_id": run_handle.run_id}
            raise AgentRunInterrupted

        if pending.strip():
            segments, _ = split_complete_segments(pending, final=True)
            for segment in segments:
                delivered_segments.append(segment)
                yield {"type": "segment", "content": segment}

        reply = "".join(visible_reply).strip()
        assistant_message = await repository.add_message(
            conversation.id,
            "assistant",
            reply,
            assistant_role=user.role,
            role_id=user.role_id,
            run_id=run_handle.run_id,
            status="completed",
        )
        await repository.commit()
        await self._schedule_background(
            user.id,
            conversation.id,
            activity_version,
            assistant_message.id,
            role_id=user.role_id,
            role_name=user.role or "朋友",
        )
        log_event(
            logger,
            logging.INFO,
            "agent.completed",
            user_id=user.id,
            conversation_id=conversation.id,
            message_id=assistant_message.id,
            duration_ms=_duration_ms(started_at),
        )
        yield {
            "type": "done",
            "run_id": run_handle.run_id,
            "message_id": assistant_message.id,
            "created_at": assistant_message.created_at.isoformat(),
            "assistant_role": assistant_message.assistant_role,
        }

    async def _prepare_run(
        self,
        repository: ConversationRepository,
        session: AsyncSession,
        user_id: str,
        content: str,
        conversation_id: str | None,
        *,
        role_id: str | None = None,
        run_id: str | None = None,
    ) -> tuple[Conversation, str | None, Message]:
        conversation = await repository.get_or_create(conversation_id)
        if conversation.title == "New conversation":
            conversation.title = content[:80]
        user_message = await repository.add_message(
            conversation.id,
            "user",
            content,
            role_id=role_id,
            run_id=run_id,
        )
        await repository.commit()
        await self._remember_explicit_fact(session, user_id, content)
        activity_version = None
        if self._engagement is not None:
            activity_version = await self._engagement.record_user_activity(user_id, conversation.id)
        return conversation, activity_version, user_message

    async def _schedule_background(
        self,
        user_id: str,
        conversation_id: str,
        activity_version: str | None,
        completed_message_id: str,
        role_id: str | None = None,
        role_name: str = "朋友",
    ) -> None:
        if self._engagement is None or activity_version is None:
            return
        await self._engagement.schedule_after_turn(
            user_id=user_id,
            conversation_id=conversation_id,
            activity_version=activity_version,
            completed_message_id=completed_message_id,
            role_id=role_id,
            role_name=role_name,
        )

    async def _save_interrupted_reply(
        self,
        repository: ConversationRepository,
        conversation_id: str,
        run_id: str,
        segments: list[str],
        user: User,
    ) -> Message | None:
        content = "".join(segments).strip()
        if not content:
            return None
        message = await repository.add_message(
            conversation_id,
            "assistant",
            content,
            assistant_role=user.role,
            role_id=user.role_id,
            run_id=run_id,
            status="interrupted",
        )
        await repository.commit()
        return message

    def _context(
        self,
        user: User,
        messages: list[Message],
        memories: list[Memory],
        *,
        role_prompt: str = "",
        current_location: str = "",
    ) -> list[ModelMessage]:
        return build_context(
            messages,
            memories,
            username=user.username or "用户",
            assistant_name=user.assistant_name or self._assistant_name,
            personality=user.personality or self._persona,
            role=user.role or "朋友",
            timezone=self._timezone,
            role_prompt=role_prompt,
            current_location=current_location,
        )

    async def _current_location(self, user_id: str) -> str:
        region = await self._location.current(user_id) if self._location else None
        return region["display"] if region else ""

    async def _remember_explicit_fact(
        self, session: AsyncSession, user_id: str, content: str
    ) -> None:
        normalized = content.strip()
        for prefix in ("请记住", "记住"):
            if normalized.startswith(prefix):
                fact = normalized[len(prefix) :].lstrip("：:，, ").strip()
                if fact:
                    await MemoryRepository(session, user_id).add(fact)
                return


def _duration_ms(started_at: float) -> int:
    return round((time.perf_counter() - started_at) * 1000)


async def _interruptible_stream(
    source: AsyncIterator[Any],
    cancelled: asyncio.Event,
) -> AsyncIterator[Any]:
    iterator = source.__aiter__()
    while True:
        if cancelled.is_set():
            await iterator.aclose()
            raise AgentRunInterrupted
        next_event = asyncio.create_task(anext(iterator))
        cancellation = asyncio.create_task(cancelled.wait())
        done, _ = await asyncio.wait(
            {next_event, cancellation},
            return_when=asyncio.FIRST_COMPLETED,
        )
        if cancellation in done and cancelled.is_set():
            next_event.cancel()
            with suppress(asyncio.CancelledError, StopAsyncIteration):
                await next_event
            await iterator.aclose()
            raise AgentRunInterrupted
        cancellation.cancel()
        with suppress(asyncio.CancelledError):
            await cancellation
        try:
            yield next_event.result()
        except StopAsyncIteration:
            return


async def _interruptible_wait(awaitable, cancelled: asyncio.Event):
    if cancelled.is_set():
        raise AgentRunInterrupted
    operation = asyncio.create_task(awaitable)
    cancellation = asyncio.create_task(cancelled.wait())
    done, _ = await asyncio.wait({operation, cancellation}, return_when=asyncio.FIRST_COMPLETED)
    if cancellation in done and cancelled.is_set():
        operation.cancel()
        with suppress(asyncio.CancelledError):
            await operation
        raise AgentRunInterrupted
    cancellation.cancel()
    with suppress(asyncio.CancelledError):
        await cancellation
    return operation.result()
