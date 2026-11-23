"""Persisted games, cancellable single-turn generation and revision-guarded writes."""

import asyncio
import json
from copy import deepcopy

from sqlalchemy import update
from sqlalchemy.exc import IntegrityError
from sqlmodel import select

from bingo.db.models import PartyGame, Role, RolePreference
from bingo.db.repositories import RoleRepository
from bingo.services import party_rules as rules
from bingo.services.exceptions import ServiceError
from bingo.services.party_ai import PartyAI
from bingo.services.voices import effective_role


async def game_role(session, user_id, role):
    role = await effective_role(session, user_id, role)
    preference = await session.get(RolePreference, (user_id, role.id))
    if preference:
        role = role.model_copy(
            update={"speaking_style": preference.speaking_style or preference.personality}
        )
    return role


class PartyGameService:
    def __init__(self, database, model, decision):
        self.database = database
        self.ai = PartyAI(model, decision)
        self.tasks = {}
        self.retiring = set()
        self.locks = {}

    async def start(self):
        # A restarted process cannot truthfully promise an old audio/task is still running.
        async with self.database.session_factory() as session:
            rows = (await session.exec(select(PartyGame))).all()
            for row in rows:
                state = json.loads(row.state_json)
                if state["phase"] != "finished":
                    state.update(
                        paused=True,
                        voice=False,
                        playback=None,
                        voice_suspended=False,
                        voice_epoch=state["voice_epoch"] + 1,
                        error="服务已重新连接，点击继续恢复本局",
                    )
                    row.state_json = json.dumps(state, ensure_ascii=False)
                    row.revision += 1
                    session.add(row)
            await session.commit()

    async def create(self, user, payload):
        async with self.database.session_factory() as session:
            available = {r.id: r for r in await RoleRepository(session).list_enabled(user.id)}
            if any(p not in available for p in payload.role_ids):
                raise ServiceError(422, "只能邀请已添加且可用的搭子")
            available = {
                p: await game_role(session, user.id, available[p]) for p in payload.role_ids
            }
            people = [
                {
                    "id": p,
                    "name": available[p].nickname,
                    "avatar_key": available[p].visible_name,
                    "speaking_style": available[p].speaking_style,
                    "personality_tags": json.loads(available[p].traits_json),
                }
                for p in payload.role_ids
            ]
            try:
                state = rules.new_game(
                    payload.mode, people, user.username or "我", payload.rounds, payload.identity
                )
                state["personas"] = {p: available[p].context_prompt for p in payload.role_ids}
                state["mood"] = payload.mood
            except ValueError as error:
                raise ServiceError(422, str(error)) from error
            row = PartyGame(
                user_id=user.id,
                active_user_id=user.id,
                state_json=json.dumps(state, ensure_ascii=False),
            )
            session.add(row)
            try:
                await session.commit()
            except IntegrityError as error:
                await session.rollback()
                raise ServiceError(409, "还有一场未结束的小聚，请先继续或结束原局") from error
            identifier = row.id
        self.kick(identifier, user.id)
        return await self.get(identifier, user.id)

    async def load(self, identifier, user_id):
        async with self.database.session_factory() as session:
            row = await session.get(PartyGame, identifier)
            if row is None or row.user_id != user_id:
                raise ServiceError(404, "小聚不存在")
            return json.loads(row.state_json), row.revision

    async def save(self, identifier, revision, state):
        async with self.database.session_factory() as session:
            values = {"state_json": json.dumps(state, ensure_ascii=False), "revision": revision + 1}
            if state["phase"] == "finished":
                values["active_user_id"] = None
            changed = await session.exec(
                update(PartyGame)
                .where(PartyGame.id == identifier, PartyGame.revision == revision)
                .values(**values)
            )
            await session.commit()
            return changed.rowcount == 1

    async def get(self, identifier, user_id):
        state, revision = await self.load(identifier, user_id)
        task = self.tasks.get(identifier)
        return {
            "id": identifier,
            **rules.public_view(state, revision),
            "processing": bool(
                task
                and not task.done()
                and not state["paused"]
                and not state["waiting_user"]
                and not state["playback"]
            ),
        }

    async def list(self, user_id):
        async with self.database.session_factory() as session:
            rows = (
                await session.exec(
                    select(PartyGame)
                    .where(PartyGame.user_id == user_id)
                    .order_by(PartyGame.created_at.desc())
                    .limit(20)
                )
            ).all()
        return [
            {"id": row.id, **rules.public_view(json.loads(row.state_json), row.revision)}
            for row in rows
        ]

    def kick(self, identifier, user_id):
        if identifier not in self.tasks or self.tasks[identifier].done():
            task = asyncio.create_task(self.drive(identifier, user_id))
            self.tasks[identifier] = task
            task.add_done_callback(lambda done: self._retire(identifier, done))

    def _retire(self, identifier, task):
        if self.tasks.get(identifier) is task:
            self.tasks.pop(identifier, None)
        if not task.cancelled():
            task.exception()

    async def action(self, identifier, user_id, command):
        lock = self.locks.setdefault(identifier, asyncio.Lock())
        async with lock:
            state, revision = await self.load(identifier, user_id)
            if command.command_id in state["commands"]:
                return await self.get(identifier, user_id)
            if command.revision != revision:
                # Sending a new contribution may interrupt an in-flight turn; choices must be exact.
                if command.type not in {
                    "say",
                    "pause",
                    "end",
                    "resume",
                    "played",
                    "voice_start",
                    "voice_stop",
                    "interrupt",
                    "recover",
                    "advance",
                    "read_aloud",
                }:
                    if not (
                        command.type in {"choice", "change_question"}
                        and command.stage
                        and command.stage == rules.action_stage(state)
                    ):
                        raise ServiceError(409, "对局已更新，请查看最新状态后重试")
            if state["phase"] == "finished" and command.type != "voice_stop":
                raise ServiceError(409, "本局已结束")
            try:
                if command.type == "played":
                    if command.epoch != state["voice_epoch"]:
                        raise ValueError("旧音频回执已失效")
                self.apply(state, command.type, command.value, command_id=command.command_id)
                if command.type in {"choice", "advance", "change_question", "resume"}:
                    state["voice_suspended"] = False
            except ValueError as error:
                raise ServiceError(422, str(error)) from error
            state["commands"] = [*state["commands"][-99:], command.command_id]
            if command.type not in {"played", "recover", "read_aloud"}:
                state["voice_epoch"] += 1
                state["playback"] = None
            if not await self.save(identifier, revision, state):
                raise ServiceError(409, "对局已更新，请重试")
            task = self.tasks.pop(identifier, None)
            if task:
                task.cancel()
                self.retiring.add(task)
                task.add_done_callback(self.retiring.discard)
            self.kick(identifier, user_id)
        return await self.get(identifier, user_id)

    @staticmethod
    def apply(state, action, value, *, command_id=None):
        if action == "read_aloud":
            state["read_aloud"] = value.strip().lower() != "false"
            return
        if action in {"interrupt", "say", "pause", "voice_stop", "end"} and state["playback"]:
            for item in state["messages"]:
                if item["id"] == state["playback"]:
                    item["playback_status"] = "interrupted"
            checkpoint = state.get("playback_checkpoint")
            if checkpoint:
                state.update(deepcopy(checkpoint))
                state["playback_checkpoint"] = None
        if action == "voice_start":
            if state["voice"]:
                raise ValueError("已有游戏语音连接")
            state.update(voice=True, voice_suspended=False)
        elif action == "voice_stop":
            state.update(voice=False, voice_suspended=False, playback=None)
        elif action == "interrupt":
            state["voice_suspended"] = True
        elif action == "recover":
            state["voice_suspended"] = False
        elif action == "played":
            if state["playback"] != value:
                raise ValueError("音频回执与当前发言不匹配")
            state["playback"] = None
            state["playback_checkpoint"] = None
            for item in state["messages"]:
                if item["id"] == value:
                    item["playback_status"] = "played"
        elif action == "end":
            state.update(phase="finished", actor=None)
            rules.message(state, "你结束了本次小聚。")
        elif action == "pause":
            state["paused"] = True
        elif action == "resume":
            state.update(paused=False, error=None, waiting_user=False)
        elif state["paused"]:
            raise ValueError("请先继续游戏")
        elif action == "choice":
            if state["phase"] == "choose" and state["actor"] == rules.SELF:
                if value not in rules.options(state, rules.SELF):
                    raise ValueError("请选择真心话或大冒险")
                state.update(kind=value, phase="question")
            elif state["phase"] == "vote":
                rules.cast_vote(state, rules.SELF, value)
            else:
                rules.night_choice(state, rules.SELF, value)
        elif action == "say":
            state["voice_suspended"] = False
            state["waiting_user"] = False
            state["user_pending"] = True
            if not value.strip():
                raise ValueError("请先说点什么")
            if rules.can_speak(state, rules.SELF):
                rules.spoken(state, rules.SELF, value.strip(), client_message_id=command_id)
            elif state["mode"] == "truth" or (
                state["phase"] == "speech" and rules.SELF in state["alive"]
            ):
                rules.message(state, value.strip(), rules.SELF, client_message_id=command_id)
            else:
                raise ValueError("当前阶段不能向场上发言")
        elif action == "change_question" and state["mode"] == "truth":
            if state["actor"] != rules.SELF or state["phase"] != "answer":
                raise ValueError("只有轮到你回答时可以换题")
            state.update(phase="question", question=None)
        elif action == "advance":
            if state["mode"] == "truth":
                rules.next_truth(state)
            elif state["phase"] == "discuss":
                if rules.SELF not in state["alive"]:
                    raise ValueError("出局后请旁观，不能替场上玩家推进投票")
                rules.begin_vote(state)
            else:
                raise ValueError("尚未完成本阶段的必要行动")
        else:
            raise ValueError("不支持的游戏操作")

    async def drive(self, identifier, user_id):
        revision = -1
        try:
            for _ in range(80):
                state, revision = await self.load(identifier, user_id)
                if (
                    state["paused"]
                    or state["phase"] == "finished"
                    or state["playback"]
                    or state["voice_suspended"]
                    or state["waiting_user"]
                ):
                    return
                old_message_ids = {m["id"] for m in state["messages"]}
                checkpoint = deepcopy(
                    {
                        key: state.get(key)
                        for key in (
                            "phase",
                            "actor",
                            "queue",
                            "kind",
                            "question",
                            "discussion_turns",
                            "recent_speakers",
                            "waiting_user",
                            "user_pending",
                        )
                    }
                )
                changed = await self.step(state, user_id)
                if not changed:
                    return
                if state["voice"]:
                    spoken = [
                        m
                        for m in state["messages"]
                        if m["id"] not in old_message_ids
                        and m["speaker"] not in {None, rules.SELF}
                        and ("recipients" not in m or rules.SELF in m["recipients"])
                    ]
                    if spoken:
                        state["playback"] = spoken[-1]["id"]
                        state["playback_checkpoint"] = checkpoint
                if not await self.save(identifier, revision, state):
                    return  # A user contribution or another worker superseded this result.
            state, revision = await self.load(identifier, user_id)
            state.update(paused=True, error="本段对局已达到运行预算，请点击继续")
            await self.save(identifier, revision, state)
        except asyncio.CancelledError:
            raise
        except Exception:
            try:
                current, current_revision = await self.load(identifier, user_id)
            except ServiceError:
                return
            if current_revision != revision:
                return
            state = current
            state.update(paused=True, error="AI 暂时无法完成本次操作，请点击继续重试")
            await self.save(identifier, revision, state)

    async def speech_source(self, identifier, message_id, user_id):
        state, _ = await self.load(identifier, user_id)
        visible = rules.visible_messages(state, rules.SELF)
        item = next((m for m in visible if m["id"] == message_id), None)
        if item is None or item.get("speaker") in {None, rules.SELF}:
            raise ServiceError(404, "消息不存在或不可朗读")
        role = await self.role(user_id, item["speaker"])
        return item["text"], role.voice

    async def role(self, user_id, identifier):
        async with self.database.session_factory() as session:
            role = await session.get(Role, identifier)
            if not role or role.deleted or not role.enabled:
                raise ValueError("搭子已不可用")
            return await game_role(session, user_id, role)

    async def say(self, state, user_id, player, instruction):
        role = await self.role(user_id, player)
        return await self.ai.speak(state, role, instruction)

    async def step(self, state, user_id):
        phase, actor = state["phase"], state["actor"]
        candidates = {p["id"]: p["name"] for p in state["people"]}
        if phase == "select":
            recent = state["recent_actors"][-len(candidates) :]
            counts = {p: recent.count(p) for p in candidates}
            eligible = {p: candidates[p] for p in candidates if counts[p] == min(counts.values())}
            actor = await self.ai.choose(
                state, None, eligible, "选择本轮被邀请回答的人，兼顾最近未被选中的人。"
            )
            state.update(actor=actor, phase="choose")
            state["recent_actors"].append(actor)
            rules.message(state, f"第 {state['round']} 轮 · 轮到{rules.name(state, actor)}")
        elif phase == "choose":
            if actor == rules.SELF:
                return False
            choice = await self.ai.choose(
                state,
                actor,
                {"truth": "真心话", "dare": "大冒险"},
                "根据自己的性格和当前气氛选择。",
            )
            rules.message(state, "我选" + ("真心话。" if choice == "truth" else "大冒险。"), actor)
            state.update(kind=choice, phase="question")
        elif phase == "question":
            people = {p: n for p, n in candidates.items() if p not in {actor, rules.SELF}}
            speaker = await self.ai.choose(
                state, None, people, "选择最适合给本轮参与者出题的搭子。"
            )
            text = await self.say(
                state,
                user_id,
                speaker,
                f"给{rules.name(state, actor)}出一道"
                + ("真心话问题" if state["kind"] == "truth" else "聊天中可完成的轻松挑战")
                + "。结合最近聊天，不重复旧题，只出一道，不替对方回答。",
            )
            rules.message(state, text, speaker)
            state.update(question=text, phase="answer")
        elif phase in {"answer", "speech", "last_words"}:
            if actor == rules.SELF:
                return False
            text = await self.say(
                state,
                user_id,
                actor,
                {
                    "answer": "认真回答当前问题或完成挑战，保持个性。",
                    "speech": "完成自己的本轮发言，给出具体判断与理由。",
                    "last_words": (
                        "你已出局，留下简短遗言，不再参与行动。"
                        "如果你是预言家或女巫等好人关键身份，可以坦诚交代已知线索帮助好人；"
                        "如果你是狼人，保持伪装。"
                    ),
                }[phase],
            )
            rules.spoken(state, actor, text)
        elif phase == "night":
            if actor == rules.SELF:
                return False
            if state["night_action"] == "wolf_chat":
                text = await self.say(
                    state, user_id, actor, "在狼队私聊中分析今晚目标和明天策略，不要虚构额外情报。"
                )
                rules.spoken(state, actor, text)
            else:
                night_options = rules.options(state, actor)
                night_action = state["night_action"]
                if night_action == "potion":
                    if state["round"] == 1:
                        # Night 1 has zero daytime discussion; never let AI witch blind-poison.
                        safe_options = {
                            k: v for k, v in night_options.items() if not k.startswith("poison:")
                        }
                        if safe_options:
                            night_options = safe_options
                        victim = state["night"].get("kill")
                        instruction = (
                            "这是第1夜，你被狼人袭击且首夜可以自救，强烈建议选择save使用解药自救。"
                            if victim == actor and "save" in night_options
                            else "这是第1夜，还没有白天发言信息，"
                            "只在使用解药救人或不用药之间选择。"
                        )
                    else:
                        instruction = (
                            "仅当公开发言或票型里已有明确高度怀疑的狼人目标时才使用毒药，"
                            "没有确凿怀疑不要随意毒人；结合局势决定是否使用解药或不用药。"
                        )
                elif night_action == "kill":
                    instruction = "结合刚才狼队私聊商议的策略，选择今晚最优先袭击的目标。"
                else:
                    instruction = "根据公开发言和局势，选择一位最值得查验的存活玩家。"
                choice = await self.ai.choose(state, actor, night_options, instruction)
                rules.night_choice(state, actor, choice)
        elif phase == "vote":
            actor = next((p for p in state["queue"] if p != rules.SELF), None)
            if actor is None:
                return False
            choice = await self.ai.choose(
                state,
                actor,
                rules.options(state, actor),
                "独立投票，不知道其他人的未公布选票。狼人可以配合自己的阵营。",
            )
            rules.cast_vote(state, actor, choice)
        elif phase == "discuss":
            limit = 5 if state["mode"] == "truth" else 8
            eligible = {
                p: n
                for p, n in candidates.items()
                if p != rules.SELF
                and p in state["alive"]
                and state["recent_speakers"][-2:] != [p, p]
            }
            if not state["user_pending"]:
                eligible["finish"] = "没有必要接话，进入下一轮或投票"
                if rules.SELF in state["alive"]:
                    eligible["wait_user"] = "上一位已向用户提问，等用户回应，不开始下一轮"
            speaker = (
                "finish"
                if state["discussion_turns"] >= limit
                else await self.ai.choose(
                    state,
                    None,
                    eligible,
                    "决定唯一下一步。有明确追问、被质疑未回应或新观点才接话，通常1至3次即可。"
                    "不凑次数、不强制轮流、不连续刷同一个人。向用户提问后应结束接话等用户。",
                )
            )
            if speaker == "wait_user":
                state["waiting_user"] = True
            elif speaker == "finish":
                if state["mode"] == "truth":
                    rules.next_truth(state)
                else:
                    rules.begin_vote(state)
            else:
                text = await self.say(
                    state,
                    user_id,
                    speaker,
                    (
                        "本轮交流已充分，本次接住最新发言后简短自然收束，不再追问用户，不开新支线。"
                        if state["discussion_turns"] >= limit - 1
                        else "自由讨论中接住最新发言，追问、回应质疑或提出新观点。不要重复附和。"
                    ),
                )
                rules.spoken(state, speaker, text)
        else:
            return False
        return True

    async def close(self):
        tasks = [*self.tasks.values(), *self.retiring]
        self.tasks.clear()
        for task in tasks:
            task.cancel()
        await asyncio.gather(*tasks, return_exceptions=True)
        self.retiring.clear()
        self.locks.clear()

    async def cancel_user(self, user_id):
        async with self.database.session_factory() as session:
            ids = (
                await session.exec(select(PartyGame.id).where(PartyGame.user_id == user_id))
            ).all()
        tasks = [self.tasks.pop(identifier) for identifier in ids if identifier in self.tasks]
        for task in tasks:
            task.cancel()
        await asyncio.gather(*tasks, return_exceptions=True)
