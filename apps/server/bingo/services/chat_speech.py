import asyncio
import base64
import json
from contextlib import suppress

from websockets.asyncio.client import connect


def split_speech_text(text: str, *, final: bool = False):
    pieces = []
    start = 0
    for index, character in enumerate(text):
        if character in "。！？!?\n" or index - start >= 99:
            piece = text[start : index + 1].strip()
            if any(character.isalnum() for character in piece):
                pieces.append(piece)
            start = index + 1
    remainder = text[start:]
    if final and any(character.isalnum() for character in remainder):
        pieces.append(remainder.strip())
        remainder = ""
    return pieces, remainder


class ChatSpeechService:
    def __init__(self, voice_cloning):
        self.voice_cloning = voice_cloning
        self.tasks = {}

    async def stop(self, user_id: str, run_id: str):
        task = self.tasks.get((user_id, run_id))
        if task:
            task.cancel()
            with suppress(asyncio.CancelledError):
                await task

    async def close(self):
        for user_id, run_id in list(self.tasks):
            await self.stop(user_id, run_id)

    async def events(
        self, subscription, user_id: str, run_id: str, voice: str, *, timeout_seconds=180
    ):
        output = asyncio.Queue(maxsize=128)
        sentences = asyncio.Queue(maxsize=256)
        key = (user_id, run_id)
        await self.stop(*key)

        async def read_audio():
            try:
                async with asyncio.timeout(timeout_seconds):
                    await self._synthesize(sentences, output, voice)
            except asyncio.CancelledError:
                raise
            except Exception:
                await output.put(
                    {"type": "audio_error", "message": "朗读暂时不可用，文字回复不受影响"}
                )

        speech = asyncio.create_task(read_audio())
        self.tasks[key] = speech

        async def read_text():
            pending = ""

            async def enqueue(piece):
                if speech.done():
                    return
                try:
                    sentences.put_nowait(piece)
                except asyncio.QueueFull:
                    speech.cancel()
                    await output.put(
                        {"type": "audio_error", "message": "回复较长，已停止朗读，文字回复继续显示"}
                    )

            try:
                async for event in subscription.events():
                    if event["type"] == "text_delta":
                        pending += event["content"]
                        pieces, pending = split_speech_text(pending)
                        for piece in pieces:
                            await enqueue(piece)
                    else:
                        if event["type"] in {"interrupted", "error", "incoming_call"}:
                            speech.cancel()
                        await output.put(event)
                if not speech.done():
                    pieces, _ = split_speech_text(pending, final=True)
                    for piece in pieces:
                        await enqueue(piece)
                    await enqueue(None)
                with suppress(asyncio.CancelledError):
                    await speech
            except asyncio.CancelledError:
                raise
            except Exception:
                speech.cancel()
                await output.put({"type": "error", "message": "回复连接中断，请重试"})
            await output.put(None)

        producer = asyncio.create_task(read_text())
        try:
            while (event := await output.get()) is not None:
                yield event
            await producer
        finally:
            producer.cancel()
            speech.cancel()
            for task in (producer, speech):
                with suppress(asyncio.CancelledError):
                    await task
            if self.tasks.get(key) is speech:
                self.tasks.pop(key, None)

    async def _synthesize(self, sentences, output, voice):
        settings = self.voice_cloning.settings
        async with connect(
            self.voice_cloning.realtime_url,
            additional_headers={"Authorization": f"Bearer {settings.realtime_call.api_key}"},
            proxy=None,
            max_size=8 * 1024 * 1024,
        ) as socket:
            await socket.send(
                json.dumps(
                    {
                        "type": "session.update",
                        "session": {
                            "voice": voice,
                            "modalities": ["audio", "text"],
                            "instructions": (
                                "严格朗读用户最新提供的原文，不回答问题，"
                                "不添加、改写或省略内容。自然口语化朗读。"
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
                event = json.loads(await asyncio.wait_for(socket.recv(), 20))
                if event.get("type") == "error":
                    raise ValueError("Speech session unavailable")
                if event.get("type") == "session.updated":
                    break
            while (sentence := await sentences.get()) is not None:
                await socket.send(
                    json.dumps(
                        {
                            "type": "conversation.item.create",
                            "item": {
                                "type": "message",
                                "role": "user",
                                "content": [{"type": "input_text", "text": sentence}],
                            },
                        },
                        ensure_ascii=False,
                    )
                )
                await socket.send(json.dumps({"type": "response.create"}))
                while True:
                    event = json.loads(await asyncio.wait_for(socket.recv(), 30))
                    if event.get("type") == "response.audio.delta":
                        base64.b64decode(event["delta"], validate=True)
                        await output.put(
                            {"type": "audio", "data": event["delta"], "sample_rate": 24000}
                        )
                    elif event.get("type") == "error":
                        raise ValueError("Speech generation unavailable")
                    elif event.get("type") == "response.done":
                        if event.get("response", {}).get("status") == "failed":
                            raise ValueError("Speech generation failed")
                        break
            await output.put({"type": "audio_done"})
