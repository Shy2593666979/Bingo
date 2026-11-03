"""Paced message allocation, model streaming and persisted message events."""

import asyncio
import json
from contextlib import suppress

from sqlmodel import select, update

from bingo.agent.handoffs import (
    agent_broadcast_targets,
    ensure_human_mention,
    normalize_agent_addresses,
)
from bingo.agent.model_client import ModelMessage, ModelTextDelta
from bingo.agent.social_runtime import ReplyHeader, ReplyIntent
from bingo.db.models import Role, User
from bingo.db.models.groups import (
    ChatGroup,
    GroupMember,
    GroupMessage,
    GroupRun,
)
from bingo.services.exceptions import ServiceError
from bingo.utils.assistant_text import clean_assistant_text
from bingo.utils.stickers.content import preview_content

from .shared import (
    StaleRun,
    event,
    message_json,
)


class GroupSpeaker:
    def __init__(self, service):
        self.service = service

    async def speaker_failed(self, run_id, message_id, role_id):
        async with self.service.database.session_factory() as session:
            run = await session.get(GroupRun, run_id)
            await self.service.runs.guard(session, run)
            message = await session.get(GroupMessage, message_id)
            if message and message.status == "streaming":
                message.status = "failed"
                await event(session, run, "message_end", message=message_json(message))
                await event(
                    session,
                    run,
                    "speaker_error",
                    role_id=role_id,
                    reason="这位搭子暂时未能回复，其他搭子会继续",
                )
            await session.commit()

    async def open_response(self, run_id, group_id, role_id, name, intent, content):
        gate = self.service.publish_locks.setdefault(group_id, asyncio.Lock())
        async with gate:
            await self.service.runs.check_run(run_id)
            now = asyncio.get_running_loop().time
            delay = self.service.message_interval_seconds - (
                now() - self.service.last_published_at.get(group_id, float("-inf"))
            )
            if delay > 0:
                await asyncio.sleep(delay)
            message_id = await self.allocate_response(
                run_id, group_id, role_id, name, intent, content
            )
            if message_id:
                self.service.last_published_at[group_id] = now()
            return message_id

    async def allocate_response(self, run_id, group_id, role_id, name, intent, content):
        async with self.service.lock(group_id), self.service.database.session_factory() as session:
            run = await session.get(GroupRun, run_id)
            await self.service.runs.guard(session, run)
            if run.emitted_ai_messages >= run.max_ai_messages:
                return None
            # Count allocated visible messages, including interrupted/failed cards.
            run.emitted_ai_messages += 1
            quote = await self.service.context.quote(session, group_id, intent.reply_to_message_id)
            seq = (
                await session.exec(
                    update(ChatGroup)
                    .where(ChatGroup.id == group_id)
                    .values(next_message_seq=ChatGroup.next_message_seq + 1)
                    .returning(ChatGroup.next_message_seq)
                )
            ).one()[0]
            message = GroupMessage(
                group_id=group_id,
                run_id=run_id,
                seq=seq,
                sender_type="assistant",
                sender_role_id=role_id,
                sender_name=name,
                status="streaming",
                content=content,
                reply_to_message_id=quote.id if quote else None,
                reply_sender_name=quote.sender_name if quote else None,
                reply_content_preview=preview_content(quote.content)[:180] if quote else None,
                reply_created_at=quote.created_at if quote else None,
                mention_targets_json=json.dumps(intent.mention_targets),
                mention_all=intent.mention_all,
                mentions_json=json.dumps(
                    [t["id"] for t in intent.mention_targets if t["type"] == "role"]
                ),
            )
            session.add(message)
            await event(session, run, "message_start", message=message_json(message))
            await session.commit()
            return message.id

    async def speak(self, run_id, role_id, intent=None, direct=False, trigger_id=None):
        async with self.service.database.session_factory() as session:
            run = await session.get(GroupRun, run_id)
            group_id = run.group_id
        context = await self.service.context.context(group_id, role_id)
        if context is None:
            return False
        name, messages = context
        intent = await self.service.scheduling.validate_intent(
            run_id, role_id, intent or ReplyIntent(action="speak")
        )
        if intent.desired_delay_ms:
            await asyncio.sleep(intent.desired_delay_ms / 1000)
        messages.insert(
            1,
            ModelMessage(
                role="system",
                content="本次已确认的引用与提及："
                + json.dumps(intent.model_dump(), ensure_ascii=False)
                + "。只生成你自己的一条简短回复。若使用提及，在正文使用对应成员的@名字，"
                "不输出JSON、ID或角色名标签。没有指定提及时不要擅自写@名字。",
            ),
        )
        if direct:
            messages[1] = ModelMessage(
                role="system",
                content=(
                    "这轮已确定由你回应指定的触发消息，直接开始，不再做是否发言的判断。"
                    "同一次输出的第一行仅给一个简短JSON元数据对象："
                    '{"replyToMessageId":null,"mentionTargets":[],"mentionAll":false}。随后换行输出回复正文。'
                    "不要输出代码围栏、思考过程、action或延迟。"
                    "引用可选，只能用上下文中同群已完成消息的真实messageId；"
                    '提及可选，格式为{"type":"role或user","id":"真实成员ID"}，'
                    "真人用user ID，搭子用Role ID；若提及，在正文写对应的@名字。"
                    "正文出现@某位成员时，首行mentionTargets必须包含该成员真实ID，不能只写名字。"
                    "明确点名请成员接话时，必须使用@名字并填写mentionTargets；"
                    "例如应写‘@暖暖先接吧’，不能只写‘暖暖先接吧’。普通谈到某人不需要@。"
                    "你也可以@全部搭子或@全体搭子，此时mentionAll=true，代表除你自己以外的所有AI搭子；"
                    "不要把你自己放进提及目标，也不要代替真人发言。"
                    "不需要引用、提及时第一行就用上面的空元数据。正文只说你自己的话，简短自然。"
                    "普通问候和眼前的闲聊优先使用空元数据，不要每句话都引用最新用户消息或@真人。"
                    "确实需要回指较早消息、点名另一位搭子或单独询问真人时再使用引用或提及。"
                    f"本次触发消息的messageId是{trigger_id}，优先回应这条消息。"
                    "如果它来自另一位搭子，请接对方的话，不要跳回旧话题。"
                    "本次已经确认的引用和提及必须保留："
                    + json.dumps(intent.model_dump(), ensure_ascii=False)
                    + "。若已有指定role提及，这是用户明确要求你去@对方："
                    "正文必须写@对方的实际名字并提出转达请求，不要替对方回答，也不要只说稍后会叫他。"
                ),
            )
        async with self.service.lock(group_id), self.service.database.session_factory() as session:
            run = await session.get(GroupRun, run_id)
            await self.service.runs.guard(session, run)
            if (
                run.emitted_ai_messages >= run.max_ai_messages
                or run.generation_calls >= self.service.settings.max_generation_calls_per_run
            ):
                return False
            run.generation_calls += 1
            await event(session, run, "speaker_start", role_id=role_id, name=name)
            await session.commit()
        message_id = None
        content = ""
        stream = self.service.model.stream(messages).__aiter__()
        next_chunk = None
        header = ReplyHeader() if direct else None
        metadata_applied = False
        try:
            async with asyncio.timeout(self.service.settings.generation_timeout_seconds):
                saved = ""
                while len(content) < 2000:
                    if next_chunk is None:
                        next_chunk = asyncio.create_task(anext(stream))
                    ready, _ = await asyncio.wait({next_chunk}, timeout=0.25)
                    if not ready:
                        if content != saved:
                            await self.text(run_id, message_id, content)
                            saved = content
                        else:
                            await self.service.runs.check_run(run_id)
                        continue
                    try:
                        delta = next_chunk.result()
                    except StopAsyncIteration:
                        next_chunk = None
                        break
                    next_chunk = None
                    if isinstance(delta, ModelTextDelta):
                        chunk = header.feed(delta.content) if header else delta.content
                        if not chunk:
                            continue
                        if header and not metadata_applied:
                            if header.intent:
                                confirmed_intent = intent
                                try:
                                    intent = await self.service.scheduling.validate_intent(
                                        run_id,
                                        role_id,
                                        header.intent.model_copy(
                                            update={
                                                "reply_to_message_id": intent.reply_to_message_id
                                                or header.intent.reply_to_message_id,
                                                "mention_targets": list(
                                                    {
                                                        (t["type"], t["id"]): t
                                                        for t in [
                                                            *intent.mention_targets,
                                                            *header.intent.mention_targets,
                                                        ]
                                                    }.values()
                                                ),
                                                "mention_all": intent.mention_all
                                                or header.intent.mention_all,
                                            }
                                        ),
                                    )
                                except ServiceError:
                                    intent = await self.service.scheduling.validate_intent(
                                        run_id, role_id, confirmed_intent
                                    )
                            metadata_applied = True
                        content = (content + chunk)[:2000]
                        if not content:
                            continue
                        if message_id is None:
                            message_id = await self.open_response(
                                run_id, group_id, role_id, name, intent, content
                            )
                            if message_id is None:
                                return False
                        if len(content) - len(saved) >= 32 or not saved:
                            await self.text(run_id, message_id, content)
                            saved = content
                content = clean_assistant_text(content).strip()
                if not content:
                    raise ValueError("Empty model response")
                await self.text(run_id, message_id, content, done=True)
                return True
        except (StaleRun, asyncio.CancelledError):
            raise
        except Exception:
            if message_id is None:
                message_id = await self.open_response(run_id, group_id, role_id, name, intent, "")
            if message_id:
                await self.speaker_failed(run_id, message_id, role_id)
            return False
        finally:
            if next_chunk and not next_chunk.done():
                next_chunk.cancel()
            if next_chunk:
                await asyncio.gather(next_chunk, return_exceptions=True)
            if hasattr(stream, "aclose"):
                with suppress(Exception):
                    await stream.aclose()

    async def text(self, run_id, message_id, content, done=False):
        async with self.service.database.session_factory() as session:
            run = await session.get(GroupRun, run_id)
            if run is None:
                raise StaleRun()
            await self.service.runs.guard(session, run)
            message = await session.get(GroupMessage, message_id)
            member = await session.get(GroupMember, (run.group_id, message.sender_role_id))
            role = await session.get(Role, message.sender_role_id)
            if not member or not member.active or not role or role.deleted or not role.enabled:
                message.status = "interrupted"
                await event(session, run, "message_end", message=message_json(message))
                await session.commit()
                raise StaleRun()
            if message.status in {"completed", "failed", "interrupted", "cancelled"}:
                return
            if done:
                await self.service.context.quote(session, run.group_id, message.reply_to_message_id)
                group = await session.get(ChatGroup, run.group_id)
                if group.mentions_enabled:
                    members = (
                        await session.exec(
                            select(Role)
                            .join(GroupMember, GroupMember.role_id == Role.id)
                            .where(
                                GroupMember.group_id == group.id,
                                GroupMember.active.is_(True),
                                Role.enabled.is_(True),
                                Role.deleted.is_(False),
                            )
                        )
                    ).all()
                    human = await session.get(User, group.owner_id)
                    people = [("role", r.id, r.nickname) for r in members]
                    if human and human.username:
                        people.append(("user", human.id, human.username))
                    content, targets = normalize_agent_addresses(
                        content, people, message.sender_role_id
                    )
                    broadcast, _ = agent_broadcast_targets(content, people, message.sender_role_id)
                    if message.mention_all and not broadcast:
                        content = "@全部搭子 " + content
                    message.mention_all = message.mention_all or broadcast
                    if message.mention_all:
                        _, current_targets = agent_broadcast_targets(
                            "@全部搭子", people, message.sender_role_id
                        )
                        targets.extend(current_targets)
                    allowed = {
                        (kind, identifier)
                        for kind, identifier, _ in people
                        if kind != "role" or identifier != message.sender_role_id
                    }
                    allowed.add(("user", group.owner_id))
                    merged = {
                        (t["type"], t["id"]): t
                        for t in [*json.loads(message.mention_targets_json), *targets]
                        if (t["type"], t["id"]) in allowed
                    }
                    message.mention_targets_json = json.dumps(
                        list(merged.values()), ensure_ascii=False
                    )
                    content = ensure_human_mention(
                        content,
                        list(merged.values()),
                        group.owner_id,
                        human.username or "我" if human else "我",
                    )
                    message.mentions_json = json.dumps(
                        [t["id"] for t in merged.values() if t["type"] == "role"]
                    )
            message.content = content
            message.status = "completed" if done else "streaming"
            await event(
                session,
                run,
                "message_end" if done else "message_delta",
                message=message_json(message),
            )
            await session.commit()
