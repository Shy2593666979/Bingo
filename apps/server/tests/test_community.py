import base64
import json
from concurrent.futures import ThreadPoolExecutor

import pytest
from fastapi.testclient import TestClient
from sqlmodel import select

from bingo.config import Settings
from bingo.db.models import Memory, Role
from bingo.db.models.community import (
    CharacterFavorite,
    CharacterInstall,
    CharacterShare,
    CommunityReport,
)
from bingo.main import create_app
from bingo.roles.community_catalog import COMMUNITY_CHARACTERS, community_share_id
from tests.api_support import api_payload

PREFIX = "/api/v1"
AVATAR = base64.b64encode(b"\x89PNG\r\n\x1a\n" + b"\x00" * 8 + b"\x00\x00\x00\x01" * 2).decode()


def test_search_finds_another_users_shares_by_author_name(community):
    client, ((alice, _), (bob, _), (charlie, _)) = community
    assert (
        client.put(
            PREFIX + "/me/user-profile",
            headers=alice,
            json={"username": "小林", "gender": "女", "birthday": "2000-01-01"},
        ).status_code
        == 200
    )
    first = publish(client, alice, create_role(client, alice, "夜谈伙伴"), "author-search-0001")
    publish(client, charlie, create_role(client, charlie, "生活伙伴"), "author-search-0002")
    result = api_payload(
        client.get(PREFIX + "/community/characters", headers=bob, params={"q": "小林"})
    )
    assert [row["id"] for row in result["items"]] == [first["id"]]


def test_share_preserves_character_fields_without_copying_a_manual_greeting(community):
    client, ((alice, _), (bob, _), _) = community
    role = api_payload(
        client.post(
            PREFIX + "/roles",
            headers=alice,
            json={
                "name": "新的陪伴搭子",
                "prompt": "温柔倾听生活里的小事。",
                "description": "你的日常陪伴",
                "opening_line": "很高兴遇见你，今天想聊点什么？",
                "traits": ["善于倾听", "陪伴聊天"],
                "relationship": "老朋友",
                "background": "住在海边，喜欢阅读和散步。",
                "speaking_style": "简洁自然，先倾听，再轻松接话。",
            },
        )
    )
    assert role["description"] == "你的日常陪伴"
    assert role["opening_line"] == ""
    payload = {
        "role_id": role["id"],
        "introduction": "把这份温柔分享给你",
        "request_id": "h2-title-tags-request",
        "title": "  遇见温柔  ",
        "share_tags": ["治愈陪伴", "日常聊天"],
    }
    response = client.post(PREFIX + "/community/characters", headers=alice, json=payload)
    assert response.status_code == 201
    share = api_payload(response)
    assert share["title"] == "遇见温柔"
    assert share["share_tags"] == payload["share_tags"]
    assert share["traits"] == role["traits"]
    assert (
        api_payload(client.post(PREFIX + "/community/characters", headers=alice, json=payload))[
            "id"
        ]
        == share["id"]
    )
    assert (
        client.post(
            PREFIX + "/community/characters", headers=alice, json={**payload, "title": "换了标题"}
        ).status_code
        == 409
    )
    copied = api_payload(
        client.post(PREFIX + f"/community/characters/{share['id']}/install", headers=bob)
    )
    assert copied["id"] != role["id"]
    assert copied["opening_line"] == ""
    assert "opening_line" not in share["persona"]
    assert copied["description"] == role["description"]
    assert copied["traits"] == role["traits"]
    for field in ("relationship", "background", "speaking_style", "personality_tags"):
        assert copied[field] == role[field]
        assert share["persona"][field] == role[field]


def test_share_metadata_rejects_too_many_or_oversize_tags(community):
    client, ((alice, _), _, _) = community
    role = create_role(client, alice)
    payload = {
        "role_id": role["id"],
        "introduction": "一份分享",
        "request_id": "h2-invalid-tags-request",
    }
    for tags in [["a", "b", "c", "d"], ["x" * 21], [" "]]:
        assert (
            client.post(
                PREFIX + "/community/characters",
                headers=alice,
                json={**payload, "share_tags": tags},
            ).status_code
            == 422
        )


@pytest.fixture
def community(tmp_path):
    settings = Settings(
        app={"environment": "test"},
        model={"provider": "echo"},
        database={"url": f"sqlite+aiosqlite:///{tmp_path / 'community.db'}"},
    )
    with TestClient(create_app(settings)) as client:
        users = []
        for index, name in enumerate(["小林", "小夏", "小雨"]):
            data = api_payload(
                client.post(
                    PREFIX + "/auth/register",
                    json={"phone": f"1991111111{index}", "password": "password123"},
                )
            )
            headers = {"Authorization": f"Bearer {data['access_token']}"}
            client.put(
                PREFIX + "/me/profile",
                headers=headers,
                json={
                    "username": name,
                    "assistant_name": "伙伴",
                    "personality": "温柔体贴",
                    "role": "朋友",
                },
            )
            users.append((headers, data["user"]["id"]))
        yield client, users


