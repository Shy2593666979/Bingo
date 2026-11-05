"""A single bounded, cancellable speech stream held until its playback turn."""

import asyncio
from contextlib import aclosing
from dataclasses import dataclass


class PreparedSpeech:
    def __init__(self, source, retire):
        self.source, self.retire = source, retire
        self.queue = asyncio.Queue(maxsize=4)
        self.playback = asyncio.Event()
        self.closed = False
        self.failed = False
        self.first_audio_ready = False
        self.task = asyncio.create_task(self._produce())

    async def _produce(self):
        try:
            async with aclosing(self.source) as source:
                async for event in source:
                    if event["type"] == "audio_error":
                        self.failed = True
                    await self.queue.put(event)
                    if event["type"] == "audio":
                        self.first_audio_ready = True
                    # Hold only the first audio chunk outside the speech service.
                    # No client event is sent until the preceding speaker finishes.
                    if event["type"] == "audio" and not self.playback.is_set():
                        await self.playback.wait()
        except asyncio.CancelledError:
            raise
        except Exception:
            self.failed = True
            await self.queue.put({"type": "audio_error"})
        finally:
            if not self.closed:
                await self.queue.put(None)

    async def events(self):
        self.playback.set()
        try:
            while (event := await self.queue.get()) is not None:
                yield event
        finally:
            await self.close()

    def cancel(self):
        if self.closed:
            return
        self.closed = True
        self.playback.set()
        self.retire(self.task)

    async def close(self):
        self.cancel()
        await asyncio.gather(self.task, return_exceptions=True)


@dataclass
class PreparedTurn:
    action: str
    role: object = None
    content: str = ""
    audio: PreparedSpeech | None = None

    def cancel(self):
        if self.audio:
            self.audio.cancel()
