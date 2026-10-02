import base64
from datetime import timedelta

import pytest
from fastapi.testclient import TestClient

from bingo.config import Settings
from bingo.db.models import User, VoiceJob
from bingo.db.repositories import ConversationRepository
from bingo.db.time import beijing_now
from bingo.main import create_app
from bingo.services.voice_cloning import VoiceCloningService
from tests.api_support import api_payload


@pytest.fixture
def client(tmp_path, monkeypatch):
    async def verify(self, voice):
        return None

    monkeypatch.setattr(VoiceCloningService, "verify", verify)

    async def generate_preview(self, voice):
        return b"preview-wav"

    monkeypatch.setattr(VoiceCloningService, "generate_preview", generate_preview)
    settings = Settings(
        app={"environment": "test"},
        database={"url": f"sqlite+aiosqlite:///{tmp_path / 'custom.db'}"},
        realtime_call={"api_key": "test-key"},
        voice_cloning={
            "sample_host": "public_url",
            "public_base_url": "https://bingo.example/api/v1",
        },
    )
    with TestClient(create_app(settings)) as connection:
        response = connection.post(
            "/api/v1/auth/register",
            json={
                "phone": "13800138000",
                "password": "password123",
            },
        )
        connection.headers["Authorization"] = f"Bearer {api_payload(response)['access_token']}"
        yield connection


def create_role(client, name="知心姐姐", **values):
    response = client.post(
        "/api/v1/roles",
        json={
            "name": name,
            "prompt": "温柔，有耐心，认真倾听。",
            **values,
        },
    )
    assert response.status_code == 201, response.text
    return api_payload(response)


def test_builtin_nicknames_preserve_role_identity(client):
    expected = {
        "女朋友": "甜甜",
        "男朋友": "暖暖",
        "同事": "小周",
        "老师": "小田老师",
        "小朋友": "星星",
        "家长": "文清",
    }
    roles = api_payload(client.get("/api/v1/roles"))
    assert [role["name"] for role in roles] == [
        "女朋友",
        "男朋友",
        "同事",
        "老师",
        "家长",
        "小朋友",
    ]
    assert {role["name"]: role["nickname"] for role in roles} == expected
    for role in roles:
        assert role["role_type"] == role["name"]
        opened = client.post(f"/api/v1/roles/{role['id']}/conversation")
        assert opened.status_code == 200
        profile = api_payload(client.get("/api/v1/me"))
        assert profile["role"] == role["name"]
        assert profile["role_id"] == role["id"]
        assert profile["assistant_name"] == role["nickname"]
    custom = create_role(client)
    assert custom["nickname"] == "知心姐姐"
    assert custom["role_type"] == "自定义角色"


def test_optional_role_identity_and_personality_round_trip(client):
    role = create_role(client, role_type="", personality="幽默风趣")
    assert role["role_type"] == ""
    assert role["personality"] == "幽默风趣"
    changed = client.put(
        f"/api/v1/roles/{role['id']}",
        json={
            "name": role["name"],
            "prompt": role["prompt"],
            "role_type": " 旅行搭子 ",
            "personality": "理性严谨",
        },
    )
    assert changed.status_code == 200
    assert api_payload(changed)["role_type"] == "旅行搭子"
    assert api_payload(changed)["personality"] == "理性严谨"
    cleared = client.put(
        f"/api/v1/roles/{role['id']}",
        json={
            "name": role["name"],
            "prompt": role["prompt"],
            "role_type": "  ",
        },
    )
    assert api_payload(cleared)["role_type"] == ""
    assert api_payload(cleared)["personality"] == "理性严谨"
    listed = {item["id"]: item for item in api_payload(client.get("/api/v1/roles"))}
    assert listed[role["id"]]["role_type"] == ""
    assert (
        client.put(
            f"/api/v1/roles/{role['id']}",
            json={
                "name": role["name"],
                "prompt": role["prompt"],
                "personality": "invalid",
            },
        ).status_code
        == 422
    )


