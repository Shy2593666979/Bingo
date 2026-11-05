"""Seed community publications without granting them to every user."""

import base64
import json
from importlib.resources import files
from pathlib import Path

from sqlalchemy import select

from bingo.db.models import Conversation, Role, User, UserCompanion
from bingo.db.models.base import new_id
from bingo.db.models.community import CharacterInstall, CharacterShare
from bingo.db.models.groups import ChatGroup, GroupMember
from bingo.db.time import beijing_now
from bingo.roles import role_id
from bingo.roles.community_catalog import (
    COMMUNITY_AUTHOR_ID,
    COMMUNITY_CHARACTERS,
    community_share_id,
)


def _preserve_legacy_access(connection, identifier, publication_id):
    """Keep IDs, conversations and group membership from the former built-in entry."""
    users = set(connection.execute(select(User.id).where(User.role_id == identifier)).scalars())
    users.update(
        connection.execute(
            select(Conversation.user_id).where(Conversation.role_id == identifier)
        ).scalars()
    )
    users.update(
        connection.execute(
            select(ChatGroup.owner_id)
            .join(GroupMember, GroupMember.group_id == ChatGroup.id)
            .where(GroupMember.role_id == identifier)
        ).scalars()
    )
    users.update(
        connection.execute(
            select(UserCompanion.user_id).where(UserCompanion.role_id == identifier)
        ).scalars()
    )
    for user_id in users:
        if (
            connection.execute(
                select(UserCompanion).where(
                    UserCompanion.user_id == user_id, UserCompanion.role_id == identifier
                )
            ).first()
            is None
        ):
            connection.execute(
                UserCompanion.__table__.insert().values(user_id=user_id, role_id=identifier)
            )
        if (
            connection.execute(
                select(CharacterInstall).where(
                    CharacterInstall.user_id == user_id, CharacterInstall.share_id == publication_id
                )
            ).first()
            is None
        ):
            connection.execute(
                CharacterInstall.__table__.insert().values(
                    id=new_id(),
                    user_id=user_id,
                    share_id=publication_id,
                    role_id=identifier,
                    created_at=beijing_now(),
                )
            )


def seed_community_characters(connection):
    now = beijing_now()
    for entry in COMMUNITY_CHARACTERS:
        character = entry.character
        identifier = role_id(character.code)
        publication_id = community_share_id(character.code)
        portrait = files("bingo.roles").joinpath(
            "avatars", Path(character.avatar).with_suffix(".webp").name
        )
        avatar_data = "data:image/webp;base64," + base64.b64encode(portrait.read_bytes()).decode(
            "ascii"
        )
        existing = (
            connection.execute(select(Role.__table__).where(Role.code == character.code))
            .mappings()
            .first()
        )
        values = {
            "role_type": character.relationship,
            "display_name": character.name,
            "description": character.description,
            "prompt": character.background,
            "background": character.background,
            "speaking_style": character.speaking_style,
            "avatar": character.avatar,
            "avatar_data": avatar_data,
            "voice": character.voice,
            "categories_json": json.dumps(character.categories, ensure_ascii=False),
            "traits_json": json.dumps(character.personality_tags, ensure_ascii=False),
            "source_publication_id": publication_id,
            "updated_at": now,
        }
        if existing is None:
            connection.execute(
                Role.__table__.insert().values(
                    id=identifier,
                    code=character.code,
                    name="community" + identifier.replace("-", "")[:20],
                    enabled=True,
                    sort_order=1000,
                    created_at=now,
                    **values,
                )
            )
        else:
            if existing["owner_id"] is not None or existing["id"] != identifier:
                raise ValueError("Community source conflicts with an existing owned role")
            if existing["source_publication_id"] != publication_id:
                _preserve_legacy_access(connection, identifier, publication_id)
            connection.execute(
                Role.__table__.update().where(Role.id == identifier).values(**values)
            )

        snapshot = {
            "name": character.name,
            "character_name": character.name,
            "prompt": character.background,
            "background": character.background,
            "description": character.description,
            "role_type": character.relationship,
            "relationship": character.relationship,
            "personality": character.speaking_style,
            "speaking_style": character.speaking_style,
            "categories": character.categories,
            "traits": character.personality_tags,
            "personality_tags": character.personality_tags,
            "voice_source_id": identifier,
            "avatar_asset": character.avatar,
        }
        summary = {
            key: snapshot[key]
            for key in (
                "role_type",
                "personality",
                "categories",
                "traits",
                "avatar_asset",
                "relationship",
                "speaking_style",
                "personality_tags",
            )
        }
        summary.update(title=entry.title, share_tags=entry.share_tags, image_count=0)
        publication = (
            connection.execute(
                select(CharacterShare.__table__).where(CharacterShare.id == publication_id)
            )
            .mappings()
            .first()
        )
        content = {
            "author_name": entry.author_name,
            "name": character.name,
            "introduction": entry.introduction,
            "snapshot_json": json.dumps(snapshot, ensure_ascii=False),
            "summary_json": json.dumps(summary, ensure_ascii=False),
            "avatar_data": avatar_data,
            "has_avatar": True,
        }
        if publication is None:
            connection.execute(
                CharacterShare.__table__.insert().values(
                    id=publication_id,
                    author_id=COMMUNITY_AUTHOR_ID,
                    source_role_id=identifier,
                    request_id=f"seed:{character.code}",
                    status="published",
                    created_at=now,
                    **content,
                )
            )
        else:
            if publication["author_id"] != COMMUNITY_AUTHOR_ID:
                raise ValueError("Community publication conflicts with a user-owned share")
            # Content follows the catalog; moderation status, dates and interactions are retained.
            connection.execute(
                CharacterShare.__table__.update()
                .where(CharacterShare.id == publication_id)
                .values(**content)
            )
