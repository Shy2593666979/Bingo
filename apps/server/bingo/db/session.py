from collections.abc import AsyncIterator
from datetime import UTC, datetime

from sqlalchemy.ext.asyncio import (
    AsyncEngine,
    async_sessionmaker,
    create_async_engine,
)
from sqlmodel import SQLModel, select
from sqlmodel.ext.asyncio.session import AsyncSession

from bingo.db.models import Role
from bingo.db.time import BEIJING_TIMEZONE
from bingo.roles import BUILTIN_ROLES, role_id


class Database:
    def __init__(self, url: str) -> None:
        self.engine: AsyncEngine = create_async_engine(url)
        self.session_factory = async_sessionmaker(
            self.engine, class_=AsyncSession, expire_on_commit=False
        )

    async def initialize(self) -> None:
        async with self.engine.begin() as connection:
            await connection.run_sync(SQLModel.metadata.create_all)
            await connection.run_sync(_upgrade_role_schema)
            await connection.run_sync(_seed_builtin_roles)
            await connection.run_sync(_upgrade_local_sqlite_schema)

    async def dispose(self) -> None:
        await self.engine.dispose()

    async def session(self) -> AsyncIterator[AsyncSession]:
        async with self.session_factory() as session:
            yield session


def _upgrade_local_sqlite_schema(connection) -> None:
    """Upgrade databases created by the pre-auth local prototype."""
    if connection.dialect.name != "sqlite":
        return

    user_columns = {row[1] for row in connection.exec_driver_sql("PRAGMA table_info(users)")}
    if "role" not in user_columns:
        connection.exec_driver_sql("ALTER TABLE users ADD COLUMN role VARCHAR(30)")
    if "role_id" not in user_columns:
        connection.exec_driver_sql(
            "ALTER TABLE users ADD COLUMN role_id VARCHAR(36) REFERENCES roles(id)"
        )
        connection.exec_driver_sql("CREATE INDEX IF NOT EXISTS ix_users_role_id ON users(role_id)")
    if "role_changed_at" not in user_columns:
        connection.exec_driver_sql("ALTER TABLE users ADD COLUMN role_changed_at DATETIME")
        connection.exec_driver_sql(
            "UPDATE users SET role_changed_at = ? WHERE role_changed_at IS NULL",
            (datetime.now(BEIJING_TIMEZONE).replace(tzinfo=None).isoformat(sep=" "),),
        )
    connection.exec_driver_sql(
        "UPDATE users SET role = '同事' WHERE role IS NULL AND onboarding_complete = 1"
    )
    connection.exec_driver_sql(
        """
        UPDATE users
        SET role = CASE role
            WHEN '朋友' THEN '同事'
            WHEN '导师' THEN '老师'
            WHEN '儿子' THEN '小孩'
            WHEN '女儿' THEN '小孩'
            WHEN '生活助理' THEN '同事'
            ELSE role
        END
        WHERE role IN ('朋友', '导师', '儿子', '女儿', '生活助理')
        """
    )
    connection.exec_driver_sql(
        """
        UPDATE users
        SET role_id = (SELECT roles.id FROM roles WHERE roles.name = users.role)
        WHERE role_id IS NULL AND role IS NOT NULL
        """
    )

    conversation_columns = {
        row[1] for row in connection.exec_driver_sql("PRAGMA table_info(conversations)")
    }
    if "user_id" not in conversation_columns:
        connection.exec_driver_sql(
            "ALTER TABLE conversations ADD COLUMN user_id VARCHAR(36) REFERENCES users(id)"
        )
        connection.exec_driver_sql(
            "CREATE INDEX IF NOT EXISTS ix_conversations_user_id ON conversations(user_id)"
        )

    message_columns = {row[1] for row in connection.exec_driver_sql("PRAGMA table_info(messages)")}
    if "assistant_role" not in message_columns:
        connection.exec_driver_sql("ALTER TABLE messages ADD COLUMN assistant_role VARCHAR(30)")
        connection.exec_driver_sql(
            """
            UPDATE messages
            SET assistant_role = (
                SELECT users.role
                FROM conversations
                JOIN users ON users.id = conversations.user_id
                WHERE conversations.id = messages.conversation_id
            )
            WHERE role = 'assistant' AND assistant_role IS NULL
            """
        )
    if "role_id" not in message_columns:
        connection.exec_driver_sql(
            "ALTER TABLE messages ADD COLUMN role_id VARCHAR(36) REFERENCES roles(id)"
        )
        connection.exec_driver_sql(
            "CREATE INDEX IF NOT EXISTS ix_messages_role_id ON messages(role_id)"
        )
    if "run_id" not in message_columns:
        connection.exec_driver_sql("ALTER TABLE messages ADD COLUMN run_id VARCHAR(80)")
        connection.exec_driver_sql(
            "CREATE INDEX IF NOT EXISTS ix_messages_run_id ON messages(run_id)"
        )
    if "status" not in message_columns:
        connection.exec_driver_sql(
            "ALTER TABLE messages ADD COLUMN status VARCHAR(20) NOT NULL DEFAULT 'completed'"
        )
        connection.exec_driver_sql(
            "CREATE INDEX IF NOT EXISTS ix_messages_status ON messages(status)"
        )
    if "image_id" not in message_columns:
        connection.exec_driver_sql("ALTER TABLE messages ADD COLUMN image_id VARCHAR(36)")
        connection.exec_driver_sql(
            "CREATE UNIQUE INDEX IF NOT EXISTS ix_messages_image_id ON messages(image_id)"
        )
    if "image_mime_type" not in message_columns:
        connection.exec_driver_sql("ALTER TABLE messages ADD COLUMN image_mime_type VARCHAR(40)")
    if "message_type" not in message_columns:
        connection.exec_driver_sql(
            "ALTER TABLE messages ADD COLUMN message_type VARCHAR(20) NOT NULL DEFAULT 'chat'"
        )
        connection.exec_driver_sql(
            "CREATE INDEX IF NOT EXISTS ix_messages_message_type ON messages(message_type)"
        )
    if "call_status" not in message_columns:
        connection.exec_driver_sql("ALTER TABLE messages ADD COLUMN call_status VARCHAR(20)")
    if "call_duration_seconds" not in message_columns:
        connection.exec_driver_sql("ALTER TABLE messages ADD COLUMN call_duration_seconds INTEGER")

    memory_columns = {row[1] for row in connection.exec_driver_sql("PRAGMA table_info(memories)")}
    if "user_id" not in memory_columns:
        connection.exec_driver_sql("ALTER TABLE memories RENAME TO memories_legacy")
        connection.exec_driver_sql(
            """
            CREATE TABLE memories (
                id VARCHAR(36) NOT NULL PRIMARY KEY,
                user_id VARCHAR(36) REFERENCES users(id) ON DELETE CASCADE,
                content TEXT NOT NULL,
                created_at DATETIME NOT NULL,
                UNIQUE (user_id, content)
            )
            """
        )
        connection.exec_driver_sql(
            """
            INSERT INTO memories (id, user_id, content, created_at)
            SELECT id, NULL, content, created_at FROM memories_legacy
            """
        )
        connection.exec_driver_sql("DROP TABLE memories_legacy")
        connection.exec_driver_sql(
            "CREATE INDEX IF NOT EXISTS ix_memories_user_id ON memories(user_id)"
        )
        connection.exec_driver_sql(
            "CREATE INDEX IF NOT EXISTS ix_memories_created_at ON memories(created_at)"
        )
        memory_columns = {
            row[1] for row in connection.exec_driver_sql("PRAGMA table_info(memories)")
        }
    if "category" not in memory_columns:
        connection.exec_driver_sql(
            "ALTER TABLE memories ADD COLUMN category VARCHAR(30) NOT NULL DEFAULT 'fact'"
        )
    if "scope" not in memory_columns:
        connection.exec_driver_sql(
            "ALTER TABLE memories ADD COLUMN scope VARCHAR(20) NOT NULL DEFAULT 'user'"
        )
        connection.exec_driver_sql(
            "CREATE INDEX IF NOT EXISTS ix_memories_scope ON memories(scope)"
        )
    if "role_id" not in memory_columns:
        connection.exec_driver_sql(
            "ALTER TABLE memories ADD COLUMN role_id VARCHAR(36) REFERENCES roles(id)"
        )
        connection.exec_driver_sql(
            "CREATE INDEX IF NOT EXISTS ix_memories_role_id ON memories(role_id)"
        )
    connection.exec_driver_sql(
        """
        UPDATE memories
        SET scope = 'user_role',
            role_id = (
                SELECT roles.id
                FROM messages
                JOIN conversations ON conversations.id = messages.conversation_id
                JOIN roles ON roles.name = messages.assistant_role
                WHERE conversations.user_id = memories.user_id
                  AND messages.role = 'assistant'
                  AND messages.created_at <= memories.created_at
                ORDER BY messages.created_at DESC
                LIMIT 1
            )
        WHERE scope = 'user'
          AND content LIKE '%助手%'
        """
    )

    _migrate_sqlite_timestamps_to_beijing(connection)


