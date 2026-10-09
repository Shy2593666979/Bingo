import asyncio
from datetime import timedelta
from pathlib import Path

import pytest
from sqlmodel import select

from bingo.agent.model_client import ModelMessage
from bingo.background.broker import InMemoryTaskBroker
from bingo.background.service import EngagementService
from bingo.config import Settings
from bingo.db.models import Conversation, MemoryCheckpoint, Message, RolePreference, User
from bingo.db.repositories import MemoryRepository, ProactiveMessageRepository, RoleRepository
from bingo.db.session import Database
from bingo.db.time import beijing_now
from bingo.roles import role_id


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


@pytest.mark.asyncio
async def test_only_one_hour_followup_is_scheduled_and_legacy_stages_are_ignored(tmp_path):
    assert Settings().engagement.follow_up_delays_seconds == (3600,)
    database, service, user_id, conversation_id = await _build_service(tmp_path)
    service._follow_up_delays = (3600,)
    try:
        version = await service.record_user_activity(user_id)
        await service.schedule_after_turn(
            user_id=user_id,
            conversation_id=conversation_id,
            activity_version=version,
            completed_message_id="completed-message",
        )
        followups = [job for _, _, job in service._broker._jobs if job.kind == "follow_up"]
        assert len(followups) == 1 and followups[0].payload["stage"] == 1
        for stage in (2, 3):
            await service._create_follow_up(
                {"stage": stage, "user_id": user_id, "conversation_id": conversation_id}
            )
        async with database.session_factory() as session:
            assert await ProactiveMessageRepository(session, user_id).list_pending() == []
    finally:
        await service.close()
        await database.dispose()


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
@pytest.mark.parametrize("region", [None, {"display": "河南省郑州市金水区"}])
async def test_followup_uses_shared_system_context_at_generation_time(
    tmp_path, monkeypatch, region
):
    database, service, user_id, conversation_id = await _build_service(tmp_path)
    captured = []
    location_users = []
    current_time = "2026年10月8日（周四下午） 16:32:00"

    def format_time(timezone):
        assert timezone == "Asia/Shanghai"
        return current_time

    async def complete(messages):
        captured.append(messages)
        return "今晚早点休息，好吗？"

    class Location:
        async def current(self, requested_user_id):
            location_users.append(requested_user_id)
            return region

    monkeypatch.setattr("bingo.agent.context.format_current_time", format_time)
    monkeypatch.setattr(service._llm, "complete", complete)
    service._location = Location()
    girlfriend_id = role_id("girlfriend")
    boyfriend_id = role_id("boyfriend")
    try:
        async with database.session_factory() as session:
            user = await session.get(User, user_id)
            user.username = "小明"
            user.role_id = boyfriend_id
            session.add(user)
            conversation = await session.get(Conversation, conversation_id)
            conversation.role_id = girlfriend_id
            session.add(conversation)
            session.add(
                RolePreference(user_id=user_id, role_id=girlfriend_id, personality="温柔俏皮")
            )
            await session.commit()
            role = await RoleRepository(session).get(girlfriend_id)
            role_prompt = role.context_prompt
            memories = MemoryRepository(session, user_id)
            await memories.add("用户喜欢浅烘咖啡")
            await memories.add("喜欢温柔陪伴", scope="role", role_id=girlfriend_id)
            await memories.add("约好周末散步", scope="user_role", role_id=girlfriend_id)
            await memories.add("其他伙伴的约定", scope="user_role", role_id=boyfriend_id)
        payload = {"user_id": user_id, "conversation_id": conversation_id, "stage": 1}
        await service._create_follow_up(payload)
        context, instruction = captured[0]
        assert context.role == "system"
        for expected in (
            "甜甜，小明 的个人 AI 助理",
            "关系角色：女朋友",
            role_prompt,
            "性格与说话风格：温柔俏皮",
            f"当前时间：{current_time}",
            "时区：Asia/Shanghai",
            f"用户当前位置：{region['display'] if region else '暂未获取'}",
            "用户喜欢浅烘咖啡",
            "喜欢温柔陪伴",
            "约好周末散步",
        ):
            assert expected in context.content
        assert "其他伙伴的约定" not in context.content
        assert instruction.role == "user"
        assert "我喜欢浅烘咖啡" in instruction.content
        assert "以系统提示词中的当前时间和时区为准" in instruction.content
        current_time = "2026年10月8日（周四晚上） 20:32:00"
        await service._create_follow_up(payload)
        assert f"当前时间：{current_time}" in captured[1][0].content
        assert "16:32:00" not in captured[1][0].content
        assert location_users == [user_id, user_id]
    finally:
        await service.close()
        await database.dispose()


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
        assert len(proactive) == 1
        assert proactive[0][0].stage == 1
        assert len(await service.get_recommendations(user_id)) == 3
        assert checkpoint.last_message_id == "completed-message"
    finally:
        await service.close()
        await database.dispose()


@pytest.mark.asyncio
async def test_new_activity_invalidates_old_engagement_jobs(tmp_path: Path) -> None:
    database, service, user_id, conversation_id = await _build_service(tmp_path)
    service._recommendation_delay = 18000
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
async def test_entry_only_reads_recommendation_cache_even_after_delay(
    tmp_path: Path,
) -> None:
    database, service, user_id, conversation_id = await _build_service(tmp_path)
    try:
        assert await service.get_recommendations(user_id) == []
        assert service._llm.prompts == []
        key = f"{user_id}:{conversation_id}"
        await service._broker.save_recommendations(key, ["缓存话题"])
        assert await service.get_recommendations(user_id) == ["缓存话题"]
        assert service._llm.prompts == []
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

    asyncio.run(scenario())


