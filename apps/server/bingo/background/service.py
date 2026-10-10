import asyncio
import json
import logging
import time
from contextlib import suppress
from typing import Any

from sqlalchemy.ext.asyncio import async_sessionmaker
from sqlmodel.ext.asyncio.session import AsyncSession

from bingo.agent.context import build_context
from bingo.agent.model_client import ModelClient, ModelMessage
from bingo.background.broker import (
    BackgroundJob,
    InMemoryTaskBroker,
    RedisTaskBroker,
    TaskBroker,
)
from bingo.background.morning import MorningGreetingService
from bingo.db.models import Message
from bingo.db.repositories import (
    ConversationRepository,
    MemoryCheckpointRepository,
    MemoryRepository,
    ProactiveMessageRepository,
    RoleRepository,
    UserRepository,
)
from bingo.prompts import (
    FOLLOW_UP_PROMPT,
    FOLLOW_UP_STAGE_INSTRUCTIONS,
    MEMORY_EXTRACTION_PROMPT,
    RECOMMENDATIONS_PROMPT,
)
from bingo.push import PushService
from bingo.services.location import LocationService
from bingo.services.logging import log_event
from bingo.utils.assistant_text import clean_assistant_text
from bingo.utils.time import format_current_time

logger = logging.getLogger(__name__)

MEMORY_CATEGORIES = {"identity", "preference", "habit", "goal", "relationship", "constraint"}


