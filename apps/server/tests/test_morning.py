import asyncio
from datetime import datetime, timedelta

import pytest
from sqlalchemy import update
from sqlmodel import select

from bingo.background import morning
from bingo.background.morning import MorningGreetingService
from bingo.db.models import Conversation, Message, MorningGreeting, PushOutbox, RolePreference, User
from bingo.db.repositories import (
    MemoryRepository,
    ProactiveMessageRepository,
    PushDeviceRepository,
    RoleRepository,
)
from bingo.db.session import Database
from bingo.db.time import BEIJING_TIMEZONE
from bingo.push.service import PushService


class MorningModel:
    def __init__(self):
        self.calls = []
        self.fail = False

    async def complete(self, messages):
        self.calls.append(messages)
        if self.fail:
            raise RuntimeError("temporary failure")
        return "小雨，早上好呀。昨天你提到的面试准备得怎么样了？"


class MorningWeather:
    def __init__(self):
        self.calls = []

    async def forecast(self, region, today, timezone):
        self.calls.append((region, today, timezone))
        return "今天的地区级预报：晴，18～25 摄氏度" if region else ""


@pytest.fixture
async def setup_morning(tmp_path, monkeypatch):
    database = Database(f"sqlite+aiosqlite:///{tmp_path / 'morning.db'}")
    await database.initialize()
    clock = [datetime(2026, 10, 3, 6, tzinfo=BEIJING_TIMEZONE)]
    monkeypatch.setattr(morning, "beijing_now", lambda: clock[0])
    monkeypatch.setattr(morning.random, "randrange", lambda limit: 0)
    async with database.session_factory() as session:
        girlfriend = await RoleRepository(session).get_by_name("女朋友")
        boyfriend = await RoleRepository(session).get_by_name("男朋友")
        user = User(
            phone="13800139991",
            password_hash="hash",
            username="小雨",
            role_id=boyfriend.id,
            role="男朋友",
            personality="沉稳克制",
        )
        session.add(user)
        await session.flush()
        first = Conversation(user_id=user.id, role_id=boyfriend.id)
        latest = Conversation(user_id=user.id, role_id=girlfriend.id)
        session.add_all([first, latest])
        await session.flush()
        session.add_all(
            [
                Message(
                    conversation_id=first.id,
                    role="user",
                    content="另外一位伙伴的秘密",
                    created_at=clock[0] - timedelta(days=2),
                ),
                Message(
                    conversation_id=latest.id,
                    role="user",
                    content="明天要面试，有一点紧张",
                    created_at=clock[0] - timedelta(hours=8),
                ),
                Message(
                    conversation_id=latest.id,
                    role="assistant",
                    content="今晚好好休息。",
                    created_at=clock[0] - timedelta(hours=8) + timedelta(seconds=1),
                ),
                Message(
                    conversation_id=latest.id,
                    role="user",
                    content="前天的旧消息",
                    created_at=clock[0] - timedelta(days=2),
                ),
                RolePreference(user_id=user.id, role_id=girlfriend.id, personality="幽默风趣"),
            ]
        )
        await session.commit()
        await MemoryRepository(session, user.id).add("用户喜欢浅烘咖啡", "preference")
        await MemoryRepository(session, user.id).add(
            "女朋友要温柔鼓励", "preference", scope="user_role", role_id=girlfriend.id
        )
        await MemoryRepository(session, user.id).add(
            "男朋友专属记忆", "preference", scope="user_role", role_id=boyfriend.id
        )
        identity = user.id
        conversation_id = latest.id
    model = MorningModel()
    weather = MorningWeather()
    service = MorningGreetingService(database.session_factory, model, weather=weather)
    yield database, service, model, clock, identity, conversation_id, weather
    await database.dispose()


