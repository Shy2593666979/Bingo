import base64
import json
from collections.abc import AsyncIterator
from datetime import UTC, datetime
from importlib.resources import files
from uuid import uuid4

from sqlalchemy import event
from sqlalchemy.ext.asyncio import (
    AsyncEngine,
    async_sessionmaker,
    create_async_engine,
)
from sqlmodel import SQLModel, select
from sqlmodel.ext.asyncio.session import AsyncSession

from bingo.db.models import MorningGreeting, Role, User
from bingo.db.seeds.community import seed_community_characters
from bingo.db.time import BEIJING_TIMEZONE
from bingo.roles import BUILTIN_ROLES, role_id
from bingo.roles.catalog import BUILTIN_NICKNAMES, BUILTIN_RELATION_ALIASES
from bingo.roles.traits import BUILTIN_TRAITS


class Database:
    def __init__(self, url: str) -> None:
        self.engine: AsyncEngine = create_async_engine(url)
        if self.engine.dialect.name == "sqlite":

            @event.listens_for(self.engine.sync_engine, "connect")
            def sqlite_on_connect(connection, _):
                cursor = connection.cursor()
                cursor.execute("PRAGMA busy_timeout=5000")
                cursor.execute("PRAGMA journal_mode=WAL")
                cursor.close()

        self.session_factory = async_sessionmaker(
            self.engine, class_=AsyncSession, expire_on_commit=False
        )

    async def initialize(self) -> None:
        async with self.engine.begin() as connection:
            await connection.run_sync(SQLModel.metadata.create_all)
            await connection.run_sync(_upgrade_role_schema)
            await connection.run_sync(_upgrade_community_source)
            await connection.run_sync(_upgrade_community_images)
            await connection.run_sync(_seed_builtin_roles)
            await connection.run_sync(_upgrade_local_sqlite_schema)
            await connection.run_sync(_upgrade_role_conversations)
            await connection.run_sync(_sync_companion_relationship)
            await connection.run_sync(_upgrade_chat_settings)
            await connection.run_sync(_upgrade_group_v2)
            await connection.run_sync(_upgrade_morning_greetings)
            await connection.run_sync(_upgrade_device_actions)
            await connection.run_sync(seed_community_characters)

    async def dispose(self) -> None:
        await self.engine.dispose()

    async def session(self) -> AsyncIterator[AsyncSession]:
        async with self.session_factory() as session:
            yield session


def _upgrade_group_v2(connection) -> None:
    if connection.dialect.name != "sqlite":
        return
    additions = {
        "chat_group_messages": {
            "attachment_json": "TEXT",
            "mention_targets_json": "TEXT NOT NULL DEFAULT '[]'",
            "mention_all": "BOOLEAN NOT NULL DEFAULT 0",
            "reply_to_message_id": "TEXT",
            "reply_sender_name": "TEXT",
            "reply_content_preview": "TEXT",
            "reply_created_at": "DATETIME",
        },
        "chat_group_runs": {
            "runtime_mode": "TEXT NOT NULL DEFAULT 'legacy_dispatcher'",
            "force_targets_json": "TEXT NOT NULL DEFAULT '[]'",
            "max_ai_messages": "INTEGER NOT NULL DEFAULT 10",
            "emitted_ai_messages": "INTEGER NOT NULL DEFAULT 0",
            "generation_calls": "INTEGER NOT NULL DEFAULT 0",
            "decision_calls": "INTEGER NOT NULL DEFAULT 0",
        },
    }
    for table, fields in additions.items():
        columns = {row[1] for row in connection.exec_driver_sql(f'PRAGMA table_info("{table}")')}
        for name, definition in fields.items():
            if name not in columns:
                connection.exec_driver_sql(
                    f'ALTER TABLE "{table}" ADD COLUMN "{name}" {definition}'
                )
                if name == "reply_created_at" and "created_at" in columns:
                    connection.exec_driver_sql(
                        "UPDATE chat_group_messages SET reply_created_at = "
                        "(SELECT source.created_at FROM chat_group_messages AS source "
                        "WHERE source.id = chat_group_messages.reply_to_message_id) "
                        "WHERE reply_to_message_id IS NOT NULL"
                    )
    connection.exec_driver_sql(
        "CREATE INDEX IF NOT EXISTS ix_chat_group_messages_reply_to_message_id "
        "ON chat_group_messages(reply_to_message_id)"
    )