@pytest.mark.asyncio
async def test_recommendation_timer_resets_from_user_message_not_reply(tmp_path, monkeypatch):
    database, service, user_id, conversation_id = await _build_service(tmp_path)
    service._recommendation_delay = 18000
    now = [100.0]
    monkeypatch.setattr("bingo.background.broker.time.time", lambda: now[0])
    try:
        version = await service.record_user_activity(user_id, conversation_id)
        now[0] += 120
        await service.schedule_after_turn(
            user_id=user_id, conversation_id=conversation_id, activity_version=version,
            completed_message_id="completed-message",
        )
        jobs = [entry for entry in service._broker._jobs if entry[2].kind == "recommendations"]
        assert len(jobs) == 1 and jobs[0][0] == 18100
        now[0] = 3700
        next_version = await service.record_user_activity(user_id, conversation_id)
        jobs = [entry for entry in service._broker._jobs if entry[2].kind == "recommendations"]
        assert len(jobs) == 1 and jobs[0][0] == 21700
        assert jobs[0][2].payload["activity_version"] == next_version != version
        now[0] = 18100
        await _drain(service)
        assert await service.get_recommendations(user_id, conversation_id) == []
        now[0] = 21700
        await _drain(service)
        assert len(await service.get_recommendations(user_id, conversation_id)) == 3
    finally:
        await service.close()
        await database.dispose()


@pytest.mark.asyncio
async def test_partner_activity_and_cache_are_independent(tmp_path):
    database, service, user_id, conversation_id = await _build_service(tmp_path)
    try:
        async with database.session_factory() as session:
            second = Conversation(user_id=user_id, role_id=role_id("boyfriend"))
            session.add(second)
            await session.commit()
            second_id = second.id
        first_version = await service.record_user_activity(user_id, conversation_id)
        second_version = await service.record_user_activity(user_id, second_id)
        assert await service._is_current({
            "user_id": user_id, "conversation_id": conversation_id,
            "activity_version": first_version,
        })
        assert await service._is_current({
            "user_id": user_id, "conversation_id": second_id,
            "activity_version": second_version,
        })
        await _drain(service)
        first_items = await service.get_recommendations(user_id, conversation_id)
        second_items = await service.get_recommendations(user_id, second_id)
        assert len(first_items) == len(second_items) == 3
        await service.clear_recommendations(user_id, conversation_id)
        assert await service.get_recommendations(user_id, conversation_id) == []
        assert await service.get_recommendations(user_id, second_id) == second_items
        service._recommendation_delay = 18000
        await service.record_user_activity(user_id, conversation_id)
        assert await service.get_recommendations(user_id, second_id) == second_items
    finally:
        await service.close()
        await database.dispose()


@pytest.mark.asyncio
@pytest.mark.parametrize("new_message", [True, False])
async def test_inflight_recommendations_cannot_restore_cleared_cache(tmp_path, new_message):
    database, service, user_id, conversation_id = await _build_service(tmp_path)
    started = asyncio.Event()
    resume = asyncio.Event()

    async def complete(messages):
        started.set()
        await resume.wait()
        return '["旧话题一","旧话题二","旧话题三"]'

    service._llm.complete = complete
    try:
        await service.record_user_activity(user_id, conversation_id)
        job = await service._broker.pop_due()
        generating = asyncio.create_task(service._execute(job))
        await asyncio.wait_for(started.wait(), timeout=3)
        service._recommendation_delay = 18000
        if new_message:
            await service.record_user_activity(user_id, conversation_id)
        else:
            await service.clear_recommendations(user_id, conversation_id)
        resume.set()
        await generating
        assert await service.get_recommendations(user_id, conversation_id) == []
        jobs = [entry for entry in service._broker._jobs if entry[2].kind == "recommendations"]
        assert len(jobs) == int(new_message)
    finally:
        resume.set()
        await service.close()
        await database.dispose()


@pytest.mark.asyncio
async def test_failed_background_recommendations_retry_without_entry_generation(
    tmp_path, monkeypatch,
):
    database, service, user_id, conversation_id = await _build_service(tmp_path)
    now = [100.0]
    monkeypatch.setattr("bingo.background.broker.time.time", lambda: now[0])
    calls = []

    async def complete(messages):
        calls.append(messages)
        if len(calls) == 1:
            raise RuntimeError("temporary failure")
        return '["话题一","话题二","话题三"]'

    service._llm.complete = complete
    try:
        await service.record_user_activity(user_id, conversation_id)
        job = await service._broker.pop_due()
        with pytest.raises(RuntimeError):
            await service._execute(job)
        assert await service.get_recommendations(user_id, conversation_id) == []
        assert len(calls) == 1
        assert await service._broker.pop_due() is None
        now[0] = 160
        await _drain(service)
        assert len(calls) == 2
        assert len(await service.get_recommendations(user_id, conversation_id)) == 3
    finally:
        await service.close()
        await database.dispose()
