from sqlalchemy import create_engine, text

from bingo.db.session import _upgrade_chat_settings
from tests.api_support import api_payload
from tests.test_chat_info import client, open_chat  # noqa: F401
from tests.test_group_chat import create, group_app, wait  # noqa: F401

P = "/api/v1"


def test_archive_preserves_single_history_and_new_message_restores_it(client):  # noqa: F811
    identifier = open_chat(client)
    role = next(
        r for r in api_payload(client.get(P + "/roles")) if r["conversation_id"] == identifier
    )
    assert (
        client.put(
            P + "/me/profile",
            json={
                "username": "测试",
                "assistant_name": "搭子",
                "personality": "温柔体贴",
                "role": role["id"],
            },
        ).status_code
        == 200
    )
    assert (
        client.post(
            P + "/chat", json={"conversation_id": identifier, "content": "保留这条聊天"}
        ).status_code
        == 200
    )
    path = P + f"/conversations/{identifier}"
    before = api_payload(client.get(path + "/messages"))
    assert client.patch(path + "/settings", json={"archived": True}).status_code == 200
    roles = api_payload(client.get(P + "/roles"))
    assert next(r for r in roles if r["id"] == role["id"])["archived"] is True
    assert api_payload(client.get(path + "/messages")) == before
    other = api_payload(
        client.post(P + "/auth/register", json={"phone": "19977770002", "password": "password123"})
    )
    assert (
        client.patch(
            path + "/settings",
            headers={"Authorization": "Bearer " + other["access_token"]},
            json={"archived": False},
        ).status_code
        == 404
    )
    assert (
        client.post(
            P + "/chat", json={"conversation_id": identifier, "content": "再聊一句"}
        ).status_code
        == 200
    )
    roles = api_payload(client.get(P + "/roles"))
    assert next(r for r in roles if r["id"] == role["id"])["archived"] is False
    assert len(api_payload(client.get(path + "/messages"))) > len(before)


def test_archive_does_not_disband_group_and_new_message_restores_it(group_app):  # noqa: F811
    c, ((alice, _), (bob, _)), roles, _ = group_app
    group = create(c, alice, roles[:2])
    path = P + f"/groups/{group['id']}"
    payload = {
        "content": "群聊记录要保留",
        "mentions": [roles[0]["id"]],
        "client_message_id": "archive-group-0001",
    }
    assert c.post(path + "/chat", headers=alice, json=payload).status_code == 200
    wait(c)
    before = api_payload(c.get(path + "/messages", headers=alice))
    assert api_payload(c.patch(path, headers=alice, json={"archived": True}))["archived"] is True
    assert c.patch(path, headers=bob, json={"archived": False}).status_code == 404
    assert api_payload(c.get(path + "/messages", headers=alice)) == before
    assert len(api_payload(c.get(path, headers=alice))["members"]) == 2
    payload["client_message_id"] = "archive-group-0002"
    assert c.post(path + "/chat", headers=alice, json=payload).status_code == 200
    wait(c)
    assert api_payload(c.get(path, headers=alice))["archived"] is False


def test_existing_sqlite_database_gains_archive_flags_without_data_loss(tmp_path):
    engine = create_engine(f"sqlite:///{tmp_path / 'old.db'}")
    with engine.begin() as conn:
        conn.execute(text("CREATE TABLE conversations (id TEXT PRIMARY KEY)"))
        conn.execute(text("CREATE TABLE chat_groups (id TEXT PRIMARY KEY)"))
        conn.execute(text("INSERT INTO conversations VALUES ('keep-single')"))
        conn.execute(text("INSERT INTO chat_groups VALUES ('keep-group')"))
        _upgrade_chat_settings(conn)
        _upgrade_chat_settings(conn)
        assert conn.execute(text("SELECT id, archived FROM conversations")).all() == [
            ("keep-single", 0)
        ]
        assert conn.execute(text("SELECT id, archived FROM chat_groups")).all() == [
            ("keep-group", 0)
        ]
    engine.dispose()