def _upgrade_chat_settings(connection) -> None:
    if connection.dialect.name != "sqlite":
        return
    columns = {row[1] for row in connection.exec_driver_sql("PRAGMA table_info(conversations)")}
    for name in ("muted", "pinned", "archived"):
        if name not in columns:
            connection.exec_driver_sql(
                f"ALTER TABLE conversations ADD COLUMN {name} BOOLEAN NOT NULL DEFAULT 0"
            )
    group_columns = {row[1] for row in connection.exec_driver_sql("PRAGMA table_info(chat_groups)")}
    for name in ("archived", "read_aloud"):
        if group_columns and name not in group_columns:
            default = 1 if name == "read_aloud" else 0
            connection.exec_driver_sql(
                f"ALTER TABLE chat_groups ADD COLUMN {name} BOOLEAN NOT NULL DEFAULT {default}"
            )


def _upgrade_community_source(connection) -> None:
    if connection.dialect.name != "sqlite":
        return
    columns = {row[1] for row in connection.exec_driver_sql("PRAGMA table_info(roles)")}
    if "opening_line" not in columns:
        connection.exec_driver_sql(
            "ALTER TABLE roles ADD COLUMN opening_line TEXT NOT NULL DEFAULT ''"
        )
    if "source_publication_id" not in columns:
        connection.exec_driver_sql("ALTER TABLE roles ADD COLUMN source_publication_id VARCHAR(36)")


def _upgrade_community_images(connection) -> None:
    if connection.dialect.name != "sqlite":
        return
    columns = {row[1] for row in connection.exec_driver_sql("PRAGMA table_info(character_shares)")}
    if not columns:
        return
    if "images_json" not in columns:
        connection.exec_driver_sql("ALTER TABLE character_shares ADD COLUMN images_json TEXT")
    if "has_images" not in columns:
        connection.exec_driver_sql(
            "ALTER TABLE character_shares ADD COLUMN has_images BOOLEAN NOT NULL DEFAULT 0"
        )


def _upgrade_device_actions(connection) -> None:
    if connection.dialect.name != "sqlite":
        return
    columns = {row[1] for row in connection.exec_driver_sql("PRAGMA table_info(device_actions)")}
    if "conversation_id" not in columns:
        connection.exec_driver_sql(
            "ALTER TABLE device_actions ADD COLUMN conversation_id VARCHAR(36)"
        )
    connection.exec_driver_sql(
        "CREATE INDEX IF NOT EXISTS ix_device_actions_conversation_id "
        "ON device_actions(conversation_id)"
    )


def _upgrade_morning_greetings(connection) -> None:
    if connection.dialect.name != "sqlite":
        return
    columns = {row[1] for row in connection.exec_driver_sql("PRAGMA table_info(morning_greetings)")}
    if "partner_key" in columns:
        return
    connection.exec_driver_sql(
        "CREATE TEMP TABLE morning_greetings_upgrade AS SELECT * FROM morning_greetings"
    )
    connection.exec_driver_sql("DROP TABLE morning_greetings")
    MorningGreeting.__table__.create(connection)
    connection.exec_driver_sql(
        """
        INSERT INTO morning_greetings
            (id, user_id, conversation_id, partner_key, greeting_date,
             scheduled_at, status, attempts, claim_until)
        SELECT greeting.id, greeting.user_id, greeting.conversation_id,
               COALESCE(conversation.role_id, greeting.conversation_id), greeting.greeting_date,
               greeting.scheduled_at, greeting.status, greeting.attempts, greeting.claim_until
        FROM morning_greetings_upgrade AS greeting
        LEFT JOIN conversations AS conversation ON conversation.id = greeting.conversation_id
        """
    )
    connection.exec_driver_sql("DROP TABLE morning_greetings_upgrade")


