import asyncio
import time

import pytest
from pydantic import ValidationError

from bingo.config import GroupCallSettings
from bingo.services.group_call import GroupCallSession, PlaybackResult
from bingo.services.group_call_scheduler import TurnDecision
from tests.test_group_calls import Speech, role


class Model:
    def __init__(self):
        self.requests = []

    async def complete(self, messages):
        self.requests.append(messages)
        if "短期讨论摘要，只输出" in messages[0].content:
            return "用户关心结婚时机，经济与感情的分歧还没有解决。"
        if "判断这句用户语音" in messages[0].content:
            return '{"action":"continue","topic":""}'
        return f"新的观点{len(self.requests)}"


class Scheduler:
    def __init__(self, actions=()):
        self.actions = iter(actions)
        self.seen = []

    async def next_turn(self, engine, state):
        self.seen.append([r["text"] for r in engine.history])
        action = next(self.actions, "speak")
        return TurnDecision(action, engine.roles[len(self.seen) % 2].id)


@pytest.fixture
def fast_sleep(monkeypatch):
    import bingo.services.group_call as module

    real_sleep = asyncio.sleep

    async def sleep(seconds):
        await real_sleep(0 if seconds in {1.5, 0.45, 0.8} else seconds)

    monkeypatch.setattr(module.asyncio, "sleep", sleep)


def session(*, ack=True, outcome="completed", model=None, scheduler=None):
    events = []
    audio_ended = asyncio.Event()

    async def emit(event):
        events.append(event)
        if event["type"] == "audio_end":
            audio_ended.set()
        if ack and event["type"] == "audio_end":
            engine.acknowledge(event["utterance_id"], event["generation"], outcome)

    engine = GroupCallSession(
        roles=[role("甲"), role("乙")], model=model or Model(), speech=Speech(), emit=emit
    )
    engine.strict_playback = engine.started = True
    engine.audio_ended_for_test = audio_ended
    engine.discussion.scheduler = scheduler or Scheduler()
    engine.discussion.state.enabled = True
    engine.discussion.state.topic = "什么时候结婚合适"
    return engine, events


@pytest.mark.parametrize("limit", [30, 40, 50])
@pytest.mark.asyncio
async def test_exact_completed_turn_limit_and_current_context(limit, fast_sleep):
    engine, events = session()
    state = engine.discussion.state
    state.max_silent_turns = GroupCallSettings(max_silent_turns=limit).max_silent_turns
    await engine.discussion.run(0, 0)
    assert state.ai_silent_turns == state.call_total_ai_turns == limit
    assert state.phase == "idle" and state.stop_reason == "turn_limit"
    assert len([e for e in events if e["type"] == "speaker"]) == limit
    assert engine.discussion.scheduler.seen[1] == [engine.call_log[0]["text"]]
    assert state.topic_summary and engine.metrics["tts_requests"] == limit
    assert "系统限制" in engine.model.requests[-1][0].content
    await engine.close()


@pytest.mark.asyncio
async def test_partial_preserves_count_final_resets_and_prioritizes_named_role(fast_sleep):
    engine, _ = session(scheduler=Scheduler(["finish"]))
    state = engine.discussion.state
    state.ai_silent_turns = state.call_total_ai_turns = 29
    state.phase = "discussing"
    await engine.partial("乙")
    assert state.ai_silent_turns == 29 and state.phase == "user_interrupting"
    await engine.sentence("乙你怎么看？")
    await engine.debounce
    await engine.task
    assert state.ai_silent_turns == 0 and state.call_total_ai_turns == 29
    assert state.episode_id == 1
    from bingo.services.group_call_scheduler import TurnScheduler

    chosen = await TurnScheduler().next_turn(engine, state)
    assert chosen.speaker_id == "乙"
    await engine.close()


@pytest.mark.asyncio
async def test_false_partial_recovers_without_new_episode_but_pause_does_not(fast_sleep):
    engine, _ = session(scheduler=Scheduler(["finish"]))
    state = engine.discussion.state
    state.ai_silent_turns = 18
    state.phase = "discussing"
    engine.partial_quiet_seconds = 0.001
    await engine.partial("噪声")
    await engine.recovery
    await engine.task
    assert state.ai_silent_turns == 18 and state.episode_id == 0
    await engine.discussion.pause()
    await engine.partial("疑似回声")
    await engine.recovery
    assert state.phase == "paused"
    await engine.close()