def test_builtin_personalities_are_private_and_used_in_chat_context(client):
    roles = api_payload(client.get("/api/v1/roles"))
    for role in roles:
        updated = client.put(
            f"/api/v1/roles/{role['id']}",
            json={
                "name": "不应修改共享名称",
                "prompt": "不应修改共享设定",
                "personality": "幽默风趣",
                "role_type": "不应修改身份",
            },
        )
        assert updated.status_code == 200
        assert api_payload(updated)["nickname"] == role["nickname"]
        assert api_payload(updated)["prompt"] == role["prompt"]
        assert api_payload(updated)["role_type"] == role["role_type"]
        assert api_payload(updated)["personality"] == "幽默风趣"
        assert client.delete(f"/api/v1/roles/{role['id']}").status_code == 404
    opened = api_payload(client.post(f"/api/v1/roles/{roles[0]['id']}/conversation"))
    user_id = api_payload(client.get("/api/v1/me"))["id"]

    async def context_personality():
        async with client.app.state.database.session_factory() as session:
            user = await session.get(User, user_id)
            context = await ConversationRepository(session, user_id).context_user(
                user, opened["id"]
            )
            return context.personality, user.personality

    selected, original = client.portal.call(context_personality)
    assert selected == "幽默风趣"
    assert original != "幽默风趣"
    other = api_payload(
        client.post(
            "/api/v1/auth/register",
            json={
                "phone": "13800138009",
                "password": "password123",
            },
        )
    )
    client.headers["Authorization"] = f"Bearer {other['access_token']}"
    assert all(
        role["personality"] != "幽默风趣" for role in api_payload(client.get("/api/v1/roles"))
    )


def test_custom_personality_is_independent_of_other_partners(client):
    first = create_role(client, name="第一个伙伴", personality="幽默风趣")
    second = create_role(client, name="第二个伙伴", personality="沉稳克制")
    user_id = api_payload(client.get("/api/v1/me"))["id"]
    for role, expected in [(first, "幽默风趣"), (second, "沉稳克制")]:
        conversation = api_payload(client.post(f"/api/v1/roles/{role['id']}/conversation"))

        async def context_personality(conversation_id=conversation["id"]):
            async with client.app.state.database.session_factory() as session:
                user = await session.get(User, user_id)
                context = await ConversationRepository(session, user_id).context_user(
                    user, conversation_id
                )
                return context.personality

        assert client.portal.call(context_personality) == expected


def test_custom_role_selection_and_builtin_compatibility(client):
    before = api_payload(client.get("/api/v1/profile/options"))
    assert len(before["roles"]) == 6
    role = create_role(client)
    assert role["avatar_data"] is None
    assert role["builtin"] is False
    response = client.put(
        "/api/v1/me/profile",
        json={
            "username": "小明",
            "assistant_name": "姐姐",
            "personality": "温柔体贴",
            "role": role["id"],
        },
    )
    assert response.status_code == 200
    assert api_payload(response)["role"] == "知心姐姐"
    assert api_payload(response)["role_id"] == role["id"]
    assert "知心姐姐" in api_payload(client.get("/api/v1/profile/options"))["roles"]
    response = client.put(
        "/api/v1/me/profile",
        json={
            "username": "小明",
            "assistant_name": "Bingo",
            "personality": "温柔体贴",
            "role": "男朋友",
        },
    )
    assert response.status_code == 200


def test_role_labels_are_persisted_and_validated(client):
    role = create_role(client, categories=["朋友", "治愈"], traits=["情绪安抚", "有趣好聊"])
    assert role["categories"] == ["朋友", "治愈"]
    assert role["traits"] == ["情绪安抚", "有趣好聊"]
    response = client.put(
        f"/api/v1/roles/{role['id']}", json={"name": role["name"], "prompt": "新设定"}
    )
    assert api_payload(response)["traits"] == role["traits"]
    response = client.post(
        "/api/v1/roles",
        json={
            "name": "坏标签",
            "prompt": "测试",
            "categories": ["朋友", "不存在"],
            "traits": ["有趣好聊", "有趣好聊"],
        },
    )
    assert response.status_code == 422


def test_legacy_child_name_still_selects_the_same_builtin_role(client):
    response = client.put(
        "/api/v1/me/profile",
        json={
            "username": "小明",
            "assistant_name": "Bingo",
            "personality": "温柔体贴",
            "role": "小孩",
        },
    )
    assert response.status_code == 200
    assert api_payload(response)["role"] == "小朋友"


