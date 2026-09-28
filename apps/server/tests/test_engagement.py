from datetime import timedelta
from pathlib import Path

import pytest
from sqlmodel import select

from bingo.agent.model_client import ModelMessage
from bingo.background.broker import InMemoryTaskBroker
from bingo.background.service import EngagementService
from bingo.db.models import Conversation, MemoryCheckpoint, Message, User
from bingo.db.repositories import MemoryRepository, ProactiveMessageRepository, RoleRepository
from bingo.db.session import Database
from bingo.db.time import beijing_now


class EngagementModel:
    def __init__(self) -> None:
        self.prompts: list[str] = []

    async def complete(self, messages: list[ModelMessage]) -> str:
        prompt = messages[-1].content
        self.prompts.append(prompt)
        if "长期保留" in prompt:
            return '[{"category":"preference","content":"用户喜欢浅烘咖啡"}]'
        if "推荐三个" in prompt:
            return '["聊聊咖啡豆的选择？","最近喝到什么好咖啡？","要不要规划一次咖啡探店？"]'
        if "主动回访" in prompt:
            return f"主动关心 {hash(prompt) % 100000}"
        return "[]"


async def _build_service(tmp_path: Path) -> tuple[Database, EngagementService, str, str]:
    database = Database(f"sqlite+aiosqlite:///{tmp_path / 'engagement.db'}")
    await database.initialize()
    async with database.session_factory() as session:
        user = User(phone="13800138001", password_hash="hash", assistant_name="Bingo")
        session.add(user)
        await session.flush()
        conversation = Conversation(user_id=user.id, title="咖啡")
        session.add(conversation)
        await session.flush()
        session.add(Message(conversation_id=conversation.id, role="user", content="我喜欢浅烘咖啡"))
        session.add(
            Message(
                id="completed-message",
                conversation_id=conversation.id,
                role="assistant",
                content="记住了。",
            )
        )
        await session.commit()
        user_id = user.id
        conversation_id = conversation.id
    service = EngagementService(
        database.session_factory,
        EngagementModel(),
        redis_url=None,
        follow_up_delays=(0, 0, 0),
        recommendation_delay=0,
        poll_seconds=0.01,
    )
    return database, service, user_id, conversation_id


async def _drain(service: EngagementService) -> None:
    broker = service._broker
    while job := await broker.pop_due():
        await service._execute(job)


@pytest.mark.asyncio
async def test_extracts_memory_and_creates_engagement_content(tmp_path: Path) -> None:
    database, service, user_id, conversation_id = await _build_service(tmp_path)
    try:
        version = await service.record_user_activity(user_id)
        await service.schedule_after_turn(
            user_id=user_id,
            conversation_id=conversation_id,
            activity_version=version,
            completed_message_id="completed-message",
        )
        await _drain(service)

        async with database.session_factory() as session:
            memories = await MemoryRepository(session, user_id).list()
            proactive = await ProactiveMessageRepository(session, user_id).list_pending()
            checkpoint = (await session.exec(select(MemoryCheckpoint))).one()
        assert [(item.category, item.content) for item in memories] == [
            ("preference", "用户喜欢浅烘咖啡")
        ]
        assert len(proactive) == 3
        assert len({message.content for _, message in proactive}) == 3
        assert len(await service.get_recommendations(user_id)) == 3
        assert checkpoint.last_message_id == "completed-message"
    finally:
        await service.close()
        await database.dispose()


@pytest.mark.asyncio
async def test_new_activity_invalidates_old_engagement_jobs(tmp_path: Path) -> None:
    database, service, user_id, conversation_id = await _build_service(tmp_path)
    try:
        old_version = await service.record_user_activity(user_id)
        await service.schedule_after_turn(
            user_id=user_id,
            conversation_id=conversation_id,
            activity_version=old_version,
            completed_message_id="completed-message",
        )
        await service.record_user_activity(user_id)
        await _drain(service)

        async with database.session_factory() as session:
            memories = await MemoryRepository(session, user_id).list()
            proactive = await ProactiveMessageRepository(session, user_id).list_pending()
        assert len(memories) == 1
        assert proactive == []
        assert await service.get_recommendations(user_id) == []
    finally:
        await service.close()
        await database.dispose()


