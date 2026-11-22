import asyncio
import base64
import json

import pytest
from fastapi.testclient import TestClient
from sqlalchemy import Column, MetaData, Table, create_engine
from sqlmodel import select

from bingo.config import Settings
from bingo.db.models import Role, RolePreference, User, Voice, VoiceJob
from bingo.db.session import Database
from bingo.main import create_app
from bingo.services.voice_cloning import VoiceCloningService, pcm_wav
from bingo.services.voices import effective_role
from tests.api_support import api_payload

P = "/api/v1"


@pytest.fixture
def assets_app(tmp_path, monkeypatch):
    async def verify(self, voice):
        return None

    async def preview(self, voice):
        return pcm_wav(b"\x01\x00\x02\x00", 24000)

    async def provider(self, action, **values):
        if action == "create_voice":
            return {"voice_id": "test-voice-" + values["prefix"]}
        return {"voice_list": []}

    monkeypatch.setattr(VoiceCloningService, "verify", verify)
    monkeypatch.setattr(VoiceCloningService, "generate_preview", preview)
    monkeypatch.setattr(VoiceCloningService, "request", provider)
    settings = Settings(
        app={"environment": "test"},
        database={"url": f"sqlite+aiosqlite:///{tmp_path / 'voices.db'}"},
        realtime_call={"api_key": "test-key"},
        voice_cloning={"sample_host": "public_url", "public_base_url": "https://test/api/v1"},
    )
    with TestClient(create_app(settings)) as client:
        token = api_payload(
            client.post(
                P + "/auth/register",
                json={
                    "phone": "13800138881",
                    "password": "password123",
                },
            )
        )["access_token"]
        client.headers["Authorization"] = f"Bearer {token}"
        yield client


def create_asset(client, name="我的测试音色"):
    response = client.post(P + "/voices", json={"name": name, "gender": "male"})
    assert response.status_code == 201, response.text
    return api_payload(response)


def clone_asset(client, asset):
    response = client.post(
        P + f"/voices/{asset['id']}/clone",
        json={
            "consent": True,
            "audio": base64.b64encode(b"\xe8\x03\x18\xfc" * 160000).decode(),
        },
    )
    assert response.status_code == 202, response.text

    async def finish():
        for _ in range(5):
            tasks = list(client.app.state.voice_cloning.tasks)
            if not tasks:
                break
            await asyncio.gather(*tasks)

    client.portal.call(finish)
    job = api_payload(client.get(P + f"/voice-jobs/{api_payload(response)['id']}"))
    assert job["status"] == "ready", job
    assert job["voice_id"] == asset["id"]
    return job


def test_standalone_create_clone_rename_and_delete_without_any_custom_role(assets_app):
    client = assets_app
    before = api_payload(client.get(P + "/roles"))
    voice = create_asset(client)
    assert voice["status"] == "draft"
    clone_asset(client, voice)
    assert api_payload(client.get(P + "/roles")) == before
    response = client.post(P + f"/voices/{voice['id']}/preview")
    assert base64.b64decode(api_payload(response)["audio"]) == pcm_wav(b"\x01\x00\x02\x00", 24000)
    streamed = client.post(P + f"/voices/{voice['id']}/preview/stream")
    assert streamed.status_code == 200
    assert streamed.headers["cache-control"] == "no-store"
    audio, done = (json.loads(line) for line in streamed.text.splitlines())
    assert base64.b64decode(audio["data"]) == b"\x01\x00\x02\x00"
    assert done == {"type": "audio_done"}
    response = client.put(P + f"/voices/{voice['id']}", json={"name": "独立保存的声音"})
    assert api_payload(response)["name"] == "独立保存的声音"
    assert client.delete(P + f"/voices/{voice['id']}").status_code == 204
    assert client.post(P + f"/voices/{voice['id']}/preview").status_code == 404


