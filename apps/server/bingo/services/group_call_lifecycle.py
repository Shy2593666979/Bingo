"""Validate group-call participants and persist the call lifecycle.

WebSocket framing and ASR bridging stay in the API adapter. Transactions and
group-chat coordination belong here, including the final system message.
"""

import json
import time

from sqlmodel import select, update

from bingo.db.models import Role
from bingo.db.models.groups import ChatGroup, GroupCall, GroupMember, GroupMessage
from bingo.db.time import beijing_now
from bingo.services.exceptions import ServiceError
from bingo.services.group_chat import owned


async def participants(database, user_id, group_id, role_ids):
    if len(role_ids) != len(set(role_ids)):
        raise ServiceError(422, "请勿重复选择搭子")
    async with database.session_factory() as session:
        group = await owned(session, group_id, user_id)
        if group.archived:
            raise ServiceError(409, "群聊已归档")
        roles = []
        for identifier in role_ids:
            member = await session.get(GroupMember, (group_id, identifier))
            role = await session.get(Role, identifier)
            if not member or not member.active or not role or not role.enabled or role.deleted:
                raise ServiceError(422, "只能邀请当前群内的搭子")
            roles.append(role)
        history = (
            await session.exec(
                select(GroupMessage)
                .where(
                    GroupMessage.group_id == group_id,
                    GroupMessage.status == "completed",
                    GroupMessage.sender_type != "system",
                )
                .order_by(GroupMessage.seq.desc())
                .limit(20)
            )
        ).all()
        return roles, [
            {"name": m.sender_name, "text": m.content[:800], "role_id": m.sender_role_id}
            for m in reversed(history)
        ]


class GroupCallLifecycle:
    def __init__(self, database, group_chat, group_id, user_id, role_ids):
        self.database = database
        self.group_chat = group_chat
        self.call = GroupCall(
            group_id=group_id, user_id=user_id, role_ids_json=json.dumps(role_ids)
        )
        self.started = time.monotonic()

    async def prepare(self, engine):
        self.group_chat.calling_groups.add(self.call.group_id)
        await self.group_chat.suspend_for_call(self.call.group_id)
        for role in engine.roles:
            _, messages = await self.group_chat.role_context(self.call.group_id, role.id)
            engine.role_contexts[role.id] = messages[0].content
        async with self.database.session_factory() as session:
            session.add(self.call)
            await session.commit()

    async def finish(self, status, engine):
        call = self.call
        group_id = call.group_id
        self.group_chat.calling_groups.discard(group_id)
        self.call.status = "disconnected" if status == "connected" else status
        self.call.duration_seconds = int(time.monotonic() - self.started) if engine.started else 0
        self.call.transcript_json = json.dumps(engine.call_log, ensure_ascii=False)
        result_label = "群聊通话" if engine.started else "群聊电话未接通"
        async with self.database.session_factory() as session:
            session.add(self.call)
            group = await session.get(ChatGroup, group_id)
            if group:
                seq = (
                    await session.exec(
                        update(ChatGroup)
                        .where(ChatGroup.id == group_id)
                        .values(
                            next_message_seq=ChatGroup.next_message_seq + 1,
                            last_activity_at=beijing_now(),
                        )
                        .returning(ChatGroup.next_message_seq)
                    )
                ).one()[0]
                session.add(
                    GroupMessage(
                        group_id=group_id,
                        run_id=self.call.id,
                        seq=seq,
                        sender_type="system",
                        sender_name="群聊电话",
                        content=(
                            f"{result_label} · {len(json.loads(self.call.role_ids_json)) + 1}人 · "
                            f"{self.call.duration_seconds // 60:02d}:"
                            f"{self.call.duration_seconds % 60:02d}"
                        ),
                    )
                )
            await session.commit()
