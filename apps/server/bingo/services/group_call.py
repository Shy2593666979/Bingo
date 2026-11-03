"""One human microphone, independent agents, one ordered audio output."""

import asyncio
import base64
import re
import time
import uuid
from contextlib import aclosing

from bingo.agent.handoffs import agent_broadcast_targets, normalize_agent_addresses
from bingo.agent.model_client import ModelMessage


class GroupCallSession:
    def __init__(
        self, *, roles, model, speech, emit, history=(), voice_fallback="", role_contexts=None
    ):
        self.roles = roles
        self.model, self.speech, self.emit = model, speech, emit
        self.voice_fallback = voice_fallback
        self.role_contexts = role_contexts or {}
        self.history = list(history)[-30:]
        self.call_log = []
        self.generation = 0
        self.task = None
        self.debounce = None
        self.pending = []
        self.played = asyncio.Event()
        self.utterance = None
        self.turn = 0
        self.user_speaking = False
        self.closed = False
        self.started = False

    async def interrupt(self):
        self.generation += 1
        self.utterance = None
        self.played.set()
        if self.task:
            self.task.cancel()
            await asyncio.gather(self.task, return_exceptions=True)
            self.task = None
        await self.emit({"type": "interrupted", "generation": self.generation})

    async def partial(self, text):
        if text.strip() and not self.user_speaking:
            self.user_speaking = True
            await self.interrupt()
        if self.debounce:
            self.debounce.cancel()

    async def sentence(self, text):
        if not text.strip():
            return
        if not self.user_speaking:
            await self.partial(text)
        self.pending.append(text.strip())
        if self.debounce:
            self.debounce.cancel()
        self.debounce = asyncio.create_task(self._commit())

    async def _commit(self):
        await asyncio.sleep(0.45)
        text = "".join(self.pending)
        self.pending.clear()
        self.user_speaking = False
        self.history.append({"name": "用户", "text": text, "role_id": None})
        self.call_log.append(self.history[-1])
        await self.emit({"type": "user_transcript", "text": text})
        self.task = asyncio.create_task(self.respond(text))

    def targets(self, text, *, exclude=None):
        roles = [r for r in self.roles if r.id != exclude]
        if exclude is not None:
            people = [("role", r.id, r.nickname) for r in self.roles]
            broadcast, targets = agent_broadcast_targets(text, people, exclude)
            if not broadcast:
                _, targets = normalize_agent_addresses(text, people, exclude)
            ids = {target["id"] for target in targets}
            return [r for r in roles if r.id in ids], bool(ids)
        if re.search(r"(?:全部|全体)搭子|所有人|(?:大家|你们).*(?:说|介绍|回答)", text):
            return roles, True
        named = [r for r in roles if re.search(r"@?" + re.escape(r.nickname), text)]
        if named:
            return named, True
        if not roles:
            return [], False
        offset = self.turn % len(roles)
        self.turn += 1
        return (roles[offset:] + roles[:offset])[:2], False

    async def respond(self, text, *, greeting=False):
        generation = self.generation
        candidates, explicit = self.targets(text)
        if greeting:
            candidates = self.roles[:1]
        queue = asyncio.Queue()

        async def prepare(role, required):
            try:
                transcript = list(self.history[-30:])
                prompt = (
                    f"你是{role.nickname}。{self.role_contexts.get(role.id, role.context_prompt)}\n"
                    "你正在与真人和其他AI搭子进行多人语音通话。只说自己的话，"
                    "自然简短，通常一到三句话，不写舞台动作、角色标签和Markdown。"
                    "不要重复别人。可以用@名字邀请一位在场搭子接话。"
                    f"在场搭子：{'、'.join(r.nickname for r in self.roles)}。\n"
                    + (
                        "这次请你回应。"
                        if required
                        else "只有有补充价值时才回应，否则仅输出[沉默]。"
                    )
                )
                async with asyncio.timeout(40):
                    result = await self.model.complete(
                        [
                            ModelMessage(role="system", content=prompt),
                            ModelMessage(
                                role="user",
                                content="\n".join(
                                    f"{row['name']}：{row['text']}" for row in transcript
                                )
                                + ("\n通话刚接通，请简短打个招呼。" if greeting else ""),
                            ),
                        ]
                    )
                result = result.strip()[:800]
                if result and result != "[沉默]":
                    await queue.put((role, result))
            except asyncio.CancelledError:
                raise
            except Exception:
                await self.emit(
                    {
                        "type": "participant_error",
                        "role_id": role.id,
                        "message": f"{role.nickname}暂时无法回应",
                    }
                )
            finally:
                await queue.put(None)

        workers = [
            asyncio.create_task(prepare(r, explicit or i == 0)) for i, r in enumerate(candidates)
        ]
        finished, emitted = 0, 0
        addressed = set(r.id for r in candidates)
        try:
            while finished < len(workers):
                item = await queue.get()
                if item is None:
                    finished += 1
                    continue
                role, content = item
                if generation != self.generation or self.closed:
                    return
                await self.say(role, content, generation)
                emitted += 1
                # A single bounded hand-off round; no unbounded AI conversation.
                followups, strong = self.targets(content, exclude=role.id)
                if strong and emitted < 10:
                    for target in followups:
                        if target.id not in addressed:
                            addressed.add(target.id)
                            workers.append(asyncio.create_task(prepare(target, True)))
                            if len(workers) >= 10:
                                break
                if emitted >= 10:
                    break
        except asyncio.CancelledError:
            raise
        except Exception:
            await self.emit(
                {"type": "participant_error", "message": "本轮通话回复未完成，请继续说话"}
            )
        finally:
            for task in workers:
                if not task.done():
                    task.cancel()
            await asyncio.gather(*workers, return_exceptions=True)
            if generation == self.generation and not self.closed:
                await self.emit({"type": "listening", "generation": generation})

    async def say(self, role, text, generation):
        utterance = uuid.uuid4().hex
        self.utterance = utterance
        self.played.clear()
        await self.emit(
            {
                "type": "speaker",
                "role_id": role.id,
                "text": text,
                "utterance_id": utterance,
                "generation": generation,
            }
        )
        self.history.append({"name": role.nickname, "role_id": role.id, "text": text})
        self.call_log.append(self.history[-1])
        self.history = self.history[-100:]
        audio = False
        audio_started, audio_bytes = None, 0
        async with aclosing(
            self.speech.message_events(text, role.voice or self.voice_fallback)
        ) as events:
            async for event in events:
                if generation != self.generation or self.closed:
                    return
                if event["type"] == "audio":
                    if audio_started is None:
                        audio_started = time.monotonic()
                    base64.b64decode(event["data"], validate=True)
                    audio = True
                    await self.emit({**event, "generation": generation, "utterance_id": utterance})
                    audio_bytes += len(base64.b64decode(event["data"]))
                    await asyncio.sleep(
                        max(0, audio_bytes / 48000 - (time.monotonic() - audio_started) - 0.35)
                    )
                elif event["type"] == "audio_error":
                    await self.emit(
                        {
                            "type": "participant_error",
                            "role_id": role.id,
                            "message": "语音暂时不可用",
                        }
                    )
        if audio:
            await self.emit(
                {"type": "audio_end", "generation": generation, "utterance_id": utterance}
            )
            await asyncio.wait_for(self.played.wait(), 90)
        if generation == self.generation:
            await asyncio.sleep(1.5)

    def acknowledge(self, utterance):
        if utterance == self.utterance:
            self.played.set()

    async def close(self):
        self.closed = True
        if self.debounce:
            self.debounce.cancel()
            await asyncio.gather(self.debounce, return_exceptions=True)
        if self.task:
            self.task.cancel()
            await asyncio.gather(self.task, return_exceptions=True)