def _upgrade_role_schema(connection) -> None:
    """Add role-owned call settings to databases created by older builds."""
    if connection.dialect.name != "sqlite":
        return

    role_columns = {row[1] for row in connection.exec_driver_sql("PRAGMA table_info(roles)")}
    if "voice" not in role_columns:
        connection.exec_driver_sql(
            "ALTER TABLE roles ADD COLUMN voice VARCHAR(255) NOT NULL DEFAULT ''"
        )


def _seed_builtin_roles(connection) -> None:
    now = datetime.now(BEIJING_TIMEZONE)
    for sort_order, role in enumerate(BUILTIN_ROLES):
        existing_id = connection.execute(
            select(Role.id).where(Role.code == role.code)
        ).scalar_one_or_none()
        values = {
            "name": role.name,
            "description": role.description,
            "prompt": role.prompt,
            "avatar": role.avatar,
            "voice": role.voice,
            "sort_order": sort_order,
            "updated_at": now,
        }
        if existing_id is None:
            connection.execute(
                Role.__table__.insert().values(
                    id=role_id(role.code),
                    code=role.code,
                    enabled=True,
                    created_at=now,
                    **values,
                )
            )
        else:
            connection.execute(
                Role.__table__.update().where(Role.id == existing_id).values(**values)
            )


