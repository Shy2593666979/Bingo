import json

import httpx
import pytest
from pydantic import ValidationError

from bingo.agent.context import build_context
from bingo.config import MapsSettings
from bingo.db.models import Message
from bingo.schemas.chat import ChatRequest
from bingo.schemas.maps import LocationInput
from bingo.services.exceptions import ServiceError
from bingo.services.maps import MapsService
from tests.api_support import api_payload
from tests.test_api import client as client

POINT = {
    "name": "天安门",
    "address": "北京市东城区长安街北侧",
    "province": "北京市",
    "city": "北京市",
    "district": "东城区",
    "longitude": 116.397463,
    "latitude": 39.909187,
    "coordinate_system": "GCJ-02",
    "source": "poi",
    "precision": "point",
}


def test_location_history_retains_model_structure_and_user_role():
    message = Message(
        id="location",
        conversation_id="conversation",
        role="user",
        content="[位置] 天安门",
        message_type="location",
        location_json=json.dumps(POINT),
        status="completed",
    )
    context = build_context(
        [message],
        [],
        username="用户",
        assistant_name="伙伴",
        personality="温柔",
        role="朋友",
        timezone="Asia/Shanghai",
        current_location="河南省郑州市金水区",
    )
    assert context[1].role == "user"
    assert json.loads(context[1].content.split("] ", 1)[1])["location"]["name"] == "天安门"
    assert "用户当前位置：河南省郑州市金水区" in context[0].content


def test_map_environment_key_overrides_blank_example_config(monkeypatch):
    monkeypatch.setenv("BINGO_AMAP_API_KEY", "environment-key")
    assert MapsSettings(api_key="").api_key == "environment-key"


def test_nearby_address_does_not_duplicate_county():
    service = MapsService(MapsSettings(api_key="test-key"))
    point = service._place(
        {"name": "测试地点", "location": "115,35", "address": "濮阳县中心路"},
        "河南省",
        "濮阳市",
        "濮阳县",
    )
    assert point.address == "河南省濮阳市濮阳县中心路"


@pytest.mark.asyncio
async def test_malformed_map_provider_response_is_safe(monkeypatch):
    service = MapsService(MapsSettings(api_key="test-key"))

    async def malformed(path, parameters):
        return {"status": "1", "regeocode": [], "pois": "invalid"}

    monkeypatch.setattr(service, "_json", malformed)
    with pytest.raises(ServiceError):
        await service.reverse("user", 116, 39)
    with pytest.raises(ServiceError):
        await service.search("user", "天安门")


def test_location_message_reaches_model_and_survives_history(client):
    response = client.post("/api/v1/chat", json={"location": POINT})
    assert response.status_code == 200
    result = api_payload(response)
    model_input = json.loads(result["content"].removeprefix("You said: ").split("] ", 1)[1])
    assert model_input["type"] == "location"
    assert model_input["location"]["longitude"] == POINT["longitude"]
    history = api_payload(client.get(f"/api/v1/conversations/{result['conversation_id']}/messages"))
    sent = next(item for item in history if item["role"] == "user")
    assert sent["message_type"] == "location"
    assert sent["location"]["name"] == "天安门"
    assert sent["content"].startswith("[位置]")
    follow_up = client.post(
        "/api/v1/chat",
        json={"conversation_id": result["conversation_id"], "content": "这里有什么好吃的？"},
    )
    assert follow_up.status_code == 200


def test_stream_location_message_has_normal_events(client):
    response = client.post(
        "/api/v1/chat/stream", json={"location": POINT, "run_id": "location-test"}
    )
    assert response.status_code == 200
    events = [json.loads(line) for line in response.text.splitlines()]
    assert events[0]["type"] == "start"
    assert any(item["type"] == "done" for item in events)
    history = api_payload(
        client.get(f"/api/v1/conversations/{events[0]['conversation_id']}/messages")
    )
    assert (
        next(item for item in history if item["role"] == "user")["location"]["latitude"]
        == POINT["latitude"]
    )


