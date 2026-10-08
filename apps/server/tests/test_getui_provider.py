import json

import httpx
import pytest

from bingo.config import Settings
from bingo.push.provider import GetuiPushProvider, PushDelivery


@pytest.mark.asyncio
async def test_getui_notification_opens_app_and_reuses_auth_token() -> None:
    settings = Settings()
    settings.push.getui.app_id = "test-app"
    settings.push.getui.app_key = "test-key"
    settings.push.getui.master_secret = "test-secret"
    requests: list[httpx.Request] = []

    def respond(request: httpx.Request) -> httpx.Response:
        requests.append(request)
        if request.url.path.endswith("/auth"):
            return httpx.Response(200, json={
                "code": 0,
                "data": {"token": "test-token", "expire_time": 9999999999999},
            })
        assert request.headers["token"] == "test-token"
        body = json.loads(request.content)
        assert body["audience"]["cid"] == ["test-client"]
        assert body["push_message"]["notification"] == {
            "title": "甜甜",
            "body": "今天过得怎么样？",
            "click_type": "startapp",
        }
        return httpx.Response(200, json={"code": 0, "data": {"task-1": {}}})

    provider = GetuiPushProvider(settings)
    await provider._client.aclose()
    provider._client = httpx.AsyncClient(transport=httpx.MockTransport(respond))
    delivery = PushDelivery(
        request_id="request-1",
        client_id="test-client",
        title="甜甜",
        body="今天过得怎么样？",
        payload={"type": "proactive_message"},
    )
    try:
        assert await provider.send(delivery) == "task-1"
        assert await provider.send(delivery) == "task-1"
        assert sum(request.url.path.endswith("/auth") for request in requests) == 1
    finally:
        await provider.close()
