import asyncio
import base64
import io
import json
import logging
import re
import struct
import wave
from collections import OrderedDict
from datetime import timedelta
from ipaddress import ip_address
from time import monotonic
from urllib.parse import urlsplit

import httpx
from sqlmodel import select
from websockets.asyncio.client import connect

from bingo.db.models import Role, VoiceJob
from bingo.db.time import beijing_now
from bingo.services.realtime_call import _model_url, derive_realtime_url

logger = logging.getLogger(__name__)


class VoiceProviderError(ValueError):
    pass


def provider_error_message(code: str) -> str:
    return {
        "Audio.AudioSilentError": "未检测到足够的人声，请检查麦克风并连续朗读 20～30 秒后重试",
        "Audio.AudioRateError": "录音采样率不受支持，请更新应用后重新录制",
        "Audio.DecoderError": "录音文件无法解码，请重新录制",
        "Audio.PreprocessError": "录音质量不符合要求，请在安静环境中清晰朗读后重试",
        "BadRequest.UnsupportedFileFormat": "录音格式不受支持，请更新应用后重新录制",
    }.get(code, "声音服务处理失败，请稍后重试")


PREVIEW_TEXT = (
    "你好，很高兴能用这样的声音与你见面。今天过得怎么样？"
    "不管是开心的小事，还是暂时让你烦恼的事情，你都可以慢慢说给我听。"
    "生活有时候会走得很快，但我们可以放慢一点，喝一口水，深呼吸，"
    "给自己留一点休息的时间。希望以后的每一天，我都能陪你聊聊生活，"
    "分享你的快乐，也认真听你说心里的话。"
)


def pcm_wav(audio: bytes, sample_rate: int = 16000) -> bytes:
    output = io.BytesIO()
    with wave.open(output, "wb") as recording:
        recording.setnchannels(1)
        recording.setsampwidth(2)
        recording.setframerate(sample_rate)
        recording.writeframes(audio)
    return output.getvalue()


def pcm_has_signal(audio: bytes) -> bool:
    lowest, highest = 32767, -32768
    for (sample,) in struct.iter_unpack("<h", audio):
        lowest = min(lowest, sample)
        highest = max(highest, sample)
        if highest - lowest >= 32:
            return True
    return False


