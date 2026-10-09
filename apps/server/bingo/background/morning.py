import asyncio
import logging
import random
from datetime import datetime, time, timedelta
from zoneinfo import ZoneInfo

from sqlalchemy import func, or_, update
from sqlalchemy.exc import IntegrityError
from sqlalchemy.ext.asyncio import async_sessionmaker
from sqlmodel import select
from sqlmodel.ext.asyncio.session import AsyncSession

from bingo.agent.context import build_context
from bingo.agent.model_client import ModelClient, ModelMessage
from bingo.db.models import Conversation, Message, MorningGreeting
from bingo.db.repositories import (
    ConversationRepository,
    MemoryRepository,
    ProactiveMessageRepository,
    RoleRepository,
    UserRepository,
)
from bingo.db.time import beijing_now
from bingo.prompts.morning import MORNING_GREETING_PROMPT
from bingo.push import PushService
from bingo.services.exceptions import ServiceError
from bingo.services.location import LocationService
from bingo.services.logging import log_event
from bingo.services.weather import WeatherService
from bingo.utils.assistant_text import clean_assistant_text

logger = logging.getLogger(__name__)


class MorningGreetingService:
    def __init__(
        self,
        session_factory: async_sessionmaker[AsyncSession],
        llm: ModelClient,
        *,
        location: LocationService | None = None,
        push_service: PushService | None = None,
        timezone: str = "Asia/Shanghai",
        weather: WeatherService | None = None,
    ) -> None:
        self._session_factory = session_factory
        self._llm = llm
        self._location = location
        self._push = push_service
        self._timezone = timezone
        self._zone = ZoneInfo(timezone)
        self._weather = weather or WeatherService()

    async def process(self) -> None:
        now = beijing_now().astimezone(self._zone)
        today = now.date().isoformat()
        async with self._session_factory() as session:
            await session.exec(
                update(MorningGreeting)
                .where(
                    MorningGreeting.status.in_(["pending", "processing"]),
                    or_(
                        MorningGreeting.greeting_date < today,
                        (MorningGreeting.greeting_date == today) & (now.hour >= 9),
                    ),
                )
                .values(status="skipped", claim_until=None)
            )
            await session.commit()
        if now.hour >= 9:
            return
        await self._discover(now)
        if now.hour < 7:
            return
        async with self._session_factory() as session:
            due = list(
                (
                    await session.exec(
                        select(MorningGreeting.id)
                        .where(
                            MorningGreeting.greeting_date == today,
                            MorningGreeting.scheduled_at <= now,
                            or_(
                                MorningGreeting.status == "pending",
                                (MorningGreeting.status == "processing")
                                & (MorningGreeting.claim_until <= now),
                            ),
                        )
                        .order_by(MorningGreeting.scheduled_at)
                        .limit(50)
                    )
                ).all()
            )
        semaphore = asyncio.Semaphore(5)

        async def send(greeting_id: str) -> None:
            try:
                async with semaphore:
                    await self._send(greeting_id)
            except asyncio.CancelledError:
                raise
            except Exception as error:
                log_event(logger, logging.ERROR, "morning.failed", error_type=type(error).__name__)

        await asyncio.gather(*(send(greeting_id) for greeting_id in due))

    async def _discover(self, now: datetime) -> None:
        day_start = datetime.combine(now.date(), time.min, self._zone)
        previous_start = day_start - timedelta(days=1)
        async with self._session_factory() as session:
            rows = (
                await session.exec(
                    select(Conversation.user_id, Conversation.role_id, Message.conversation_id)
                    .join(Message, Message.conversation_id == Conversation.id)
                    .where(
                        Conversation.user_id.is_not(None),
                        Message.role == "user",
                        Message.message_type == "chat",
                        Message.created_at >= previous_start,
                        Message.created_at < day_start,
                        ~select(MorningGreeting.id)
                        .where(
                            MorningGreeting.user_id == Conversation.user_id,
                            MorningGreeting.partner_key
                            == func.coalesce(Conversation.role_id, Conversation.id),
                            MorningGreeting.greeting_date == now.date().isoformat(),
                        )
                        .exists(),
                    )
                    .order_by(Message.created_at.desc(), Message.id.desc())
                )
            ).all()
        latest = dict()
        for user_id, role_id, conversation_id in rows:
            latest.setdefault((user_id, role_id or conversation_id), conversation_id)
        earliest = max(day_start + timedelta(hours=7), now)
        window_end = day_start + timedelta(hours=9)
        for (user_id, partner_key), conversation_id in latest.items():
            async with self._session_factory() as session:
                existing = (
                    await session.exec(
                        select(MorningGreeting).where(
                            MorningGreeting.user_id == user_id,
                            MorningGreeting.partner_key == partner_key,
                            MorningGreeting.greeting_date == now.date().isoformat(),
                        )
                    )
                ).first()
                if existing:
                    continue
                scheduled_at = earliest + timedelta(
                    seconds=random.randrange(max(1, int((window_end - earliest).total_seconds())))
                )
                session.add(
                    MorningGreeting(
                        user_id=user_id,
                        conversation_id=conversation_id,
                        partner_key=partner_key,
                        greeting_date=now.date().isoformat(),
                        scheduled_at=scheduled_at,
                    )
                )
                try:
                    await session.commit()
                except IntegrityError:
                    await session.rollback()

    async def _send(self, greeting_id: str) -> None:
        now = beijing_now().astimezone(self._zone)
        if not 7 <= now.hour < 9:
            return
        lease = now + timedelta(minutes=5)
        async with self._session_factory() as session:
            claimed = await session.exec(
                update(MorningGreeting)
                .where(
                    MorningGreeting.id == greeting_id,
                    MorningGreeting.scheduled_at <= now,
                    MorningGreeting.greeting_date == now.date().isoformat(),
                    or_(
                        MorningGreeting.status == "pending",
                        (MorningGreeting.status == "processing")
                        & (MorningGreeting.claim_until <= now),
                    ),
                )
                .values(
                    status="processing", claim_until=lease, attempts=MorningGreeting.attempts + 1
                )
            )
            await session.commit()
            if claimed.rowcount != 1:
                return
        try:
            await self._generate(greeting_id, lease)
        except asyncio.CancelledError:
            raise
        except Exception as error:
            async with self._session_factory() as session:
                greeting = await session.get(MorningGreeting, greeting_id)
                if greeting and greeting.status == "processing" and greeting.claim_until == lease:
                    greeting.status = (
                        "skipped"
                        if isinstance(error, ServiceError) or greeting.attempts >= 3
                        else "pending"
                    )
                    greeting.claim_until = None
                    await session.commit()
            raise

    async def _generate(self, greeting_id: str, lease: datetime) -> None:
        async with self._session_factory() as session:
            greeting = await session.get(MorningGreeting, greeting_id)
            user = await UserRepository(session).get(greeting.user_id)
            if user is None:
                raise ServiceError(404, "用户已失效")
            user = await ConversationRepository(session, user.id).context_user(
                user, greeting.conversation_id
            )
            role = await RoleRepository(session).get(user.role_id)
            memories = await MemoryRepository(session, user.id).list(30, role_id=user.role_id)
            today = datetime.combine(
                datetime.fromisoformat(greeting.greeting_date).date(), time.min, self._zone
            )
            yesterday = today - timedelta(days=1)
            messages = list(
                (
                    await session.exec(
                        select(Message)
                        .where(
                            Message.conversation_id == greeting.conversation_id,
                            Message.message_type == "chat",
                            Message.created_at >= yesterday,
                            Message.created_at < today,
                            Message.status != "streaming",
                        )
                        .order_by(Message.created_at.desc(), Message.id.desc())
                        .limit(80)
                    )
                ).all()
            )
        if not any(message.role == "user" for message in messages):
            raise ServiceError(409, "昨天没有用户对话")
        region = await self._location.current(user.id) if self._location else None
        weather = await self._weather.forecast(region, today.date(), self._timezone)
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
        transcript = "\n".join(
            f"{message.role}: {message.content}" for message in reversed(messages)
        )
        prompt = MORNING_GREETING_PROMPT.format(
            today=today.date().isoformat(),
            yesterday=yesterday.date().isoformat(),
            transcript=transcript,
            weather=weather or "未获取",
        )
        async with asyncio.timeout(90):
            content = clean_assistant_text(
                await self._llm.complete([*context, ModelMessage(role="user", content=prompt)])
            ).strip()
        if not content:
            raise ValueError("Empty morning greeting")
        async with self._session_factory() as session:
            now = beijing_now().astimezone(self._zone)
            locked = await session.exec(
                update(MorningGreeting)
                .where(
                    MorningGreeting.id == greeting_id,
                    MorningGreeting.status == "processing",
                    MorningGreeting.claim_until == lease,
                )
                .values(
                    status="sent" if now.date() == today.date() and now.hour < 9 else "skipped",
                    claim_until=None,
                )
            )
            if locked.rowcount != 1:
                return
            if now.date() != today.date() or not 7 <= now.hour < 9:
                await session.commit()
                return
            await ConversationRepository(session, user.id).context_user(
                user, greeting.conversation_id
            )
            proactive = await ProactiveMessageRepository(session, user.id).create_uncommitted(
                greeting.conversation_id,
                content[:500],
                0,
                assistant_role=user.role,
                role_id=user.role_id,
            )
            if self._push:
                await self._push.enqueue(
                    proactive, user.assistant_name or "Bingo", content[:500], session=session
                )
            await session.commit()
