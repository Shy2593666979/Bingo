import asyncio
import json

import pytest
from fastapi.testclient import TestClient
from sqlmodel import select

from bingo.config import Settings
from bingo.db.models.community import CharacterShare
from bingo.db.models.welcome import WelcomeJob
from bingo.main import create_app
from tests.api_support import api_payload

PREFIX = "/api/v1"


class WelcomeModel:
    def __init__(self):
        self.prompts = []

    async def complete(self, messages):
        data = json.loads(messages[-1].content)
        self.prompts.append(data)
        return json.dumps(
            {
                "private": f"{data['用户']['昵称']}，我是{data['你']['名字']}。今天想聊什么？",
                "group": "",
            },
            ensure_ascii=False,
        )


@pytest.fixture
def client(tmp_path):
    settings = Settings(
        app={"environment": "test"},
        database={"url": f"sqlite+aiosqlite:///{tmp_path / 'added-welcome.db'}"},
    )
    with TestClient(create_app(settings)) as connection:
        connection.app.state.services.companion_welcome.model = WelcomeModel()
        register(connection, "19900117101", "小林", "女")
        yield connection


def register(client, phone, name, gender):
    auth = api_payload(
        client.post(
            PREFIX + "/auth/register",
            json={
                "phone": phone,
                "password": "password123",
            },
        )
    )
    client.headers["Authorization"] = f"Bearer {auth['access_token']}"
    assert (
        client.put(
            PREFIX + "/me/user-profile",
            json={
                "username": name,
                "gender": gender,
                "birthday": "2000-01-01",
            },
        ).status_code
        == 200
    )
    return auth["user"]["id"]


def create(client, *, draft=False):
    response = client.post(
        PREFIX + "/roles",
        json={
            "character_name": "创业老友",
            "relationship": "创业前辈",
            "background": "喜欢琢磨产品，平时也爱散步和听人分享生活。",
            "speaking_style": "口语简洁，不堆术语，先倾听再接话。",
            "personality_tags": ["思路梳理", "轻松幽默"],
            "opening_line": "这一句是旧的手写开场白，不能发送。",
            "draft": draft,
        },
    )
    assert response.status_code == 201, response.text
    return api_payload(response)


def drain(client):
    async def finish():
        service = client.app.state.services.companion_welcome
        await service.tick()
        await asyncio.gather(*list(service.tasks.values()))

    client.portal.call(finish)


def jobs(client):
    async def load():
        async with client.app.state.database.session_factory() as session:
            return (await session.exec(select(WelcomeJob))).all()

    return client.portal.call(load)


def conversation_messages(client, role):
    opened = api_payload(client.post(PREFIX + f"/roles/{role['id']}/conversation"))
    messages = api_payload(client.get(PREFIX + f"/conversations/{opened['id']}/messages"))
    return opened, messages


def test_custom_add_generates_a_personalized_greeting_once(client):
    role = create(client)
    assert role["opening_line"] == ""
    opened, _ = conversation_messages(client, role)
    assert opened["welcome_unread"]
    drain(client)
    _, messages = conversation_messages(client, role)
    assert len(messages) == 1
    assert messages[0]["content"] == "小林，我是创业老友。今天想聊什么？"
    assert messages[0]["run_id"].startswith("welcome-")
    assert messages[0]["status"] == "completed"
    prompt = client.app.state.services.companion_welcome.model.prompts[0]
    assert prompt["用户"]["昵称"] == "小林" and prompt["用户"]["性别"] == "女"
    assert prompt["用户"]["年龄"] is not None
    assert prompt["你"]["关系"] == "创业前辈"
    assert prompt["你"]["说话风格"] == role["speaking_style"]
    assert "散步" in prompt["你"]["人设"]
    assert "opening_line" not in json.dumps(prompt)
    response = client.put(
        PREFIX + f"/roles/{role['id']}",
        json={
            "character_name": "创业老友",
            "background": "新的背景资料。",
            "speaking_style": "轻松直接，少说套话。",
        },
    )
    assert response.status_code == 200
    drain(client)
    assert len(jobs(client)) == 1
    assert len(client.app.state.services.companion_welcome.model.prompts) == 1
    assert len(conversation_messages(client, role)[1]) == 1
    assert api_payload(client.get(PREFIX + "/groups")) == []


def test_draft_does_not_greet_until_creation_is_finished(client):
    role = create(client, draft=True)
    drain(client)
    assert jobs(client) == []
    assert client.app.state.services.companion_welcome.model.prompts == []
    payload = {"name": "创业老友", "background": "喜欢产品和生活。", "draft": False}
    assert client.put(PREFIX + f"/roles/{role['id']}", json=payload).status_code == 200
    drain(client)
    assert len(jobs(client)) == 1
    assert conversation_messages(client, role)[1][0]["content"].startswith("小林，")
    assert client.put(PREFIX + f"/roles/{role['id']}", json=payload).status_code == 200
    drain(client)
    assert len(jobs(client)) == 1


def test_installing_legacy_community_share_generates_for_the_new_user(client):
    source = create(client)
    drain(client)
    share = api_payload(
        client.post(
            PREFIX + "/community/characters",
            json={
                "role_id": source["id"],
                "introduction": "分享一个愿意陪你聊生活的创业前辈。",
                "request_id": "welcome-share-request-001",
            },
        )
    )
    assert "opening_line" not in share["persona"]

    async def legacy_snapshot():
        async with client.app.state.database.session_factory() as session:
            record = await session.get(CharacterShare, share["id"])
            snapshot = json.loads(record.snapshot_json)
            snapshot["opening_line"] = "小林你好，这段旧招呼不应该给其他用户。"
            record.snapshot_json = json.dumps(snapshot, ensure_ascii=False)
            await session.commit()

    client.portal.call(legacy_snapshot)
    register(client, "19900117102", "小周", "男")
    route = PREFIX + f"/community/characters/{share['id']}/install"
    copied = api_payload(client.post(route))
    assert copied["opening_line"] == ""
    assert api_payload(client.post(route))["id"] == copied["id"]
    drain(client)
    _, messages = conversation_messages(client, copied)
    assert len(messages) == 1
    assert messages[0]["content"] == "小周，我是创业老友。今天想聊什么？"
    prompts = client.app.state.services.companion_welcome.model.prompts
    assert len(prompts) == 2
    assert prompts[-1]["用户"]["性别"] == "男"
    assert prompts[-1]["你"]["关系"] == source["relationship"]
    assert len(jobs(client)) == 2
    assert api_payload(client.get(PREFIX + "/groups")) == []
