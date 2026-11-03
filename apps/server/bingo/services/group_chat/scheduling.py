"""Participation decisions and bounded multi-character scheduling."""

import asyncio
import json

from sqlmodel import select, update

from bingo.agent.model_client import ModelMessage
from bingo.agent.social_runtime import GroupScheduler, ReplyIntent
from bingo.db.models import Role
from bingo.db.models.groups import (
    ChatGroup,
    GroupMember,
    GroupMessage,
    GroupRun,
)
from bingo.services.exceptions import ServiceError
from bingo.utils.stickers.content import model_sticker_text

from .shared import (
    StaleRun,
)


class GroupParticipation:
    def __init__(self, service):
        self.service = service

    async def claim_decision(self, run_id):
        async with self.service.database.session_factory() as session:
            run = await session.get(GroupRun, run_id)
            if not run:
                raise StaleRun()
            await self.service.runs.guard(session, run)
            claimed = (
                await session.exec(
                    update(GroupRun)
                    .where(
                        GroupRun.id == run_id,
                        GroupRun.decision_calls < self.service.settings.max_decision_calls_per_run,
                    )
                    .values(decision_calls=GroupRun.decision_calls + 1)
                    .returning(GroupRun.id)
                )
            ).first()
            await session.commit()
            return claimed is not None

    async def validate_intent(self, run_id, role_id, intent):
        await self.service.runs.check_run(run_id)
        async with self.service.database.session_factory() as session:
            run = await session.get(GroupRun, run_id)
            group = await session.get(ChatGroup, run.group_id)
            await self.service.context.quote(session, group.id, intent.reply_to_message_id)
            valid = []
            if group.mentions_enabled:
                if intent.mention_all:
                    roles = (
                        await session.exec(
                            select(Role)
                            .join(GroupMember, GroupMember.role_id == Role.id)
                            .where(
                                GroupMember.group_id == group.id,
                                GroupMember.active.is_(True),
                                Role.enabled.is_(True),
                                Role.deleted.is_(False),
                                Role.id != role_id,
                            )
                        )
                    ).all()
                    valid.extend({"type": "role", "id": r.id} for r in roles)
                for target in intent.mention_targets:
                    if target.get("type") == "user" and target.get("id") == group.owner_id:
                        valid.append({"type": "user", "id": group.owner_id})
                    elif target.get("type") == "role":
                        member = await session.get(GroupMember, (group.id, target.get("id")))
                        role = await session.get(Role, target.get("id"))
                        if (
                            not member
                            or not member.active
                            or not role
                            or role.deleted
                            or not role.enabled
                        ):
                            raise ServiceError(422, "无效的提及成员")
                        if role.id != role_id:
                            valid.append({"type": "role", "id": role.id})
                    else:
                        raise ServiceError(422, "无效的提及成员")
            return intent.model_copy(
                update={
                    "mention_all": intent.mention_all and group.mentions_enabled,
                    "mention_targets": list({(t["type"], t["id"]): t for t in valid}.values()),
                }
            )

    async def candidates(self, run_id, trigger_id, followup=False):
        await self.service.runs.check_run(run_id)
        async with self.service.database.session_factory() as session:
            run = await session.get(GroupRun, run_id)
            group = await session.get(ChatGroup, run.group_id)
            trigger = await session.get(GroupMessage, trigger_id)
            if not trigger or (followup and not group.allow_ai_to_ai):
                return []
            members = (
                await session.exec(
                    select(GroupMember).where(
                        GroupMember.group_id == group.id, GroupMember.active.is_(True)
                    )
                )
            ).all()
            recent = (
                await session.exec(
                    select(GroupMessage)
                    .where(GroupMessage.group_id == group.id, GroupMessage.status == "completed")
                    .order_by(GroupMessage.seq.desc())
                    .limit(40)
                )
            ).all()
            mentioned = set(json.loads(trigger.mentions_json)) if group.mentions_enabled else set()
            if trigger.reply_to_message_id:
                quoted = await session.get(GroupMessage, trigger.reply_to_message_id)
                if quoted and quoted.sender_role_id:
                    mentioned.add(quoted.sender_role_id)
            ranked = []
            for member in members:
                if member.role_id == trigger.sender_role_id:
                    continue
                role = await session.get(Role, member.role_id)
                if role and role.enabled and not role.deleted:
                    times = sum(m.sender_role_id == role.id for m in recent)
                    ranked.append((role.id not in mentioned, times, role.id))
            ranked.sort()
            limit = (
                min(2, self.service.settings.decision_candidate_limit)
                if followup
                else self.service.settings.decision_candidate_limit
            )
            addressed = [row[2] for row in ranked if row[2] in mentioned]
            if not followup:
                return [row[2] for row in ranked[:limit]]
            return addressed + [row[2] for row in ranked if row[2] not in mentioned][:limit]

    async def independent(self, run_id):
        scheduler = GroupScheduler()
        depths = {}
        async with self.service.database.session_factory() as session:
            run = await session.get(GroupRun, run_id)
            required = json.loads(run.force_targets_json)
            handoffs = json.loads(run.request_json).get("_user_handoffs", {})
            root = (
                await session.exec(
                    select(GroupMessage)
                    .where(
                        GroupMessage.run_id == run_id,
                        GroupMessage.sender_type.in_(["user", "system"]),
                    )
                    .order_by(GroupMessage.seq)
                )
            ).first()
        if root is None:
            raise StaleRun()

        async def speak(role_id, intent, trigger, direct=False, delegated=False):
            if intent is None:
                return
            if role_id in handoffs and (trigger.sender_type == "user" or delegated):
                targets = intent.mention_targets + [
                    {"type": "role", "id": target} for target in handoffs[role_id]
                ]
                intent = intent.model_copy(
                    update={
                        "mention_targets": list({(t["type"], t["id"]): t for t in targets}.values())
                    }
                )
            depth = depths.get(trigger.id, 0) + (trigger.sender_type == "assistant")
            if depth > self.service.settings.max_thread_replies:
                return
            pair = None
            if trigger.sender_role_id:
                pair = (trigger.group_id, *sorted([trigger.sender_role_id, role_id]))
                elapsed = asyncio.get_running_loop().time() - self.service.pair_last.get(pair, 0)
                if not delegated and elapsed < self.service.settings.pair_cooldown_seconds:
                    return
            try:
                success = await self.service.speaking.speak(
                    run_id, role_id, intent, direct=direct, trigger_id=trigger.id
                )
            except StaleRun:
                raise
            except Exception:
                return
            if success:
                async with self.service.database.session_factory() as session:
                    message = (
                        await session.exec(
                            select(GroupMessage)
                            .where(
                                GroupMessage.run_id == run_id,
                                GroupMessage.sender_role_id == role_id,
                                GroupMessage.status == "completed",
                            )
                            .order_by(GroupMessage.seq.desc())
                        )
                    ).first()
                scheduler.published.append(message.id)
                depths[message.id] = depth
                if pair:
                    self.service.pair_last[pair] = asyncio.get_running_loop().time()

        # Each role proceeds immediately after its own decision; no all-decisions barrier.
        initial = required or await self.candidates(run_id, root.id)
        attempted = set()

        async def reply(role_id):
            scheduler.first_assessment(root.id, role_id)
            direct = bool(required) or (root.sender_type == "user" and role_id == initial[0])
            intent = (
                ReplyIntent(action="speak")
                if direct
                else await self.service.social.decide(run_id, role_id, trigger_id=root.id)
            )
            if intent is not None:
                attempted.add(role_id)
                await speak(role_id, intent, root, direct=direct)

        tasks = [asyncio.create_task(reply(role_id)) for role_id in initial]
        try:
            await asyncio.gather(*tasks)
        finally:
            # A superseded/paused run must not leave sibling model requests behind.
            for task in tasks:
                if not task.done():
                    task.cancel()
            await asyncio.gather(*tasks, return_exceptions=True)
        if not attempted and initial and root.sender_type == "user":
            # Independent agents may all decline a casual human message. Assign one
            # host to acknowledge it, rather than leaving an ordinary conversation cold.
            await speak(initial[0], ReplyIntent(action="speak"), root)
        depth = 0
        delegated_pairs = set()
        while depth < len(scheduler.published):
            await self.service.runs.check_run(run_id)
            async with self.service.database.session_factory() as session:
                run = await session.get(GroupRun, run_id)
                group = await session.get(ChatGroup, run.group_id)
                allow_ai_to_ai = group.allow_ai_to_ai
                if run.emitted_ai_messages >= run.max_ai_messages:
                    break
            trigger_id = scheduler.published[depth]
            depth += 1
            async with self.service.database.session_factory() as session:
                trigger = await session.get(GroupMessage, trigger_id)
            explicit = [
                target
                for target in handoffs.get(trigger.sender_role_id, [])
                if target in json.loads(trigger.mentions_json)
                and (trigger.sender_role_id, target) not in delegated_pairs
            ]
            for target in explicit:
                delegated_pairs.add((trigger.sender_role_id, target))
                if scheduler.first_assessment(trigger_id, target):
                    await speak(
                        target,
                        ReplyIntent(action="speak", reply_to_message_id=trigger.id),
                        trigger,
                        direct=True,
                        delegated=True,
                    )
            # AI mentions, including broadcasts, are strong reply requests.
            # Assess every addressed role once; keep the run/thread budgets intact.
            strong = []
            for target in json.loads(trigger.mentions_json):
                pair = (trigger.sender_role_id, target)
                if target != trigger.sender_role_id and pair not in delegated_pairs:
                    delegated_pairs.add(pair)
                    if scheduler.first_assessment(trigger_id, target):
                        strong.append(target)
            if strong:
                responses = [
                    asyncio.create_task(
                        speak(
                            target,
                            ReplyIntent(action="speak", reply_to_message_id=trigger.id),
                            trigger,
                            direct=True,
                            delegated=True,
                        )
                    )
                    for target in strong
                ]
                try:
                    await asyncio.gather(*responses)
                finally:
                    for response in responses:
                        if not response.done():
                            response.cancel()
                    await asyncio.gather(*responses, return_exceptions=True)
            if not allow_ai_to_ai:
                continue
            candidates = [
                id
                for id in await self.candidates(run_id, trigger_id, True)
                if scheduler.first_assessment(trigger_id, id)
            ]
            intents = await asyncio.gather(
                *[
                    self.service.social.decide(run_id, id, trigger_id=trigger_id)
                    for id in candidates
                ]
            )
            for role_id, intent in zip(candidates, intents, strict=True):
                await speak(role_id, intent, trigger)

    async def plan(self, group_id, exclude=None, followup=False):
        async with self.service.database.session_factory() as session:
            group = await session.get(ChatGroup, group_id)
            members = (
                await session.exec(
                    select(GroupMember).where(
                        GroupMember.group_id == group_id, GroupMember.active.is_(True)
                    )
                )
            ).all()
            candidates = []
            for member in members:
                role = await session.get(Role, member.role_id)
                if role and role.enabled and not role.deleted and role.id != exclude:
                    candidates.append(
                        {"id": role.id, "name": role.nickname, "persona": role.description[:160]}
                    )
            history = (
                await session.exec(
                    select(GroupMessage)
                    .where(GroupMessage.group_id == group_id, GroupMessage.content != "")
                    .order_by(GroupMessage.seq.desc())
                    .limit(30)
                )
            ).all()
        if not candidates:
            return []
        prompt = (
            '你是群聊发言调度器。只输出 JSON {"speakers":[角色ID]}。可以无人发言。不要强制附和。'
        )
        prompt += (
            "根据上一位伙伴的发言，选择至多一位需要自然接话的伙伴，不值得接话就返回空列表。"
            if followup
            else "选择0到2位最适合回应用户的伙伴。"
        )
        try:
            raw = await self.service.model.complete(
                [
                    ModelMessage(role="system", content=prompt),
                    ModelMessage(
                        role="user",
                        content=json.dumps(
                            {
                                "group": group.name,
                                "candidates": candidates,
                                "messages": [
                                    {
                                        "name": m.sender_name,
                                        "text": model_sticker_text(m.content)[:1000],
                                    }
                                    for m in reversed(history)
                                ],
                            },
                            ensure_ascii=False,
                        ),
                    ),
                ]
            )
            start, end = raw.find("{"), raw.rfind("}")
            ids = json.loads(raw[start : end + 1])["speakers"]
            if not isinstance(ids, list):
                raise ValueError("speakers")
            valid = {candidate["id"] for candidate in candidates}
            return list(
                dict.fromkeys(
                    identifier
                    for identifier in ids
                    if isinstance(identifier, str) and identifier in valid
                )
            )[: 1 if followup else 2]
        except (ValueError, KeyError, TypeError):
            return [] if followup else [candidates[0]["id"]]
