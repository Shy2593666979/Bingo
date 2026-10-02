import pytest
from fastapi.testclient import TestClient
from sqlmodel import select

from bingo.background.service import EngagementService
from bingo.config import Settings
from bingo.db.models import (
    CallInvitation,
    Conversation,
    MemoryCheckpoint,
    Message,
    ProactiveMessage,
    User,
)
from bingo.db.repositories import MemoryRepository
from bingo.db.session import Database
from bingo.db.time import beijing_now
from bingo.main import create_app
from bingo.roles import role_id
from tests.api_support import api_payload


@pytest.fixture
def client(tmp_path):
    settings = Settings(
        app={"environment": "test"},
        database={"url": f"sqlite+aiosqlite:///{tmp_path / 'roles.db'}"},
        model={"provider": "echo"},
    )
    with TestClient(create_app(settings)) as connection:
        result = api_payload(
            connection.post(
                "/api/v1/auth/register",
                json={
                    "phone": "13800138000",
                    "password": "password123",
                },
            )
        )
        connection.headers["Authorization"] = f"Bearer {result['access_token']}"
        connection.put(
            "/api/v1/me/profile",
            json={
                "username": "小明",
                "assistant_name": "Bingo",
                "personality": "温柔体贴",
                "role": "女朋友",
            },
        )
        yield connection


def open_role(client, code):
    response = client.post(f"/api/v1/roles/{role_id(code)}/conversation")
    assert response.status_code == 200, response.text
    return api_payload(response)["id"]


def send(client, conversation, content):
    response = client.post(
        "/api/v1/chat",
        json={
            "conversation_id": conversation,
            "content": content,
        },
    )
    assert response.status_code == 200, response.text
    return api_payload(response)


def test_role_threads_restore_history_and_context_even_after_switching(client):
    captured = []

    async def complete(messages):
        captured.append(messages)
        return "我在听。"

    client.app.state.runtime._llm.complete = complete
    girlfriend = open_role(client, "girlfriend")
    send(client, girlfriend, "只告诉女朋友的故事")
    boyfriend = open_role(client, "boyfriend")
    assert boyfriend != girlfriend
    send(client, boyfriend, "只告诉男朋友的故事")
    send(client, girlfriend, "继续之前的故事")
    assert "只告诉女朋友的故事" in "\n".join(item.content for item in captured[-1])
    assert "只告诉男朋友的故事" not in "\n".join(item.content for item in captured[-1])
    assert "女朋友" in captured[-1][0].content
    assert open_role(client, "girlfriend") == girlfriend
    messages = api_payload(client.get(f"/api/v1/conversations/{boyfriend}/messages"))
    assert len(messages) == 2
    assert messages[0]["content"] == "只告诉男朋友的故事"
    assert len(api_payload(client.get("/api/v1/conversations"))) == 2


def test_unread_and_access_are_separate_for_each_user_and_role(client):
    girlfriend = open_role(client, "girlfriend")
    boyfriend = open_role(client, "boyfriend")
    send(client, girlfriend, "你好")
    roles = {item["name"]: item for item in api_payload(client.get("/api/v1/roles"))}
    assert roles["女朋友"]["unread_count"] == 1
    assert roles["男朋友"]["unread_count"] == 0
    assert client.post(f"/api/v1/conversations/{girlfriend}/read").status_code == 204
    roles = {item["name"]: item for item in api_payload(client.get("/api/v1/roles"))}
    assert roles["女朋友"]["unread_count"] == 0
    registration = api_payload(
        client.post(
            "/api/v1/auth/register",
            json={
                "phone": "13900138000",
                "password": "password123",
            },
        )
    )
    client.headers["Authorization"] = f"Bearer {registration['access_token']}"
    assert client.post(f"/api/v1/conversations/{boyfriend}/read").status_code == 404
    assert open_role(client, "boyfriend") != boyfriend
    assert api_payload(client.get(f"/api/v1/conversations/{girlfriend}/messages")) == []


def test_memories_do_not_cross_roles(client):
    girlfriend = open_role(client, "girlfriend")
    open_role(client, "boyfriend")
    user_id = api_payload(client.get("/api/v1/me"))["id"]

    async def setup():
        async with client.app.state.database.session_factory() as session:
            memories = MemoryRepository(session, user_id)
            await memories.add("共同昵称小明")
            await memories.add("女朋友专属约定", scope="user_role", role_id=role_id("girlfriend"))
            await memories.add("男朋友专属约定", scope="user_role", role_id=role_id("boyfriend"))

    client.portal.call(setup)
    captured = []

    async def complete(messages):
        captured.extend(messages)
        return "好的。"

    client.app.state.runtime._llm.complete = complete
    send(client, girlfriend, "你记得吗")
    assert "共同昵称小明" in captured[0].content
    assert "女朋友专属约定" in captured[0].content
    assert "男朋友专属约定" not in captured[0].content


