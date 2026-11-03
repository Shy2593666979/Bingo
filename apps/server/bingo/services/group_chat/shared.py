"""Shared group ownership, serialization and transactional event helpers."""

import json

from sqlmodel import delete, select, update

from bingo.db.models import Role, User
from bingo.db.models.groups import (
    ChatGroup,
    GroupCall,
    GroupMember,
    GroupMemory,
    GroupMessage,
    GroupRun,
    GroupRunEvent,
)
from bingo.services.exceptions import ServiceError

TERMINAL = {"completed", "cancelled", "failed"}


class StaleRun(Exception):
    pass


def message_json(message, client_message_id=None):
    return {
        key: getattr(message, key)
        for key in (
            "id",
            "group_id",
            "run_id",
            "seq",
            "sender_type",
            "sender_role_id",
            "sender_name",
            "content",
            "status",
        )
    } | {
        "attachment": json.loads(message.attachment_json) if message.attachment_json else None,
        "created_at": message.created_at.isoformat(),
        "client_message_id": client_message_id if message.sender_type == "user" else None,
        "mentions": json.loads(message.mentions_json),
        "mention_all": message.mention_all,
        "mention_targets": json.loads(message.mention_targets_json),
        "reply_to_message_id": message.reply_to_message_id,
        "reply_to": (
            {
                "id": message.reply_to_message_id,
                "sender_name": message.reply_sender_name,
                "content": message.reply_content_preview,
                "created_at": message.reply_created_at.isoformat()
                if message.reply_created_at
                else None,
            }
            if message.reply_to_message_id
            else None
        ),
    }


async def owned(session, group_id, user_id):
    group = await session.get(ChatGroup, group_id)
    if not group or group.owner_id != user_id:
        raise ServiceError(404, "群聊不存在")
    return group


async def valid_roles(session, user_id, ids):
    if len(ids) != len(set(ids)):
        raise ServiceError(422, "请勿重复选择同一位伙伴")
    from bingo.db.repositories import RoleRepository

    user = await session.get(User, user_id)
    roles = []
    for identifier in ids:
        role = await session.get(Role, identifier)
        if not user or not await RoleRepository(session).can_access(user, role):
            raise ServiceError(404, "所选伙伴不存在或不属于你")
        roles.append(role)
    return roles


async def event(session, run, kind, **payload):
    seq = (
        await session.exec(
            update(GroupRun)
            .where(GroupRun.id == run.id)
            .values(next_event_seq=GroupRun.next_event_seq + 1)
            .returning(GroupRun.next_event_seq)
        )
    ).one()[0]
    data = {"type": kind, "run_id": run.id, "group_id": run.group_id, "event_seq": seq, **payload}
    session.add(
        GroupRunEvent(run_id=run.id, event_seq=seq, event_json=json.dumps(data, ensure_ascii=False))
    )
    return data


async def delete_group_data(session, group_id):
    runs = select(GroupRun.id).where(GroupRun.group_id == group_id)
    await session.exec(delete(GroupRunEvent).where(GroupRunEvent.run_id.in_(runs)))
    for model in (GroupMessage, GroupMemory, GroupRun, GroupMember, GroupCall):
        await session.exec(delete(model).where(model.group_id == group_id))


async def delete_user_groups(session, user_id):
    ids = (await session.exec(select(ChatGroup.id).where(ChatGroup.owner_id == user_id))).all()
    for group_id in ids:
        await delete_group_data(session, group_id)
    await session.exec(delete(ChatGroup).where(ChatGroup.owner_id == user_id))