def test_shared_asset_survives_role_deletion_and_cannot_delete_while_in_use(assets_app):
    client = assets_app
    voice = create_asset(client)
    clone_asset(client, voice)
    roles = []
    for name in ["第一个角色", "第二个角色"]:
        response = client.post(
            P + "/roles",
            json={
                "name": name,
                "background": "一位热心的测试伙伴。",
                "voice_id": voice["id"],
            },
        )
        assert response.status_code == 201, response.text
        roles.append(api_payload(response))
    assert client.delete(P + f"/voices/{voice['id']}").status_code == 409
    assert client.delete(P + f"/roles/{roles[0]['id']}").status_code == 204
    assert client.post(P + f"/voices/{voice['id']}/preview").status_code == 200
    remaining = api_payload(client.get(P + "/roles"))
    assert (
        next(role for role in remaining if role["id"] == roles[1]["id"])["voice_id"] == voice["id"]
    )
    assert client.delete(P + f"/roles/{roles[1]['id']}").status_code == 204
    assert client.delete(P + f"/voices/{voice['id']}").status_code == 204


def test_private_assets_are_not_visible_or_assignable_to_another_user(assets_app):
    client = assets_app
    voice = create_asset(client)
    clone_asset(client, voice)
    other = api_payload(
        client.post(
            P + "/auth/register",
            json={
                "phone": "13800138882",
                "password": "password123",
            },
        )
    )["access_token"]
    headers = {"Authorization": f"Bearer {other}"}
    assert voice["id"] not in {
        item["id"] for item in api_payload(client.get(P + "/voices", headers=headers))
    }
    for method, suffix, body in [
        ("post", "/preview", None),
        ("post", "/preview/stream", None),
        ("put", "", {"name": "窃取"}),
        ("delete", "", None),
    ]:
        response = client.request(
            method, P + f"/voices/{voice['id']}" + suffix, headers=headers, json=body
        )
        assert response.status_code == 404
    role = api_payload(client.get(P + "/roles", headers=headers))[0]
    assert (
        client.put(
            P + f"/roles/{role['id']}/voice", headers=headers, json={"voice_id": voice["id"]}
        ).status_code
        == 404
    )


def test_official_role_voice_selection_is_per_user_and_not_a_shared_role_mutation(assets_app):
    client = assets_app
    user = api_payload(client.get(P + "/me"))
    voice = create_asset(client)
    clone_asset(client, voice)
    role = api_payload(client.get(P + "/roles"))[0]
    assert (
        client.put(P + f"/roles/{role['id']}/voice", json={"voice_id": voice["id"]}).status_code
        == 200
    )

    async def inspect_choice():
        async with client.app.state.database.session_factory() as session:
            stored = await session.get(Role, role["id"])
            own = await effective_role(session, user["id"], stored)
            other = await effective_role(session, "another-user", stored)
            assert own.voice_id == voice["id"]
            assert other.voice_id == stored.voice_id == role["voice_id"]
            assert own.voice != other.voice

    client.portal.call(inspect_choice)
    chosen = next(
        item for item in api_payload(client.get(P + "/roles")) if item["id"] == role["id"]
    )
    assert chosen["voice_id"] == voice["id"]
    assert chosen["personality"] == role["personality"]
    assert client.delete(P + f"/voices/{voice['id']}").status_code == 409


@pytest.mark.asyncio
async def test_idempotent_migration_preserves_legacy_voice_after_its_role_is_deleted(tmp_path):
    database = Database(f"sqlite+aiosqlite:///{tmp_path / 'legacy.db'}")
    try:
        await database.initialize()
        async with database.session_factory() as session:
            user = User(phone="13800138883", password_hash="test")
            session.add(user)
            await session.flush()
            role = Role(
                name="legacy",
                code="legacy",
                owner_id=user.id,
                avatar="x.png",
                voice="old-provider-voice",
                owned_voice="old-provider-voice",
            )
            session.add(role)
            await session.commit()
            identifier = role.id
        await database.initialize()
        await database.initialize()
        async with database.session_factory() as session:
            role = await session.get(Role, identifier)
            voice = await session.get(Voice, role.voice_id)
            assert voice.provider_voice == "old-provider-voice"
            assert (
                len((await session.exec(select(Voice).where(Voice.owner_id == user.id))).all()) == 1
            )
            assert (
                len((await session.exec(select(Voice).where(Voice.scope == "system"))).all()) == 12
            )
            await session.delete(role)
            await session.commit()
            assert (await session.get(Voice, voice.id)).deleted is False
    finally:
        await database.dispose()