def test_private_roles_cannot_be_read_selected_or_mutated_by_another_user(client):
    role = create_role(client)
    other = api_payload(
        client.post(
            "/api/v1/auth/register",
            json={
                "phone": "13900139000",
                "password": "password123",
            },
        )
    )
    client.headers["Authorization"] = f"Bearer {other['access_token']}"
    assert role["id"] not in {item["id"] for item in api_payload(client.get("/api/v1/roles"))}
    assert client.delete(f"/api/v1/roles/{role['id']}").status_code == 404
    assert (
        client.put(
            f"/api/v1/roles/{role['id']}",
            json={
                "name": "偷来的角色",
                "prompt": "测试",
            },
        ).status_code
        == 404
    )
    assert (
        client.put(
            "/api/v1/me/profile",
            json={
                "username": "另一人",
                "assistant_name": "测试",
                "personality": "温柔体贴",
                "role": role["id"],
            },
        ).status_code
        == 422
    )
    assert create_role(client)["name"] == "知心姐姐"


def test_drafts_and_duplicate_names(client):
    role = create_role(client, draft=True)
    assert role["id"] not in {item["id"] for item in api_payload(client.get("/api/v1/roles"))}
    assert (
        client.post(
            "/api/v1/roles",
            json={
                "name": "知心姐姐",
                "prompt": "重复",
            },
        ).status_code
        == 409
    )
    assert (
        client.put(
            f"/api/v1/roles/{role['id']}",
            json={
                "name": "知心姐姐",
                "prompt": "温柔耐心",
            },
        ).status_code
        == 200
    )
    assert role["id"] in {item["id"] for item in api_payload(client.get("/api/v1/roles"))}


def test_short_recordings_and_consent_are_checked_server_side(client):
    role = create_role(client)
    endpoint = f"/api/v1/roles/{role['id']}/voice-clone"
    response = client.post(
        endpoint,
        json={
            "audio": base64.b64encode(bytes(32000 * 14)).decode(),
            "consent": True,
        },
    )
    assert response.status_code == 422
    assert "时间太短" in api_payload(response)["detail"]
    assert (
        client.post(
            endpoint,
            json={
                "audio": base64.b64encode(bytes(32000 * 20)).decode(),
                "consent": False,
            },
        ).status_code
        == 422
    )
    assert client.post(endpoint, json={"audio": "invalid!", "consent": True}).status_code == 422
    response = client.post(
        endpoint, json={"audio": base64.b64encode(bytes(32000 * 20)).decode(), "consent": True}
    )
    assert response.status_code == 422
    assert "没有检测到声音" in api_payload(response)["detail"]


def test_clone_job_cleans_sample_and_delete_invalidates_reused_voice(client, monkeypatch):
    calls = []

    async def provider(self, action, **values):
        calls.append((action, values))
        if action == "list_voice":
            return {"voice_list": []}
        if action == "create_voice":
            return {"voice_id": "private-clone"}
        return {}

    monkeypatch.setattr(VoiceCloningService, "request", provider)
    role = create_role(client)
    response = client.post(
        f"/api/v1/roles/{role['id']}/voice-clone",
        json={
            "audio": base64.b64encode(b"\xe8\x03\x18\xfc" * (8000 * 20)).decode(),
            "consent": True,
        },
    )
    assert response.status_code == 202
    identifier = api_payload(response)["id"]

    async def finish_jobs():
        tasks = list(client.app.state.voice_cloning.tasks)
        if tasks:
            import asyncio

            await asyncio.gather(*tasks)

    client.portal.call(finish_jobs)
    assert api_payload(client.get(f"/api/v1/voice-jobs/{identifier}"))["status"] == "ready"

    async def check_cleanup():
        async with client.app.state.database.session_factory() as session:
            job = await session.get(VoiceJob, identifier)
            assert job.sample is None
            assert job.sample_token is None

    client.portal.call(check_cleanup)
    second = create_role(client, "倾听伙伴", voice_source_id=role["id"])
    assert second["voice_source_id"] == role["id"]
    client.put(
        "/api/v1/me/profile",
        json={
            "username": "小明",
            "assistant_name": "姐姐",
            "personality": "温柔体贴",
            "role": role["id"],
        },
    )
    assert client.delete(f"/api/v1/roles/{role['id']}").status_code == 204
    client.portal.call(finish_jobs)
    assert api_payload(client.get("/api/v1/me"))["role"] == "女朋友"
    remaining = api_payload(client.get("/api/v1/roles"))
    fallback = next(item for item in remaining if item["name"] == "女朋友")
    assert (
        next(item for item in remaining if item["id"] == second["id"])["voice_source_id"]
        == fallback["id"]
    )
    assert client.post(f"/api/v1/roles/{role['id']}/voice-preview").status_code == 404
    assert ("delete_voice", {"voice_id": "private-clone"}) in calls