def create_role(client, headers, name="星野"):
    response = client.post(
        PREFIX + "/roles",
        headers=headers,
        json={
            "name": name,
            "prompt": "喜欢星星，也擅长倾听。",
            "personality": "幽默风趣",
            "role_type": "朋友",
            "avatar_data": AVATAR,
            "categories": ["陪伴", "朋友"],
            "traits": ["善于倾听", "陪伴聊天"],
        },
    )
    assert response.status_code == 201, response.text
    return api_payload(response)


def test_home_recommendations_filter_before_pagination_and_advance_after_install(community):
    client, ((alice, _), (bob, _), (charlie, _)) = community
    shares = [
        publish(client, alice, create_role(client, alice, f"推荐{i}"), f"recommend-{i:04}")
        for i in range(5)
    ]
    publish(client, bob, create_role(client, bob), "recommend-own-001")
    path = PREFIX + "/community/characters"
    client.delete(path + f"/{shares[4]['id']}", headers=alice)
    client.post(path + f"/{shares[3]['id']}/reports", headers=bob, json={"reason": "不想看到"})
    # A popular older publication outranks a newer zero-score publication.
    client.put(path + f"/{shares[0]['id']}/like", headers=charlie, json={"liked": True})

    def recommended():
        response = client.get(path, headers=bob, params={"scope": "recommended", "limit": 1})
        assert response.status_code == 200
        return api_payload(response)

    first = recommended()
    assert first["total"] == 3 + len(COMMUNITY_CHARACTERS)
    assert first["items"][0]["id"] == shares[0]["id"]
    assert first["next_offset"] == 1
    copied = api_payload(client.post(path + f"/{shares[0]['id']}/install", headers=bob))
    assert copied["id"] != shares[0]["id"]
    second = recommended()
    assert second["total"] == 2 + len(COMMUNITY_CHARACTERS)
    assert second["items"][0]["id"] == shares[2]["id"]
    # Deleted copies remain in install history and are not reintroduced as new.
    client.delete(PREFIX + f"/roles/{copied['id']}", headers=bob)
    assert recommended()["total"] == 2 + len(COMMUNITY_CHARACTERS)


def publish(client, headers, role, key="request-key-0001", introduction="一起看星星的搭子"):
    response = client.post(
        PREFIX + "/community/characters",
        headers=headers,
        json={"role_id": role["id"], "introduction": introduction, "request_id": key},
    )
    assert response.status_code == 201, response.text
    return api_payload(response)


def test_popularity_uses_likes_favorites_comments_and_time_not_installs(community):
    client, ((alice, _), (bob, _), (charlie, _)) = community
    shares = [
        publish(client, alice, create_role(client, alice, f"热度搭子{i}"), f"hot-request-{i:03}")
        for i in range(4)
    ]
    path = PREFIX + "/community/characters"

    def ranked():
        return api_payload(client.get(path, headers=bob, params={"sort": "popular", "limit": 3}))[
            "items"
        ]

    assert [row["id"] for row in ranked()] == [row["id"] for row in reversed(shares[1:])]
    for headers in (bob, charlie):
        assert client.post(path + f"/{shares[0]['id']}/install", headers=headers).status_code == 200
    assert ranked()[0]["id"] == shares[3]["id"]
    for headers in (bob, charlie):
        result = client.put(
            path + f"/{shares[0]['id']}/like", headers=headers, json={"liked": True}
        )
        assert result.status_code == 200
    result = api_payload(
        client.put(path + f"/{shares[0]['id']}/like", headers=bob, json={"liked": True})
    )
    assert result["like_count"] == 2
    client.put(path + f"/{shares[1]['id']}/favorite", headers=bob, json={"favorite": True})
    comment_ids = []
    for index in range(3):
        result = client.post(
            path + f"/{shares[2]['id']}/comments",
            headers=bob,
            json={"content": f" 很喜欢这个搭子 {index} ", "request_id": f"comment-hot-{index:03}"},
        )
        assert result.status_code == 201, result.text
        comment_ids.append(api_payload(result)["id"])
    ranked_rows = ranked()
    assert [row["id"] for row in ranked_rows] == [shares[2]["id"], shares[0]["id"], shares[1]["id"]]
    assert [row["popularity_score"] for row in ranked_rows] == [3, 2, 1]
    duplicate = client.post(
        path + f"/{shares[2]['id']}/comments",
        headers=bob,
        json={"content": "很喜欢这个搭子 0", "request_id": "comment-hot-000"},
    )
    assert api_payload(duplicate)["id"] == comment_ids[0]
    assert (
        client.post(
            path + f"/{shares[2]['id']}/comments",
            headers=bob,
            json={"content": "不同内容", "request_id": "comment-hot-000"},
        ).status_code
        == 409
    )
    comments = api_payload(client.get(path + f"/{shares[2]['id']}/comments", headers=bob))["items"]
    assert len(comments) == 3 and all(row["is_mine"] for row in comments)
    assert (
        client.delete(
            path + f"/{shares[2]['id']}/comments/{comment_ids[0]}", headers=charlie
        ).status_code
        == 404
    )
    assert (
        client.delete(
            path + f"/{shares[2]['id']}/comments/{comment_ids[0]}", headers=bob
        ).status_code
        == 204
    )
    assert ranked()[0]["popularity_score"] == 2
    client.delete(path + f"/{shares[2]['id']}", headers=alice)
    assert all(row["id"] != shares[2]["id"] for row in ranked())
    assert (
        client.post(
            path + f"/{shares[2]['id']}/comments",
            headers=bob,
            json={"content": "已经撤回", "request_id": "comment-withdrawn"},
        ).status_code
        == 404
    )


