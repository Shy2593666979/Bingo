import json
import re

import pytest

from bingo.agent.handoffs import initial_recipients, requested_handoffs
from bingo.agent.model_client import ModelTextDelta
from tests.api_support import api_payload
from tests.test_group_chat import P, create, group_app, wait  # noqa: F401
from tests.test_group_v2 import v2  # noqa: F401


class HandoffModel:
    def __init__(self, source, target, human=None):
        self.source, self.target, self.human = source, target, human
        self.generations = []
        self.bad_optional_header = False

    async def complete(self, messages):
        return '{"action":"silent"}' if '"action"' in messages[-1].content else "[]"

    async def stream(self, messages, tools=None):
        role = re.search(r"你的Role ID=([^；]+)", messages[0].content).group(1)
        self.generations.append((role, messages))
        targets = []
        if self.bad_optional_header:
            targets = [{"type": "user", "id": "not-the-group-human"}]
        elif role == self.source:
            targets = [{"type": "role", "id": self.target}]
        if "第一行" in messages[1].content:
            yield ModelTextDelta(
                json.dumps({"replyToMessageId": None, "mentionTargets": targets}) + "\n"
            )
        yield ModelTextDelta(
            "@暖暖 过来跟我说句话吧。"
            if role == self.source
            else "听到甜甜叫我啦，我在！今天想聊点什么？"
        )


def setup(request, auto=False):
    client, ((headers, uid), _), roles, _ = request.getfixturevalue("v2")
    sweet = next(r for r in roles if r["nickname"] == "甜甜")
    warm = next(r for r in roles if r["nickname"] == "暖暖")
    group = create(client, headers, [sweet, warm])
    api_payload(
        client.patch(P + f"/groups/{group['id']}", headers=headers, json={"allow_ai_to_ai": auto})
    )
    model = HandoffModel(sweet["id"], warm["id"], uid)
    client.app.state.services.group_chat.model = model
    return client, headers, group, sweet, warm, model


@pytest.mark.parametrize("selected_target", [False, True])
def test_human_delegation_reaches_the_named_recipient_even_with_auto_chat_off(
    request, selected_target
):
    client, headers, group, sweet, warm, model = setup(request)
    payload = {
        "content": "让甜甜@暖暖给我说句话",
        "clientMessageId": "delegation-once",
        "mentions": [warm["id"]] if selected_target else [],
    }
    first = api_payload(
        client.post(P + f"/groups/{group['id']}/chat", headers=headers, json=payload)
    )
    wait(client)
    rows = api_payload(client.get(P + f"/groups/{group['id']}/messages", headers=headers))
    ai = [m for m in rows if m["sender_type"] == "assistant"]
    assert [m["sender_role_id"] for m in ai] == [sweet["id"], warm["id"]]
    assert ai[0]["mention_targets"] == [{"type": "role", "id": warm["id"]}]
    assert ai[1]["reply_to_message_id"] == ai[0]["id"]
    assert ai[1]["reply_to"]["sender_name"] == "甜甜"
    assert "本次触发消息的messageId是" + ai[0]["id"] in model.generations[1][1][1].content
    repeat = api_payload(
        client.post(P + f"/groups/{group['id']}/chat", headers=headers, json=payload)
    )
    assert repeat["run_id"] == first["run_id"]
    assert len(model.generations) == 2
    # A second explicit human command is not swallowed by the spontaneous pair cooldown.
    payload["clientMessageId"] = "delegation-twice"
    api_payload(client.post(P + f"/groups/{group['id']}/chat", headers=headers, json=payload))
    wait(client)
    assert len(model.generations) == 4


def test_bad_optional_metadata_cannot_erase_user_requested_handoff(request):
    client, headers, group, sweet, warm, model = setup(request)
    model.bad_optional_header = True
    api_payload(
        client.post(
            P + f"/groups/{group['id']}/chat",
            headers=headers,
            json={
                "content": "@甜甜 帮我叫一下暖暖说句话",
                "clientMessageId": "bad-metadata-handoff",
                "mentions": [sweet["id"]],
            },
        )
    )
    wait(client)
    rows = api_payload(client.get(P + f"/groups/{group['id']}/messages", headers=headers))
    assert [m["sender_role_id"] for m in rows if m["sender_type"] == "assistant"] == [
        sweet["id"],
        warm["id"],
    ]
    assert rows[1]["mention_targets"] == [{"type": "role", "id": warm["id"]}]


def test_ai_role_mention_can_trigger_independent_followup_with_auto_chat_on(request):
    client, headers, group, sweet, warm, model = setup(request, auto=True)

    # No human delegation in this root. An AI's own @ is assessed independently.
    async def complete(messages):
        return '{"action":"speak"}' if '"action"' in messages[-1].content else "[]"

    model.complete = complete
    api_payload(
        client.post(
            P + f"/groups/{group['id']}/chat",
            headers=headers,
            json={
                "content": "@甜甜 想聊点什么？",
                "mentions": [sweet["id"]],
                "clientMessageId": "spontaneous-role-at",
            },
        )
    )
    wait(client)
    assert [id for id, _ in model.generations][:2] == [sweet["id"], warm["id"]]


def test_delegation_parser_ignores_names_only_negation_and_ambiguous_names():
    people = {"sweet": "甜甜", "warm": "暖暖"}
    assert requested_handoffs("我喜欢甜甜和暖暖", people) == {}
    assert requested_handoffs("@甜甜 @暖暖 你们都在干嘛", people) == {}
    assert requested_handoffs("不要让甜甜@暖暖", people) == {}
    assert requested_handoffs("别让甜甜@暖暖", people) == {}
    assert requested_handoffs("让甜甜@暖暖说句话", people) == {"sweet": ["warm"]}
    assert requested_handoffs("让甜甜@暖暖", {**people, "other": "甜甜"}) == {}
    assert initial_recipients(["warm"], {"sweet": ["warm"]}) == ["sweet"]
    assert initial_recipients(["sweet", "warm"], {"sweet": ["warm"]}, all_targets=True) == [
        "sweet",
        "warm",
    ]