@pytest.mark.asyncio
async def test_memory_batch_waits_for_completion_and_includes_interrupted_reply(
    tmp_path: Path,
) -> None:
    database = Database(f"sqlite+aiosqlite:///{tmp_path / 'memory-batch.db'}")
    await database.initialize()
    model = EngagementModel()
    service = EngagementService(
        database.session_factory,
        model,
        redis_url=None,
        follow_up_delays=(60, 120, 300),
        recommendation_delay=600,
        poll_seconds=0.01,
    )
    try:
        async with database.session_factory() as session:
            user = User(phone="13800138077", password_hash="hash")
            session.add(user)
            await session.flush()
            conversation = Conversation(user_id=user.id, title="连续对话")
            session.add(conversation)
            await session.flush()
            started_at = beijing_now()
            session.add_all(
                [
                    Message(
                        id="question-a",
                        conversation_id=conversation.id,
                        role="user",
                        content="我喜欢浅烘咖啡",
                        run_id="run-a",
                        created_at=started_at,
                    ),
                    Message(
                        id="partial-a",
                        conversation_id=conversation.id,
                        role="assistant",
                        content="我记住了。",
                        run_id="run-a",
                        status="interrupted",
                        created_at=started_at + timedelta(seconds=1),
                    ),
                    Message(
                        id="question-b",
                        conversation_id=conversation.id,
                        role="user",
                        content="以后优先推荐果香明显的",
                        run_id="run-b",
                        created_at=started_at + timedelta(seconds=2),
                    ),
                    Message(
                        id="answer-b",
                        conversation_id=conversation.id,
                        role="assistant",
                        content="好的。",
                        run_id="run-b",
                        created_at=started_at + timedelta(seconds=3),
                    ),
                ]
            )
            await session.commit()
            user_id = user.id
            conversation_id = conversation.id

        payload = {
            "user_id": user_id,
            "conversation_id": conversation_id,
            "completed_message_id": "answer-b",
            "role_id": None,
            "role_name": "朋友",
        }
        await service._extract_memories(payload)
        memory_prompt = model.prompts[-1]
        assert "用户：我喜欢浅烘咖啡" in memory_prompt
        assert "助手（回答被中断）：我记住了。" in memory_prompt
        assert "用户：以后优先推荐果香明显的" in memory_prompt
        assert "（时区：Asia/Shanghai）" in memory_prompt
        assert "当前时间：" in memory_prompt
        assert "（周" in memory_prompt
        assert "必须换算成包含具体年月日的绝对时间" in memory_prompt
        assert "不得原样保留相对时间" in memory_prompt

        prompt_count = len(model.prompts)
        await service._extract_memories(payload)
        assert len(model.prompts) == prompt_count
    finally:
        await service.close()
        await database.dispose()


@pytest.mark.asyncio
async def test_memory_extraction_prompt_resolves_relative_time(tmp_path: Path) -> None:
    database = Database(f"sqlite+aiosqlite:///{tmp_path / 'memory-time.db'}")
    await database.initialize()
    model = EngagementModel()
    service = EngagementService(
        database.session_factory,
        model,
        redis_url=None,
        follow_up_delays=(60, 120, 300),
        recommendation_delay=600,
        poll_seconds=0.01,
        timezone="Asia/Shanghai",
    )
    try:
        await service._extract_memories(
            {
                "user_id": "user-time",
                "conversation_id": "conversation-time",
                "user_text": "明天早上八点去动物园",
                "assistant_text": "好。",
                "role_name": "朋友",
            }
        )

        prompt = model.prompts[-1]
        assert "当前时间：" in prompt
        assert "用户：明天早上八点去动物园" in prompt
        assert "用户将在 YYYY年MM月DD日上午8点去动物园" in prompt
    finally:
        await service.close()
        await database.dispose()


@pytest.mark.asyncio
async def test_memory_context_only_includes_current_role(tmp_path: Path) -> None:
    database = Database(f"sqlite+aiosqlite:///{tmp_path / 'scoped-memory.db'}")
    await database.initialize()
    try:
        async with database.session_factory() as session:
            user = User(phone="13800138009", password_hash="hash")
            session.add(user)
            await session.commit()
            roles = RoleRepository(session)
            teacher = await roles.get_by_name("老师")
            girlfriend = await roles.get_by_name("女朋友")
            assert teacher is not None
            assert girlfriend is not None
            memories = MemoryRepository(session, user.id)
            await memories.add("用户住在北京")
            await memories.add(
                "老师需要检查学习计划",
                scope="role",
                role_id=teacher.id,
            )
            await memories.add(
                "用户称女朋友角色为对象",
                category="relationship",
                scope="user_role",
                role_id=girlfriend.id,
            )

            teacher_context = await memories.list(role_id=teacher.id)

        assert {item.content for item in teacher_context} == {
            "用户住在北京",
            "老师需要检查学习计划",
        }
    finally:
        await database.dispose()


@pytest.mark.asyncio
async def test_entry_regenerates_recommendations_when_delay_has_elapsed(
    tmp_path: Path,
) -> None:
    database, service, user_id, _ = await _build_service(tmp_path)
    try:
        assert await service.get_recommendations(user_id) == []

        recommendations = await service.recommendations_for_entry(user_id)

        assert len(recommendations) == 3
        assert await service.get_recommendations(user_id) == recommendations
    finally:
        await service.close()
        await database.dispose()


@pytest.mark.asyncio
async def test_proactive_messages_are_user_scoped_and_acknowledged(tmp_path: Path) -> None:
    database, _, user_id, conversation_id = await _build_service(tmp_path)
    try:
        async with database.session_factory() as session:
            second = User(phone="13800138002", password_hash="hash")
            session.add(second)
            await session.commit()
            proactive = await ProactiveMessageRepository(session, user_id).create(
                conversation_id, "还想继续聊聊咖啡吗？", 1
            )
            assert await ProactiveMessageRepository(session, second.id).list_pending() == []
            assert not await ProactiveMessageRepository(session, second.id).acknowledge(
                proactive.id
            )
            assert await ProactiveMessageRepository(session, user_id).acknowledge(proactive.id)
            assert await ProactiveMessageRepository(session, user_id).list_pending() == []
    finally:
        await database.dispose()


def test_in_memory_activity_clears_recommendations() -> None:
    async def scenario() -> None:
        broker = InMemoryTaskBroker()
        await broker.save_recommendations("user-1", ["问题一"])
        await broker.record_activity("user-1")
        assert await broker.get_recommendations("user-1") == []

    import asyncio

    asyncio.run(scenario())
