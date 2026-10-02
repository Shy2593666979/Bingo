import base64

import httpx
import pytest

from bingo.config import Settings
from bingo.db.models import VoiceJob
from bingo.services.voice_cloning import VoiceCloningService, VoiceProviderError, pcm_has_signal


@pytest.mark.asyncio
@pytest.mark.parametrize(
    "code, message",
    [
        ("Audio.AudioSilentError", "未检测到足够的人声"),
        ("Audio.AudioShortError", "有效人声太短"),
    ],
)
async def test_provider_silence_error_is_specific_and_does_not_log_private_data(
    monkeypatch, caplog, code, message
):
    mock_http(
        monkeypatch,
        lambda request: httpx.Response(
            400,
            json={
                "code": code,
                "message": "silent audio https://private.example/token",
            },
        ),
    )
    service = VoiceCloningService(None, Settings(realtime_call={"api_key": "test-key"}))
    with pytest.raises(VoiceProviderError, match=message):
        await service.request("create_voice")
    assert code in caplog.text
    assert "private.example" not in caplog.text
    assert "test-key" not in caplog.text


def test_pcm_signal_detection():
    assert not pcm_has_signal(bytes(32000))
    assert not pcm_has_signal(b"\x01\x00" * 16000)
    assert pcm_has_signal(b"\x14\x00\xec\xff")


@pytest.mark.asyncio
async def test_upload_502_falls_back_to_public_backend(monkeypatch):
    mock_http(monkeypatch, lambda request: httpx.Response(502))
    service = VoiceCloningService(None, Settings())
    job = VoiceJob(
        user_id="user",
        role_id="role",
        sample=base64.b64encode(b"wav").decode(),
        public_base_url="https://agentchat.cloud/bingo/api/v1",
        sample_token="random",
    )
    url, uploaded = await service.sample_url(job)
    assert url == "https://agentchat.cloud/bingo/api/v1/role-voice-samples/random"
    assert uploaded is None


@pytest.mark.asyncio
async def test_upload_failure_does_not_use_private_backend(monkeypatch):
    mock_http(monkeypatch, lambda request: httpx.Response(502))
    service = VoiceCloningService(None, Settings())
    job = VoiceJob(
        user_id="user",
        role_id="role",
        sample=base64.b64encode(b"wav").decode(),
        public_base_url="https://127.0.0.1/api/v1",
        sample_token="random",
    )
    with pytest.raises(httpx.HTTPStatusError):
        await service.sample_url(job)


def mock_http(monkeypatch, handler):
    client_type = httpx.AsyncClient
    monkeypatch.setattr(
        httpx,
        "AsyncClient",
        lambda **kwargs: client_type(transport=httpx.MockTransport(handler), **kwargs),
    )


@pytest.mark.asyncio
async def test_yukisbox_upload_uses_wav_and_download_limit(monkeypatch):
    def handler(request):
        assert str(request.url) == "https://yukisbox.com/upload"
        assert request.method == "POST"
        assert b"audio/wav" in request.content
        assert b"RIFF-test" in request.content
        assert b'name="max_downloads"\r\n\r\n10' in request.content
        return httpx.Response(
            200, json={"success": True, "url": "https://yukisbox.com/file/random"}
        )

    mock_http(monkeypatch, handler)
    service = VoiceCloningService(None, Settings())
    job = VoiceJob(user_id="user", role_id="role", sample=base64.b64encode(b"RIFF-test").decode())
    assert await service.upload_sample(job) == "https://yukisbox.com/file/random"


@pytest.mark.asyncio
@pytest.mark.parametrize(
    "url",
    ["http://yukisbox.com/file/id", "https://localhost/file/id", "https://yukisbox.com/login"],
)
async def test_upload_rejects_unexpected_download_urls(monkeypatch, url):
    mock_http(monkeypatch, lambda request: httpx.Response(200, json={"success": True, "url": url}))
    service = VoiceCloningService(None, Settings())
    job = VoiceJob(user_id="user", role_id="role", sample=base64.b64encode(b"wav").decode())
    with pytest.raises(ValueError, match="下载地址"):
        await service.upload_sample(job)


@pytest.mark.asyncio
async def test_cleanup_stops_when_sample_is_unavailable(monkeypatch):
    requests = []

    def handler(request):
        requests.append(request)
        return httpx.Response(200 if len(requests) < 3 else 404, content=b"wav")

    mock_http(monkeypatch, handler)
    await VoiceCloningService(None, Settings()).cleanup_sample("https://yukisbox.com/file/random")
    assert len(requests) == 3


@pytest.mark.asyncio
async def test_cleanup_failure_is_logged_without_leaking_sample_url(monkeypatch, caplog):
    mock_http(monkeypatch, lambda request: httpx.Response(503))
    await VoiceCloningService(None, Settings()).cleanup_sample("https://yukisbox.com/file/secret")
    assert "cleanup failed" in caplog.text
    assert "secret" not in caplog.text
