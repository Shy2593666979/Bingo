import pytest
from fastapi.testclient import TestClient

from bingo.config import Settings
from bingo.main import create_app
from tests.api_support import api_payload


@pytest.fixture
def client(tmp_path):
    settings = Settings(
        app={"environment": "test"},
        database={"url": f"sqlite+aiosqlite:///{tmp_path / 'account.db'}"},
    )
    with TestClient(create_app(settings)) as connection:
        result = api_payload(
            connection.post(
                "/api/v1/auth/register", json={"phone": "13800138000", "password": "original123"}
            )
        )
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
    assert api_payload(client.get("/api/v1/me"))["birthday"] == "2000-05-01"
    assert "recovery_code" not in api_payload(result)


def reset_payload():
    return {
        "phone": "13800138000",
        "username": "小明",
        "birthday": "2000-05-01",
        "new_password": "newpassword123",
    }


def test_reset_without_code_revokes_sessions(client):
    recovery(client)
    result = client.post("/api/v1/auth/reset-password", json=reset_payload())
    assert result.status_code == 200
    assert "recovery_code" not in api_payload(result)
    assert client.get("/api/v1/me").status_code == 401
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
    assert "recovery_hash" not in api_payload(client.get("/api/v1/me"))
    assert (
        client.post("/api/v1/me/recovery-profile", json={"birthday": "2000-05-01"}).status_code
        == 409
    )


def test_reset_rejects_account_without_birthday(client):
    assert client.post("/api/v1/auth/reset-password", json=reset_payload()).status_code == 400


def test_reset_rejects_invalid_password_without_changing_login(client):
    recovery(client)
    assert client.post(
        "/api/v1/auth/reset-password", json={**reset_payload(), "new_password": "short"}
    ).status_code == 422
    assert client.get("/api/v1/me").status_code == 200


def test_legacy_recovery_hash_is_not_required(client):
    import asyncio

    from bingo.db.repositories import UserRepository

    recovery(client)

    async def set_legacy_hash():
        async with client.app.state.database.session_factory() as session:
            user = await UserRepository(session).get_by_phone("13800138000")
            user.recovery_hash = "a" * 64
            session.add(user)
            await session.commit()

    asyncio.run(set_legacy_hash())
    assert client.post("/api/v1/auth/reset-password", json=reset_payload()).status_code == 200


@pytest.mark.parametrize(
    "overrides",
    [{"phone": "13900139000"}, {"username": "小红"}, {"birthday": "2000-05-02"}],
)
def test_reset_requires_matching_phone_username_and_birthday(client, overrides):
    recovery(client)
    assert api_payload(
        client.post(
            "/api/v1/auth/reset-password", json={**reset_payload(), **overrides}
        )
    ) == {"detail": "找回信息验证失败，请检查后重试"}


def test_recovery_rate_limit(client):
    recovery(client)
    for _ in range(10):
        assert (
            client.post(
                "/api/v1/auth/reset-password",
                json={**reset_payload(), "birthday": "2000-05-02"},
            ).status_code
            == 400
        )
    assert client.post("/api/v1/auth/reset-password", json=reset_payload()).status_code == 429


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
