"""Group management and the shared lifecycle of group-chat components.

Components deliberately share this aggregate's locks, task registry and model.
They do not create independent sessions spanning model calls or copy run state.
"""

import asyncio
import json
from contextlib import suppress
from datetime import timedelta

from sqlmodel import delete, select, update

from bingo.agent.handoffs import (
    initial_recipients,
    requested_handoffs,
)
from bingo.agent.social_runtime import SocialAgentRuntime
from bingo.config import SocialRuntimeSettings
from bingo.db.models import Role, User
from bingo.db.models.groups import (
    MAX_GROUP_AI_MEMBERS,
    ChatGroup,
    GroupCall,
    GroupMember,
    GroupMemory,
    GroupMessage,
    GroupRun,
    GroupRunEvent,
)
from bingo.db.models.welcome import WelcomeJob
from bingo.db.time import beijing_now
from bingo.schemas.group_chat import GroupCreate, GroupSend
from bingo.services.exceptions import ServiceError
from bingo.services.stickers import normalize_sticker
from bingo.utils.assistant_text import clean_assistant_text, strip_mentions_for_speech
from bingo.utils.stickers.content import parse_sticker, preview_content

from .context import GroupContext
from .memory import GroupMemoryExtractor
from .proactive import GroupProactiveTopics
from .runs import GroupRunCoordinator
from .scheduling import GroupParticipation
from .shared import (
    delete_group_data,
    event,
    message_json,
    owned,
    valid_roles,
)
from .speaking import GroupSpeaker


