import asyncio
import base64

import pytest

from tests.test_group_call_discussion import Model, Scheduler, session


class Chunks:
    def __init__(self):
        self.started = []
        self.pulled = {}
        self.closed = set()
        self.next_ready = asyncio.Event()

    async def message_events(self, text, voice):
        self.started.append(voice)
        self.pulled[voice] = 0
        try:
            for _ in range(3):
                self.pulled[voice] += 1
                if len(self.started) == 2:
                    self.next_ready.set()
                yield {"type": "audio", "data": base64.b64encode(bytes(480)).decode()}
            yield {"type": "audio_done"}
        finally:
            self.closed.add(voice)


async def ready(engine, speech):
    await asyncio.wait_for(speech.next_ready.wait(), 2)
    await asyncio.wait_for(engine.audio_ended_for_test.wait(), 2)


async def finish_two(engine):
    engine.audio_ended_for_test.clear()
    assert engine.acknowledge(engine.utterance, engine.generation)
    await asyncio.wait_for(engine.audio_ended_for_test.wait(), 2)
    assert engine.acknowledge(engine.utterance, engine.generation)
    await asyncio.wait_for(engine.task, 2)


@pytest.mark.parametrize("greeting", [False, True])
@pytest.mark.asyncio
async def test_next_text_and_first_audio_are_ready_before_ack_without_early_playback(greeting):
    engine, events = session(ack=False)
    speech = engine.speech = Chunks()
    engine.discussion.state.max_silent_turns = 2
    engine.task = asyncio.create_task(
        engine.open_conversation() if greeting else engine.discussion.run(0, 0)
    )
    try:
        await ready(engine, speech)
        first, following = speech.started
        assert len(engine.model.requests) == 2
        assert speech.pulled[first] == 3 and speech.pulled[following] == 1
        assert len([e for e in events if e["type"] == "speaker"]) == 1
        assert {e["utterance_id"] for e in events if e["type"] == "audio"} == {engine.utterance}
        assert len(engine.call_log) == 1 and not engine.history
        assert engine.discussion.state.ai_silent_turns == 0
        assert engine.call_log[0]["text"] in engine.model.requests[1][-1].content
        assert engine.discussion.scheduler.seen[-1][-1] == engine.call_log[0]["text"]
        await finish_two(engine)
        assert speech.started == [first, following]  # No duplicate synthesis on consumption.
        assert speech.closed == {first, following}
        assert engine.metrics["tts_requests"] == engine.metrics["completed_turns"] == 2
        assert engine.metrics["prefetched_audio_turns"] == 1
        assert engine.metrics["prefetch_requests"] == 1
        assert len(engine.history) == engine.discussion.state.ai_silent_turns == 2
    finally:
        await engine.close()


@pytest.mark.parametrize("action", ["interrupt", "close", "failed", "timeout"])
@pytest.mark.asyncio
async def test_prefetched_audio_is_discarded_on_interrupt_failure_or_hangup(action):
    engine, events = session(ack=False)
    speech = engine.speech = Chunks()
    engine.task = asyncio.create_task(engine.discussion.run(0, 0))
    try:
        await ready(engine, speech)
        first, following = speech.started
        if action == "interrupt":
            await engine.partial("等等，我想换个话题")
        elif action == "close":
            await engine.close()
        else:
            assert engine.acknowledge(engine.utterance, 0, action)
            await asyncio.wait_for(engine.task, 2)
        await engine.close()
        assert speech.pulled[following] == 1
        assert speech.closed == {first, following}
        assert len([e for e in events if e["type"] == "speaker"]) == 1
        assert engine.discussion.state.ai_silent_turns == 0 and not engine.history
        assert engine.discussion.prefetch is None
    finally:
        await engine.close()