def _migrate_sqlite_timestamps_to_beijing(connection) -> None:
    """Convert timestamps written by older UTC builds to Beijing wall-clock values once."""
    connection.exec_driver_sql(
        """
        CREATE TABLE IF NOT EXISTS bingo_schema_meta (
            key VARCHAR(100) NOT NULL PRIMARY KEY,
            value VARCHAR(255) NOT NULL
        )
        """
    )
    migration_key = "timestamps_beijing_v1"
    migrated = connection.exec_driver_sql(
        "SELECT value FROM bingo_schema_meta WHERE key = ?", (migration_key,)
    ).first()
    if migrated is not None:
        return

    timestamp_columns = {
        "users": ("created_at",),
        "auth_sessions": ("expires_at", "created_at"),
        "device_actions": ("created_at",),
        "conversations": ("created_at",),
        "messages": ("created_at",),
        "memories": ("created_at",),
        "proactive_messages": ("delivered_at", "created_at"),
        "push_devices": ("last_seen_at", "created_at"),
        "push_outbox": ("next_attempt_at", "created_at", "sent_at"),
    }
    existing_tables = {
        row[0]
        for row in connection.exec_driver_sql("SELECT name FROM sqlite_master WHERE type = 'table'")
    }
    for table, columns in timestamp_columns.items():
        if table not in existing_tables:
            continue
        existing_columns = {
            row[1] for row in connection.exec_driver_sql(f'PRAGMA table_info("{table}")')
        }
        for column in columns:
            if column not in existing_columns:
                continue
            rows = connection.exec_driver_sql(
                f'SELECT id, "{column}" FROM "{table}" WHERE "{column}" IS NOT NULL'
            ).all()
            for row_id, raw_value in rows:
                parsed = (
                    raw_value
                    if isinstance(raw_value, datetime)
                    else datetime.fromisoformat(str(raw_value))
                )
                if parsed.tzinfo is None:
                    parsed = parsed.replace(tzinfo=UTC)
                beijing_value = parsed.astimezone(BEIJING_TIMEZONE).replace(tzinfo=None)
                connection.exec_driver_sql(
                    f'UPDATE "{table}" SET "{column}" = ? WHERE id = ?',
                    (beijing_value.isoformat(sep=" ", timespec="microseconds"), row_id),
                )

    connection.exec_driver_sql(
        "INSERT INTO bingo_schema_meta (key, value) VALUES (?, ?)",
        (migration_key, datetime.now(BEIJING_TIMEZONE).isoformat()),
    )