def test_voice_sample_is_temporary_and_unavailable_after_role_deletion(client):
    role = create_role(client)
    user_id = api_payload(client.get("/api/v1/me"))["id"]

    async def add_sample():
        async with client.app.state.database.session_factory() as session:
            job = VoiceJob(
                user_id=user_id,
                role_id=role["id"],
                sample=base64.b64encode(b"wav").decode(),
                sample_token="random-token",
                created_at=beijing_now() - timedelta(minutes=11),
            )
            session.add(job)
            await session.commit()

    client.portal.call(add_sample)
    assert client.get("/api/v1/role-voice-samples/random-token").status_code == 404


def test_failed_clone_retry_recovers_existing_provider_voice_without_recreating(
    client, monkeypatch
):
    created = []
    recovered = []

    async def provider(self, action, **values):
        if action == "list_voice":
            if created:
                identifier = f"{self.settings.realtime_call.model}-{values['prefix']}-existing"
                recovered.append(identifier)
                return {"voice_list": [{"voice_id": identifier, "status": "OK"}]}
            return {"voice_list": []}
        if action == "create_voice":
            created.append(values)
            raise TimeoutError("provider response lost")
        return {}

    monkeypatch.setattr(VoiceCloningService, "request", provider)
    role = create_role(client)
    payload = {
        "audio": base64.b64encode(b"\xe8\x03\x18\xfc" * (8000 * 20)).decode(),
        "consent": True,
    }
    first = api_payload(client.post(f"/api/v1/roles/{role['id']}/voice-clone", json=payload))

    async def finish_jobs():
        import asyncio

        tasks = list(client.app.state.voice_cloning.tasks)
        if tasks:
            await asyncio.gather(*tasks)

    client.portal.call(finish_jobs)
    assert api_payload(client.get(f"/api/v1/voice-jobs/{first['id']}"))["status"] == "failed"
    second = api_payload(client.post(f"/api/v1/roles/{role['id']}/voice-clone", json=payload))
    client.portal.call(finish_jobs)
    assert second["id"] == first["id"]
    assert api_payload(client.get(f"/api/v1/voice-jobs/{second['id']}"))["status"] == "ready"
    assert len(created) == 1
    assert len(recovered) == 1


def test_bad_avatar_rejected(client):
    assert (
        client.post(
            "/api/v1/roles",
            json={
                "name": "测试",
                "prompt": "设定",
                "avatar_data": base64.b64encode(b"not-png").decode(),
            },
        ).status_code
        == 422
    )


@pytest.mark.parametrize("provider_fails", [False, True])
def test_yukisbox_clone_passes_uploaded_url_and_always_cleans_it(
    client, monkeypatch, provider_fails
):
    events = []
    sample_url = "https://yukisbox.com/file/temporary"
    client.app.state.settings.voice_cloning.sample_host = "yukisbox"

    async def upload(self, job):
        assert base64.b64decode(job.sample).startswith(b"RIFF")
        events.append("upload")
        return sample_url

    async def cleanup(self, url):
        assert url == sample_url
        events.append("cleanup")

    async def provider(self, action, **values):
        if action == "list_voice":
            return {"voice_list": []}
        assert action == "create_voice"
        assert values["url"] == sample_url
        events.append("create")
        if provider_fails:
            raise ValueError("provider rejected sample")
        return {"voice_id": "test-clone"}

    monkeypatch.setattr(VoiceCloningService, "upload_sample", upload)
    monkeypatch.setattr(VoiceCloningService, "cleanup_sample", cleanup)
    monkeypatch.setattr(VoiceCloningService, "request", provider)
    role = create_role(client)
    response = client.post(
        f"/api/v1/roles/{role['id']}/voice-clone",
        json={
            "audio": base64.b64encode(b"\xe8\x03\x18\xfc" * (8000 * 20)).decode(),
            "consent": True,
        },
    )
    assert response.status_code == 202

    async def finish_jobs():
        import asyncio

        tasks = list(client.app.state.voice_cloning.tasks)
        if tasks:
            await asyncio.gather(*tasks)

    client.portal.call(finish_jobs)
    status = api_payload(client.get(f"/api/v1/voice-jobs/{api_payload(response)['id']}"))["status"]
    assert status == ("failed" if provider_fails else "ready")
    assert events == ["upload", "create", "cleanup"]
