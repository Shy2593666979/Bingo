import asyncio
import re

from sqlmodel import select

from bingo.agent.model_client import ModelTextDelta
from bingo.db.models.groups import GroupMessage
from tests.api_support import api_payload
from tests.test_group_chat import P, create, group_app, wait  # noqa: F401
from tests.test_group_v2 import IndependentModel, v2  # noqa: F401


class RacingModel(IndependentModel):
    def __init__(self, ids):
        super().__init__()
        self.started = {id: asyncio.Event() for id in ids}
        self.gates = {id: asyncio.Event() for id in ids}
        self.closed = set()

    async def stream(self, messages, tools=None):
        role_id = re.search(r"你的Role ID=([^；]+)", messages[0].content).group(1)
        self.started[role_id].set()
        try:
            await self.gates[role_id].wait()
            yield ModelTextDelta("回应：" + role_id)
        finally:
            self.closed.add(role_id)


def prepare(request, count=8):
    client, ((headers, _), _), roles, _ = request.getfixturevalue("v2")
    roles = roles[:count]
    group = create(client, headers, roles)
    api_payload(
        client.patch(P + f"/groups/{group['id']}", headers=headers, json={"allow_ai_to_ai": False})
    )
    model = RacingModel([r["id"] for r in roles])
    client.app.state.services.group_chat.model = model
    run = api_payload(
        client.post(
            P + f"/groups/{group['id']}/chat",
            headers=headers,
            json={
                "content": "@全部搭子 一起说说吧",
                "mentionAll": True,
                "clientMessageId": "concurrent-all-test",
            },
        )
    )
    return client, headers, roles, group, model, run


def test_all_eight_streams_start_together_and_fastest_token_is_first(request):
    client, headers, roles, group, model, _ = prepare(request)

    async def all_started():
        await asyncio.wait_for(asyncio.gather(*[e.wait() for e in model.started.values()]), 8)

    client.portal.call(all_started)
    # No ordered empty bubbles were persisted while all eight providers are waiting.
    history = api_payload(client.get(P + f"/groups/{group['id']}/messages", headers=headers))
    assert len(history) == 1
    assert history[0]["sender_type"] == "user"

    async def release_and_wait(role_id, count):
        model.gates[role_id].set()
        async with asyncio.timeout(5):
            while True:
                async with client.app.state.database.session_factory() as session:
                    ai = (
                        await session.exec(
                            select(GroupMessage).where(
                                GroupMessage.group_id == group["id"],
                                GroupMessage.sender_type == "assistant",
                                GroupMessage.status == "completed",
                            )
                        )
                    ).all()
                if len(ai) == count:
                    return
                await asyncio.sleep(0.02)

    order = [r["id"] for r in reversed(roles)]
    for count, role_id in enumerate(order, 1):
        client.portal.call(release_and_wait, role_id, count)
    wait(client)
    history = api_payload(client.get(P + f"/groups/{group['id']}/messages", headers=headers))
    assert [m["sender_role_id"] for m in history[1:]] == order
    assert [m["seq"] for m in history] == list(range(1, 10))
    assert model.closed == set(order)


def test_stop_cancels_every_parallel_request_without_late_bubbles(request):
    client, headers, roles, group, model, run = prepare(request)

    async def started():
        await asyncio.wait_for(asyncio.gather(*[e.wait() for e in model.started.values()]), 8)

    client.portal.call(started)
    response = client.post(
        P + f"/groups/{group['id']}/runs/{run['run_id']}/cancel", headers=headers
    )
    assert response.status_code == 204
    wait(client)
    assert model.closed == {r["id"] for r in roles}
    history = api_payload(client.get(P + f"/groups/{group['id']}/messages", headers=headers))
    assert len(history) == 1


def test_all_silent_casual_human_message_still_gets_one_real_reply(request):
    client, ((headers, _), _), roles, model = request.getfixturevalue("v2")
    model.silent = True
    group = create(client, headers, roles[:3])
    api_payload(
        client.post(
            P + f"/groups/{group['id']}/chat",
            headers=headers,
            json={"content": "今天好累啊", "clientMessageId": "casual-host-test"},
        )
    )
    wait(client)
    history = api_payload(client.get(P + f"/groups/{group['id']}/messages", headers=headers))
    ai = [m for m in history if m["sender_type"] == "assistant"]
    assert len(ai) == 1
    assert ai[0]["status"] == "completed"
    assert len(model.generations) == 1
