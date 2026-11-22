import json
from types import SimpleNamespace

from bingo.services.group_chat.turn_state import pending_handoffs


def message(sender, targets=(), *, identifier="message", all_members=False):
    return SimpleNamespace(
        sender_role_id=sender,
        id=identifier,
        content="请接着说说你的看法",
        mention_targets_json=json.dumps(list(targets)),
        mention_all=all_members,
    )


def test_handoff_is_consumed_by_target_and_can_be_requested_again():
    invite = message("a", [{"type": "role", "id": "b"}])
    pending, _ = pending_handoffs([invite], {"a": {}, "b": {}}, "human")
    assert pending[0]["to"] == "b"
    pending, _ = pending_handoffs([invite, message("b")], {"a": {}, "b": {}}, "human")
    assert pending == []
    pending, _ = pending_handoffs([invite, message("b"), invite], {"a": {}, "b": {}}, "human")
    assert pending[0]["to"] == "b"


def test_user_question_and_broadcast_have_distinct_targets():
    pending, waiting = pending_handoffs(
        [message("a", [{"type": "user", "id": "human"}])],
        {"a": {}, "b": {}},
        "human",
    )
    assert pending == [] and waiting["message_id"] == "message"
    pending, waiting = pending_handoffs(
        [message("a", all_members=True)], {"a": {}, "b": {}, "c": {}}, "human"
    )
    assert {p["to"] for p in pending} == {"b", "c"}
    assert waiting is None


def test_removed_or_self_addressed_members_are_not_pending():
    pending, _ = pending_handoffs(
        [message("a", [{"type": "role", "id": "a"}, {"type": "role", "id": "gone"}])],
        {"a": {}},
        "human",
    )
    assert pending == []