@pytest.mark.asyncio
async def test_receipts_are_generation_bound_idempotent_and_ignore_early_ack(fast_sleep):
    engine, events = session(ack=False)
    assert not engine.acknowledge(None, 0)
    task = asyncio.create_task(engine.say(engine.roles[0], "你好", 0, autonomous=True))
    await asyncio.wait_for(engine.audio_ended_for_test.wait(), 0.5)
    identifier = engine.utterance
    assert not engine.acknowledge(identifier, 9)
    assert not engine.acknowledge(identifier)
    assert not engine.history
    assert engine.acknowledge(identifier, 0)
    assert not engine.acknowledge(identifier, 0)
    assert await task == PlaybackResult.COMPLETED
    assert engine.discussion.state.ai_silent_turns == 1
    assert len(engine.history) == 1
    await engine.close()


@pytest.mark.parametrize("outcome", ["failed", "timeout", "interrupted"])
@pytest.mark.asyncio
async def test_failed_playback_never_advances_or_enters_heard_history(outcome, fast_sleep):
    engine, events = session(outcome=outcome)
    await engine.discussion.run(0, 0)
    assert engine.discussion.state.ai_silent_turns == 0
    assert not engine.history
    assert len([e for e in events if e["type"] == "speaker"]) == 1
    assert engine.call_log[0]["status"] == outcome
    assert engine.discussion.state.phase == "idle"
    await engine.close()


@pytest.mark.asyncio
async def test_stop_is_immediate_even_if_old_model_needs_cleanup(fast_sleep):
    entered, release = asyncio.Event(), asyncio.Event()

    class Slow:
        async def complete(self, messages):
            entered.set()
            try:
                await asyncio.Event().wait()
            except asyncio.CancelledError:
                await release.wait()
                return "过期回复"

    engine, events = session(model=Slow())
    engine.task = asyncio.create_task(engine.discussion.run(0, 0))
    await entered.wait()
    await asyncio.wait_for(engine.discussion.pause(), 0.1)
    assert any(e["type"] == "interrupted" for e in events)
    assert engine.discussion.state.phase == "paused"
    release.set()
    await asyncio.sleep(0.01)
    assert not any(e["type"] == "speaker" for e in events)
    await engine.close()


@pytest.mark.asyncio
async def test_natural_finish_yields_and_silence_do_not_fill_the_quota(fast_sleep):
    for scheduler in [Scheduler(["finish"]), Scheduler(["yield"] * 9)]:
        engine, _ = session(scheduler=scheduler)
        await engine.discussion.run(0, 0)
        assert engine.discussion.state.ai_silent_turns == 0
        assert len(scheduler.seen) <= 3
        await engine.close()

    class Silent(Model):
        async def complete(self, messages):
            return "[沉默]"

    engine, _ = session(model=Silent())
    await engine.discussion.run(0, 0)
    assert engine.discussion.state.stop_reason == "no_new_content"
    assert engine.metrics["model_requests"] == 2
    await engine.close()


@pytest.mark.asyncio
async def test_limits_budget_and_stale_summary(fast_sleep):
    engine, _ = session()
    assert engine.discussion.state.max_silent_turns == 30
    for invalid in [True, 0, 101, "40", None, [], 40.0]:
        with pytest.raises(ValidationError):
            GroupCallSettings(max_silent_turns=invalid)
    state = engine.discussion.state
    state.ai_silent_turns = 35
    await engine.discussion.run(0, 0)
    assert state.ai_silent_turns == 35 and engine.metrics["model_requests"] == 0
    engine.discussion.user_committed()
    engine.max_model_requests = 1
    await engine.discussion.run(0, state.episode_id)
    assert engine.metrics["model_requests"] == 1
    assert state.stop_reason == "call_budget"
    engine.max_model_requests = 400
    state.call_total_ai_turns = 8
    generation = engine.generation
    engine.discussion.user_committed()
    await engine.discussion.summarize(generation, state.episode_id - 1)
    assert not state.topic_summary
    engine.call_started = time.monotonic() - engine.max_call_seconds - 1
    assert not engine.within_budget()
    await engine.close()


@pytest.mark.asyncio
async def test_legacy_client_keeps_compatible_bounded_response(fast_sleep):
    engine, events = session(scheduler=Scheduler(["finish"]))
    engine.started = False
    engine.start(strict_playback=False)
    await engine.task
    assert not engine.discussion.state.enabled
    assert not engine.discussion.scheduler.seen
    assert engine.discussion.state.ai_silent_turns == 0
    await engine.close()


