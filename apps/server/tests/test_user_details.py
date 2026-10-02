import base64

import pytest
from fastapi.testclient import TestClient

from bingo.config import Settings
from bingo.main import create_app
from tests.api_support import api_payload


@pytest.fixture
def client(tmp_path):
    settings = Settings(
        app={"environment": "test"},
        database={"url": f"sqlite+aiosqlite:///{tmp_path / 'user-details.db'}"},
    )
    with TestClient(create_app(settings)) as connection:
        result = api_payload(
            connection.post(
                "/api/v1/auth/register", json={"phone": "13800002222", "password": "original123"}
            )
        )
        connection.headers["Authorization"] = "Bearer " + result["access_token"]
        yield connection


def payload(**overrides):
    return {"username": " 小雨 ", "birthday": "2000-05-01", "gender": "女", **overrides}


def test_user_only_onboarding_and_recovery(client):
    result = client.put("/api/v1/me/user-profile", json=payload())
    assert result.status_code == 200
    profile = api_payload(result)["user"]
    assert profile["username"] == "小雨"
    assert profile["gender"] == "女"
    assert profile["birthday"] == "2000-05-01"
    assert profile["user_avatar_data"] is None
    assert profile["onboarding_complete"] is True
    assert profile["role"] is None
    assert "recovery_hash" not in profile
    code = api_payload(result)["recovery_code"]
    assert len(code) >= 20

    retry = client.put("/api/v1/me/user-profile", json=payload())
    assert api_payload(retry)["recovery_code"] is None
    assert (
        client.put("/api/v1/me/user-profile", json=payload(birthday="2001-01-01")).status_code
        == 409
    )
    assert (
        client.post(
            "/api/v1/auth/reset-password",
            json={
                "phone": "13800002222",
                "username": "小雨",
                "birthday": "2000-05-01",
                "recovery_code": code,
                "new_password": "newpassword123",
            },
        ).status_code
        == 200
    )


@pytest.mark.parametrize(
    "overrides",
    [
        {"gender": "invalid"},
        {"username": "   "},
        {"birthday": "2099-01-01"},
        {"user_avatar_data": "not an image"},
    ],
)
def test_invalid_user_details_do_not_complete_onboarding(client, overrides):
    assert client.put("/api/v1/me/user-profile", json=payload(**overrides)).status_code == 422
    assert api_payload(client.get("/api/v1/me"))["onboarding_complete"] is False


def test_user_avatar_does_not_replace_role_avatar(client):
    client.put(
        "/api/v1/me/profile",
        json={
            "username": "旧昵称",
            "assistant_name": "小宝",
            "role": "女朋友",
            "personality": "温柔体贴",
        },
    )
    avatar = base64.b64encode(
        base64.b64decode(
            "iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mP8/x8AAwMCAO+jDVsAAAAASUVORK5CYII="
        )
    ).decode()
    result = client.put("/api/v1/me/user-profile", json=payload(user_avatar_data=avatar))
    assert result.status_code == 200
    profile = api_payload(client.get("/api/v1/me"))
    assert profile["user_avatar_data"] == avatar
    assert profile["avatar_data"] is None
    assert profile["assistant_name"] == "小宝"
    assert profile["role"] == "女朋友"
    assert profile["personality"] == "温柔体贴"


def test_personality_update_does_not_change_role_or_user_details(client):
    client.put("/api/v1/me/user-profile", json=payload())
    before = api_payload(client.get("/api/v1/me"))
    response = client.put("/api/v1/me/personality", json={"personality": "幽默风趣"})
    assert response.status_code == 200
    after = api_payload(response)
    assert after["personality"] == "幽默风趣"
    for key in ("role_id", "role", "assistant_name", "username", "birthday", "gender"):
        assert after[key] == before[key]
    assert client.put("/api/v1/me/personality", json={"personality": "invalid"}).status_code == 422
