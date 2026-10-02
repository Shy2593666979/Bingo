import asyncio
import json

from redis.asyncio import Redis
from redis.exceptions import RedisError

from bingo.db.time import beijing_now
from bingo.schemas.location import RegionLocation
from bingo.services.exceptions import ServiceError


class LocationService:
    ttl_seconds = 86400

    def __init__(self, redis_url: str | None):
        self.cache = (
            Redis.from_url(
                redis_url, decode_responses=True, socket_connect_timeout=1, socket_timeout=1
            )
            if redis_url
            else None
        )

    def key(self, user_id: str) -> str:
        return f"bingo:user:{user_id}:location"

    async def update(self, user_id: str, region: RegionLocation) -> dict:
        if self.cache is None:
            raise ServiceError(503, "地区缓存暂时不可用")
        value = {
            **region.model_dump(),
            "display": region.display,
            "updated_at": beijing_now().isoformat(),
        }
        try:
            await self.cache.set(
                self.key(user_id), json.dumps(value, ensure_ascii=False), ex=self.ttl_seconds
            )
        except RedisError as error:
            raise ServiceError(503, "地区缓存暂时不可用") from error
        return value

    async def current(self, user_id: str) -> dict | None:
        if self.cache is None:
            return None
        try:
            async with asyncio.timeout(1.5):
                raw = await self.cache.get(self.key(user_id))
            if raw is None:
                return None
            value = json.loads(raw)
            region = RegionLocation.model_validate(
                {key: value.get(key, "") for key in ("province", "city", "district")}
            )
            return {
                **region.model_dump(),
                "display": region.display,
                "updated_at": value.get("updated_at"),
            }
        except (RedisError, ValueError, TypeError, TimeoutError):
            return None

    async def clear(self, user_id: str) -> None:
        if self.cache is None:
            return
        try:
            await self.cache.delete(self.key(user_id))
        except RedisError as error:
            raise ServiceError(503, "地区缓存暂时不可用") from error

    async def close(self) -> None:
        if self.cache is not None:
            await self.cache.aclose()