@pytest.mark.asyncio
async def test_missing_ack_stops_without_counting_or_hanging(fast_sleep):
    engine, _ = session(ack=False)
    engine.playback_timeout = 0.01
    await asyncio.wait_for(engine.discussion.run(0, 0), 0.5)
    assert engine.discussion.state.stop_reason == "playback_timeout"
    assert engine.discussion.state.ai_silent_turns == 0
    assert not engine.history
    await engine.close()


@pytest.mark.asyncio
async def test_expired_episode_and_cancelled_audio_cannot_write_new_segment(fast_sleep):
    engine, _ = session(ack=False)
    engine.task = asyncio.create_task(engine.discussion.run(0, 0))
    await asyncio.wait_for(engine.audio_ended_for_test.wait(), 0.5)
    identifier, generation = engine.utterance, engine.generation
    await engine.partial("我来说一句")
    await engine.sentence("你们先停一下")
    await engine.debounce
    await engine.task
    assert engine.discussion.state.episode_id == 1
    assert not engine.acknowledge(identifier, generation)
    assert engine.discussion.state.ai_silent_turns == 0
    assert engine.discussion.state.phase == "paused"
    assert engine.call_log[0]["status"] == "interrupted"
    await engine.close()
    assert not engine.retired


@pytest.mark.asyncio
async def test_start_switch_topic_and_resume_preserve_call_statistics(fast_sleep):
    engine, _ = session(scheduler=Scheduler(["finish"] * 3))
    state = engine.discussion.state
    state.enabled = False
    engine.history.append({"name": "用户", "role_id": None, "text": "最近心情不太好"})
    await engine.discussion.handle_user("最近心情不太好", 0, 0)
    assert state.enabled and state.phase == "idle"

    class Topic(Model):
        async def complete(self, messages):
            return '{"action":"continue","topic":"工作"}'

    engine.model = Topic()
    state.call_total_ai_turns = 27
    engine.discussion.user_committed()
    await engine.discussion.handle_user("别聊结婚了，改聊工作", 0, state.episode_id)
    assert state.topic == "工作" and state.call_total_ai_turns == 27
    await engine.discussion.pause()
    engine.discussion.user_committed()
    await engine.discussion.handle_user("最近心情不太好", engine.generation, state.episode_id)
    assert state.phase == "idle"
    assert state.call_total_ai_turns == 27 and state.ai_silent_turns == 0
    await engine.close()


@pytest.mark.asyncio
async def test_call_ready_automatically_starts_once_without_controls(fast_sleep):
    engine, events = session(scheduler=Scheduler(["finish"]))
    engine.started = False
    engine.start(strict_playback=True)
    first = engine.task
    engine.start(strict_playback=True)
    assert engine.task is first
    await engine.task
    assert engine.discussion.state.enabled
    assert engine.discussion.state.episode_id == 0
    assert engine.discussion.state.max_silent_turns == 30
    assert len(engine.discussion.scheduler.seen) == 1
    assert len([e for e in events if e["type"] == "speaker"]) == 1
    await engine.close()


@pytest.mark.asyncio
async def test_episode_deadline_during_playback_clears_audio_and_returns_to_listening(fast_sleep):
    engine, events = session(ack=False)
    engine.discussion.max_episode_seconds = 0.02
    await asyncio.wait_for(engine.discussion.run(0, 0), 0.5)
    assert engine.discussion.state.stop_reason == "duration_limit"
    assert engine.discussion.state.phase == "idle"
    assert engine.discussion.state.ai_silent_turns == 0
    assert any(e["type"] == "interrupted" for e in events)
    assert events[-1]["type"] == "listening"
    await engine.close()


@pytest.mark.parametrize(
    "text", ["最近心情不太好", "帮我想想明天早餐吃什么", "你们辩论一下经济和感情哪个重要"]
)
@pytest.mark.asyncio
async def test_every_user_contribution_enters_natural_conversation_without_opt_in(text, fast_sleep):
    engine, events = session(scheduler=Scheduler(["speak", "finish"]))
    state = engine.discussion.state
    state.enabled = False
    state.phase = "paused"
    state.topic = ""
    engine.history.append({"name": "用户", "role_id": None, "text": text})
    engine.discussion.user_committed()
    await engine.discussion.handle_user(text, 0, state.episode_id)
    assert state.enabled and state.topic == text
    assert state.ai_silent_turns == 1
    assert any(e["type"] == "speaker" for e in events)
    assert not any(e["type"] == "command_error" for e in events)
    await engine.close()
