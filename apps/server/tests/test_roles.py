import sqlite3
from pathlib import Path

import pytest

from bingo.db.repositories import RoleRepository
from bingo.db.session import Database


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
