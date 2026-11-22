"""Conversation obligations derived from persisted messages, never invented summaries."""

import json


def pending_handoffs(replies, members, user_id):
    pending = {}
    waiting_for_user = None
    for message in replies:
        pending.pop(message.sender_role_id, None)
        waiting_for_user = None
        targets = json.loads(message.mention_targets_json or "[]")
        if message.mention_all:
            targets += [{"type": "role", "id": i} for i in members]
        for target in targets:
            identifier = target.get("id")
            if target.get("type") == "role" and identifier in members:
                if identifier != message.sender_role_id:
                    pending[identifier] = {
                        "from": message.sender_role_id,
                        "to": identifier,
                        "message_id": message.id,
                        "text": message.content[:800],
                    }
            elif target.get("type") == "user" and identifier == user_id:
                waiting_for_user = {"message_id": message.id, "text": message.content[:800]}
    return list(pending.values()), waiting_for_user
