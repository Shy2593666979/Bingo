import asyncio
from array import array

import pytest

from bingo.services.group_call_barge_in import BargeInEvidence
from tests.test_group_call_discussion import Scheduler, session


def activity(milliseconds, amplitude=1000):
    return array("h", [amplitude] * (16000 * milliseconds // 1000)).tobytes()


def test_audio_evidence_rejects_short_impacts_and_expires():
    now = [0.0]
    evidence = BargeInEvidence(clock=lambda: now[0])
    evidence.observe(activity(40, 15000))
    evidence.observe(activity(300, 0))
    assert not evidence.supports_speech(final=True)
    evidence.observe(activity(240))
    assert evidence.supports_speech()
    now[0] = 2
    assert not evidence.supports_speech()


@pytest.mark.asyncio
async def test_unstable_fragment_does_not_cancel_discussion_or_prefetch():
    engine, events = session()
    engine.require_audio_evidence = True
    running = asyncio.create_task(asyncio.Event().wait())
    engine.task = running
    engine.barge_in.observe(activity(40, 20000))
    await engine.partial("啊")
    await engine.partial_candidate
    assert not running.done()
    assert engine.generation == 0
    assert not any(e["type"] == "interrupted" for e in events)
    await engine.close()


@pytest.mark.asyncio
async def test_confirmed_activity_interrupts_once_duplicates_do_not_extend_recovery():
    engine, events = session()
    engine.require_audio_evidence = True
    engine.discussion.state.phase = "discussing"
    engine.discussion.state.ai_silent_turns = 18
    engine.barge_in.observe(activity(260))
    await engine.partial("等等")
    await engine.partial_candidate
    recovery = engine.recovery
    assert engine.generation == 1 and engine.user_speaking
    assert engine.discussion.state.ai_silent_turns == 18
    for text in ["等等", "等等。", "等等！"]:
        await engine.partial(text)
    assert engine.recovery is recovery
    assert len([e for e in events if e["type"] == "interrupted"]) == 1
    await engine.close()


@pytest.mark.asyncio
async def test_one_character_final_can_interrupt_without_waiting_for_partial():
    engine, events = session(scheduler=Scheduler(["finish"]))
    engine.require_audio_evidence = True
    engine.barge_in.observe(activity(140))
    await engine.sentence("停")
    assert engine.generation == 1
    assert any(e["type"] == "interrupted" for e in events)
    await engine.debounce
    await engine.task
    assert engine.discussion.state.episode_id == 1
    await engine.close()


@pytest.mark.asyncio
async def test_empty_final_resumes_quickly_without_resetting_episode():
    engine, _ = session(scheduler=Scheduler(["finish"]))
    engine.require_audio_evidence = True
    engine.discussion.state.phase = "discussing"
    engine.discussion.state.ai_silent_turns = 18
    engine.barge_in.observe(activity(260))
    await engine.partial("疑似人声")
    await engine.partial_candidate
    await engine.sentence("")
    await asyncio.wait_for(engine.recovery, 0.7)
    await engine.task
    assert not engine.user_speaking
    assert engine.discussion.state.ai_silent_turns == 18
    assert engine.discussion.state.episode_id == 0
    await engine.close()


@pytest.mark.asyncio
async def test_playback_text_echo_does_not_interrupt():
    engine, events = session()
    engine.require_audio_evidence = True
    engine.playback_record = {"status": "speaking", "text": "我们刚才讨论的是工作和生活的平衡"}
    engine.barge_in.observe(activity(400))
    await engine.partial("我们刚才讨论的是工作")
    await engine.sentence("我们刚才讨论的是工作和生活的平衡")
    assert engine.generation == 0
    assert not any(e["type"] == "interrupted" for e in events)
    engine.playback_record = None
    await engine.close()
