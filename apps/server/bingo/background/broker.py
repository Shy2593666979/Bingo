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


def recommendation_job(key: str, version: str, payload: dict[str, Any]) -> BackgroundJob:
    return BackgroundJob(
        f"recommendations:{key}", "recommendations", {**payload, "activity_version": version}
    )


class TaskBroker(Protocol):
    async def close(self) -> None: ...
    async def record_activity(
        self,
        user_id: str,
        *,
        recommendation_payload: dict[str, Any] | None = None,
        recommendation_delay: int = 0,
    ) -> str: ...
    async def current_version(self, user_id: str) -> str | None: ...
    async def schedule(self, kind: str, payload: dict[str, Any], delay: int) -> None: ...
    async def pop_due(self) -> BackgroundJob | None: ...
    async def save_recommendations(
        self, user_id: str, items: list[str], *, activity_version: str | None = None
    ) -> None: ...
    async def get_recommendations(self, user_id: str) -> list[str]: ...
    async def clear_recommendations(self, user_id: str) -> None: ...
    async def forget_user(self, user_id: str, conversation_ids: list[str]) -> None: ...


class InMemoryTaskBroker:
    def __init__(self) -> None:
        self._versions: dict[str, str] = {}
        self._recommendations: dict[str, list[str]] = {}
        self._jobs: list[tuple[float, str, BackgroundJob]] = []
        self._lock = asyncio.Lock()

    async def close(self) -> None:
        return None

    async def record_activity(
        self,
        user_id: str,
        *,
        recommendation_payload: dict[str, Any] | None = None,
        recommendation_delay: int = 0,
    ) -> str:
        version = str(uuid4())
        async with self._lock:
            self._versions[user_id] = version
            self._recommendations.pop(user_id, None)
            if recommendation_payload is not None:
                job = recommendation_job(user_id, version, recommendation_payload)
                self._jobs = [entry for entry in self._jobs if entry[1] != job.id]
                heapq.heapify(self._jobs)
                heapq.heappush(self._jobs, (time.time() + recommendation_delay, job.id, job))
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

    async def save_recommendations(
        self, user_id: str, items: list[str], *, activity_version: str | None = None
    ) -> None:
        if activity_version is not None and self._versions.get(user_id) != activity_version:
            return
        self._recommendations[user_id] = items

    async def get_recommendations(self, user_id: str) -> list[str]:
        return self._recommendations.get(user_id, [])

    async def forget_user(self, user_id: str, conversation_ids: list[str]) -> None:
        async with self._lock:
            for key in [user_id, *(f"{user_id}:{value}" for value in conversation_ids)]:
                self._recommendations.pop(key, None)
                self._versions.pop(key, None)
            self._jobs = [
                entry for entry in self._jobs if entry[2].payload.get("user_id") != user_id
            ]
            heapq.heapify(self._jobs)

    async def clear_recommendations(self, user_id: str) -> None:
        async with self._lock:
            self._recommendations.pop(user_id, None)
            self._versions.pop(user_id, None)
            self._jobs = [entry for entry in self._jobs if entry[1] != f"recommendations:{user_id}"]
            heapq.heapify(self._jobs)


class RedisTaskBroker:
    SCHEDULED_KEY = "bingo:jobs:scheduled"
    POP_DUE_SCRIPT = """
local ids = redis.call('ZRANGEBYSCORE', KEYS[1], '-inf', ARGV[1], 'LIMIT', 0, 1)
if #ids == 0 then return nil end
redis.call('ZREM', KEYS[1], ids[1])
local key = ARGV[2] .. ids[1]
local data = redis.call('GET', key)
redis.call('DEL', key)
return data
"""
    SAVE_RECOMMENDATIONS_SCRIPT = """
if ARGV[1] ~= '' and redis.call('GET', KEYS[1]) ~= ARGV[1] then return 0 end
redis.call('SET', KEYS[2], ARGV[2])
return 1
"""

    def __init__(self, url: str) -> None:
        self._redis = Redis.from_url(url, decode_responses=True)

    async def start(self) -> None:
        await self._redis.ping()

    async def close(self) -> None:
        await self._redis.aclose()

    async def record_activity(
        self,
        user_id: str,
        *,
        recommendation_payload: dict[str, Any] | None = None,
        recommendation_delay: int = 0,
    ) -> str:
        version = str(uuid4())
        now = time.time()
        async with self._redis.pipeline(transaction=True) as pipeline:
            pipeline.set(f"bingo:user:{user_id}:activity_version", version)
            pipeline.set(f"bingo:user:{user_id}:last_active_at", str(now))
            pipeline.delete(f"bingo:user:{user_id}:recommendations")
            if recommendation_payload is not None:
                job = recommendation_job(user_id, version, recommendation_payload)
                data = json.dumps({"id": job.id, "kind": job.kind, "payload": job.payload})
                pipeline.set(f"bingo:job:{job.id}", data, ex=7 * 24 * 3600)
                pipeline.zadd(self.SCHEDULED_KEY, {job.id: now + recommendation_delay})
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
        raw = await self._redis.eval(
            self.POP_DUE_SCRIPT, 1, self.SCHEDULED_KEY, time.time(), "bingo:job:"
        )
        if raw is None:
            return None
        data = json.loads(raw)
        return BackgroundJob(data["id"], data["kind"], data["payload"])

    async def save_recommendations(
        self, user_id: str, items: list[str], *, activity_version: str | None = None
    ) -> None:
        await self._redis.eval(
            self.SAVE_RECOMMENDATIONS_SCRIPT,
            2,
            f"bingo:user:{user_id}:activity_version",
            f"bingo:user:{user_id}:recommendations",
            activity_version or "",
            json.dumps(items, ensure_ascii=False),
        )

    async def get_recommendations(self, user_id: str) -> list[str]:
        raw = await self._redis.get(f"bingo:user:{user_id}:recommendations")
        return [] if raw is None else list(json.loads(raw))

    async def forget_user(self, user_id: str, conversation_ids: list[str]) -> None:
        for key in [user_id, *(f"{user_id}:{value}" for value in conversation_ids)]:
            await self.clear_recommendations(key)
        async for key in self._redis.scan_iter(match="bingo:job:*", count=100):
            raw = await self._redis.get(key)
            if raw is None:
                continue
            data = json.loads(raw)
            if data.get("payload", {}).get("user_id") == user_id:
                async with self._redis.pipeline(transaction=True) as pipeline:
                    pipeline.delete(key)
                    pipeline.zrem(self.SCHEDULED_KEY, data["id"])
                    await pipeline.execute()

    async def clear_recommendations(self, user_id: str) -> None:
        async with self._redis.pipeline(transaction=True) as pipeline:
            pipeline.delete(
                f"bingo:user:{user_id}:recommendations",
                f"bingo:user:{user_id}:activity_version",
                f"bingo:job:recommendations:{user_id}",
            )
            pipeline.zrem(self.SCHEDULED_KEY, f"recommendations:{user_id}")
            await pipeline.execute()