def test_location_validation_and_region_privacy(client):
    for invalid in [
        {**POINT, "latitude": 100},
        {**POINT, "longitude": float("inf")},
        {**POINT, "coordinate_system": "WGS84"},
        {**POINT, "latitude": None},
    ]:
        with pytest.raises(ValidationError):
            LocationInput.model_validate(invalid)
    with pytest.raises(ValidationError):
        ChatRequest(location=POINT, images=[{"mime_type": "image/png", "data": "abc"}])
    region = {
        field: value for field, value in POINT.items() if field not in {"longitude", "latitude"}
    }
    region.update(precision="district", source="user_shared_region")
    normalized = LocationInput.model_validate({**region, "accuracy_m": 10})
    assert normalized.name == normalized.address == "北京市东城区"
    assert normalized.accuracy_m is None
    assert client.post("/api/v1/chat", json={"location": region}).status_code == 200
    assert (
        client.post(
            "/api/v1/chat", json={"location": {**POINT, "precision": "district"}}
        ).status_code
        == 422
    )


def test_location_routes_are_authenticated_and_map_is_binary(client, monkeypatch):
    service = client.app.state.services.maps

    async def image(*arguments):
        return b"\x89PNG\r\n\x1a\nmap"

    monkeypatch.setattr(service, "map_image", image)
    response = client.get("/api/v1/locations/map?longitude=116&latitude=39")
    assert response.status_code == 200
    assert response.headers["content-type"] == "image/png"
    assert response.content.startswith(b"\x89PNG")
    client.headers.pop("Authorization")
    assert client.get("/api/v1/locations/search?keywords=test").status_code == 401
    assert client.get("/api/v1/locations/map?longitude=116&latitude=39").status_code == 401


@pytest.mark.asyncio
async def test_maps_normalizes_municipality_converts_gps_and_caches(monkeypatch):
    service = MapsService(MapsSettings(api_key="test-key"))
    calls = []

    async def get(path, parameters):
        calls.append((path, parameters))
        if path == "assistant/coordinate/convert":
            return httpx.Response(200, json={"status": "1", "locations": "116.397,39.909"})
        if path == "staticmap":
            return httpx.Response(200, content=b"\x89PNG\r\n\x1a\nmap")
        return httpx.Response(
            200,
            json={
                "status": "1",
                "regeocode": {
                    "formatted_address": "北京市东城区天安门",
                    "pois": [],
                    "addressComponent": {"province": "北京市", "city": [], "district": "东城区"},
                },
            },
        )

    monkeypatch.setattr(service, "_get", get)
    result = await service.reverse("user", 116.39, 39.90, "WGS84")
    cached = await service.reverse("user", 116.39, 39.90, "WGS84")
    assert cached.location.longitude == result.location.longitude
    assert len(calls) == 2
    assert result.location.city == "北京市"
    assert result.location.longitude == 116.397
    assert calls[0][0] == "assistant/coordinate/convert"
    await service.map_image("user", 116.397, 39.909, 15)
    await service.map_image("user", 116.397, 39.909, 15)
    assert len([call for call in calls if call[0] == "staticmap"]) == 1
    for _ in range(56):
        service._limit("user")
    with pytest.raises(ServiceError):
        service._limit("user")


@pytest.mark.asyncio
async def test_maps_reuses_connection_client_and_closes_it():
    requests = []

    def handle(request):
        requests.append(request.url.path)
        return httpx.Response(200, json={"status": "1", "pois": []})

    service = MapsService(MapsSettings(api_key="test-key"))
    client = httpx.AsyncClient(transport=httpx.MockTransport(handle))
    service._client = client
    await service.search("user", "first")
    await service.search("user", "second")
    await service.search("user", "first")
    assert len(requests) == 2
    assert service._client is client
    await service.close()
    assert client.is_closed
    assert service._client is None
