import json
from dataclasses import replace

import pytest
from fastapi.testclient import TestClient
from sqlmodel import select

from bingo.config import Settings
from bingo.db.models import Conversation, Message, Role, RolePreference, User
from bingo.db.models.community import CharacterFavorite, CharacterInstall, CharacterShare
from bingo.db.models.groups import ChatGroup, GroupMember
from bingo.db.models.welcome import WelcomeJob
from bingo.db.repositories import RoleRepository
from bingo.db.session import Database
from bingo.main import create_app
from bingo.roles import role_id
from bingo.roles.community_catalog import (
    COMMUNITY_AUTHOR_ID,
    COMMUNITY_CHARACTERS,
    community_share_id,
)
from bingo.services.roles import response_for_user
from tests.api_support import api_payload
from tests.test_added_companion_welcome import WelcomeModel, drain, register

P = "/api/v1"
CHARACTER = COMMUNITY_CHARACTERS[0].character


@pytest.fixture
def client(tmp_path):
    settings = Settings(
        app={"environment": "test"},
        model={"provider": "echo"},
        database={"url": f"sqlite+aiosqlite:///{tmp_path / 'community-seeds.db'}"},
    )
    with TestClient(create_app(settings)) as connection:
        connection.app.state.services.companion_welcome.model = WelcomeModel()
        yield connection


def test_defaults_stay_twelve_and_chairman_is_only_a_community_publication(client):
    register(client, "19900117201", "小林", "女")
    roles = api_payload(client.get(P + "/roles"))
    candidates = api_payload(client.get(P + "/onboarding/companions"))
    assert len(roles) == len(candidates) == 12
    assert all(role["id"] != role_id("chairman") for role in roles + candidates)
    assert client.post(P + f"/roles/{role_id('chairman')}/conversation").status_code == 404
    listing = api_payload(client.get(P + "/community/characters"))
    assert listing["total"] == 1
    share = listing["items"][0]
    assert share["id"] == community_share_id("chairman")
    assert share["name"] == CHARACTER.name and share["author_name"] == "Bingo 社区"
    assert share["installed_role_id"] is None
    assert share["has_avatar"] and not share["is_mine"]
    assert client.delete(P + f"/community/characters/{share['id']}").status_code == 404


def test_seed_install_uses_the_copy_voice_and_personalized_welcome(client):
    user_id = register(client, "19900117202", "小林", "女")
    share_id = community_share_id("chairman")
    route = P + f"/community/characters/{share_id}/install"
    copied = api_payload(client.post(route))
    assert not copied["builtin"]
    assert copied["character_name"] == CHARACTER.name
    assert copied["relationship"] == CHARACTER.relationship
    assert copied["source_publication_id"] == share_id
    assert copied["voice_source_id"] == role_id("chairman")
    assert api_payload(client.post(route))["id"] == copied["id"]
    drain(client)
    opened = api_payload(client.post(P + f"/roles/{copied['id']}/conversation"))
    messages = api_payload(client.get(P + f"/conversations/{opened['id']}/messages"))
    assert len(messages) == 1
    assert messages[0]["content"].startswith(f"小林，我是{CHARACTER.name}。")
    assert len(api_payload(client.get(P + "/roles"))) == 13
    assert len(api_payload(client.get(P + "/onboarding/companions"))) == 12
    edited = client.put(
        P + f"/roles/{copied['id']}",
        json={
            "character_name": CHARACTER.name,
            "background": "虚构的董事长，喜欢聊产品和生活。",
            "speaking_style": "简洁自然，平等交流。",
            "voice_source_id": copied["id"],
        },
    )
    assert edited.status_code == 200, edited.text

    async def verify():
        async with client.app.state.database.session_factory() as session:
            source = await session.get(Role, role_id("chairman"))
            role = await session.get(Role, copied["id"])
            assert role.owner_id == user_id
            assert role.voice == source.voice
            assert role.voice_source_id == source.id
            jobs = (await session.exec(select(WelcomeJob))).all()
            assert len(jobs) == 1

    client.portal.call(verify)