@pytest.mark.asyncio
async def test_recommendations_and_follow_up_use_the_original_role(tmp_path):
    database = Database(f"sqlite+aiosqlite:///{tmp_path / 'engagement.db'}")
    await database.initialize()
    prompts = []

    class Model:
        async def complete(self, messages):
            prompts.append(messages[-1].content)
            return "女朋友的主动关心"

    service = EngagementService(
        database.session_factory,
        Model(),
        redis_url=None,
        follow_up_delays=(0, 0, 0),
        recommendation_delay=0,
        poll_seconds=1,
    )
    try:
        async with database.session_factory() as session:
            user = User(phone="13800138000", password_hash="hash", role_id=role_id("boyfriend"))
            session.add(user)
            await session.flush()
            girlfriend = Conversation(user_id=user.id, role_id=role_id("girlfriend"))
            boyfriend = Conversation(user_id=user.id, role_id=role_id("boyfriend"))
            session.add(girlfriend)
            session.add(boyfriend)
            await session.flush()
            session.add(Message(conversation_id=girlfriend.id, role="user", content="女朋友的故事"))
            session.add(Message(conversation_id=boyfriend.id, role="user", content="男朋友的故事"))
            await session.commit()
        await service._broker.save_recommendations(f"{user.id}:{girlfriend.id}", ["女朋友话题"])
        await service._broker.save_recommendations(f"{user.id}:{boyfriend.id}", ["男朋友话题"])
        assert await service.recommendations_for_entry(user.id, girlfriend.id) == ["女朋友话题"]
        await service.clear_recommendations(user.id, girlfriend.id)
        assert await service.get_recommendations(user.id, boyfriend.id) == ["男朋友话题"]
        await service._create_follow_up(
            {"user_id": user.id, "conversation_id": girlfriend.id, "stage": 1}
        )
        assert "女朋友的故事" in prompts[-1]
        assert "男朋友的故事" not in prompts[-1]
        async with database.session_factory() as session:
            proactive = (await session.exec(select(ProactiveMessage))).one()
            message = await session.get(Message, proactive.message_id)
            assert message.role_id == role_id("girlfriend")
            assert message.assistant_role == "女朋友"
    finally:
        await service.close()
        await database.dispose()


@pytest.mark.asyncio
async def test_migration_splits_mixed_history_and_preserves_related_records(tmp_path):
    database = Database(f"sqlite+aiosqlite:///{tmp_path / 'legacy.db'}")
    await database.initialize()
    async with database.session_factory() as session:
        user = User(phone="13800138000", password_hash="hash", role_id=role_id("girlfriend"))
        session.add(user)
        await session.flush()
        conversation = Conversation(user_id=user.id)
        session.add(conversation)
        await session.flush()
        for speaker, content, role in [
            ("user", "给女朋友的消息", None),
            ("assistant", "女朋友的回复", role_id("girlfriend")),
            ("user", "给男朋友的消息", None),
            ("assistant", "男朋友的回复", role_id("boyfriend")),
        ]:
            message = Message(
                conversation_id=conversation.id, role=speaker, content=content, role_id=role
            )
            session.add(message)
            await session.flush()
        session.add(
            ProactiveMessage(
                user_id=user.id, conversation_id=conversation.id, message_id=message.id
            )
        )
        session.add(
            MemoryCheckpoint(
                user_id=user.id,
                conversation_id=conversation.id,
                role_id=role_id("boyfriend"),
                last_message_id=message.id,
            )
        )
        session.add(
            CallInvitation(
                user_id=user.id,
                conversation_id=conversation.id,
                role_id=role_id("boyfriend"),
                caller_name="男朋友",
                expires_at=beijing_now(),
            )
        )
        await session.commit()
    try:
        await database.initialize()
        await database.initialize()
        async with database.session_factory() as session:
            conversations = (await session.exec(select(Conversation))).all()
            assert len(conversations) == 2
            lookup = {item.id: item.role_id for item in conversations}
            messages = (await session.exec(select(Message))).all()
            assert len(messages) == 4
            assert all(item.role_id == lookup[item.conversation_id] for item in messages)
            for model in (CallInvitation, MemoryCheckpoint, ProactiveMessage):
                record = (await session.exec(select(model))).one()
                assert lookup[record.conversation_id] == role_id("boyfriend")
    finally:
        await database.dispose()