class GroupChatService:
    def __init__(self, database, model, settings=None):
        self.database = database
        self.model = model
        self.settings = settings or SocialRuntimeSettings()
        self.tasks = {}
        self.locks = {}
        # Model requests race independently; only visible message starts are paced.
        self.message_interval_seconds = 1.5
        self.publish_locks = {}
        self.last_published_at = {}
        self.worker = None
        self.pair_last = {}
        self.calling_groups = set()
        self.runs = GroupRunCoordinator(self)
        self.scheduling = GroupParticipation(self)
        self.context = GroupContext(self)
        self.speaking = GroupSpeaker(self)
        self.memory = GroupMemoryExtractor(self)
        self.proactive = GroupProactiveTopics(self)
        self.social = SocialAgentRuntime(
            settings=self.settings,
            complete=lambda messages: self.model.complete(messages),
            claim_decision=self.scheduling.claim_decision,
            context_for_run=self.context.context_for_run,
            validate_intent=self.scheduling.validate_intent,
        )

    def lock(self, group_id):
        return self.locks.setdefault(group_id, asyncio.Lock())

    async def image_source(self, group_id, message_id, user_id):
        from bingo.services.chat import IMAGE_DIRECTORY

        async with self.database.session_factory() as session:
            await owned(session, group_id, user_id)
            message = await session.get(GroupMessage, message_id)
            if not message or message.group_id != group_id or not message.attachment_json:
                raise ServiceError(404, "图片不存在")
            attachment = json.loads(message.attachment_json)
            if attachment.get("type") != "image":
                raise ServiceError(404, "图片不存在")
            path = IMAGE_DIRECTORY / f"{attachment['image_id']}.jpg"
            if not path.is_file():
                raise ServiceError(404, "图片已不可用")
            return path, attachment["mime_type"]

    async def speech_source(self, group_id, message_id, user_id):
        async with self.database.session_factory() as session:
            group = await owned(session, group_id, user_id)
            message = await session.get(GroupMessage, message_id)
            if not message or message.group_id != group_id:
                raise ServiceError(404, "消息不存在")
            if message.sender_type != "assistant" or message.status != "completed":
                raise ServiceError(422, "只能朗读已完成的搭子消息")
            text = clean_assistant_text(message.content).strip()
            if not text or parse_sticker(message.content):
                raise ServiceError(422, "这条消息没有可朗读的文字")
            members = (
                await session.exec(
                    select(Role)
                    .join(GroupMember, GroupMember.role_id == Role.id)
                    .where(
                        GroupMember.group_id == group_id,
                        GroupMember.active.is_(True),
                        Role.enabled.is_(True),
                        Role.deleted.is_(False),
                    )
                )
            ).all()
            names = [member.nickname for member in members]
            if (human := await session.get(User, group.owner_id)) and human.username:
                names.append(human.username)
            text = strip_mentions_for_speech(text, names)
            if not text:
                raise ServiceError(422, "这条消息没有可朗读的文字")
            role = await session.get(Role, message.sender_role_id)
            if not role or role.deleted or role.owner_id not in {None, user_id}:
                raise ServiceError(404, "搭子音色已失效")
            return text, role.voice

    async def start(self, proactive=False):
        # A restart never silently replays model generation or duplicates a user message.
        async with self.database.session_factory() as session:
            runs = (
                await session.exec(
                    select(GroupRun).where(GroupRun.status.in_(["pending", "running"]))
                )
            ).all()
            for run in runs:
                run.status = "failed"
                run.error = "服务已重启，这轮回复已停止，可以继续发消息"
                await session.exec(
                    update(GroupMessage)
                    .where(GroupMessage.run_id == run.id, GroupMessage.status == "streaming")
                    .values(status="interrupted")
                )
                await event(session, run, "run_error", message=run.error)
            await session.commit()
        if proactive:
            self.worker = asyncio.create_task(self.proactive.proactive_loop())

    async def close(self):
        if self.worker:
            self.worker.cancel()
            with suppress(asyncio.CancelledError):
                await self.worker
        tasks = list(self.tasks.values())
        for task in tasks:
            task.cancel()
        await asyncio.gather(*tasks, return_exceptions=True)
        close_model = getattr(self.model, "aclose", None)
        if close_model:
            await close_model()

    async def cancel_user(self, user_id):
        async with self.database.session_factory() as session:
            groups = (
                await session.exec(select(ChatGroup).where(ChatGroup.owner_id == user_id))
            ).all()
        for group in groups:
            await self.cancel(group.id, user_id)

    async def create(self, user, payload: GroupCreate):
        async with self.database.session_factory() as session:
            roles = await valid_roles(session, user.id, payload.role_ids)
            group = ChatGroup(owner_id=user.id, **payload.model_dump(exclude={"role_ids"}))
            session.add(group)
            for role in roles:
                session.add(
                    GroupMember(
                        group_id=group.id,
                        role_id=role.id,
                        name=role.nickname,
                        role_name=role.visible_name,
                        avatar_asset=role.avatar,
                        avatar_data=role.avatar_data,
                    )
                )
            await session.commit()
        return await self.get(group.id, user.id)

    async def get(self, group_id, user_id):
        async with self.database.session_factory() as session:
            group = await owned(session, group_id, user_id)
            members = (
                await session.exec(select(GroupMember).where(GroupMember.group_id == group_id))
            ).all()
            human = await session.get(User, user_id)
            people = []
            for member in members:
                role = await session.get(Role, member.role_id)
                active = member.active and role is not None and not role.deleted and role.enabled
                people.append(
                    {
                        "id": member.role_id,
                        "name": role.nickname if active else member.name,
                        "role_name": role.visible_name if active else member.role_name,
                        "avatar_asset": role.avatar if active else member.avatar_asset,
                        "avatar_data": role.avatar_data if active else member.avatar_data,
                        "active": active,
                    }
                )
            latest = (
                await session.exec(
                    select(GroupMessage)
                    .where(GroupMessage.group_id == group_id)
                    .order_by(GroupMessage.seq.desc())
                    .limit(1)
                )
            ).first()
            unread_rows = (
                await session.exec(
                    select(GroupMessage).where(
                        GroupMessage.group_id == group_id,
                        GroupMessage.seq > group.last_read_seq,
                        GroupMessage.sender_type == "assistant",
                        GroupMessage.status == "completed",
                    )
                )
            ).all()
            unread = len(unread_rows)
            unread_mentions = sum(
                any(
                    t.get("type") == "user" and t.get("id") == user_id
                    for t in json.loads(m.mention_targets_json)
                )
                for m in unread_rows
            )
            active_run = (
                await session.exec(
                    select(GroupRun)
                    .where(
                        GroupRun.group_id == group_id, GroupRun.status.in_(["pending", "running"])
                    )
                    .order_by(GroupRun.version.desc())
                    .limit(1)
                )
            ).first()
            return {
                "id": group.id,
                "last_read_seq": group.last_read_seq,
                "welcome_pending": (
                    await session.exec(
                        select(WelcomeJob.id)
                        .where(
                            WelcomeJob.group_id == group.id,
                            WelcomeJob.status.in_(("queued", "running", "retry")),
                        )
                        .limit(1)
                    )
                ).first()
                is not None,
                "name": group.name,
                "description": group.description,
                "cover": group.cover,
                "members": people,
                "member_count": sum(person["active"] for person in people),
                "allow_ai_to_ai": group.allow_ai_to_ai,
                "mentions_enabled": group.mentions_enabled,
                "proactive_enabled": group.proactive_enabled,
                "muted": group.muted,
                "read_aloud": group.read_aloud,
                "pinned": group.pinned,
                "archived": group.archived,
                "unread_count": unread,
                "unread_mentions": unread_mentions,
                "human": {"id": user_id, "name": human.username or "我"},
                "last_message": message_json(latest) if latest else None,
                "last_activity_at": group.last_activity_at.isoformat(),
                "active_run_id": active_run.id if active_run else None,
            }

    async def list(self, user_id):
        async with self.database.session_factory() as session:
            ids = (
                await session.exec(
                    select(ChatGroup.id)
                    .where(ChatGroup.owner_id == user_id)
                    .order_by(ChatGroup.pinned.desc(), ChatGroup.last_activity_at.desc())
                )
            ).all()
        return [await self.get(identifier, user_id) for identifier in ids]

    async def update(self, group_id, user_id, payload):
        async with self.lock(group_id), self.database.session_factory() as session:
            group = await owned(session, group_id, user_id)
            for key, value in payload.model_dump(exclude_none=True).items():
                if key == "name":
                    value = value.strip()
                    if not value:
                        raise ServiceError(422, "请填写群聊名称")
                setattr(group, key, value)
            if group.archived:
                await self.runs.cancel_in_session(session, group_id)
            await session.commit()
        if payload.archived:
            await self.runs.cancel_tasks(group_id)
        return await self.get(group_id, user_id)

    async def members(self, group_id, user_id, ids=None, remove=None):
        async with self.lock(group_id), self.database.session_factory() as session:
            await owned(session, group_id, user_id)
            current = (
                await session.exec(
                    select(GroupMember).where(
                        GroupMember.group_id == group_id, GroupMember.active.is_(True)
                    )
                )
            ).all()
            if remove:
                member = await session.get(GroupMember, (group_id, remove))
                if member:
                    member.active = False
            else:
                roles = await valid_roles(session, user_id, ids)
                if len({member.role_id for member in current} | set(ids)) > MAX_GROUP_AI_MEMBERS:
                    raise ServiceError(422, "一个群最多 8 位 AI 伙伴")
                for role in roles:
                    member = await session.get(GroupMember, (group_id, role.id))
                    if member:
                        member.active = True
                    else:
                        session.add(
                            GroupMember(
                                group_id=group_id,
                                role_id=role.id,
                                name=role.nickname,
                                role_name=role.visible_name,
                                avatar_asset=role.avatar,
                                avatar_data=role.avatar_data,
                            )
                        )
            await session.commit()
        return await self.get(group_id, user_id)

    async def messages(self, group_id, user_id, before=None, limit=100):
        async with self.database.session_factory() as session:
            await owned(session, group_id, user_id)
            statement = select(GroupMessage).where(GroupMessage.group_id == group_id)
            if before:
                statement = statement.where(GroupMessage.seq < before)
            rows = (
                await session.exec(statement.order_by(GroupMessage.seq.desc()).limit(limit))
            ).all()
            result = []
            for row in reversed(rows):
                command = (
                    await session.get(GroupRun, row.run_id) if row.sender_type == "user" else None
                )
                value = message_json(row, command.client_message_id if command else None)
                if (
                    row.reply_to_message_id
                    and await session.get(GroupMessage, row.reply_to_message_id) is None
                ):
                    value["reply_to"] = {"id": row.reply_to_message_id, "unavailable": True}
                result.append(value)
            return result

    async def read(self, group_id, user_id, seq):
        async with self.database.session_factory() as session:
            group = await owned(session, group_id, user_id)
            group.last_read_seq = max(group.last_read_seq, min(seq, group.next_message_seq))
            await session.commit()

    async def message_context(self, group_id, message_id, user_id):
        async with self.database.session_factory() as session:
            await owned(session, group_id, user_id)
            target = await session.get(GroupMessage, message_id)
            if not target or target.group_id != group_id:
                raise ServiceError(404, "原消息已不可用")
            rows = (
                await session.exec(
                    select(GroupMessage)
                    .where(
                        GroupMessage.group_id == group_id,
                        GroupMessage.seq >= max(1, target.seq - 15),
                        GroupMessage.seq <= target.seq + 15,
                    )
                    .order_by(GroupMessage.seq)
                )
            ).all()
            return [message_json(row) for row in rows]

    async def begin(self, group_id, user, payload: GroupSend, system=False):
        request_json = json.dumps(payload.model_dump(), ensure_ascii=False, sort_keys=True)
        async with self.lock(group_id), self.database.session_factory() as session:
            group = await owned(session, group_id, user.id)
            if group_id in self.calling_groups:
                if system:
                    return {"run_id": None, "status": "skipped"}
                raise ServiceError(409, "群聊电话进行中，请先结束通话")
            payload = payload.model_copy(
                update={"content": await normalize_sticker(session, user.id, payload.content)}
            )
            request_json = json.dumps(payload.model_dump(), ensure_ascii=False, sort_keys=True)
            if system and (
                group.archived
                or not group.proactive_enabled
                or group.muted
                or group.last_activity_at > beijing_now() - timedelta(hours=2)
            ):
                return {"run_id": None, "status": "skipped"}
            duplicate = (
                await session.exec(
                    select(GroupRun).where(
                        GroupRun.group_id == group_id,
                        GroupRun.client_message_id == payload.client_message_id,
                    )
                )
            ).first()
            if duplicate:
                saved_request = GroupSend.model_validate(
                    json.loads(duplicate.request_json)
                ).model_dump()
                if saved_request != payload.model_dump():
                    raise ServiceError(409, "消息标识已使用，请重新发送")
                return {"run_id": duplicate.id, "status": duplicate.status}
            members = (
                await session.exec(
                    select(GroupMember).where(
                        GroupMember.group_id == group_id, GroupMember.active.is_(True)
                    )
                )
            ).all()
            eligible = []
            people = {}
            for member in members:
                role = await session.get(Role, member.role_id)
                if role and role.enabled and not role.deleted:
                    eligible.append(role.id)
                    people[role.id] = role.nickname
            if not eligible:
                raise ServiceError(422, "请先给群聊添加可用的伙伴")
            targets = [t.model_dump() for t in payload.mention_targets]
            role_targets = list(
                dict.fromkeys(
                    [*payload.mentions, *[t["id"] for t in targets if t["type"] == "role"]]
                )
            )
            if any(t["type"] == "user" and t["id"] != user.id for t in targets):
                raise ServiceError(422, "只能提及当前群里的真人")
            if set(role_targets) - set(eligible):
                raise ServiceError(422, "@ 的伙伴不在当前群聊中")
            if (role_targets or targets or payload.mention_all) and not group.mentions_enabled:
                raise ServiceError(422, "这个群已关闭 @ 指定回复")
            if payload.mention_all:
                role_targets = list(eligible)
            targets = [{"type": "role", "id": id} for id in role_targets] + [
                t for t in targets if t["type"] == "user"
            ]
            targets = list({(t["type"], t["id"]): t for t in targets}.values())
            quote = await self.context.quote(session, group_id, payload.reply_to_message_id)
            attachment = None
            if payload.images and payload.location:
                raise ServiceError(422, "图片和位置请分别发送")
            if payload.images:
                from bingo.services.chat import _save_images

                _, image_id, mime = _save_images(payload.images)
                attachment = {"type": "image", "image_id": image_id, "mime_type": mime}
            elif payload.location:
                attachment = {"type": "location", "location": payload.location.model_dump()}
            handoffs = requested_handoffs(payload.content, people) if group.mentions_enabled else {}
            response_targets = initial_recipients(role_targets, handoffs, payload.mention_all)
            request_json = json.dumps(
                {**payload.model_dump(), "_user_handoffs": handoffs},
                ensure_ascii=False,
                sort_keys=True,
            )
            old = await self.runs.cancel_in_session(session, group_id, advance=False)
            version, seq = (
                await session.exec(
                    update(ChatGroup)
                    .where(ChatGroup.id == group_id)
                    .values(
                        active_run_version=ChatGroup.active_run_version + 1,
                        next_message_seq=ChatGroup.next_message_seq + 1,
                        last_activity_at=beijing_now(),
                        archived=False,
                    )
                    .returning(ChatGroup.active_run_version, ChatGroup.next_message_seq)
                )
            ).one()
            run = GroupRun(
                group_id=group_id,
                client_message_id=payload.client_message_id,
                request_json=request_json,
                version=version,
                runtime_mode=self.settings.mode,
                force_targets_json=json.dumps(response_targets),
                max_ai_messages=self.settings.max_ai_messages_per_run,
            )
            message = GroupMessage(
                group_id=group_id,
                run_id=run.id,
                seq=seq,
                sender_type="system" if system else "user",
                sender_name="群话题" if system else user.username or "我",
                content=payload.content,
                attachment_json=json.dumps(attachment, ensure_ascii=False) if attachment else None,
                mentions_json=json.dumps(role_targets),
                mention_targets_json=json.dumps(targets),
                mention_all=payload.mention_all,
                reply_to_message_id=quote.id if quote else None,
                reply_sender_name=quote.sender_name if quote else None,
                reply_content_preview=preview_content(quote.content)[:180] if quote else None,
                reply_created_at=quote.created_at if quote else None,
            )
            session.add(run)
            session.add(message)
            await session.flush()
            await event(
                session,
                run,
                "run_start",
                response_targets=response_targets,
                max_ai_messages=run.max_ai_messages,
            )
            await event(
                session, run, "message_saved", message=message_json(message, run.client_message_id)
            )
            await session.commit()
        for previous in old:
            if task := self.tasks.get(previous.id):
                task.cancel()
        task = asyncio.create_task(self.runs.execute(run.id))
        self.tasks[run.id] = task
        task.add_done_callback(lambda _: self.tasks.pop(run.id, None))
        return {"run_id": run.id, "status": "pending"}

    async def events(self, group_id, run_id, user_id, after=0):
        async with self.database.session_factory() as session:
            await owned(session, group_id, user_id)
            run = await session.get(GroupRun, run_id)
            if not run or run.group_id != group_id:
                raise ServiceError(404, "这轮对话不存在")
            rows = (
                await session.exec(
                    select(GroupRunEvent)
                    .where(GroupRunEvent.run_id == run_id, GroupRunEvent.event_seq > after)
                    .order_by(GroupRunEvent.event_seq)
                    .limit(1000)
                )
            ).all()
            return {
                "events": [json.loads(row.event_json) for row in rows],
                "status": run.status,
                "last_event_seq": rows[-1].event_seq if rows else after,
                "has_more": bool(rows and rows[-1].event_seq < run.next_event_seq),
            }

    async def cancel(self, group_id, user_id, run_id=None):
        async with self.lock(group_id), self.database.session_factory() as session:
            await owned(session, group_id, user_id)
            statement = select(GroupRun).where(
                GroupRun.group_id == group_id, GroupRun.status.in_(["pending", "running"])
            )
            if run_id:
                statement = statement.where(GroupRun.id == run_id)
            runs = (await session.exec(statement)).all()
            for run in runs:
                await session.exec(
                    update(ChatGroup)
                    .where(ChatGroup.id == group_id, ChatGroup.active_run_version == run.version)
                    .values(active_run_version=ChatGroup.active_run_version + 1)
                )
                run.status = "cancelled"
                await session.exec(
                    update(GroupMessage)
                    .where(GroupMessage.run_id == run.id, GroupMessage.status == "streaming")
                    .values(status="interrupted")
                )
                await event(session, run, "run_cancelled")
            await session.commit()
        for run in runs:
            if task := self.tasks.get(run.id):
                task.cancel()

    async def clear(self, group_id, user_id, destroy=False):
        if group_id in self.calling_groups:
            raise ServiceError(409, "请先结束群聊电话")
        await self.cancel(group_id, user_id)
        async with self.lock(group_id), self.database.session_factory() as session:
            group = await owned(session, group_id, user_id)
            if destroy:
                await delete_group_data(session, group_id)
                await session.delete(group)
            else:
                runs = select(GroupRun.id).where(GroupRun.group_id == group_id)
                await session.exec(delete(GroupRunEvent).where(GroupRunEvent.run_id.in_(runs)))
                for model in (GroupMessage, GroupRun, GroupMemory, GroupCall):
                    await session.exec(delete(model).where(model.group_id == group_id))
                group.last_read_seq = group.next_message_seq
            await session.commit()

    async def role_context(self, group_id, role_id):
        """Expose validated persona context to the group-call service."""
        return await self.context.context(group_id, role_id)

    async def suspend_for_call(self, group_id):
        """Invalidate text generation before a call, under the existing group lock."""
        async with self.lock(group_id), self.database.session_factory() as session:
            await self.runs.cancel_in_session(session, group_id)
            await session.commit()
