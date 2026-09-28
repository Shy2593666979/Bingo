import asyncio
import heapq
import json
import time
from dataclasses import dataclass
from typing import Any, Protocol
from uuid import uuid4

from redis.asyncio import Redis


@dataclass(frozen=True, slots=True)
class BackgroundJob:
    id: str
    kind: str
    payload: dict[str, Any]


class TaskBroker(Protocol):
    async def close(self) -> None: ...
    async def record_activity(self, user_id: str) -> str: ...
    async def current_version(self, user_id: str) -> str | None: ...
    async def schedule(self, kind: str, payload: dict[str, Any], delay: int) -> None: ...
    async def pop_due(self) -> BackgroundJob | None: ...
    async def save_recommendations(self, user_id: str, items: list[str]) -> None: ...
    async def get_recommendations(self, user_id: str) -> list[str]: ...
    async def clear_recommendations(self, user_id: str) -> None: ...


class InMemoryTaskBroker:
    def __init__(self) -> None:
        self._versions: dict[str, str] = {}
        self._recommendations: dict[str, list[str]] = {}
        self._jobs: list[tuple[float, str, BackgroundJob]] = []
        self._lock = asyncio.Lock()

    async def close(self) -> None:
        return None

    async def record_activity(self, user_id: str) -> str:
        version = str(uuid4())
        self._versions[user_id] = version
        self._recommendations.pop(user_id, None)
        return version

    async def current_version(self, user_id: str) -> str | None:
        return self._versions.get(user_id)

    async def schedule(self, kind: str, payload: dict[str, Any], delay: int) -> None:
        job = BackgroundJob(str(uuid4()), kind, payload)
        async with self._lock:
            heapq.heappush(self._jobs, (time.time() + delay, job.id, job))

    async def pop_due(self) -> BackgroundJob | None:
        async with self._lock:
            if not self._jobs or self._jobs[0][0] > time.time():
                return None
            return heapq.heappop(self._jobs)[2]

    async def save_recommendations(self, user_id: str, items: list[str]) -> None:
        self._recommendations[user_id] = items

    async def get_recommendations(self, user_id: str) -> list[str]:
        return self._recommendations.get(user_id, [])

    async def clear_recommendations(self, user_id: str) -> None:
        self._recommendations.pop(user_id, None)


class RedisTaskBroker:
    SCHEDULED_KEY = "bingo:jobs:scheduled"

    def __init__(self, url: str) -> None:
        self._redis = Redis.from_url(url, decode_responses=True)

    async def start(self) -> None:
        await self._redis.ping()

    async def close(self) -> None:
        await self._redis.aclose()

    async def record_activity(self, user_id: str) -> str:
        version = str(uuid4())
        async with self._redis.pipeline(transaction=True) as pipeline:
            pipeline.set(f"bingo:user:{user_id}:activity_version", version)
            pipeline.set(f"bingo:user:{user_id}:last_active_at", str(time.time()))
            pipeline.delete(f"bingo:user:{user_id}:recommendations")
            await pipeline.execute()
        return version

    async def current_version(self, user_id: str) -> str | None:
        return await self._redis.get(f"bingo:user:{user_id}:activity_version")

    async def schedule(self, kind: str, payload: dict[str, Any], delay: int) -> None:
        job_id = str(uuid4())
        data = json.dumps({"id": job_id, "kind": kind, "payload": payload})
        async with self._redis.pipeline(transaction=True) as pipeline:
            pipeline.set(f"bingo:job:{job_id}", data, ex=7 * 24 * 3600)
            pipeline.zadd(self.SCHEDULED_KEY, {job_id: time.time() + delay})
            await pipeline.execute()

    async def pop_due(self) -> BackgroundJob | None:
        ids = await self._redis.zrangebyscore(
            self.SCHEDULED_KEY,
            min=0,
            max=time.time(),
            start=0,
            num=1,
        )
        if not ids:
            return None
        job_id = ids[0]
        if await self._redis.zrem(self.SCHEDULED_KEY, job_id) != 1:
            return None
        key = f"bingo:job:{job_id}"
        raw = await self._redis.get(key)
        await self._redis.delete(key)
        if raw is None:
            return None
        data = json.loads(raw)
        return BackgroundJob(data["id"], data["kind"], data["payload"])

    async def save_recommendations(self, user_id: str, items: list[str]) -> None:
        await self._redis.set(
            f"bingo:user:{user_id}:recommendations",
            json.dumps(items, ensure_ascii=False),
            ex=7 * 24 * 3600,
        )

    async def get_recommendations(self, user_id: str) -> list[str]:
        raw = await self._redis.get(f"bingo:user:{user_id}:recommendations")
        return [] if raw is None else list(json.loads(raw))

    async def clear_recommendations(self, user_id: str) -> None:
        await self._redis.delete(f"bingo:user:{user_id}:recommendations")