@pytest.mark.asyncio
async def test_random_time_persists_across_restart(setup_morning, monkeypatch):
    database, service, model, clock, identity, conversation_id, weather = setup_morning
    monkeypatch.setattr(morning.random, "randrange", lambda limit: limit - 1)
    await service.process()
    async with database.session_factory() as session:
        scheduled = (await session.exec(select(MorningGreeting))).one()
        assert scheduled.scheduled_at.hour == 8
        assert scheduled.scheduled_at.minute == 59
        assert scheduled.scheduled_at.second == 59
        original = scheduled.scheduled_at
    restarted = MorningGreetingService(database.session_factory, model, weather=weather)
    monkeypatch.setattr(morning.random, "randrange", lambda limit: 0)
    await restarted.process()
    async with database.session_factory() as session:
        assert (await session.exec(select(MorningGreeting))).one().scheduled_at == original
    assert model.calls == []


@pytest.mark.asyncio
async def test_greeting_uses_partner_yesterday_memory_and_personality_once(setup_morning):
    database, service, model, clock, identity, conversation_id, weather = setup_morning
    await service.process()
    clock[0] = clock[0].replace(hour=7)
    async with database.session_factory() as session:
        session.add(
            Message(
                conversation_id=conversation_id,
                role="user",
                content="今天的新消息",
                created_at=clock[0],
            )
        )
        await session.commit()
    await service.process()
    await service.process()
    assert len(model.calls) == 1
    system, prompt = [message.content for message in model.calls[0]]
    assert "甜甜" in system and "幽默风趣" in system and "女朋友" in system
    assert "用户喜欢浅烘咖啡" in system and "女朋友要温柔鼓励" in system
    assert "男朋友专属记忆" not in system
    assert "今天是 2026-10-03，昨天是 2026-10-02" in prompt
    assert "明天要面试" in prompt
    assert "今天的新消息" not in prompt and "前天的旧消息" not in prompt
    assert "另外一位伙伴的秘密" not in prompt
    assert "没有天气资料就完全省略" in prompt
    assert "未获取" in prompt
    async with database.session_factory() as session:
        pending = await ProactiveMessageRepository(session, identity).list_pending()
        assert len(pending) == 1 and pending[0][0].stage == 0
        assert pending[0][1].conversation_id == conversation_id
        assert (await session.exec(select(MorningGreeting))).one().status == "sent"


@pytest.mark.asyncio
async def test_does_not_greet_without_yesterday_user_message(setup_morning):
    database, service, model, clock, identity, conversation_id, weather = setup_morning
    async with database.session_factory() as session:
        await session.exec(update(Message).where(Message.role == "user").values(role="assistant"))
        await session.commit()
    clock[0] = clock[0].replace(hour=8)
    await service.process()
    async with database.session_factory() as session:
        assert list((await session.exec(select(MorningGreeting))).all()) == []
    assert model.calls == []


@pytest.mark.asyncio
async def test_never_sends_after_nine(setup_morning):
    database, service, model, clock, identity, conversation_id, weather = setup_morning
    await service.process()
    clock[0] = clock[0].replace(hour=9)
    await service.process()
    async with database.session_factory() as session:
        assert (await session.exec(select(MorningGreeting))).one().status == "skipped"
    assert model.calls == []


@pytest.mark.asyncio
async def test_failure_retries_without_duplicate_message(setup_morning):
    database, service, model, clock, identity, conversation_id, weather = setup_morning
    await service.process()
    clock[0] = clock[0].replace(hour=7)
    model.fail = True
    await service.process()
    async with database.session_factory() as session:
        greeting = (await session.exec(select(MorningGreeting))).one()
        assert greeting.status == "pending" and greeting.attempts == 1
    model.fail = False
    await service.process()
    async with database.session_factory() as session:
        assert len(await ProactiveMessageRepository(session, identity).list_pending()) == 1


@pytest.mark.asyncio
async def test_parallel_workers_do_not_duplicate_greeting(setup_morning):
    database, service, model, clock, identity, conversation_id, weather = setup_morning
    await service.process()
    clock[0] = clock[0].replace(hour=7)
    second = MorningGreetingService(database.session_factory, model, weather=weather)
    await asyncio.gather(service.process(), second.process())
    async with database.session_factory() as session:
        assert len(await ProactiveMessageRepository(session, identity).list_pending()) == 1
    assert len(model.calls) == 1


