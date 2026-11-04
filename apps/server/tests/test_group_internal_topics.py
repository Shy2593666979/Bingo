import json

from sqlmodel import select

from bingo.db.models.groups import ChatGroup, GroupMessage, GroupRun, GroupRunEvent
from tests.api_support import api_payload
from tests.test_group_chat import P, create, group_app  # noqa: F401


def test_internal_topics_are_hidden_without_deleting_real_history(group_app):  # noqa: F811
    client, ((headers, _), _), roles, _ = group_app
    group = create(client, headers, roles[:2])
    phrase = "如果现在有值得聊的话题，和大家自然地聊一会儿；没有就安静陪伴。"

    async def seed():
        async with client.app.state.database.session_factory() as session:
            run = GroupRun(
                group_id=group["id"],
                client_message_id="proactive-legacy",
                request_json="{}",
                version=1,
                status="completed",
                next_event_seq=1,
            )
            visible = GroupMessage(
                group_id=group["id"],
                run_id=run.id,
                seq=1,
                sender_type="user",
                sender_name="我",
                content=phrase,
            )
            call = GroupMessage(
                group_id=group["id"],
                run_id=run.id,
                seq=2,
                sender_type="system",
                sender_name="群聊电话",
                content="群聊通话 · 00:10",
            )
            internal = GroupMessage(
                group_id=group["id"],
                run_id=run.id,
                seq=3,
                sender_type="system",
                sender_name="群话题",
                content=phrase,
            )
            session.add_all([run, visible, call, internal])
            session.add(
                GroupRunEvent(
                    run_id=run.id,
                    event_seq=1,
                    event_json=json.dumps(
                        {
                            "type": "message_saved",
                            "event_seq": 1,
                            "message": {
                                "sender_type": "system",
                                "sender_name": "群话题",
                                "content": phrase,
                            },
                        }
                    ),
                )
            )
            current = await session.get(ChatGroup, group["id"])
            current.next_message_seq = 3
            await session.commit()
            return run.id, visible.id, internal.id

    run_id, visible_id, hidden_id = client.portal.call(seed)
    base = P + f"/groups/{group['id']}"
    rows = api_payload(client.get(base + "/messages", headers=headers))
    assert [row["seq"] for row in rows] == [1, 2]
    assert rows[0]["content"] == phrase
    assert api_payload(client.get(base, headers=headers))["last_message"]["seq"] == 2
    context = api_payload(client.get(base + f"/messages/{visible_id}/context", headers=headers))
    assert [row["seq"] for row in context] == [1, 2]
    assert client.get(base + f"/messages/{hidden_id}/context", headers=headers).status_code == 404
    events = api_payload(client.get(base + f"/runs/{run_id}/events", headers=headers))
    assert events["events"] == [] and events["last_event_seq"] == 1

    async def retained():
        async with client.app.state.database.session_factory() as session:
            assert (
                len(
                    (
                        await session.exec(
                            select(GroupMessage).where(GroupMessage.group_id == group["id"])
                        )
                    ).all()
                )
                == 3
            )

    client.portal.call(retained)
