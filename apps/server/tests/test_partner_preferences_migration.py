import sqlite3

import pytest

from bingo.db.models import Role, RolePreference
from bingo.db.session import Database


@pytest.mark.asyncio
async def test_old_role_schema_upgrades_without_losing_private_partners(tmp_path):
    path = tmp_path / "legacy.db"
    database = Database(f"sqlite+aiosqlite:///{path}")
    await database.initialize()
    async with database.session_factory() as session:
        session.add(
            Role(
                id="legacy-role",
                code="legacy-role",
                name="legacy-role",
                display_name="旧伙伴",
                owner_id="owner",
                avatar="bingo_logo.png",
                prompt="认真倾听",
                description="陪伴聊天",
            )
        )
        await session.commit()
    await database.dispose()
    with sqlite3.connect(path) as connection:
        connection.execute("ALTER TABLE roles DROP COLUMN role_type")
        connection.execute("DROP TABLE role_preferences")
    database = Database(f"sqlite+aiosqlite:///{path}")
    try:
        await database.initialize()
        async with database.session_factory() as session:
            role = await session.get(Role, "legacy-role")
            assert role.visible_name == "旧伙伴"
            assert role.prompt == "认真倾听"
            assert role.role_type is None
            session.add(
                RolePreference(
                    user_id="owner",
                    role_id=role.id,
                    personality="幽默风趣",
                )
            )
            await session.commit()
        await database.initialize()
        async with database.session_factory() as session:
            preference = await session.get(RolePreference, ("owner", "legacy-role"))
            assert preference.personality == "幽默风趣"
            assert (await session.get(Role, "legacy-role")).visible_name == "旧伙伴"
    finally:
        await database.dispose()