class VoiceCloningService:
    def __init__(self, database, settings) -> None:
        self.database = database
        self.settings = settings
        self.tasks: set[asyncio.Task] = set()
        self.running_ids: set[str] = set()
        self.cleanup_worker: asyncio.Task | None = None
        self.preview_cache: OrderedDict[str, tuple[float, bytes]] = OrderedDict()
        self.preview_tasks: dict[str, asyncio.Task] = {}
        self.stages: dict[str, str] = {}

    @property
    def endpoint(self) -> str:
        configured = self.settings.voice_cloning.endpoint
        if configured:
            return configured
        host = urlsplit(self.settings.asr.realtime.url).netloc
        return f"https://{host}/api/v1/services/audio/tts/customization"

    async def start(self) -> None:
        async with self.database.session_factory() as session:
            jobs = (
                await session.exec(
                    select(VoiceJob).where(VoiceJob.status.in_(["pending", "processing"]))
                )
            ).all()
            for job in jobs:
                if job.kind == "clone" and job.created_at < beijing_now() - timedelta(minutes=10):
                    job.status = "failed"
                    job.error = "录音已过期，请重新录制"
                    job.sample = None
                    job.sample_token = None
                else:
                    self.schedule(job.id)
            await session.commit()
        self.cleanup_worker = asyncio.create_task(self.retry_cleanup())

    async def retry_cleanup(self) -> None:
        while True:
            await asyncio.sleep(30)
            async with self.database.session_factory() as session:
                jobs = (
                    await session.exec(
                        select(VoiceJob).where(
                            VoiceJob.kind.in_(["delete", "delete_prefix"]),
                            VoiceJob.status == "failed",
                        )
                    )
                ).all()
                for job in jobs:
                    self.schedule(job.id)

    def schedule(self, job_id: str) -> None:
        if job_id in self.running_ids:
            return
        self.running_ids.add(job_id)
        task = asyncio.create_task(self.process(job_id))
        self.tasks.add(task)
        task.add_done_callback(self.tasks.discard)
        task.add_done_callback(lambda _: self.running_ids.discard(job_id))

    async def close(self) -> None:
        if self.cleanup_worker:
            self.cleanup_worker.cancel()
            await asyncio.gather(self.cleanup_worker, return_exceptions=True)
        for task in list(self.tasks):
            task.cancel()
        if self.tasks:
            await asyncio.gather(*self.tasks, return_exceptions=True)

    async def request(self, action: str, **values) -> dict:
        key = self.settings.realtime_call.api_key
        if not key:
            raise ValueError("服务器尚未配置声音复刻，请联系管理员")
        async with httpx.AsyncClient(timeout=self.settings.voice_cloning.timeout_seconds) as client:
            response = await client.post(
                self.endpoint,
                headers={"Authorization": f"Bearer {key}"},
                json={"model": "voice-enrollment", "input": {"action": action, **values}},
            )
            try:
                payload = response.json()
            except ValueError:
                response.raise_for_status()
                raise VoiceProviderError("声音服务返回异常，请稍后重试") from None
            if response.is_error or payload.get("code"):
                code = re.sub(r"[^a-zA-Z0-9_.-]", "", str(payload.get("code", "Unknown")))[:100]
                logger.error(
                    "Voice provider rejected action=%s status=%s code=%s",
                    action,
                    response.status_code,
                    code,
                )
                raise VoiceProviderError(provider_error_message(code))
            return payload.get("output", {})

    async def upload_sample(self, job: VoiceJob) -> str:
        if not job.sample:
            raise ValueError("录音已过期，请重新录制")
        endpoint = self.settings.voice_cloning.upload_endpoint
        async with httpx.AsyncClient(timeout=60) as client:
            response = await client.post(
                endpoint,
                files={"file": ("voice-sample.wav", base64.b64decode(job.sample), "audio/wav")},
                data={"max_downloads": "10"},
            )
            response.raise_for_status()
            payload = response.json()
        url = payload.get("url", "")
        parsed = urlsplit(url)
        if (
            payload.get("success") is not True
            or parsed.scheme != "https"
            or parsed.netloc != urlsplit(endpoint).netloc
            or not parsed.path.startswith("/file/")
            or parsed.query
            or parsed.fragment
        ):
            raise ValueError("录音上传未返回有效下载地址")
        return url

    async def cleanup_sample(self, url: str) -> None:
        try:
            async with asyncio.timeout(60), httpx.AsyncClient(timeout=10) as client:
                for _ in range(11):
                    response = await client.get(url)
                    if response.status_code == 404:
                        return
                    response.raise_for_status()
            logger.warning("Temporary voice sample remained accessible after cleanup")
        except Exception as error:
            logger.warning("Temporary voice sample cleanup failed: %s", type(error).__name__)

    def public_sample_url(self, job: VoiceJob) -> str | None:
        parsed = urlsplit(job.public_base_url)
        host = parsed.hostname or ""
        if (
            parsed.scheme != "https"
            or not host
            or parsed.username
            or parsed.password
            or parsed.query
            or parsed.fragment
            or host == "localhost"
            or host.endswith(".local")
        ):
            return None
        try:
            if not ip_address(host).is_global:
                return None
        except ValueError:
            pass
        return f"{job.public_base_url.rstrip('/')}/role-voice-samples/{job.sample_token}"

    async def sample_url(self, job: VoiceJob) -> tuple[str, str | None]:
        public_url = self.public_sample_url(job)
        if self.settings.voice_cloning.sample_host == "public_url":
            if not public_url:
                raise ValueError("录音下载需要公网 HTTPS 地址")
            return public_url, None
        try:
            uploaded = await self.upload_sample(job)
            return uploaded, uploaded
        except (httpx.HTTPError, ValueError) as error:
            if not public_url:
                raise
            logger.warning(
                "Voice upload unavailable; using backend download: %s", type(error).__name__
            )
            return public_url, None

    async def process(self, job_id: str) -> None:
        async with self.database.session_factory() as session:
            job = await session.get(VoiceJob, job_id)
            if not job:
                return
            job.status = "processing"
            await session.commit()
            uploaded_url = None
            try:
                if job.kind == "delete":
                    self.preview_cache.pop(job.voice, None)
                    await self.request("delete_voice", voice_id=job.voice)
                elif job.kind == "delete_prefix":
                    listed = await self.request("list_voice", prefix=job.voice, page_size=100)
                    for item in listed.get("voice_list", []):
                        identifier = item.get("voice_id", "")
                        if identifier.startswith(
                            f"{self.settings.realtime_call.model}-{job.voice}-"
                        ):
                            await self.request("delete_voice", voice_id=identifier)
                else:
                    prefix = "u" + job.id.replace("-", "")[:9]
                    existing = await self.request("list_voice", prefix=prefix, page_size=10)
                    voices = existing.get("voice_list", [])
                    voice = next(
                        (
                            item["voice_id"]
                            for item in voices
                            if item.get("voice_id", "").startswith(
                                f"{self.settings.realtime_call.model}-{prefix}-"
                            )
                            and item.get("status") == "OK"
                        ),
                        "",
                    )
                    if not voice:
                        self.stages[job.id] = "uploading"
                        sample_url, uploaded_url = await self.sample_url(job)
                        self.stages[job.id] = "cloning"
                        created = await self.request(
                            "create_voice",
                            prefix=prefix,
                            target_model=self.settings.realtime_call.model,
                            url=sample_url,
                        )
                        voice = created.get("voice_id", "")
                    if not voice:
                        raise ValueError("未生成可用音色，请重新录制")
                    self.stages[job.id] = "verifying"
                    await self.verify(voice)
                    await session.refresh(job)
                    role = await session.get(Role, job.role_id)
                    if not role or role.deleted:
                        cleanup = VoiceJob(
                            user_id=job.user_id, role_id=job.role_id, kind="delete", voice=voice
                        )
                        session.add(cleanup)
                        await session.commit()
                        self.schedule(cleanup.id)
                        raise ValueError("角色已删除")
                    previous = role.owned_voice
                    role.owned_voice = voice
                    role.voice = voice
                    role.voice_source_id = role.id
                    dependents = (
                        await session.exec(
                            select(Role).where(
                                Role.voice_source_id == role.id, Role.deleted.is_(False)
                            )
                        )
                    ).all()
                    for dependent in dependents:
                        dependent.voice = voice
                    job.voice = voice
                    if previous and previous != voice:
                        cleanup = VoiceJob(
                            user_id=job.user_id,
                            role_id=role.id,
                            kind="delete",
                            voice=previous,
                        )
                        session.add(cleanup)
                        await session.commit()
                        self.schedule(cleanup.id)
                job.status = "ready"
                job.error = None
            except asyncio.CancelledError:
                raise
            except Exception as error:
                stage = self.stages.get(job.id, "processing")
                logger.error(
                    "Voice job failed: %s stage=%s error=%s", job.id, stage, type(error).__name__
                )
                job.status = "failed"
                job.error = (
                    str(error)
                    if isinstance(error, VoiceProviderError)
                    else "录音上传服务暂时不可用，请稍后重试"
                    if stage == "uploading"
                    else "音色处理失败，请稍后重试或重新录制清晰的声音"
                )
            finally:
                self.stages.pop(job.id, None)
                if job.status in {"ready", "failed"}:
                    job.sample = None
                    job.sample_token = None
                    await session.commit()
                    if job.status == "ready" and job.kind == "clone":
                        task = asyncio.create_task(self.warm_preview(job.voice))
                        self.tasks.add(task)
                        task.add_done_callback(self.tasks.discard)
                if uploaded_url:
                    await self.cleanup_sample(uploaded_url)

    @property
    def realtime_url(self) -> str:
        settings = self.settings
        return _model_url(
            derive_realtime_url(settings.realtime_call.url, settings.asr.realtime.url),
            settings.realtime_call.model,
        )

    async def verify(self, voice: str) -> None:
        async with (
            asyncio.timeout(30),
            connect(
                self.realtime_url,
                additional_headers={
                    "Authorization": f"Bearer {self.settings.realtime_call.api_key}"
                },
                proxy=None,
            ) as socket,
        ):
            await socket.send(
                json.dumps(
                    {
                        "type": "session.update",
                        "session": {
                            "voice": voice,
                            "modalities": ["audio", "text"],
                        },
                    }
                )
            )
            while True:
                event = json.loads(await socket.recv())
                if event.get("type") == "error":
                    raise ValueError("音色暂时不可用，请稍后重试")
                if event.get("type") == "session.updated":
                    return

    async def preview(self, voice: str) -> bytes:
        cached = self.preview_cache.get(voice)
        if cached and monotonic() - cached[0] < 600:
            self.preview_cache.move_to_end(voice)
            return cached[1]
        self.preview_cache.pop(voice, None)
        task = self.preview_tasks.get(voice)
        if task is None:
            task = asyncio.create_task(self.cache_preview(voice))
            self.preview_tasks[voice] = task
            self.tasks.add(task)
            task.add_done_callback(self.tasks.discard)
            task.add_done_callback(
                lambda completed: None if completed.cancelled() else completed.exception()
            )
        return await asyncio.shield(task)

    async def cache_preview(self, voice: str) -> bytes:
        try:
            audio = await self.generate_preview(voice)
            self.preview_cache[voice] = (monotonic(), audio)
            while (
                len(self.preview_cache) > 16
                or sum(len(entry[1]) for entry in self.preview_cache.values()) > 32 * 1024 * 1024
            ):
                self.preview_cache.popitem(last=False)
            return audio
        finally:
            self.preview_tasks.pop(voice, None)

    async def warm_preview(self, voice: str) -> None:
        try:
            await self.preview(voice)
        except Exception as error:
            logger.warning("Voice preview warmup failed: %s", type(error).__name__)

    async def generate_preview(self, voice: str) -> bytes:
        settings = self.settings
        audio = bytearray()
        async with (
            asyncio.timeout(90),
            connect(
                self.realtime_url,
                additional_headers={"Authorization": f"Bearer {settings.realtime_call.api_key}"},
                proxy=None,
                max_size=8 * 1024 * 1024,
            ) as socket,
        ):
            await socket.send(
                json.dumps(
                    {
                        "type": "session.update",
                        "session": {
                            "modalities": ["audio", "text"],
                            "voice": voice,
                            "instructions": (
                                "请严格朗读用户提供的中文原文，不要添加任何内容，语速舒缓。"
                            ),
                            "input_audio_format": "pcm",
                            "output_audio_format": "pcm",
                            "turn_detection": None,
                            "tools": [],
                            "output_audio": {"language": "zh"},
                        },
                    }
                )
            )
            while True:
                event = json.loads(await socket.recv())
                if event.get("type") == "error":
                    raise ValueError("试听生成失败，请稍后重试")
                if event.get("type") == "session.updated":
                    break
            await socket.send(
                json.dumps(
                    {
                        "type": "conversation.item.create",
                        "item": {
                            "type": "message",
                            "role": "user",
                            "content": [{"type": "input_text", "text": PREVIEW_TEXT}],
                        },
                    },
                    ensure_ascii=False,
                )
            )
            await socket.send(json.dumps({"type": "response.create"}))
            while True:
                event = json.loads(await socket.recv())
                if event.get("type") == "response.audio.delta":
                    audio.extend(base64.b64decode(event["delta"]))
                if event.get("type") == "error":
                    raise ValueError("试听生成失败，请稍后重试")
                if event.get("type") == "response.done":
                    if not audio or event.get("response", {}).get("status") == "failed":
                        raise ValueError("试听生成失败，请稍后重试")
                    return pcm_wav(bytes(audio), 24000)