def _upgrade_local_sqlite_schema(connection) -> None:
    """Upgrade databases created by the pre-auth local prototype."""
    if connection.dialect.name != "sqlite":
        return

    user_columns = {row[1] for row in connection.exec_driver_sql("PRAGMA table_info(users)")}
    for column, definition in {
        "birthday": "VARCHAR(10)",
        "recovery_hash": "VARCHAR(64)",
        "gender": "VARCHAR(10)",
        "user_avatar_data": "TEXT",
        "selective_companions": "BOOLEAN NOT NULL DEFAULT 0",
        "companion_selection_complete": "BOOLEAN NOT NULL DEFAULT 1",
    }.items():
        if column not in user_columns:
            connection.exec_driver_sql(f"ALTER TABLE users ADD COLUMN {column} {definition}")
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
            WHEN '儿子' THEN '小朋友'
            WHEN '女儿' THEN '小朋友'
            WHEN '小孩' THEN '小朋友'
            WHEN '生活助理' THEN '同事'
            ELSE role
        END
        WHERE role IN ('朋友', '导师', '儿子', '女儿', '小孩', '生活助理')
        """
    )
    for old_label, code in BUILTIN_RELATION_ALIASES.items():
        connection.exec_driver_sql(
            "UPDATE users SET role_id = (SELECT id FROM roles WHERE code = ? AND owner_id IS NULL) "
            "WHERE role_id IS NULL AND role = ?", (code, old_label),
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
    if "location_json" not in message_columns:
        connection.exec_driver_sql("ALTER TABLE messages ADD COLUMN location_json TEXT")
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
    additions = {
        "owner_id": "VARCHAR(36)",
        "display_name": "VARCHAR(30)",
        "role_type": "VARCHAR(30)",
        "avatar_data": "TEXT",
        "voice_source_id": "VARCHAR(36)",
        "owned_voice": "VARCHAR(255) NOT NULL DEFAULT ''",
        "deleted": "BOOLEAN NOT NULL DEFAULT 0",
        "categories_json": 'TEXT NOT NULL DEFAULT \'["陪伴", "朋友"]\'',
        "traits_json": 'TEXT NOT NULL DEFAULT \'["善于倾听", "陪伴聊天"]\'',
        "background": "TEXT",
        "speaking_style": "TEXT NOT NULL DEFAULT ''",
    }
    for column, definition in additions.items():
        if column not in role_columns:
            connection.exec_driver_sql(f"ALTER TABLE roles ADD COLUMN {column} {definition}")
    # Preserve free-form legacy settings verbatim; never guess which sentences are biography.
    connection.exec_driver_sql("UPDATE roles SET background = prompt WHERE background IS NULL")
    preference_columns = {
        row[1] for row in connection.exec_driver_sql("PRAGMA table_info(role_preferences)")
    }
    if "speaking_style" not in preference_columns:
        connection.exec_driver_sql("ALTER TABLE role_preferences ADD COLUMN speaking_style TEXT")


def _upgrade_role_conversations(connection) -> None:
    if connection.dialect.name != "sqlite":
        return
    columns = {row[1] for row in connection.exec_driver_sql("PRAGMA table_info(conversations)")}
    if "role_id" not in columns:
        connection.exec_driver_sql(
            "ALTER TABLE conversations ADD COLUMN role_id VARCHAR(36) REFERENCES roles(id)"
        )
        connection.exec_driver_sql(
            "CREATE INDEX IF NOT EXISTS ix_conversations_role_id ON conversations(role_id)"
        )
    if "last_read_at" not in columns:
        connection.exec_driver_sql("ALTER TABLE conversations ADD COLUMN last_read_at DATETIME")
    now = datetime.now(BEIJING_TIMEZONE).replace(tzinfo=None).isoformat(sep=" ")
    names = dict(connection.exec_driver_sql("SELECT name, id FROM roles").all())
    builtin_ids = dict(connection.exec_driver_sql(
        "SELECT code, id FROM roles WHERE owner_id IS NULL"
    ).all())
    for old_label, code in BUILTIN_RELATION_ALIASES.items():
        names[old_label] = builtin_ids.get(code, role_id(code))
    conversations = connection.exec_driver_sql(
        "SELECT c.id, c.user_id, c.title, c.created_at, u.role_id "
        "FROM conversations c JOIN users u ON u.id = c.user_id WHERE c.role_id IS NULL"
    ).all()
    for identifier, user_id, title, created_at, selected_role in conversations:
        fallback = selected_role or role_id("girlfriend")
        messages = connection.exec_driver_sql(
            "SELECT id, role, role_id, assistant_role FROM messages "
            "WHERE conversation_id = ? ORDER BY created_at, rowid",
            (identifier,),
        ).all()
        assignments = []
        current_role = fallback
        for index, (message_id, speaker, message_role, assistant_role) in enumerate(messages):
            target_role = message_role or names.get(assistant_role)
            if target_role is None and speaker == "user":
                for upcoming in messages[index + 1 :]:
                    if upcoming[1] == "user":
                        break
                    target_role = upcoming[2] or names.get(upcoming[3])
                    if target_role:
                        break
            current_role = target_role or current_role
            assignments.append((message_id, current_role))
        original_role = assignments[0][1] if assignments else fallback
        targets = {original_role: identifier}
        connection.exec_driver_sql(
            "UPDATE conversations SET role_id = ?, last_read_at = ? WHERE id = ?",
            (original_role, now, identifier),
        )
        for message_id, target_role in assignments:
            if target_role not in targets:
                targets[target_role] = str(uuid4())
                connection.exec_driver_sql(
                    "INSERT INTO conversations "
                    "(id, user_id, title, created_at, role_id, last_read_at) "
                    "VALUES (?, ?, ?, ?, ?, ?)",
                    (targets[target_role], user_id, title, created_at, target_role, now),
                )
            target = targets[target_role]
            connection.exec_driver_sql(
                "UPDATE messages SET conversation_id = ?, role_id = ? WHERE id = ?",
                (target, target_role, message_id),
            )
            connection.exec_driver_sql(
                "UPDATE proactive_messages SET conversation_id = ? WHERE message_id = ?",
                (target, message_id),
            )
        for target_role, target in targets.items():
            connection.exec_driver_sql(
                "UPDATE call_invitations SET conversation_id = ? "
                "WHERE conversation_id = ? AND role_id = ?",
                (target, identifier, target_role),
            )
            connection.exec_driver_sql(
                "UPDATE memory_checkpoints SET conversation_id = ? "
                "WHERE conversation_id = ? AND role_id = ?",
                (target, identifier, target_role),
            )


def _sync_companion_relationship(connection) -> None:
    """Rename the default relationship while retaining ownership and history IDs."""
    for old_label, code in BUILTIN_RELATION_ALIASES.items():
        relationship = next(role.relationship for role in BUILTIN_ROLES if role.code == code)
        connection.execute(
            User.__table__.update().where(
                User.role_id.in_(select(Role.id).where(Role.code == code, Role.owner_id.is_(None))),
                User.role == old_label,
            ).values(role=relationship)
        )
    connection.execute(User.__table__.update().where(
        User.role_id.in_(select(Role.id).where(Role.code == "parent", Role.owner_id.is_(None))),
        User.assistant_name == "文清",
    ).values(assistant_name=BUILTIN_NICKNAMES["parent"]))


def _seed_builtin_roles(connection) -> None:
    now = datetime.now(BEIJING_TIMEZONE)
    for sort_order, role in enumerate(BUILTIN_ROLES):
        existing_id = connection.execute(
            select(Role.id).where(Role.code == role.code)
        ).scalar_one_or_none()
        values = {
            "name": role.relationship,
            "description": role.description,
            "prompt": role.background,
            "background": role.background,
            "speaking_style": role.speaking_style,
            "avatar": role.avatar,
            "voice": role.voice,
            "sort_order": sort_order,
            "updated_at": now,
            "categories_json": json.dumps(BUILTIN_TRAITS[role.code][0], ensure_ascii=False),
            "traits_json": json.dumps(BUILTIN_TRAITS[role.code][1], ensure_ascii=False),
        }
        # New portraits are also delivered to installed clients without bundled assets.
        portrait = files("bingo.roles").joinpath("avatars", f"{role.code}.webp")
        if portrait.is_file():
            values["avatar_data"] = "data:image/webp;base64," + base64.b64encode(
                portrait.read_bytes()
            ).decode("ascii")
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
