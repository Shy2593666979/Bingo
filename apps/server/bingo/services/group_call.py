"""One human microphone, independent agents, one ordered audio output."""

import asyncio
import base64
import re
import time
import uuid
from contextlib import aclosing
from enum import StrEnum

from bingo.agent.handoffs import agent_broadcast_targets, normalize_agent_addresses
from bingo.agent.model_client import ModelMessage
from bingo.prompts.group_call import DISCUSSION_SPEECH, ENDING, ROLE_SPEECH
from bingo.services.group_call_discussion import DiscussionController
from bingo.services.group_call_prefetch import PreparedSpeech


class PlaybackResult(StrEnum):
    COMPLETED = "completed"
    INTERRUPTED = "interrupted"
    TIMEOUT = "timeout"
    FAILED = "failed"


class GroupCallSession:
    def __init__(
        self,
        *,
        roles,
        model,
        speech,
        emit,
        history=(),
        voice_fallback="",
        role_contexts=None,
        max_silent_turns=30,
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
        self.audio_lock = asyncio.Lock()
        self.retired = set()
        self.playback_record = None
        self.awaiting_ack = False
        self.strict_playback = False
        self.metrics = {
            "model_requests": 0,
            "tts_requests": 0,
            "audio_bytes": 0,
            "completed_turns": 0,
            "playback_failures": 0,
            "prefetch_requests": 0,
            "prefetched_audio_turns": 0,
        }
        self.call_started = time.monotonic()
        self.max_call_seconds = 3600
        self.max_model_requests = 400
        self.recovery = None
        self.partial_quiet_seconds = 8
        self.playback_timeout = 90
        self.discussion = DiscussionController(self)
        self.discussion.state.max_silent_turns = max_silent_turns

    def start(self, *, strict_playback):
        if self.started or self.closed:
            return
        self.started = True
        self.strict_playback = strict_playback
        self.discussion.state.enabled = strict_playback
        if self.task is None and not self.user_speaking:
            self.task = asyncio.create_task(
                self.open_conversation() if strict_playback else self.respond("", greeting=True)
            )

    async def open_conversation(self):
        generation, episode = self.generation, self.discussion.state.episode_id
        state = self.discussion.state
        latest_user = next(
            (r["text"] for r in reversed(self.history) if r.get("role_id") is None), ""
        )
        state.topic = (
            latest_user or "和用户及在场朋友自然聊聊近况，照顾用户感受，没新内容就等用户说话"
        )
        await self.discussion.notify()
        if not self.roles:
            return
        content = await self.generate_one(self.roles[0], required=True, greeting=True)
        if not self.discussion.valid(generation, episode):
            return
        if content:
            await self.discussion.run(generation, episode, initial=(self.roles[0], content))
        elif self.discussion.valid(generation, episode):
            await self.discussion.run(generation, episode)

    def within_budget(self):
        return (
            time.monotonic() - self.call_started < self.max_call_seconds
            and self.metrics["model_requests"] < self.max_model_requests
        )

    async def complete(self, messages):
        if not self.within_budget():
            raise RuntimeError("Call generation budget exhausted")
        self.metrics["model_requests"] += 1
        remaining = self.max_call_seconds - (time.monotonic() - self.call_started)
        async with asyncio.timeout(min(40, remaining)):
            return await self.model.complete(messages)

    async def generate_one(
        self, role, *, required=False, greeting=False, autonomous=False, history=None, state=None
    ):
        state = self.discussion.state if state is None else state
        history = self.history if history is None else history
        instruction = "这次请你回应。" if required else "只有有补充价值时才回应，否则仅输出[沉默]。"
        if autonomous:
            instruction = DISCUSSION_SPEECH.format(
                topic=state.topic,
                summary=state.topic_summary,
                ending=ENDING if state.phase == "winding_down" else "",
            )
        prompt = ROLE_SPEECH.format(
            nickname=role.nickname,
            context=self.role_contexts.get(role.id, role.context_prompt),
            participants="、".join(r.nickname for r in self.roles),
            instruction=instruction,
        )
        result = await self.complete(
            [
                ModelMessage(role="system", content=prompt),
                ModelMessage(
                    role="user",
                    content="\n".join(
                        f"{r['name']}：{r['text']}" for r in history[-(20 if autonomous else 30) :]
                    )
                    + ("\n通话刚接通，请简短打个招呼。" if greeting else ""),
                ),
            ]
        )
        result = result.strip()[:800]
        return "" if result == "[沉默]" else result

    def retire(self, task):
        if task and task.done():
            self._reaped(task)
        elif task:
            task.cancel()
            self.retired.add(task)
            task.add_done_callback(self._reaped)

    def _reaped(self, task):
        self.retired.discard(task)
        if not task.cancelled():
            task.exception()

    async def interrupt(self):
        self.generation += 1
        self.discussion.cancel_prefetch()
        generation = self.generation
        self.utterance = None
        self.awaiting_ack = False
        if self.playback_record and self.playback_record["status"] == "speaking":
            self.playback_record["status"] = PlaybackResult.INTERRUPTED
        self.played.set()
        task, self.task = self.task, None
        self.retire(task)
        await self.emit({"type": "interrupted", "generation": generation})
        await asyncio.sleep(0)
        return generation

    async def partial(self, text):
        if self.closed or not text.strip():
            return
        if text.strip() and not self.user_speaking:
            self.user_speaking = True
            state = self.discussion.state
            if state.enabled and state.phase != "paused":
                state.phase = "user_interrupting"
            generation = await self.interrupt()
            if generation != self.generation or self.closed:
                return
        if self.debounce:
            self.debounce.cancel()
        self.retire(self.recovery)
        self.recovery = asyncio.create_task(self._recover_partial(self.generation))

    async def _recover_partial(self, generation):
        await asyncio.sleep(self.partial_quiet_seconds)
        if generation != self.generation or self.closed:
            return
        if self.pending:
            self.debounce = asyncio.create_task(self._commit(self.generation))
            return
        self.user_speaking = False
        state = self.discussion.state
        if state.enabled and state.phase == "user_interrupting":
            self.task = asyncio.create_task(self.discussion.run(generation, state.episode_id))
        else:
            await self.emit({"type": "listening", "generation": generation})

    async def sentence(self, text):
        if self.closed or not any(c.isalnum() for c in text):
            return
        if not self.user_speaking:
            await self.partial(text)
        self.pending.append(text.strip())
        self.retire(self.recovery)
        if self.debounce:
            self.debounce.cancel()
        self.debounce = asyncio.create_task(self._commit(self.generation))

    async def _commit(self, generation=None):
        generation = self.generation if generation is None else generation
        await asyncio.sleep(0.45)
        text = "".join(self.pending)
        if self.closed or not text or generation != self.generation:
            return
        self.pending.clear()
        self.user_speaking = False
        self.history.append({"name": "用户", "text": text, "role_id": None})
        self.call_log.append(self.history[-1])
        self.discussion.user_committed()
        episode = self.discussion.state.episode_id
        await self.emit({"type": "user_transcript", "text": text})
        if self.discussion.valid(generation, episode):
            self.task = asyncio.create_task(self.discussion.handle_user(text, generation, episode))

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
                result = await self.generate_one(role, required=required, greeting=greeting)
                if result and result != "[沉默]":
                    await queue.put((role, result))
            except asyncio.CancelledError:
                raise
            except Exception:
                if generation == self.generation and not self.closed:
                    await self.emit(
                        {
                            "type": "participant_error",
                            "generation": generation,
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
                result = await self.say(role, content, generation)
                if result != PlaybackResult.COMPLETED:
                    return
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
            if generation == self.generation and not self.closed:
                await self.emit(
                    {
                        "type": "participant_error",
                        "generation": generation,
                        "message": "本轮通话回复未完成，请继续说话",
                    }
                )
        finally:
            for task in workers:
                if not task.done():
                    task.cancel()
            await asyncio.gather(*workers, return_exceptions=True)
            if generation == self.generation and not self.closed:
                await self.emit({"type": "listening", "generation": generation})

    def speech_events(self, role, text):
        self.metrics["tts_requests"] += 1
        return self.speech.message_events(text, role.voice or self.voice_fallback)

    def prepare_speech(self, role, text):
        return PreparedSpeech(self.speech_events(role, text), self.retire)

    async def say(self, role, text, generation, *, autonomous=False, prepared_audio=None):
        async with self.audio_lock:
            if generation != self.generation or self.closed:
                return PlaybackResult.INTERRUPTED
            try:
                remaining = self.max_call_seconds - (time.monotonic() - self.call_started)
                async with asyncio.timeout(min(150, max(0.01, remaining))):
                    return await self._say(
                        role, text, generation, autonomous=autonomous, prepared_audio=prepared_audio
                    )
            except TimeoutError:
                return self._playback_failed(PlaybackResult.TIMEOUT)
            except asyncio.CancelledError:
                self._playback_failed(PlaybackResult.INTERRUPTED)
                raise
            except Exception:
                return self._playback_failed(PlaybackResult.FAILED)
            finally:
                self.awaiting_ack = False
                row = self.playback_record
                if row and row["status"] != "completed" and generation == self.generation:
                    self.generation += 1
                    self.utterance = None
                    await self.emit({"type": "interrupted", "generation": self.generation})

    def _playback_failed(self, result):
        row = self.playback_record
        if row and row["status"] == "speaking":
            row["status"] = result
            self.metrics["playback_failures"] += 1
        return result

    async def _say(self, role, text, generation, *, autonomous=False, prepared_audio=None):
        utterance = uuid.uuid4().hex
        self.utterance = utterance
        self.played.clear()
        self.awaiting_ack = False
        row = {
            "name": role.nickname,
            "role_id": role.id,
            "text": text,
            "utterance_id": utterance,
            "generation": generation,
            "status": "speaking",
            "episode_id": self.discussion.state.episode_id,
            "autonomous": autonomous,
        }
        self.playback_record = row
        self.call_log.append(row)
        await self.emit(
            {
                "type": "speaker",
                "role_id": role.id,
                "text": text,
                "utterance_id": utterance,
                "generation": generation,
            }
        )
        audio = False
        audio_started, audio_bytes = None, 0
        if prepared_audio and prepared_audio.first_audio_ready:
            self.metrics["prefetched_audio_turns"] += 1
        source = prepared_audio.events() if prepared_audio else self.speech_events(role, text)
        async with aclosing(source) as events:
            async for event in events:
                if generation != self.generation or self.closed:
                    return self._playback_failed(PlaybackResult.INTERRUPTED)
                if event["type"] == "audio":
                    if audio_started is None:
                        audio_started = time.monotonic()
                    base64.b64decode(event["data"], validate=True)
                    audio = True
                    await self.emit({**event, "generation": generation, "utterance_id": utterance})
                    audio_bytes += len(base64.b64decode(event["data"]))
                    self.metrics["audio_bytes"] += len(base64.b64decode(event["data"]))
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
                    return self._playback_failed(PlaybackResult.FAILED)
        if audio:
            self.awaiting_ack = True
            await self.emit(
                {"type": "audio_end", "generation": generation, "utterance_id": utterance}
            )
            await asyncio.wait_for(self.played.wait(), self.playback_timeout)
        else:
            return self._playback_failed(PlaybackResult.FAILED)
        return PlaybackResult(row["status"])

    def acknowledge(self, utterance, generation=None, status="completed"):
        row = self.playback_record
        if (
            not row
            or not self.awaiting_ack
            or utterance != self.utterance
            or row["generation"] != self.generation
            or row["status"] != "speaking"
            or (generation is not None and generation != self.generation)
            or (self.strict_playback and generation is None)
        ):
            return False
        if (
            not isinstance(status, str)
            or status not in set(PlaybackResult)
            or (generation is not None and type(generation) is not int)
        ):
            return False
        row["status"] = status
        if status == PlaybackResult.COMPLETED:
            self.history.append(dict(row))
            self.history = self.history[-100:]
            self.metrics["completed_turns"] += 1
            self.discussion.on_played(row)
        else:
            self.metrics["playback_failures"] += 1
        self.played.set()
        return True

    async def close(self):
        self.closed = True
        self.generation += 1
        self.discussion.cancel_prefetch()
        self.awaiting_ack = False
        self.utterance = None
        self._playback_failed(PlaybackResult.INTERRUPTED)
        self.played.set()
        self.discussion.state.phase = "closed"
        self.retire(self.recovery)
        if self.debounce:
            self.debounce.cancel()
            await asyncio.gather(self.debounce, return_exceptions=True)
        self.retire(self.task)
        if self.retired:
            await asyncio.wait(self.retired, timeout=2)