@pytest.mark.asyncio
async def test_deleted_partner_is_skipped(setup_morning):
    database, service, model, clock, identity, conversation_id, weather = setup_morning
    await service.process()
    async with database.session_factory() as session:
        role = await RoleRepository(session).get_by_name("女朋友")
        role.deleted = True
        session.add(role)
        await session.commit()
    clock[0] = clock[0].replace(hour=7)
    await service.process()
    async with database.session_factory() as session:
        assert (await session.exec(select(MorningGreeting))).one().status == "skipped"
    assert model.calls == []


@pytest.mark.asyncio
async def test_weather_is_injected_only_after_real_region_lookup(setup_morning):
    database, service, model, clock, identity, conversation_id, weather = setup_morning

    class Location:
        async def current(self, user_id):
            return {
                "province": "北京市",
                "city": "",
                "district": "海淀区",
                "display": "北京市海淀区",
            }

    service._location = Location()
    await service.process()
    clock[0] = clock[0].replace(hour=7)
    await service.process()
    assert "晴，18～25" in model.calls[0][-1].content
    assert "用户当前位置：北京市海淀区" in model.calls[0][0].content


@pytest.mark.asyncio
async def test_push_failure_rolls_back_message_and_daily_marker(setup_morning):
    database, service, model, clock, identity, conversation_id, weather = setup_morning

    class FailingPush:
        async def enqueue(self, *args, session=None):
            raise RuntimeError("queue offline")

    service._push = FailingPush()
    await service.process()
    clock[0] = clock[0].replace(hour=7)
    await service.process()
    async with database.session_factory() as session:
        assert await ProactiveMessageRepository(session, identity).list_pending() == []
        assert (await session.exec(select(MorningGreeting))).one().status == "pending"
    service._push = None
    await service.process()
    async with database.session_factory() as session:
        assert len(await ProactiveMessageRepository(session, identity).list_pending()) == 1


@pytest.mark.asyncio
async def test_morning_message_and_real_push_outbox_are_committed_once(setup_morning):
    database, service, model, clock, identity, conversation_id, weather = setup_morning

    class Provider:
        enabled = True

    service._push = PushService(database.session_factory, Provider(), poll_seconds=1)
    async with database.session_factory() as session:
        await PushDeviceRepository(session).upsert(
            user_id=identity,
            installation_id="morning-installation",
            provider="getui",
            client_id="morning-client",
            manufacturer="test",
            model="test",
            app_version="test",
        )
    await service.process()
    clock[0] = clock[0].replace(hour=7)
    await service.process()
    await service.process()
    async with database.session_factory() as session:
        proactive = (await ProactiveMessageRepository(session, identity).list_pending())[0][0]
        outbox = (await session.exec(select(PushOutbox))).one()
        assert outbox.proactive_message_id == proactive.id
        assert outbox.title == "甜甜"
        assert (await session.exec(select(MorningGreeting))).one().status == "sent"


@pytest.mark.asyncio
async def test_failures_stop_after_three_attempts(setup_morning):
    database, service, model, clock, identity, conversation_id, weather = setup_morning
    await service.process()
    clock[0] = clock[0].replace(hour=7)
    model.fail = True
    for _attempt in range(4):
        await service.process()
    assert len(model.calls) == 3
    async with database.session_factory() as session:
        assert (await session.exec(select(MorningGreeting))).one().status == "skipped"


@pytest.mark.asyncio
async def test_greeting_finishing_after_nine_is_not_sent(setup_morning):
    database, service, model, clock, identity, conversation_id, weather = setup_morning
    await service.process()
    clock[0] = clock[0].replace(hour=8, minute=59)

    async def slow_complete(messages):
        clock[0] = clock[0].replace(hour=9)
        return "早上好"

    model.complete = slow_complete
    await service.process()
    async with database.session_factory() as session:
        assert await ProactiveMessageRepository(session, identity).list_pending() == []
        assert (await session.exec(select(MorningGreeting))).one().status == "skipped"