class EngagementService:
    def __init__(
        self,
        session_factory: async_sessionmaker[AsyncSession],
        llm: ModelClient,
        *,
        redis_url: str | None,
        follow_up_delays: tuple[int, ...],
        recommendation_delay: int,
        poll_seconds: float,
        push_service: PushService | None = None,
        timezone: str = "Asia/Shanghai",
        location: LocationService | None = None,
    ) -> None:
        self._session_factory = session_factory
        self._llm = llm
        self._broker: TaskBroker = RedisTaskBroker(redis_url) if redis_url else InMemoryTaskBroker()
        self._follow_up_delays = follow_up_delays[:1]
        self._recommendation_delay = recommendation_delay
        self._poll_seconds = poll_seconds
        self._push_service = push_service
        self._timezone = timezone
        self._location = location
        self._worker: asyncio.Task[None] | None = None
        self._active_jobs: dict[str, asyncio.Task] = {}
        self._morning = MorningGreetingService(
            session_factory, llm, location=location, push_service=push_service, timezone=timezone
        )
        self._morning_worker: asyncio.Task[None] | None = None

    async def start(self) -> None:
        if isinstance(self._broker, RedisTaskBroker):
            await self._broker.start()
        self._worker = asyncio.create_task(self._run_worker(), name="bingo-background-worker")
        self._morning_worker = asyncio.create_task(
            self._run_morning_worker(), name="bingo-morning-worker"
        )

    async def close(self) -> None:
        if self._morning_worker is not None:
            self._morning_worker.cancel()
            with suppress(asyncio.CancelledError):
                await self._morning_worker
        if self._worker is not None:
            self._worker.cancel()
            with suppress(asyncio.CancelledError):
                await self._worker
        await self._broker.close()

    async def record_user_activity(self, user_id: str, conversation_id: str | None = None) -> str:
        key, target = await self._recommendation_target(user_id, conversation_id)
        return await self._broker.record_activity(
            key,
            recommendation_payload=(
                {"user_id": user_id, "conversation_id": target} if target else None
            ),
            recommendation_delay=self._recommendation_delay,
        )

    async def schedule_after_turn(
        self,
        *,
        user_id: str,
        conversation_id: str,
        activity_version: str,
        completed_message_id: str,
        role_id: str | None = None,
        role_name: str = "朋友",
    ) -> None:
        common = {
            "user_id": user_id,
            "conversation_id": conversation_id,
            "activity_version": activity_version,
            "role_id": role_id,
            "role_name": role_name,
        }
        await self._broker.schedule(
            "memory_extract",
            {**common, "completed_message_id": completed_message_id},
            0,
        )
        for stage, delay in enumerate(self._follow_up_delays, start=1):
            await self._broker.schedule("follow_up", {**common, "stage": stage}, delay)
        log_event(
            logger,
            logging.INFO,
            "background.scheduled",
            user_id=user_id,
            conversation_id=conversation_id,
            count=len(self._follow_up_delays) + 1,
        )

    async def _recommendation_target(
        self, user_id: str, conversation_id: str | None = None
    ) -> tuple[str, str | None]:
        async with self._session_factory() as session:
            repository = ConversationRepository(session, user_id)
            if conversation_id:
                conversation = await repository.get_or_create(conversation_id)
            else:
                user = await UserRepository(session).get(user_id)
                conversations = await repository.list_conversations(200)
                conversation = next(
                    (item for item in conversations if user and item.role_id == user.role_id), None
                )
        target = conversation.id if conversation else None
        return (f"{user_id}:{target}" if target else user_id), target

    async def get_recommendations(
        self, user_id: str, conversation_id: str | None = None
    ) -> list[str]:
        key, _ = await self._recommendation_target(user_id, conversation_id)
        return await self._broker.get_recommendations(key)

    async def clear_recommendations(self, user_id: str, conversation_id: str | None = None) -> None:
        key, _ = await self._recommendation_target(user_id, conversation_id)
        await self._broker.clear_recommendations(key)

    async def forget_user(self, user_id: str, conversation_ids: list[str]) -> None:
        await self._broker.forget_user(user_id, conversation_ids)
        task = self._active_jobs.get(user_id)
        if task is not None:
            task.cancel()
            await asyncio.gather(task, return_exceptions=True)

    async def _run_worker(self) -> None:
        while True:
            try:
                job = await self._broker.pop_due()
                if job is None:
                    await asyncio.sleep(self._poll_seconds)
                    continue
                user_id = job.payload.get("user_id", "")
                task = asyncio.create_task(self._execute(job))
                self._active_jobs[user_id] = task
                try:
                    await task
                except asyncio.CancelledError:
                    if asyncio.current_task().cancelling():
                        raise
                finally:
                    self._active_jobs.pop(user_id, None)
            except asyncio.CancelledError:
                raise
            except Exception as error:
                log_event(
                    logger,
                    logging.ERROR,
                    "background.failed",
                    error_type=type(error).__name__,
                )
                await asyncio.sleep(self._poll_seconds)

    async def _run_morning_worker(self) -> None:
        while True:
            try:
                await self._morning.process()
            except asyncio.CancelledError:
                raise
            except Exception as error:
                log_event(
                    logger, logging.ERROR, "morning.scan_failed", error_type=type(error).__name__
                )
            await asyncio.sleep(30)

    async def _execute(self, job: BackgroundJob) -> None:
        started_at = time.perf_counter()
        if job.kind != "memory_extract" and not await self._is_current(job.payload):
            return
        if job.kind == "memory_extract":
            await self._extract_memories(job.payload)
        elif job.kind == "follow_up":
            await self._create_follow_up(job.payload)
        elif job.kind == "recommendations":
            try:
                await self._create_recommendations(job.payload)
            except Exception:
                attempts = job.payload.get("attempts", 0)
                if attempts < 3 and await self._is_current(job.payload):
                    await self._broker.schedule(
                        "recommendations",
                        {**job.payload, "attempts": attempts + 1},
                        60 * (attempts + 1),
                    )
                raise
        log_event(
            logger,
            logging.INFO,
            "background.completed",
            job=job.kind,
            user_id=job.payload.get("user_id"),
            duration_ms=round((time.perf_counter() - started_at) * 1000),
        )

    async def _is_current(self, payload: dict[str, Any]) -> bool:
        key = f"{payload['user_id']}:{payload['conversation_id']}"
        return await self._broker.current_version(key) == payload["activity_version"]

    async def _extract_memories(self, payload: dict[str, Any]) -> None:
        completed_message_id = payload.get("completed_message_id")
        if completed_message_id:
            async with self._session_factory() as session:
                checkpoints = MemoryCheckpointRepository(session, payload["user_id"])
                messages = await checkpoints.pending_messages(
                    payload["conversation_id"],
                    completed_message_id,
                    payload.get("role_id"),
                )
            if not messages:
                return
            transcript = "\n".join(_memory_transcript_line(message) for message in messages)
        else:
            # Drain jobs queued by versions that embedded one completed turn.
            transcript = (
                f"用户：{payload.get('user_text', '')}\n助手：{payload.get('assistant_text', '')}"
            )
        prompt = MEMORY_EXTRACTION_PROMPT.format(
            transcript=transcript,
            role_name=payload.get("role_name") or "朋友",
            current_time=format_current_time(self._timezone),
            timezone=self._timezone,
        )
        raw = await self._llm.complete([ModelMessage(role="user", content=prompt)])
        items = _parse_json_list(raw)
        saved_count = 0
        async with self._session_factory() as session:
            repository = MemoryRepository(session, payload["user_id"])
            for item in items[:5]:
                if not isinstance(item, dict):
                    continue
                category = str(item.get("category", "fact"))
                scope = str(item.get("scope", "user"))
                content = str(item.get("content", "")).strip()
                if (
                    category in MEMORY_CATEGORIES
                    and scope in {"user", "role", "user_role"}
                    and content
                ):
                    if scope != "user" and not payload.get("role_id"):
                        continue
                    await repository.add(
                        content[:2000],
                        category,
                        scope=scope,
                        role_id=payload.get("role_id"),
                    )
                    saved_count += 1
            if completed_message_id:
                await MemoryCheckpointRepository(session, payload["user_id"]).advance(
                    payload["conversation_id"],
                    payload.get("role_id"),
                    completed_message_id,
                )
        log_event(
            logger,
            logging.INFO,
            "memory.extracted",
            user_id=payload["user_id"],
            count=saved_count,
        )

    async def _create_follow_up(self, payload: dict[str, Any]) -> None:
        stage = int(payload["stage"])
        if stage != 1:
            return
        async with self._session_factory() as session:
            user = await UserRepository(session).get(payload["user_id"])
            if user is None:
                return
            user = await ConversationRepository(session, user.id).context_user(
                user, payload["conversation_id"]
            )
            messages = await ConversationRepository(session, user.id).list_messages(
                payload["conversation_id"], 30
            )
            role = await RoleRepository(session).get(user.role_id)
            memories = await MemoryRepository(session, user.id).list(30, role_id=user.role_id)
            region = await self._location.current(user.id) if self._location else None
            context = build_context(
                [],
                memories,
                username=user.username or "用户",
                assistant_name=user.assistant_name or "Bingo",
                personality=user.personality or "温柔体贴",
                role=user.role or "朋友",
                timezone=self._timezone,
                role_prompt=role.context_prompt if role else "",
                current_location=region["display"] if region else "",
            )
            chat_messages = [item for item in messages if item.message_type == "chat"]
            transcript = "\n".join(f"{item.role}: {item.content}" for item in chat_messages)
            prompt = FOLLOW_UP_PROMPT.format(
                assistant_name=user.assistant_name or "Bingo",
                role_name=user.role or "朋友",
                stage_instruction=FOLLOW_UP_STAGE_INSTRUCTIONS[stage],
                transcript=transcript,
            )
            content = clean_assistant_text(
                await self._llm.complete([*context, ModelMessage(role="user", content=prompt)])
            ).strip()
            if content:
                proactive = await ProactiveMessageRepository(session, user.id).create(
                    payload["conversation_id"],
                    content[:500],
                    stage,
                    assistant_role=user.role,
                    role_id=user.role_id,
                )
                if self._push_service is not None:
                    await self._push_service.enqueue(
                        proactive,
                        user.assistant_name or "Bingo",
                        content[:500],
                    )

    async def _create_recommendations(self, payload: dict[str, Any]) -> None:
        if not await self._is_current(payload):
            return
        async with self._session_factory() as session:
            user = await UserRepository(session).get(payload["user_id"])
            if user is None:
                return
            user = await ConversationRepository(session, user.id).context_user(
                user, payload["conversation_id"]
            )
            messages = await ConversationRepository(session, user.id).list_messages(
                payload["conversation_id"], 40
            )
            memories = await MemoryRepository(session, user.id).list(30, role_id=user.role_id)
            chat_messages = [item for item in messages if item.message_type == "chat"]
            transcript = "\n".join(f"{item.role}: {item.content}" for item in chat_messages)
            memory_text = "\n".join(item.content for item in memories)
            prompt = RECOMMENDATIONS_PROMPT.format(
                memory_text=memory_text,
                transcript=transcript,
            )
            raw = await self._llm.complete([ModelMessage(role="user", content=prompt)])
            parsed = _parse_json_list(raw)
            items = [str(item).strip()[:120] for item in parsed if isinstance(item, str)]
            if len(items) < 3:
                topic = next(
                    (item.content for item in reversed(chat_messages) if item.role == "user"),
                    "最近的话题",
                )
                items = [
                    f"帮我从「{topic[:20]}」继续挖掘一个有意思的方向",
                    "结合我的长期偏好，陪我聊聊最近最值得投入的兴趣",
                    "帮我回看最近的目标，找出最值得继续深入的线索",
                ]
            await self._broker.save_recommendations(
                f"{user.id}:{payload['conversation_id']}",
                items[:3],
                activity_version=payload["activity_version"],
            )


def _parse_json_list(raw: str) -> list[Any]:
    text = raw.strip()
    if text.startswith("```"):
        text = text.removeprefix("```json").removeprefix("```")
        text = text.removesuffix("```").strip()
    try:
        value = json.loads(text)
    except json.JSONDecodeError:
        return []
    return value if isinstance(value, list) else []


def _memory_transcript_line(message: Message) -> str:
    speaker = "用户" if message.role == "user" else "助手"
    interrupted = "（回答被中断）" if message.status == "interrupted" else ""
    return f"{speaker}{interrupted}：{message.content}"