def test_copy_edit_reshare_chain_and_private_data_isolation(community):
    client, ((alice, alice_id), (bob, bob_id), (charlie, _)) = community
    role = create_role(client, alice)

    async def private_data():
        async with client.app.state.database.session_factory() as session:
            original = await session.get(Role, role["id"])
            original.voice = original.owned_voice = "private-voice-secret"
            original.voice_source_id = original.id
            session.add(Memory(user_id=alice_id, role_id=role["id"], content="作者私人秘密"))
            await session.commit()

    client.portal.call(private_data)
    share = publish(client, alice, role)
    assert "private-voice-secret" not in json.dumps(share)
    assert "作者私人秘密" not in json.dumps(share)
    assert "source_role_id" not in share
    assert share["persona"]["personality"] == "幽默风趣"
    listing = api_payload(client.get(PREFIX + "/community/characters", headers=bob))
    assert listing["items"][0]["id"] == share["id"]
    assert "persona" not in listing["items"][0]
    assert "avatar_data" not in listing["items"][0]
    avatar = client.get(PREFIX + f"/community/characters/{share['id']}/avatar", headers=bob)
    assert avatar.headers["content-type"] == "image/png"
    assert avatar.content == base64.b64decode(AVATAR)
    copy = api_payload(
        client.post(PREFIX + f"/community/characters/{share['id']}/install", headers=bob)
    )
    assert copy["id"] != role["id"] and not copy["builtin"]
    for field in ["prompt", "personality", "avatar_data", "role_type", "categories", "traits"]:
        assert copy[field] == role[field]
    assert copy["source_publication_id"] == share["id"]
    assert copy["has_cloned_voice"] is False
    assert copy["voice_source_id"] != role["id"]
    edited = client.put(
        PREFIX + f"/roles/{copy['id']}",
        headers=bob,
        json={
            "name": "星野改编版",
            "prompt": "新的人设，喜欢海边散步。",
            "personality": "积极活泼",
            "avatar_data": copy["avatar_data"],
            "voice_source_id": copy["voice_source_id"],
            "role_type": copy["role_type"],
            "categories": copy["categories"],
            "traits": copy["traits"],
        },
    )
    assert edited.status_code == 200, edited.text
    second = publish(client, bob, api_payload(edited), key="bob-reshare-0001")
    assert second["parent_share_id"] == share["id"] and second["id"] != share["id"]
    third = api_payload(
        client.post(PREFIX + f"/community/characters/{second['id']}/install", headers=charlie)
    )
    assert third["id"] not in {copy["id"], role["id"]}
    assert third["prompt"] == "新的人设，喜欢海边散步。"
    assert (
        client.delete(PREFIX + f"/community/characters/{share['id']}", headers=alice).status_code
        == 204
    )
    assert (
        client.post(
            PREFIX + f"/community/characters/{share['id']}/install", headers=charlie
        ).status_code
        == 404
    )
    assert client.delete(PREFIX + f"/roles/{role['id']}", headers=alice).status_code == 204
    own = api_payload(client.get(PREFIX + "/roles", headers=bob))
    assert (
        next(item for item in own if item["id"] == copy["id"])["prompt"]
        == "新的人设，喜欢海边散步。"
    )

    async def verify():
        async with client.app.state.database.session_factory() as session:
            assert not (await session.exec(select(Memory).where(Memory.user_id == bob_id))).all()

    client.portal.call(verify)