@pytest.mark.asyncio
async def test_one_lookahead_only_and_slow_cancelled_model_cannot_publish_stale_result():
    entered, cancelled, release = asyncio.Event(), asyncio.Event(), asyncio.Event()

    class Slow(Model):
        async def complete(self, messages):
            if self.requests:
                self.requests.append(messages)
                entered.set()
                try:
                    await asyncio.Event().wait()
                except asyncio.CancelledError:
                    cancelled.set()
                    await release.wait()
                    return "这句已经过期，不可以播放。"
            return await super().complete(messages)

    engine, events = session(ack=False, model=Slow())
    engine.task = asyncio.create_task(engine.discussion.run(0, 0))
    try:
        await asyncio.wait_for(entered.wait(), 2)
        assert len(engine.model.requests) == 2
        await asyncio.wait_for(engine.partial("停一下"), 0.2)
        await asyncio.wait_for(cancelled.wait(), 2)
        assert any(e["type"] == "interrupted" for e in events)
        release.set()
        await engine.close()
        assert engine.metrics["tts_requests"] == 1
        assert len([e for e in events if e["type"] == "speaker"]) == 1
        assert not engine.history
    finally:
        release.set()
        await engine.close()


@pytest.mark.asyncio
async def test_episode_change_invalidates_pending_text_without_committing_predicted_counts():
    entered, release = asyncio.Event(), asyncio.Event()

    class Delayed(Model):
        async def complete(self, messages):
            entered.set()
            await release.wait()
            return await super().complete(messages)

    engine, _ = session(model=Delayed())
    controller = engine.discussion
    context = controller.turn_context((engine.roles[0], "这句正在播放。"))
    task = asyncio.create_task(controller.prepare_turn(0, 0, context))
    try:
        await entered.wait()
        controller.user_committed()
        release.set()
        result = await task
        assert result.audio is None
        assert not engine.history and engine.metrics["tts_requests"] == 0
        assert controller.state.ai_silent_turns == controller.state.call_total_ai_turns == 0
    finally:
        release.set()
        await asyncio.gather(task, return_exceptions=True)
        await engine.close()


@pytest.mark.asyncio
async def test_prefetched_finish_waits_for_current_speech_and_real_ack_timeout_cleans_up():
    engine, events = session(ack=False, scheduler=Scheduler(["speak", "finish"]))
    engine.playback_timeout = 0.03
    engine.task = asyncio.create_task(engine.discussion.run(0, 0))
    try:
        await asyncio.wait_for(engine.audio_ended_for_test.wait(), 2)
        assert engine.discussion.state.phase != "idle"
        await asyncio.wait_for(engine.task, 2)
        assert not engine.history and engine.discussion.state.ai_silent_turns == 0
        assert engine.call_log[0]["status"] == "timeout"
        assert len([e for e in events if e["type"] == "speaker"]) == 1
        assert engine.discussion.prefetch is None
    finally:
        await engine.close()


@pytest.mark.asyncio
async def test_failure_while_prefetching_audio_retries_only_when_that_speaker_is_due():
    class Transient:
        def __init__(self):
            self.calls = 0
            self.failed = asyncio.Event()

        async def message_events(self, text, voice):
            self.calls += 1
            if self.calls == 2:
                self.failed.set()
                yield {"type": "audio_error"}
            else:
                yield {"type": "audio", "data": base64.b64encode(bytes(480)).decode()}
                yield {"type": "audio_done"}

    engine, events = session(ack=False)
    speech = engine.speech = Transient()
    engine.discussion.state.max_silent_turns = 2
    engine.task = asyncio.create_task(engine.discussion.run(0, 0))
    try:
        await asyncio.wait_for(speech.failed.wait(), 2)
        await asyncio.wait_for(engine.audio_ended_for_test.wait(), 2)
        assert speech.calls == 2
        assert len([e for e in events if e["type"] == "speaker"]) == 1
        await finish_two(engine)
        assert speech.calls == 3
        assert engine.discussion.state.ai_silent_turns == 2
        assert not any(e["type"] == "participant_error" for e in events)
    finally:
        await engine.close()
