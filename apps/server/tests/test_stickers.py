import base64

import pytest
from fastapi.testclient import TestClient

from bingo.agent.model_client import ModelMessage
from bingo.config import Settings
from bingo.main import create_app
from bingo.services import stickers
from bingo.utils.stickers.catalog import CATALOG
from bingo.utils.stickers.content import encode_sticker, parse_sticker
from tests.api_support import api_payload
from tests.test_group_chat import create, group_app, wait  # noqa: F401,F811

P = "/api/v1"
PNG = base64.b64decode(
    "iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mP8/x8AAwMCAO+jVn0AAAAASUVORK5CYII="
)


@pytest.fixture
def app(tmp_path, monkeypatch):
    monkeypatch.setattr(stickers, "DIRECTORY", tmp_path / "stickers")
    settings = Settings(
        app={"environment": "test"},
        model={"provider": "echo"},
        database={"url": f"sqlite+aiosqlite:///{tmp_path / 'stickers.db'}"},
    )
    with TestClient(create_app(settings)) as client:
        users = []
        for number in ("19966660001", "19966660002"):
            data = api_payload(
                client.post(P + "/auth/register", json={"phone": number, "password": "password123"})
            )
            headers = {"Authorization": "Bearer " + data["access_token"]}
            client.put(
                P + "/me/profile",
                headers=headers,
                json={
                    "username": "表情测试",
                    "assistant_name": "搭子",
                    "personality": "温柔体贴",
                    "role": "同事",
                },
            )
            users.append(headers)
        yield client, users


def upload(client, headers, **changes):
    payload = {"label": "晚安啦", "mime_type": "image/png", "data": base64.b64encode(PNG).decode()}
    payload.update(changes)
    return client.post(P + "/stickers", headers=headers, json=payload)


def test_private_upload_dedup_remove_and_old_message_image(app):
    client, (alice, bob) = app
    response = upload(client, alice)
    assert response.status_code == 201, response.text
    value = api_payload(response)
    path = P + "/stickers/" + value["id"][7:]
    assert api_payload(upload(client, alice))["id"] == value["id"]
    assert len(api_payload(client.get(P + "/stickers", headers=alice))) == 1
    assert api_payload(client.get(P + "/stickers", headers=bob)) == []
    assert client.get(path + "/image", headers=bob).status_code == 404
    assert client.delete(path, headers=bob).status_code == 404
    assert client.get(path + "/image", headers=alice).content == PNG
    assert (
        client.post(P + "/chat", headers=bob, json={"content": encode_sticker(value)}).status_code
        == 404
    )
    assert client.delete(path, headers=alice).status_code == 204
    assert api_payload(client.get(P + "/stickers", headers=alice)) == []
    assert client.get(path + "/image", headers=alice).content == PNG
    assert (
        client.post(P + "/chat", headers=alice, json={"content": encode_sticker(value)}).status_code
        == 404
    )
    assert api_payload(upload(client, alice))["id"] == value["id"]
    assert (
        client.request(
            "DELETE", P + "/me/account", headers=alice, json={"confirmed": True}
        ).status_code
        == 204
    )
    assert list(stickers.DIRECTORY.glob("*.image")) == []


def test_builtin_canonical_caption_round_trip_and_model_semantics(app):
    client, (alice, _) = app
    spoofed = {**CATALOG["girlfriend_1"], "label": "假文字", "description": "伪造语义"}
    result = client.post(P + "/chat", headers=alice, json={"content": encode_sticker(spoofed)})
    assert result.status_code == 200, result.text
    value = api_payload(result)
    assert "抱抱" in value["content"]
    assert "伪造语义" not in value["content"]
    messages = api_payload(
        client.get(P + f"/conversations/{value['conversation_id']}/messages", headers=alice)
    )
    sent = next(row for row in messages if row["role"] == "user")
    assert parse_sticker(sent["content"])["label"] == "抱抱"
    model = ModelMessage(role="user", content=sent["content"])
    assert "张开双臂" in model.content
    assert "bingo.sticker" not in model.content and "girlfriend_1" not in model.content
    titles = api_payload(client.get(P + "/conversations", headers=alice))
    assert titles[0]["title"] == "[表情] 抱抱"


@pytest.mark.parametrize(
    "changes", [{"label": "  "}, {"data": "notbase64"}, {"mime_type": "text/plain"}]
)
def test_invalid_upload_rejected(app, changes):
    client, (alice, _) = app
    assert upload(client, alice, **changes).status_code == 422


def test_invalid_envelope_and_mixed_attachments_rejected(app):
    client, (alice, _) = app
    assert (
        client.post(
            P + "/chat", headers=alice, json={"content": "[[bingo.sticker.v1]]bad"}
        ).status_code
        == 422
    )
    assert (
        client.post(
            P + "/chat",
            headers=alice,
            json={
                "content": encode_sticker(CATALOG["girlfriend_2"]),
                "images": [{"mime_type": "image/png", "data": base64.b64encode(PNG).decode()}],
            },
        ).status_code
        == 422
    )


def test_group_sticker_keeps_caption_and_model_receives_meaning(group_app):  # noqa: F811
    client, ((alice, _), _), roles, model = group_app
    group = create(client, alice, roles[:2])
    response = client.post(
        P + f"/groups/{group['id']}/chat",
        headers=alice,
        json={
            "content": encode_sticker(CATALOG["girlfriend_2"]),
            "mentions": [roles[0]["id"]],
            "client_message_id": "sticker-group-test-0001",
        },
    )
    assert response.status_code == 200, response.text
    wait(client)
    messages = api_payload(client.get(P + f"/groups/{group['id']}/messages", headers=alice))
    assert parse_sticker(messages[0]["content"])["label"] == "晚安啦"
    assert model.contexts
    context = "\n".join(message.content for message in model.contexts[0])
    assert "晚安啦" in context and "闭眼抱枕" in context
    assert "bingo.sticker" not in context