@pytest.mark.asyncio
async def test_every_chatted_partner_greets_once_with_separate_context(setup_morning):
    database, service, model, clock, identity, conversation_id, weather = setup_morning
    async with database.session_factory() as session:
        boyfriend = await RoleRepository(session).get_by_name("男朋友")
        first = (
            await session.exec(select(Conversation).where(Conversation.role_id == boyfriend.id))
        ).one()
        session.add(
            Message(
                conversation_id=first.id,
                role="user",
                content="昨天向暖暖说的话",
                created_at=clock[0] - timedelta(hours=9),
            )
        )
        other = Conversation(user_id=identity, role_id=boyfriend.id)
        session.add(other)
        await session.flush()
        session.add(
            Message(
                conversation_id=other.id,
                role="user",
                content="同一伙伴最新会话",
                created_at=clock[0] - timedelta(hours=7),
            )
        )
        await session.commit()
        latest_boyfriend_conversation = other.id
    await service.process()
    clock[0] = clock[0].replace(hour=7)
    await service.process()
    await service.process()
    assert len(model.calls) == 2
    girlfriend_call = next(call for call in model.calls if "甜甜" in call[0].content)
    boyfriend_call = next(call for call in model.calls if "暖暖" in call[0].content)
    assert "女朋友要温柔鼓励" in girlfriend_call[0].content
    assert "男朋友专属记忆" not in girlfriend_call[0].content
    assert "男朋友专属记忆" in boyfriend_call[0].content
    assert "女朋友要温柔鼓励" not in boyfriend_call[0].content
    assert "明天要面试" in girlfriend_call[-1].content
    assert "同一伙伴最新会话" not in girlfriend_call[-1].content
    assert "同一伙伴最新会话" in boyfriend_call[-1].content
    assert "明天要面试" not in boyfriend_call[-1].content
    async with database.session_factory() as session:
        pending = await ProactiveMessageRepository(session, identity).list_pending()
        assert {message.conversation_id for proactive, message in pending} == {
            conversation_id,
            latest_boyfriend_conversation,
        }
        scheduled = (await session.exec(select(MorningGreeting))).all()
        assert len(scheduled) == 2
        assert all(greeting.status == "sent" for greeting in scheduled)


@pytest.mark.asyncio
async def test_upgrade_preserves_previously_sent_greeting_and_allows_other_partner(setup_morning):
    database, service, model, clock, identity, conversation_id, weather = setup_morning
    async with database.engine.begin() as connection:
        await connection.exec_driver_sql("DROP TABLE morning_greetings")
        await connection.exec_driver_sql(
            """
            CREATE TABLE morning_greetings (
                id VARCHAR(36) PRIMARY KEY, user_id VARCHAR(36), conversation_id VARCHAR(36),
                greeting_date VARCHAR(10), scheduled_at DATETIME, status VARCHAR(20),
                attempts INTEGER, claim_until DATETIME, UNIQUE(user_id, greeting_date)
            )
            """
        )
        await connection.exec_driver_sql(
            "INSERT INTO morning_greetings VALUES (?, ?, ?, ?, ?, ?, ?, ?)",
            ("old-greeting", identity, conversation_id, "2026-10-03", "2026-10-03 07:00:00",
             "sent", 1, None),
        )
    await database.initialize()
    await database.initialize()
    async with database.session_factory() as session:
        preserved = await session.get(MorningGreeting, "old-greeting")
        girlfriend = await RoleRepository(session).get_by_name("女朋友")
        assert preserved.partner_key == girlfriend.id and preserved.status == "sent"
        boyfriend = await RoleRepository(session).get_by_name("男朋友")
        conversation = (
            await session.exec(select(Conversation).where(Conversation.role_id == boyfriend.id))
        ).one()
        session.add(
            MorningGreeting(
                user_id=identity,
                conversation_id=conversation.id,
                partner_key=boyfriend.id,
                greeting_date="2026-10-03",
                scheduled_at=clock[0].replace(hour=8),
            )
        )
        await session.commit()
        assert len((await session.exec(select(MorningGreeting))).all()) == 2
