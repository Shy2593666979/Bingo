import json
import sqlite3

import pytest
from fastapi.testclient import TestClient

from bingo.config import Settings
from bingo.db.models import Role, RolePreference, User
from bingo.db.repositories import ConversationRepository
from bingo.db.session import Database
from bingo.main import create_app
from bingo.roles import BUILTIN_ROLES, role_id
from bingo.roles.catalog import BUILTIN_NICKNAMES, BUILTIN_PERSONALITIES
from bingo.services.roles import response_for_user
from tests.api_support import api_payload


@pytest.fixture
def client(tmp_path):
    settings = Settings(
        app={"environment": "test"},
        database={"url": f"sqlite+aiosqlite:///{tmp_path / 'fields.db'}"},
    )
    with TestClient(create_app(settings)) as connection:
        auth = api_payload(
            connection.post(
                "/api/v1/auth/register", json={"phone": "19900117001", "password": "password123"}
            )
        )
        connection.headers["Authorization"] = f"Bearer {auth['access_token']}"
        yield connection


def test_seven_fields_round_trip_and_feed_chat_context(client):
    payload = {
        "character_name": "晚间朋友",
        "relationship": "老朋友",
        "background": "在山间经营一家小书店，喜欢散步和读书。",
        "speaking_style": "轻松口语，短句交流，先倾听再给建议。",
        "personality_tags": ["善于倾听", "幽默风趣"],
        "voice_source_id": role_id("chairman"),
    }
    created = client.post("/api/v1/roles", json=payload)
    assert created.status_code == 201, created.text
    role = api_payload(created)
    for key in (
        "character_name",
        "relationship",
        "background",
        "speaking_style",
        "personality_tags",
    ):
        assert role[key] == payload[key]
    assert role["name"] == role["character_name"]
    assert role["role_type"] == role["relationship"]
    assert role["traits"] == role["personality_tags"]
    assert role["prompt"] == role["background"]
    assert role["has_voice"] and role["voice_source_id"] == role_id("chairman")
    opened = api_payload(client.post(f"/api/v1/roles/{role['id']}/conversation"))
    user_id = api_payload(client.get("/api/v1/me"))["id"]

    async def context():
        async with client.app.state.database.session_factory() as session:
            user = await session.get(User, user_id)
            effective = await ConversationRepository(session, user_id).context_user(
                user, opened["id"]
            )
            saved = await session.get(Role, role["id"])
            return effective.personality, saved.context_prompt

    style, prompt = client.portal.call(context)
    assert style == payload["speaking_style"]
    assert all(value in prompt for value in ["晚间朋友", "老朋友", "小书店", "幽默风趣"])
    payload.update(
        background="搬到海边开书店，喜欢看日落。", speaking_style="温和慢聊，不急着给结论。"
    )
    updated = api_payload(client.put(f"/api/v1/roles/{role['id']}", json=payload))
    assert updated["background"] == payload["background"]
    assert updated["speaking_style"] == payload["speaking_style"]
    assert updated["personality_tags"] == payload["personality_tags"]


def test_builtin_style_is_private_and_legacy_updates_still_work(client):
    role = next(r for r in api_payload(client.get("/api/v1/roles")) if r["nickname"] == "老雷")
    changed = api_payload(
        client.put(
            f"/api/v1/roles/{role['id']}",
            json={
                "character_name": "不能改共享身份",
                "relationship": "不能改共享关系",
                "background": "不能改共享背景",
                "speaking_style": "简洁直白，像朋友一样交流。",
                "personality_tags": ["善于倾听", "温柔体贴"],
            },
        )
    )
    assert changed["speaking_style"] == "简洁直白，像朋友一样交流。"
    assert changed["character_name"] == "老雷" and changed["relationship"] == "董事长"
    assert changed["background"] == role["background"]
    assert changed["personality_tags"] == role["personality_tags"]
    other = api_payload(
        client.post(
            "/api/v1/auth/register",
            json={
                "phone": "19900117002",
                "password": "password123",
            },
        )
    )
    other_roles = api_payload(
        client.get(
            "/api/v1/roles",
            headers={
                "Authorization": f"Bearer {other['access_token']}",
            },
        )
    )
    assert next(r for r in other_roles if r["id"] == role["id"])["speaking_style"] == "幽默风趣"
    legacy = api_payload(
        client.put(
            f"/api/v1/roles/{role['id']}",
            json={
                "name": "董事长",
                "prompt": "旧客户端兼容",
                "personality": "沉稳克制",
            },
        )
    )
    assert legacy["speaking_style"] == "沉稳克制"


def test_legacy_prompt_clients_and_blank_new_fields(client):
    role = api_payload(
        client.post(
            "/api/v1/roles",
            json={
                "name": "旧客户端朋友",
                "prompt": "有自己的经历，耐心陪伴。",
                "personality": "幽默风趣",
            },
        )
    )
    assert role["background"] == "有自己的经历，耐心陪伴。"
    assert role["speaking_style"] == "幽默风趣"
    for key in ("background", "speaking_style"):
        assert (
            client.post(
                "/api/v1/roles",
                json={
                    "character_name": "空白资料",
                    "background": "一些背景",
                    key: "   ",
                },
            ).status_code
            == 422
        )


@pytest.mark.asyncio
async def test_legacy_database_upgrade_preserves_fields_and_preferences(tmp_path):
    path = tmp_path / "legacy.db"
    database = Database(f"sqlite+aiosqlite:///{path}")
    await database.initialize()
    async with database.session_factory() as session:
        user = User(phone="19900117003", password_hash="unchanged")
        role = Role(
            code="old-friend",
            name="old-friend",
            avatar="bingo_logo.png",
            prompt="旧设定原文：经历和说话习惯混在一起，也不能丢。",
            voice="old-voice",
        )
        session.add(user)
        await session.flush()
        role.owner_id = user.id
        session.add(role)
        await session.flush()
        session.add(RolePreference(user_id=user.id, role_id=role.id, personality="幽默风趣"))
        await session.commit()
        identifiers = user.id, role.id
    await database.dispose()
    with sqlite3.connect(path) as connection:
        connection.execute("ALTER TABLE roles DROP COLUMN background")
        connection.execute("ALTER TABLE roles DROP COLUMN speaking_style")
        connection.execute("ALTER TABLE role_preferences DROP COLUMN speaking_style")
    try:
        await database.initialize()
        await database.initialize()
        async with database.session_factory() as session:
            user = await session.get(User, identifiers[0])
            role = await session.get(Role, identifiers[1])
            assert (
                role.background == role.prompt == "旧设定原文：经历和说话习惯混在一起，也不能丢。"
            )
            assert role.voice == "old-voice" and user.password_hash == "unchanged"
            info = await response_for_user(session, user, role)
            assert info["speaking_style"] == "幽默风趣"
            assert info["personality_tags"] == json.loads(role.traits_json)
    finally:
        await database.dispose()


def test_catalogue_has_one_complete_definition_for_every_character():
    for role in BUILTIN_ROLES:
        assert all(
            (
                role.avatar,
                role.name,
                role.relationship,
                role.speaking_style,
                role.personality_tags,
                role.background,
                role.voice,
            )
        )
        assert BUILTIN_NICKNAMES[role.code] == role.name
        assert BUILTIN_PERSONALITIES[role.code] == role.speaking_style
