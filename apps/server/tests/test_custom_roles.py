import base64
from datetime import timedelta

import pytest
from fastapi.testclient import TestClient

from bingo.config import Settings
from bingo.db.models import VoiceJob
from bingo.db.time import beijing_now
from bingo.main import create_app
from bingo.services.voice_cloning import VoiceCloningService


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
        voice_cloning={"sample_host": "public_url"},
    )
    with TestClient(create_app(settings)) as connection:
        response = connection.post(
            "/api/v1/auth/register",
            json={
                "phone": "13800138000",
                "password": "password123",
            },
        )
        connection.headers["Authorization"] = f"Bearer {response.json()['access_token']}"
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
    return response.json()


def test_builtin_nicknames_preserve_role_identity(client):
    expected = {
        "女朋友": "甜甜",
        "男朋友": "暖暖",
        "同事": "小周",
        "老师": "小田老师",
        "小朋友": "星星",
        "家长": "文清",
    }
    roles = client.get("/api/v1/roles").json()
    assert [role["name"] for role in roles] == [
        "女朋友", "男朋友", "同事", "老师", "家长", "小朋友"
    ]
    assert {role["name"]: role["nickname"] for role in roles} == expected
    for role in roles:
        assert role["role_type"] == role["name"]
        opened = client.post(f"/api/v1/roles/{role['id']}/conversation")
        assert opened.status_code == 200
        profile = client.get("/api/v1/me").json()
        assert profile["role"] == role["name"]
        assert profile["role_id"] == role["id"]
        assert profile["assistant_name"] == role["nickname"]
    custom = create_role(client)
    assert custom["nickname"] == "知心姐姐"
    assert custom["role_type"] == "自定义角色"


def test_custom_role_selection_and_builtin_compatibility(client):
    before = client.get("/api/v1/profile/options").json()
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
    assert response.json()["role"] == "知心姐姐"
    assert response.json()["role_id"] == role["id"]
    assert "知心姐姐" in client.get("/api/v1/profile/options").json()["roles"]
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
    assert response.json()["traits"] == role["traits"]
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
    assert response.json()["role"] == "小朋友"


def test_private_roles_cannot_be_read_selected_or_mutated_by_another_user(client):
    role = create_role(client)
    other = client.post(
        "/api/v1/auth/register",
        json={
            "phone": "13900139000",
            "password": "password123",
        },
    ).json()
    client.headers["Authorization"] = f"Bearer {other['access_token']}"
    assert role["id"] not in {item["id"] for item in client.get("/api/v1/roles").json()}
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
    assert role["id"] not in {item["id"] for item in client.get("/api/v1/roles").json()}
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
    assert role["id"] in {item["id"] for item in client.get("/api/v1/roles").json()}


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
    assert "时间太短" in response.json()["detail"]
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
            "audio": base64.b64encode(bytes(32000 * 20)).decode(),
            "consent": True,
        },
    )
    assert response.status_code == 202
    identifier = response.json()["id"]

    async def finish_jobs():
        tasks = list(client.app.state.voice_cloning.tasks)
        if tasks:
            import asyncio

            await asyncio.gather(*tasks)

    client.portal.call(finish_jobs)
    assert client.get(f"/api/v1/voice-jobs/{identifier}").json()["status"] == "ready"

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
    assert client.get("/api/v1/me").json()["role"] == "女朋友"
    remaining = client.get("/api/v1/roles").json()
    fallback = next(item for item in remaining if item["name"] == "女朋友")
    assert (
        next(item for item in remaining if item["id"] == second["id"])["voice_source_id"]
        == fallback["id"]
    )
    assert client.post(f"/api/v1/roles/{role['id']}/voice-preview").status_code == 404
    assert ("delete_voice", {"voice_id": "private-clone"}) in calls


def test_voice_sample_is_temporary_and_unavailable_after_role_deletion(client):
    role = create_role(client)
    user_id = client.get("/api/v1/me").json()["id"]

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
    payload = {"audio": base64.b64encode(bytes(32000 * 20)).decode(), "consent": True}
    first = client.post(f"/api/v1/roles/{role['id']}/voice-clone", json=payload).json()

    async def finish_jobs():
        import asyncio

        tasks = list(client.app.state.voice_cloning.tasks)
        if tasks:
            await asyncio.gather(*tasks)

    client.portal.call(finish_jobs)
    assert client.get(f"/api/v1/voice-jobs/{first['id']}").json()["status"] == "failed"
    second = client.post(f"/api/v1/roles/{role['id']}/voice-clone", json=payload).json()
    client.portal.call(finish_jobs)
    assert second["id"] == first["id"]
    assert client.get(f"/api/v1/voice-jobs/{second['id']}").json()["status"] == "ready"
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
        json={"audio": base64.b64encode(bytes(32000 * 20)).decode(), "consent": True},
    )
    assert response.status_code == 202

    async def finish_jobs():
        import asyncio

        tasks = list(client.app.state.voice_cloning.tasks)
        if tasks:
            await asyncio.gather(*tasks)

    client.portal.call(finish_jobs)
    status = client.get(f"/api/v1/voice-jobs/{response.json()['id']}").json()["status"]
    assert status == ("failed" if provider_fails else "ready")
    assert events == ["upload", "create", "cleanup"]
