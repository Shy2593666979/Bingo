import sqlite3
from pathlib import Path

import pytest

from bingo.db.repositories import RoleRepository
from bingo.db.session import Database
from bingo.roles import BUILTIN_ROLES, role_id


@pytest.mark.parametrize(
    "code,old_label,new_label,old_nickname,new_nickname",
    [
        ("confidant", "知己", "树洞搭子", "木木", "木木"),
        ("parent", "家长", "邻家大叔", "文清", "陈叔"),
        ("child", "小朋友", "弟弟", "星星", "星星"),
    ],
)
@pytest.mark.asyncio
async def test_relationship_update_preserves_existing_companion_and_chat(
    tmp_path, code, old_label, new_label, old_nickname, new_nickname
):
    from bingo.db.models import Conversation, Message, Role, RolePreference, User, UserCompanion

    database = Database(f"sqlite+aiosqlite:///{tmp_path / 'relationship.db'}")
    await database.initialize()
    builtin_id = role_id(code)
    async with database.session_factory() as session:
        user = User(
            phone="19900118888",
            password_hash="existing",
            role_id=builtin_id,
            role=old_label,
            assistant_name=old_nickname,
            selective_companions=True,
            companion_selection_complete=True,
        )
        session.add(user)
        await session.flush()
        session.add(UserCompanion(user_id=user.id, role_id=builtin_id))
        session.add(RolePreference(user_id=user.id, role_id=builtin_id, personality="幽默风趣"))
        conversation = Conversation(user_id=user.id, role_id=builtin_id)
        session.add(conversation)
        await session.flush()
        message = Message(
            conversation_id=conversation.id,
            role="assistant",
            content="我在这里听。",
            role_id=builtin_id,
            assistant_role=old_label,
        )
        session.add(message)
        custom = Role(
            code="my-copy",
            name="my-copy",
            display_name="自己的搭子",
            role_type=old_label,
            owner_id=user.id,
            avatar="confidant.png",
            voice="my-original-voice",
        )
        session.add(custom)
        old = await session.get(Role, builtin_id)
        old.name = old_label
        legacy = User(
            phone="19900117777",
            password_hash="legacy",
            role=old_label,
            assistant_name=old_nickname,
            onboarding_complete=True,
        )
        session.add(legacy)
        await session.commit()
        legacy_id = legacy.id
        user_id, conversation_id, message_id, custom_id = (
            user.id,
            conversation.id,
            message.id,
            custom.id,
        )
    await database.dispose()
    await database.initialize()
    try:
        async with database.session_factory() as session:
            user = await session.get(User, user_id)
            assert user.role == new_label
            assert user.assistant_name == new_nickname
            assert user.role_id == builtin_id
            legacy = await session.get(User, legacy_id)
            assert legacy.role_id == builtin_id and legacy.role == new_label
            assert legacy.assistant_name == new_nickname
            assert await session.get(UserCompanion, (user_id, builtin_id))
            assert (
                await session.get(RolePreference, (user_id, builtin_id))
            ).personality == "幽默风趣"
            assert (await session.get(Conversation, conversation_id)).role_id == builtin_id
            assert (await session.get(Message, message_id)).content == "我在这里听。"
            assert (await session.get(Role, builtin_id)).voice == next(
                role.voice for role in BUILTIN_ROLES if role.code == code
            )
            assert (await RoleRepository(session).get_by_name(old_label)).id == builtin_id
            custom = await session.get(Role, custom_id)
            assert custom.role_type == old_label and custom.voice == "my-original-voice"
    finally:
        await database.dispose()


@pytest.mark.asyncio
async def test_existing_role_table_is_upgraded_and_seeded_with_voices(tmp_path: Path) -> None:
    database_path = tmp_path / "roles.db"
    with sqlite3.connect(database_path) as connection:
        connection.execute(
            """
            CREATE TABLE roles (
                id VARCHAR(36) NOT NULL PRIMARY KEY,
                code VARCHAR(40) NOT NULL UNIQUE,
                name VARCHAR(30) NOT NULL UNIQUE,
                description TEXT NOT NULL,
                prompt TEXT NOT NULL,
                avatar VARCHAR(255) NOT NULL,
                enabled BOOLEAN NOT NULL,
                sort_order INTEGER NOT NULL,
                created_at DATETIME NOT NULL,
                updated_at DATETIME NOT NULL
            )
            """
        )

    database = Database(f"sqlite+aiosqlite:///{database_path}")
    await database.initialize()
    try:
        async with database.session_factory() as session:
            roles = await RoleRepository(session).list_enabled()
            voices = {role.code: role.voice for role in roles}
            assert len(roles) == len(BUILTIN_ROLES) == 13
            added = {
                role.code: role
                for role in roles
                if role.code
                in {"bestie", "bro", "senior_sister", "senior_brother", "confidant", "fitness"}
            }
            assert len(added) == 6
            for code, role in added.items():
                assert role.id == role_id(code)
                assert role.opening_line
                assert role.avatar == f"{code}.png"
                assert role.voice not in {
                    voices["girlfriend"],
                    voices["boyfriend"],
                    voices["parent"],
                }
        assert voices["boyfriend"] == (
            "qwen-audio-3.1-realtime-plus-selfvoice2-d25f4b945c284a3385381230a2bb2052"
        )
        assert voices["girlfriend"] == "longanqian_v3.1"
        assert voices["parent"].startswith("qwen-audio-3.1-realtime-plus-parent-")
        assert voices["teacher"].startswith("qwen-audio-3.1-realtime-plus-teacher-")
        assert voices["child"].startswith("qwen-audio-3.1-realtime-plus-child-")
        assert voices["colleague"].startswith("qwen-audio-3.1-realtime-plus-colleague-")
    finally:
        await database.dispose()


@pytest.mark.asyncio
async def test_chairman_is_seeded_once_with_portrait_and_independent_voice(tmp_path):
    import base64

    from bingo.services.roles import role_response

    database = Database(f"sqlite+aiosqlite:///{tmp_path / 'chairman.db'}")
    try:
        await database.initialize()
        await database.initialize()
        async with database.session_factory() as session:
            roles = await RoleRepository(session).list_enabled()
            chairmen = [role for role in roles if role.code == "chairman"]
            assert len(chairmen) == 1
            role = chairmen[0]
            assert role.id == role_id("chairman")
            assert role.nickname == "老雷"
            assert role.name == "董事长"
            assert role.owner_id is None
            assert role.voice.startswith("qwen-audio-3.1-realtime-plus-self7f639e-")
            assert "虚构" in role.description and "不是雷军或任何现实人物" in role.prompt
            assert role.opening_line
            response = role_response(role)
            assert response["builtin"] and response["has_voice"]
            assert response["role_type"] == "董事长"
            assert response["nickname"] == "老雷"
            header, encoded = response["avatar_data"].split(",", 1)
            assert header == "data:image/webp;base64"
            assert base64.b64decode(encoded).startswith(b"RIFF")
            assert response["traits"] == ["思路梳理", "轻松幽默", "鼓励支持"]
    finally:
        await database.dispose()