@pytest.mark.asyncio
async def test_pre_asset_database_columns_upgrade_without_losing_legacy_audio(tmp_path):
    path = tmp_path / "before-assets.db"
    engine = create_engine(f"sqlite:///{path}")
    metadata = MetaData()
    # The three tables had precisely these columns before voice_id was introduced.
    tables = {}
    for model in (Role, RolePreference, VoiceJob):
        columns = [
            Column(
                column.name,
                column.type,
                primary_key=column.primary_key,
                nullable=column.nullable,
                default=column.default,
                server_default=column.server_default,
            )
            for column in model.__table__.columns
            if column.name != "voice_id"
        ]
        tables[model.__tablename__] = Table(model.__tablename__, metadata, *columns)
    metadata.create_all(engine)
    with engine.begin() as connection:
        legacy = Role(
            id="old-role",
            name="old-role",
            code="old-role",
            owner_id="old-user",
            avatar="bingo_logo.png",
            voice="legacy-provider-id",
            owned_voice="legacy-provider-id",
        ).model_dump(exclude={"voice_id"})
        connection.execute(tables["roles"].insert().values(**legacy))
    engine.dispose()
    database = Database(f"sqlite+aiosqlite:///{path}")
    try:
        await database.initialize()
        await database.initialize()
        async with database.session_factory() as session:
            role = await session.get(Role, "old-role")
            asset = await session.get(Voice, role.voice_id)
            assert asset.owner_id == "old-user"
            assert asset.provider_voice == "legacy-provider-id"
            assert role.owned_voice == "legacy-provider-id"
    finally:
        await database.dispose()


def test_system_catalog_does_not_require_selecting_any_companion(assets_app):
    client = assets_app
    user_id = api_payload(client.get(P + "/me"))["id"]

    async def clear_selection():
        async with client.app.state.database.session_factory() as session:
            user = await session.get(User, user_id)
            user.selective_companions = True
            await session.commit()

    client.portal.call(clear_selection)
    assert api_payload(client.get(P + "/roles")) == []
    system = api_payload(client.get(P + "/voices?scope=system"))
    assert len(system) == 12
    assert all(voice["has_audio"] and voice["scope"] == "system" for voice in system)


def test_community_install_reuses_asset_instead_of_a_voice_source_role(assets_app):
    client = assets_app
    voices = api_payload(client.get(P + "/voices?scope=system"))
    chosen = next(voice for voice in voices if voice["name"] == "阳光男声")
    role = api_payload(
        client.post(
            P + "/roles",
            json={
                "name": "独立音色分享",
                "background": "一位喜欢聊天的原创人物。",
                "voice_id": chosen["id"],
            },
        )
    )
    shared = api_payload(
        client.post(
            P + "/community/characters",
            json={
                "role_id": role["id"],
                "introduction": "这是使用独立公开音色的搭子。",
                "request_id": "asset-sharing-test",
            },
        )
    )
    other = api_payload(
        client.post(
            P + "/auth/register",
            json={
                "phone": "13800138884",
                "password": "password123",
            },
        )
    )["access_token"]
    installed = api_payload(
        client.post(
            P + f"/community/characters/{shared['id']}/install",
            headers={"Authorization": f"Bearer {other}"},
        )
    )
    assert installed["voice_id"] == chosen["id"]
