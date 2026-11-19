"""Cheap PCM activity evidence for ASR-backed interruption, not a speech recognizer."""

import math
import sys
import time
from array import array
from collections import deque


class BargeInEvidence:
    def __init__(self, sample_rate=16000, *, clock=time.monotonic):
        self.sample_rate = sample_rate
        self.clock = clock
        self.frames = deque()
        self.pending = b""
        self.noise_floor = 80.0

    def observe(self, pcm):
        self.pending += pcm
        size = self.sample_rate // 50 * 2  # PCM16 mono, 20 ms frames.
        while len(self.pending) >= size:
            frame, self.pending = self.pending[:size], self.pending[size:]
            samples = array("h", frame)
            if sys.byteorder != "little":
                samples.byteswap()
            rms = math.sqrt(sum(value * value for value in samples) / len(samples))
            active = rms >= max(120, self.noise_floor * 2.5)
            if not active:
                self.noise_floor = max(30, min(400, self.noise_floor * 0.98 + rms * 0.02))
            self.frames.append((self.clock(), active))
        self._prune()

    def _prune(self):
        cutoff = self.clock() - 1.2
        while self.frames and self.frames[0][0] < cutoff:
            self.frames.popleft()

    def supports_speech(self, *, final=False):
        self._prune()
        run = longest = total = 0
        for _, active in self.frames:
            run = run + 1 if active else 0
            longest = max(longest, run)
            total += active
        return longest >= 6 and total >= (6 if final else 12)

    def recent_voice(self):
        return any(active and stamp > self.clock() - 0.35 for stamp, active in self.frames)

    def reset(self):
        self.frames.clear()
        self.pending = b""
