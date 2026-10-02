import pytest
from fastapi.testclient import TestClient

from bingo.config import Settings
from bingo.main import create_app


@pytest.fixture
def client(tmp_path):
    settings = Settings(
        app={"environment": "test"},
        database={"url": f"sqlite+aiosqlite:///{tmp_path / 'account.db'}"},
    )
    with TestClient(create_app(settings)) as connection:
        result = connection.post(
            "/api/v1/auth/register", json={"phone": "13800138000", "password": "original123"}
        ).json()
        connection.headers["Authorization"] = "Bearer " + result["access_token"]
        connection.put(
            "/api/v1/me/profile",
            json={
                "username": "小明",
                "assistant_name": "Bingo",
                "personality": "温柔体贴",
                "role": "女朋友",
            },
        )
        yield connection


def recovery(client):
    result = client.post("/api/v1/me/recovery-profile", json={"birthday": "2000-05-01"})
    assert result.status_code == 200
    assert client.get("/api/v1/me").json()["birthday"] == "2000-05-01"
    return result.json()["recovery_code"]


def reset_payload(code):
    return {
        "phone": "13800138000",
        "username": "小明",
        "birthday": "2000-05-01",
        "recovery_code": code,
        "new_password": "newpassword123",
    }


def test_reset_revokes_sessions_and_rotates_recovery_code(client):
    code = recovery(client)
    result = client.post("/api/v1/auth/reset-password", json=reset_payload(code))
    assert result.status_code == 200
    assert result.json()["recovery_code"] != code
    assert client.get("/api/v1/me").status_code == 401
    assert client.post("/api/v1/auth/reset-password", json=reset_payload(code)).status_code == 400
    assert (
        client.post(
            "/api/v1/auth/login", json={"phone": "13800138000", "password": "original123"}
        ).status_code
        == 401
    )
    assert (
        client.post(
            "/api/v1/auth/login", json={"phone": "13800138000", "password": "newpassword123"}
        ).status_code
        == 200
    )


def test_public_profile_does_not_reveal_recovery_hash(client):
    recovery(client)
    assert "recovery_hash" not in client.get("/api/v1/me").json()
    assert (
        client.post("/api/v1/me/recovery-profile", json={"birthday": "2000-05-01"}).status_code
        == 409
    )


def test_birthday_and_username_are_not_sufficient_to_reset(client):
    recovery(client)
    assert (
        client.post("/api/v1/auth/reset-password", json=reset_payload("x" * 32)).status_code == 400
    )
    assert client.post(
        "/api/v1/auth/reset-password", json={**reset_payload("x" * 32), "phone": "13900139000"}
    ).json() == {"detail": "找回信息验证失败，请检查后重试"}


def test_recovery_rate_limit(client):
    code = recovery(client)
    for _ in range(10):
        assert (
            client.post(
                "/api/v1/auth/reset-password",
                json={**reset_payload(code), "birthday": "2000-05-02"},
            ).status_code
            == 400
        )
    assert client.post("/api/v1/auth/reset-password", json=reset_payload(code)).status_code == 429


def test_change_password_requires_old_password_and_revokes_sessions(client):
    assert (
        client.post(
            "/api/v1/me/password",
            json={"old_password": "incorrect123", "new_password": "newpassword123"},
        ).status_code
        == 400
    )
    assert (
        client.post(
            "/api/v1/me/password",
            json={"old_password": "original123", "new_password": "newpassword123"},
        ).status_code
        == 204
    )
    assert client.get("/api/v1/me").status_code == 401
