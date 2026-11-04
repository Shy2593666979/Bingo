"""One cancellable discussion driver per call; completed playback owns turn accounting."""

import asyncio
import re
import time
from dataclasses import asdict, dataclass, field

from bingo.agent.model_client import ModelMessage
from bingo.prompts.group_call import SUMMARY, USER_INTENT
from bingo.services.group_call_scheduler import TurnScheduler, json_object


@dataclass
class DiscussionState:
    enabled: bool = False
    phase: str = "idle"
    topic: str = ""
    max_silent_turns: int = 40
    ai_silent_turns: int = 0
    call_total_ai_turns: int = 0
    episode_id: int = 0
    last_speaker_id: str | None = None
    recent_speakers: list[str] = field(default_factory=list)
    topic_summary: str = ""
    no_content_streak: int = 0
    stop_reason: str = ""


class DiscussionController:
    def __init__(self, engine, scheduler=None):
        self.engine = engine
        self.state = DiscussionState()
        self.scheduler = scheduler or TurnScheduler()
        self.episode_started = time.monotonic()
        self.max_episode_seconds = 20 * 60
        self.max_yields = 2
        self.summary_at = 0

    def valid(self, generation, episode):
        return (
            not self.engine.closed
            and generation == self.engine.generation
            and episode == self.state.episode_id
        )

    async def notify(self):
        await self.engine.emit(
            {"type": "discussion_state", **asdict(self.state), "generation": self.engine.generation}
        )

    def user_committed(self):
        self.state.episode_id += 1
        self.state.ai_silent_turns = 0
        self.state.no_content_streak = 0
        self.state.stop_reason = ""
        self.episode_started = time.monotonic()

    def on_played(self, row):
        self.state.call_total_ai_turns += 1
        if row.get("episode_id") == self.state.episode_id and row.get("autonomous"):
            self.state.ai_silent_turns += 1
            self.state.last_speaker_id = row["role_id"]
            self.state.recent_speakers = (self.state.recent_speakers + [row["role_id"]])[-12:]

    async def configure(self, limit):
        if type(limit) is not int or limit not in {30, 40, 50}:
            raise ValueError("自主发言上限只能是30、40或50")
        self.state.max_silent_turns = limit
        # An already-started utterance may finish; no new utterance exceeds the new limit.
        await self.notify()

    async def pause(self):
        self.state.phase = "paused"
        self.state.stop_reason = "user_paused"
        self.engine.retire(self.engine.debounce)
        self.engine.retire(self.engine.recovery)
        self.engine.pending.clear()
        self.engine.user_speaking = False
        generation = await self.engine.interrupt()
        if generation == self.engine.generation and not self.engine.closed:
            await self.notify()

    async def resume(self):
        if not self.engine.strict_playback:
            raise ValueError("请更新客户端后使用自主讨论")
        if not self.engine.started or self.engine.closed:
            raise ValueError("通话尚未准备好")
        generation = await self.engine.interrupt()
        if generation != self.engine.generation or self.engine.closed:
            return
        self.engine.retire(self.engine.debounce)
        self.engine.retire(self.engine.recovery)
        self.engine.pending.clear()
        self.engine.user_speaking = False
        self.state.enabled = True
        self.state.phase = "discussing"
        self.state.topic = self.state.topic or "自由聊聊最近的生活"
        self.user_committed()
        self.engine.task = asyncio.create_task(
            self.run(self.engine.generation, self.state.episode_id)
        )

    async def handle_user(self, text, generation, episode):
        state = self.state
        if not self.valid(generation, episode):
            return
        if re.search(r"^(?:你们|大家)?(?:先)?(?:停一下|暂停|别说了|别聊了|不要说话|别说)", text):
            action = "pause"
            topic = ""
        elif not re.search(r"不要|不能|不许|别", text) and re.search(
            r"(?:你们|大家).*(?:自己聊|自由聊|自由讨论|聊聊|接着聊|继续聊)", text
        ):
            action, topic = "start", text
        elif re.search(r"^(?:继续|接着聊|恢复讨论)[吧呀啊。！! ]*$", text):
            action, topic = "start", ""
        elif not state.enabled and not re.search(
            r"你们|大家|他们|自由|自己|继续|停|暂停|接着|讨论|聊聊|聊吧", text
        ):
            action, topic = "normal", ""
        else:
            try:
                result = json_object(
                    await self.engine.complete(
                        [
                            ModelMessage(role="system", content=USER_INTENT),
                            ModelMessage(
                                role="user",
                                content=f"自主讨论已启用：{state.enabled}，状态：{state.phase}\n用户：{text}",
                            ),
                        ]
                    )
                )
                action = result.get("action", "continue" if state.enabled else "normal")
                topic = result.get("topic", "")
                if not isinstance(action, str) or action not in {
                    "start",
                    "continue",
                    "pause",
                    "normal",
                }:
                    action = "continue" if state.enabled else "normal"
            except Exception:
                action, topic = ("continue" if state.enabled else "normal"), ""
        if not self.valid(generation, episode):
            return
        if action == "pause":
            state.phase, state.stop_reason = "paused", "user_paused"
            await self.notify()
            return
        if action == "start" and self.engine.strict_playback:
            state.enabled = True
        if isinstance(topic, str) and topic.strip() and state.enabled:
            state.topic = topic.strip()[:800]
            state.topic_summary = ""
            self.summary_at = state.call_total_ai_turns
        if state.enabled and (state.phase != "paused" or action == "start"):
            state.topic = state.topic or text[:800]
            await self.run(generation, episode)
        else:
            if action == "start":
                await self.engine.emit(
                    {"type": "participant_error", "message": "请更新客户端后使用自主讨论"}
                )
            await self.engine.respond(text)

    async def summarize(self, generation, episode):
        state = self.state
        if state.call_total_ai_turns - self.summary_at < 8:
            return
        rows = self.engine.history[-16:]
        text = await self.engine.complete(
            [
                ModelMessage(role="system", content=SUMMARY),
                ModelMessage(
                    role="user",
                    content=f"主题：{state.topic}\n旧摘要：{state.topic_summary}\n"
                    + "\n".join(f"{r['name']}：{r['text']}" for r in rows),
                ),
            ]
        )
        if self.valid(generation, episode):
            state.topic_summary = text.strip()[:1200]
            self.summary_at = state.call_total_ai_turns

    async def run(self, generation, episode):
        state, engine = self.state, self.engine
        yields = errors = 0
        if not self.valid(generation, episode):
            return
        state.phase = "discussing"
        try:
            async with asyncio.timeout(
                max(0.01, self.max_episode_seconds - (time.monotonic() - self.episode_started))
            ):
                while self.valid(generation, episode) and state.enabled:
                    remaining = state.max_silent_turns - state.ai_silent_turns
                    if remaining <= 0:
                        state.stop_reason = "turn_limit"
                        break
                    if not engine.within_budget():
                        state.stop_reason = "call_budget"
                        break
                    state.phase = "winding_down" if remaining <= 5 else "discussing"
                    await self.notify()
                    try:
                        await self.summarize(generation, episode)
                        if not self.valid(generation, episode):
                            return
                        decision = await self.scheduler.next_turn(engine, state)
                        if not self.valid(generation, episode):
                            return
                        if decision.action == "finish":
                            state.stop_reason = "natural_finish"
                            break
                        if decision.action == "yield":
                            yields += 1
                            if yields > self.max_yields:
                                state.stop_reason = "silence"
                                break
                            await asyncio.sleep(0.8)
                            continue
                        yields = 0
                        role = next((r for r in engine.roles if r.id == decision.speaker_id), None)
                        if role is None:
                            raise ValueError("Unknown speaker")
                        content = await engine.generate_one(role, autonomous=True)
                        if not self.valid(generation, episode):
                            return
                        if not content or any(content == r["text"] for r in engine.history[-6:]):
                            state.no_content_streak += 1
                            state.last_speaker_id = role.id
                            if state.no_content_streak >= 2:
                                state.stop_reason = "no_new_content"
                                break
                            continue
                        state.no_content_streak = 0
                        outcome = await engine.say(role, content, generation, autonomous=True)
                        if outcome != "completed":
                            state.stop_reason = f"playback_{outcome}"
                            if (
                                episode == state.episode_id
                                and not engine.user_speaking
                                and state.phase != "paused"
                            ):
                                state.phase = "idle"
                                await self.notify()
                                await engine.emit(
                                    {"type": "listening", "generation": engine.generation}
                                )
                            break
                        errors = 0
                    except asyncio.CancelledError:
                        raise
                    except Exception:
                        errors += 1
                        if errors >= 2:
                            state.stop_reason = "generation_failed"
                            break
        except TimeoutError:
            if (
                episode == state.episode_id
                and not engine.closed
                and not engine.user_speaking
                and state.phase != "paused"
            ):
                state.stop_reason = "duration_limit"
        finally:
            if self.valid(generation, episode) or (
                episode == state.episode_id
                and not engine.closed
                and not engine.user_speaking
                and state.phase != "paused"
                and state.stop_reason == "duration_limit"
            ):
                state.phase = "idle"
                await self.notify()
                await engine.emit({"type": "listening", "generation": engine.generation})
