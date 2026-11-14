"""Idempotent migration of existing provider voices into standalone assets."""

from hashlib import sha256
from uuid import NAMESPACE_URL, uuid5

from sqlalchemy import inspect, select

from bingo.db.models import Role, Voice
from bingo.db.time import beijing_now
from bingo.roles.catalog import BUILTIN_NICKNAMES

SYSTEM_NAMES = {
    "girlfriend": ("温柔女声", "female"),
    "boyfriend": ("阳光男声", "male"),
    "colleague": ("干练男声", "male"),
    "teacher": ("知性女声", "female"),
    "parent": ("醇厚男声", "male"),
    "child": ("活泼少年", "male"),
    "bestie": ("爽朗女声", "female"),
    "bro": ("随和男声", "male"),
    "senior_sister": ("清晰女声", "female"),
    "senior_brother": ("从容男声", "male"),
    "confidant": ("温和男声", "male"),
    "fitness": ("元气男声", "male"),
}


def legacy_voice_id(provider_voice: str, owner_id: str | None = None) -> str:
    return str(uuid5(NAMESPACE_URL, f"bingo-voice:{owner_id or 'public'}:{provider_voice}"))


def upgrade_voice_schema(connection) -> None:
    for table in ("roles", "role_preferences", "voice_jobs"):
        columns = {column["name"] for column in inspect(connection).get_columns(table)}
        if "voice_id" not in columns:
            connection.exec_driver_sql(
                f'ALTER TABLE "{table}" ADD COLUMN voice_id VARCHAR(36) REFERENCES voices(id)'
            )
        connection.exec_driver_sql(
            f'CREATE INDEX IF NOT EXISTS ix_{table}_voice_id ON "{table}" (voice_id)'
        )


def seed_voice_assets(connection) -> None:
    voices = Voice.__table__
    roles = Role.__table__
    existing = {row.id: row for row in connection.execute(select(voices))}
    records = list(connection.execute(select(roles)).mappings())

    def ensure(provider, owner, name, scope, gender="unknown", description=""):
        identifier = legacy_voice_id(provider, owner)
        if identifier not in existing:
            connection.execute(
                voices.insert().values(
                    id=identifier,
                    name=name,
                    description=description,
                    gender=gender,
                    owner_id=owner,
                    scope=scope,
                    provider_voice=provider,
                    status="ready",
                    legacy_key=sha256(f"{owner or 'public'}:{provider}".encode()).hexdigest(),
                    created_at=beijing_now(),
                    updated_at=beijing_now(),
                )
            )
            existing[identifier] = True
        return identifier

    # Public defaults and published community voices remain available without installing a role.
    for role in records:
        if role["owner_id"] is not None or not role["voice"] or role["deleted"]:
            continue
        name, gender = SYSTEM_NAMES.get(
            role["code"], (role["display_name"] or role["name"], "unknown")
        )
        identifier = ensure(
            role["voice"],
            None,
            name,
            "system" if role["code"] in BUILTIN_NICKNAMES else "community",
            gender,
            role["speaking_style"] or role["description"],
        )
        if role["voice_id"] != identifier:
            connection.execute(
                roles.update().where(roles.c.id == role["id"]).values(voice_id=identifier)
            )

    for role in records:
        if role["owner_id"] is None or role["deleted"]:
            continue
        if role["owned_voice"]:
            ensure(
                role["owned_voice"],
                role["owner_id"],
                f"{role['display_name'] or role['name']}的声音",
                "private",
            )
        if role["voice"] and not role["voice_id"]:
            public_id = legacy_voice_id(role["voice"])
            identifier = (
                public_id
                if public_id in existing
                else ensure(
                    role["voice"],
                    role["owner_id"],
                    f"{role['display_name'] or role['name']}的声音",
                    "private",
                )
            )
            connection.execute(
                roles.update().where(roles.c.id == role["id"]).values(voice_id=identifier)
            )
