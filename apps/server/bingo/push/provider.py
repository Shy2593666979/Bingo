import hashlib
import json
import time
from dataclasses import dataclass
from typing import Protocol

import httpx

from bingo.config import Settings


@dataclass(frozen=True, slots=True)
class PushDelivery:
    request_id: str
    client_id: str
    title: str
    body: str
    payload: dict[str, str]


class PushProvider(Protocol):
    @property
    def enabled(self) -> bool: ...

    async def send(self, delivery: PushDelivery) -> str | None: ...

    async def close(self) -> None: ...


class DisabledPushProvider:
    @property
    def enabled(self) -> bool:
        return False

    async def send(self, delivery: PushDelivery) -> str | None:
        raise RuntimeError("Push provider is disabled")

    async def close(self) -> None:
        return None


class GetuiPushProvider:
    def __init__(self, settings: Settings) -> None:
        if not all(
            (
                settings.push.getui.app_id,
                settings.push.getui.app_key,
                settings.push.getui.master_secret,
            )
        ):
            raise ValueError("Getui push credentials are incomplete")
        self._app_id = settings.push.getui.app_id
        self._app_key = settings.push.getui.app_key
        self._master_secret = settings.push.getui.master_secret
        self._base_url = settings.push.getui.base_url.rstrip("/")
        self._channel_id = settings.push.android.channel_id
        self._channel_name = settings.push.android.channel_name
        self._client = httpx.AsyncClient(timeout=15.0)
        self._token: str | None = None
        self._token_expires_at = 0.0

    @property
    def enabled(self) -> bool:
        return True

    async def close(self) -> None:
        await self._client.aclose()

    async def send(self, delivery: PushDelivery) -> str | None:
        token = await self._access_token()
        response = await self._client.post(
            f"{self._base_url}/v2/{self._app_id}/push/single/cid",
            headers={"token": token},
            json={
                "request_id": delivery.request_id.replace("-", "")[:32],
                "settings": {"ttl": 24 * 60 * 60 * 1000, "strategy": {"default": 1}},
                "audience": {"cid": [delivery.client_id]},
                "push_message": {
                    "notification": {
                        "title": delivery.title,
                        "body": delivery.body,
                        "click_type": "payload",
                        "payload": json.dumps(delivery.payload, ensure_ascii=False),
                    }
                },
                "push_channel": {
                    "android": {
                        "ups": {
                            "notification": {
                                "title": delivery.title,
                                "body": delivery.body,
                                "click_type": "startapp",
                                "channel_id": self._channel_id,
                                "channel_name": self._channel_name,
                                "channel_level": 4,
                            },
                            "options": {
                                "XM": {"/extra.channel_id": self._channel_id},
                            },
                        }
                    }
                },
            },
        )
        response.raise_for_status()
        data = response.json()
        if str(data.get("code")) != "0":
            raise RuntimeError(f"Getui push rejected: {data.get('code')} {data.get('msg', '')}")
        result = data.get("data") or {}
        return str(next(iter(result), "")) or None

    async def _access_token(self) -> str:
        now = time.time()
        if self._token and now < self._token_expires_at - 60:
            return self._token
        timestamp = str(int(now * 1000))
        sign = hashlib.sha256(
            f"{self._app_key}{timestamp}{self._master_secret}".encode()
        ).hexdigest()
        response = await self._client.post(
            f"{self._base_url}/v2/{self._app_id}/auth",
            json={"sign": sign, "timestamp": timestamp, "appkey": self._app_key},
        )
        response.raise_for_status()
        data = response.json()
        if str(data.get("code")) != "0":
            raise RuntimeError(f"Getui auth rejected: {data.get('code')} {data.get('msg', '')}")
        token_data = data.get("data") or {}
        self._token = str(token_data["token"])
        expire_time = float(token_data.get("expire_time", (now + 23 * 3600) * 1000))
        self._token_expires_at = expire_time / 1000 if expire_time > 10_000_000_000 else expire_time
        return self._token


def create_push_provider(settings: Settings) -> PushProvider:
    if settings.push.provider == "getui":
        return GetuiPushProvider(settings)
    return DisabledPushProvider()