def test_permissions_idempotency_favorites_reports_and_pagination(community):
    client, ((alice, _), (bob, _), _) = community
    role = create_role(client, alice)
    assert (
        client.post(
            PREFIX + "/community/characters",
            headers=bob,
            json={
                "role_id": role["id"],
                "introduction": "不能分享别人的私有角色",
                "request_id": "illegal-attempt",
            },
        ).status_code
        == 404
    )
    share = publish(client, alice, role)
    assert publish(client, alice, role)["id"] == share["id"]
    path = PREFIX + f"/community/characters/{share['id']}"
    copies = [api_payload(client.post(path + "/install", headers=bob)) for _ in range(2)]
    assert copies[0]["id"] == copies[1]["id"]
    assert client.delete(path, headers=bob).status_code == 404
    for _ in range(2):
        assert (
            client.put(path + "/favorite", headers=bob, json={"favorite": True}).status_code == 200
        )
        assert (
            client.post(path + "/reports", headers=bob, json={"reason": "侵权内容"}).status_code
            == 204
        )
    favorites = api_payload(
        client.get(PREFIX + "/community/characters", headers=bob, params={"scope": "favorites"})
    )
    assert [item["id"] for item in favorites["items"]] == [share["id"]]
    for index in range(3):
        publish(client, alice, role, key=f"new-snapshot-{index}")
    first = api_payload(
        client.get(PREFIX + "/community/characters", headers=bob, params={"limit": 2})
    )
    second = api_payload(
        client.get(
            PREFIX + "/community/characters",
            headers=bob,
            params={"limit": 2, "offset": first["next_offset"]},
        )
    )
    assert len({item["id"] for item in first["items"] + second["items"]}) == 4
    assert second["next_offset"] == 4
    third = api_payload(
        client.get(
            PREFIX + "/community/characters",
            headers=bob,
            params={"limit": 2, "offset": second["next_offset"]},
        )
    )
    remaining = list(third["items"])
    while third["next_offset"] is not None:
        third = api_payload(
            client.get(
                PREFIX + "/community/characters",
                headers=bob,
                params={"limit": 2, "offset": third["next_offset"]},
            )
        )
        remaining.extend(third["items"])
    assert len(remaining) == len(COMMUNITY_CHARACTERS)
    assert {item["id"] for item in remaining} == {
        community_share_id(entry.character.code) for entry in COMMUNITY_CHARACTERS
    }
    assert third["next_offset"] is None
    assert (
        api_payload(
            client.get(PREFIX + "/community/characters", headers=bob, params={"q": "100%"})
        )["items"]
        == []
    )

    async def verify():
        async with client.app.state.database.session_factory() as session:
            assert len((await session.exec(select(CharacterFavorite))).all()) == 1
            assert len((await session.exec(select(CommunityReport))).all()) == 1

    client.portal.call(verify)


def test_parallel_install_creates_one_copy_and_deleted_copy_can_be_added_again(community):
    client, ((alice, _), (bob, _), _) = community
    share = publish(client, alice, create_role(client, alice))
    path = PREFIX + f"/community/characters/{share['id']}/install"
    with ThreadPoolExecutor(max_workers=2) as pool:
        replies = list(pool.map(lambda _: client.post(path, headers=bob), range(2)))
    assert all(reply.status_code == 200 for reply in replies), [reply.text for reply in replies]
    ids = {api_payload(reply)["id"] for reply in replies}
    assert len(ids) == 1
    old = ids.pop()
    assert client.delete(PREFIX + f"/roles/{old}", headers=bob).status_code == 204
    with ThreadPoolExecutor(max_workers=2) as pool:
        replies = list(pool.map(lambda _: client.post(path, headers=bob), range(2)))
    assert all(reply.status_code == 200 for reply in replies), [reply.text for reply in replies]
    assert len({api_payload(reply)["id"] for reply in replies}) == 1
    new = api_payload(replies[0])
    assert new["id"] != old


def test_account_deletion_removes_public_data_but_keeps_other_users_copies(community):
    client, ((alice, alice_id), (bob, bob_id), _) = community
    share = publish(client, alice, create_role(client, alice))
    copy = api_payload(
        client.post(PREFIX + f"/community/characters/{share['id']}/install", headers=bob)
    )

    async def delete_data():
        from bingo.services.community import delete_user_community_data

        async with client.app.state.database.session_factory() as session:
            await delete_user_community_data(session, alice_id)
            await session.commit()
            assert await session.get(CharacterShare, share["id"]) is None
            assert not (await session.exec(select(CharacterInstall))).all()
            role = await session.get(Role, copy["id"])
            assert role.owner_id == bob_id and not role.deleted

    client.portal.call(delete_data)
