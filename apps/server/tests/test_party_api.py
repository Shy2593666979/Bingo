import asyncio
import base64
import struct
import threading
import time

from bingo.api.party_voice import playback_echo
from tests.api_support import api_payload
from tests.test_api import client as _base_client
from tests.test_party_games import Decision, Model, wait_idle

client = _base_client


def hangup(socket):
    socket.send_json({"type": "hangup"})
    for _ in range(30):
        if socket.receive()["type"] == "websocket.close":
            return
    raise AssertionError("Voice session did not close")


def test_short_answers_and_post_playback_repetition_are_not_discarded_as_echo():
    prompt = "你想选择真心话还是大冒险？"
    assert not playback_echo("真心话", prompt, True)
    assert not playback_echo(prompt, prompt, False)
    assert playback_echo(prompt, prompt, True)


def test_slow_tts_is_cancelled_and_pause_state_arrives_without_waiting(client, monkeypatch):
    identifier, service = create_game(client)
    settings = client.app.state.settings
    settings.asr.api_key = settings.realtime_call.api_key = "test-only"
    started, cancelled = threading.Event(), threading.Event()

    class ASR:
        def __init__(self, **kwargs):
            pass

        async def run(self, bridge, **kwargs):
            await bridge.send_json({"type": "ready"})
            while True:
                if (await bridge.receive()).get("text"):
                    return

    class SlowSpeech:
        async def message_events(self, text, voice):
            started.set()
            try:
                await asyncio.sleep(3)
                yield {"type": "audio_done"}
            finally:
                cancelled.set()

    monkeypatch.setattr("bingo.api.party_voice.RealtimeAsrProxy", ASR)
    client.app.state.services.chat_speech = SlowSpeech()
    with client.websocket_connect(f"/api/v1/games/{identifier}/voice") as socket:
        assert socket.receive_json()["type"] == "ready"
        socket.send_json({"type": "client_audio_ready"})
        while True:
            event = socket.receive_json()
            if event["type"] == "game_state":
                snapshot = event["state"]
                if snapshot["options"]:
                    break
        socket.send_json(
            {
                "type": "game_choice",
                "value": "truth",
                "revision": snapshot["revision"],
                "stage": snapshot["action_stage"],
            }
        )
        assert started.wait(2)
        start = time.monotonic()
        socket.send_json({"type": "game_action", "action": "pause"})
        while True:
            event = socket.receive_json()
            if event["type"] == "game_state" and event["state"]["paused"]:
                break
        assert time.monotonic() - start < 1.5
        assert cancelled.wait(0.5)
        hangup(socket)


def create_game(client):
    service = client.app.state.party_games
    service.ai.decision, service.ai.model = Decision(), Model()
    ids = [role["id"] for role in api_payload(client.get("/api/v1/roles"))[:2]]
    response = client.post("/api/v1/games", json={"mode": "truth", "role_ids": ids})
    assert response.status_code == 201
    identifier = api_payload(response)["id"]
    client.portal.call(wait_idle, service)
    return identifier, service


def test_authenticated_api_roundtrip_and_duplicate_action(client):
    identifier, service = create_game(client)
    url = f"/api/v1/games/{identifier}"
    snapshot = api_payload(client.get(url))
    assert snapshot["phase"] == "choose"
    body = {
        "type": "choice",
        "value": "truth",
        "revision": snapshot["revision"],
        "command_id": "choice-once",
    }
    assert client.post(url + "/actions", json=body).status_code == 200
    client.portal.call(wait_idle, service)
    after = api_payload(client.get(url))
    assert after["phase"] == "answer" and after["messages"]
    ai_msg = next(m for m in after["messages"] if m["speaker"] not in {None, "self"})

    class FakeSpeech:
        async def message_events(self, text, voice):
            yield {"type": "audio", "data": base64.b64encode(b"pcm-bytes").decode()}
            yield {"type": "audio_done"}

    client.app.state.services.chat_speech = FakeSpeech()
    speech_resp = client.post(f"{url}/messages/{ai_msg['id']}/speech")
    assert speech_resp.status_code == 200
    assert "pcm-bytes" in base64.b64decode(
        speech_resp.text.splitlines()[0].split('"data": "')[1].split('"')[0]
    ).decode()
    duplicate = api_payload(client.post(url + "/actions", json=body))
    assert duplicate["revision"] == after["revision"]
    assert client.post(url + "/actions", json={**body, "type": "voice_start"}).status_code == 422
    token = client.headers.pop("Authorization")
    assert client.get(url).status_code == 401
    client.headers["Authorization"] = token
    assert api_payload(client.get("/api/v1/games"))[0]["id"] == identifier


def test_voice_uses_real_protocol_and_does_not_advance_until_played(client, monkeypatch):
    identifier, service = create_game(client)
    settings = client.app.state.settings
    settings.asr.api_key = settings.realtime_call.api_key = "test-transport-only"

    class ASR:
        def __init__(self, **kwargs):
            pass

        async def run(self, bridge, **kwargs):
            await bridge.send_json({"type": "ready"})
            first = True
            while True:
                event = await bridge.receive()
                if event.get("text"):
                    return
                if first:
                    first = False
                    await bridge.send_json({"type": "sentence", "text": "我选真心话"})

    class VoiceDecision(Decision):
        async def decide(self, state, candidates, instructions):
            if "option:truth" in candidates:
                return "option:truth"
            return await super().decide(state, candidates, instructions)

    class Speech:
        async def message_events(self, text, voice):
            yield {
                "type": "audio",
                "data": base64.b64encode(bytes(480)).decode(),
                "sample_rate": 24000,
            }
            yield {"type": "audio_done"}

    service.ai.decision = VoiceDecision()
    client.app.state.services.chat_speech = Speech()
    monkeypatch.setattr("bingo.api.party_voice.RealtimeAsrProxy", ASR)
    with client.websocket_connect(f"/api/v1/games/{identifier}/voice") as socket:
        assert socket.receive_json()["type"] == "ready"
        socket.send_json({"type": "client_audio_ready", "playback_results": True})
        # 400 ms PCM16 energy evidence, not an empty/noisy partial.
        pcm = struct.pack("<" + "h" * 6400, *([900, -900] * 3200))
        socket.send_bytes(pcm)
        events = []
        while True:
            event = socket.receive_json()
            events.append(event)
            if event["type"] == "audio_end":
                break
            assert len(events) < 30
        assert any(event["type"] == "audio" for event in events)
        pending = api_payload(client.get(f"/api/v1/games/{identifier}"))
        assert pending["playback"] == event["utterance_id"]
        socket.send_json(
            {
                "type": "played",
                "generation": event["generation"],
                "utterance_id": event["utterance_id"],
                "status": "completed",
            }
        )
        hangup(socket)
    final = api_payload(client.get(f"/api/v1/games/{identifier}"))
    assert final["playback"] is None