def test_reinitialization_preserves_moderation_dates_and_favorites(client):
    register(client, "19900117203", "小林", "女")
    share_id = community_share_id("chairman")
    route = P + f"/community/characters/{share_id}"
    original = api_payload(client.get(route))
    client.put(route + "/favorite", json={"favorite": True})

    async def verify():
        database = client.app.state.database
        async with database.session_factory() as session:
            publication = await session.get(CharacterShare, share_id)
            publication.status = "withdrawn"
            await session.commit()
        await database.initialize()
        await database.initialize()
        async with database.session_factory() as session:
            shares = (await session.exec(select(CharacterShare))).all()
            assert len(shares) == 1
            assert shares[0].status == "withdrawn"
            assert shares[0].created_at.isoformat() == original["created_at"]
            assert shares[0].author_id == COMMUNITY_AUTHOR_ID
            assert len((await session.exec(select(User))).all()) == 1
            assert len((await session.exec(select(CharacterInstall))).all()) == 0
            assert len((await session.exec(select(CharacterFavorite))).all()) == 1

    client.portal.call(verify)
    favorites = api_payload(client.get(P + "/community/characters", params={"scope": "favorites"}))
    assert favorites["total"] == 0  # Withdrawing hides it without deleting the favorite row.


@pytest.mark.asyncio
async def test_migrating_previous_default_keeps_chat_group_voice_and_private_style(tmp_path):
    database = Database(f"sqlite+aiosqlite:///{tmp_path / 'legacy-chairman.db'}")
    await database.initialize()
    async with database.session_factory() as session:
        source = await session.get(Role, role_id("chairman"))
        source.source_publication_id = None
        source.name = "董事长"
        source.display_name = None
        source.role_type = None
        publication = await session.get(CharacterShare, community_share_id("chairman"))
        await session.delete(publication)
        user = User(phone="19900117204", password_hash="unchanged", role_id=source.id)
        stranger = User(phone="19900117205", password_hash="unchanged")
        session.add(user)
        session.add(stranger)
        await session.flush()
        conversation = Conversation(user_id=user.id, role_id=source.id)
        group = ChatGroup(owner_id=user.id, name="旧群聊")
        session.add(conversation)
        session.add(group)
        await session.flush()
        message = Message(
            conversation_id=conversation.id, role="assistant", content="以前聊过的话。"
        )
        session.add(message)
        session.add(
            GroupMember(
                group_id=group.id,
                role_id=source.id,
                name="老雷",
                role_name="董事长",
                avatar_asset="chairman.png",
            )
        )
        session.add(
            RolePreference(
                user_id=user.id,
                role_id=source.id,
                personality="幽默风趣",
                speaking_style="像老朋友一样简洁交流。",
            )
        )
        await session.commit()
        user_id, stranger_id, conversation_id = user.id, stranger.id, conversation.id
        group_id, message_id, voice = group.id, message.id, source.voice
    try:
        await database.initialize()
        await database.initialize()
        async with database.session_factory() as session:
            user = await session.get(User, user_id)
            stranger = await session.get(User, stranger_id)
            source = await session.get(Role, role_id("chairman"))
            repository = RoleRepository(session)
            assert await repository.can_access(user, source)
            assert not await repository.can_access(stranger, source)
            assert len(await repository.list_enabled(user_id)) == 13
            assert len(await repository.list_enabled(stranger_id)) == 12
            assert len(await repository.list_enabled()) == 12
            assert source.voice == voice and user.role_id == source.id
            assert (await session.get(Conversation, conversation_id)).role_id == source.id
            assert (await session.get(Message, message_id)).content == "以前聊过的话。"
            assert await session.get(GroupMember, (group_id, source.id))
            info = await response_for_user(session, user, source)
            assert not info["builtin"] and not info["identity_editable"]
            assert info["speaking_style"] == "像老朋友一样简洁交流。"
            installs = (await session.exec(select(CharacterInstall))).all()
            assert len(installs) == 1 and installs[0].role_id == source.id
            assert (
                json.loads(
                    (
                        await session.get(CharacterShare, community_share_id("chairman"))
                    ).snapshot_json
                )["name"]
                == CHARACTER.name
            )
            assert (await session.exec(select(WelcomeJob))).all() == []
    finally:
        await database.dispose()


@pytest.mark.asyncio
async def test_multiple_community_characters_can_share_the_same_relationship(tmp_path, monkeypatch):
    from bingo.db.seeds import community

    first = COMMUNITY_CHARACTERS[0]
    another = replace(
        first, character=replace(first.character, code="another-chairman", name="另一位董事长")
    )
    monkeypatch.setattr(community, "COMMUNITY_CHARACTERS", (first, another))
    database = Database(f"sqlite+aiosqlite:///{tmp_path / 'same-relationship.db'}")
    try:
        await database.initialize()
        await database.initialize()
        async with database.session_factory() as session:
            one = await session.get(Role, role_id(first.character.code))
            two = await session.get(Role, role_id(another.character.code))
            assert one.id != two.id and one.name != two.name
            assert one.relationship == two.relationship == first.character.relationship
            assert len((await session.exec(select(CharacterShare))).all()) == 2
            assert len(await RoleRepository(session).list_enabled()) == 12
    finally:
        await database.dispose()
