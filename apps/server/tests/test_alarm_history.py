import json

import pytest
from fastapi.testclient import TestClient

from bingo.agent.runtime import AgentRuntime
from bingo.services.chat_runs import ChatRunService
from bingo.tools import create_tool_registry
from tests.api_support import api_payload
from tests.test_api import _AlarmModelClient
from tests.test_api import client as client


class RecordingAlarmModel(_AlarmModelClient):
    def __init__(self):
        self.contexts = []

    async def stream(self, messages, tools=None):
        self.contexts.append([message.content for message in messages])
        async for event in super().stream(messages, tools):
            yield event


@pytest.mark.parametrize(
    ("status", "result", "expected"),
    [
        ("succeeded", "已由 Bingo 在设备本地创建闹钟", "设备已确认创建成功"),
        ("submitted", "已提交给系统时钟创建闹钟", "是否创建成功尚未确认"),
        ("failed", "没有闹钟权限", "创建失败"),
        ("rejected", None, "用户已取消，未创建"),
    ],
)
def test_alarm_card_history_and_model_context(client: TestClient, status, result, expected):
    model = RecordingAlarmModel()
    runtime = AgentRuntime(
        model,
        create_tool_registry(),
        assistant_name="Bingo",
        persona="可靠",
        timezone="Asia/Shanghai",
    )
    client.app.state.runtime = runtime
    client.app.state.chat_runs = ChatRunService(client.app.state.database.session_factory, runtime)
    response = client.post("/api/v1/chat/stream", json={"content": "明早七点叫我"})
    events = [json.loads(line) for line in response.text.splitlines()]
    conversation_id = events[0]["conversation_id"]
    action_id = next(event["action_id"] for event in events if event["type"] == "approval_required")
    path = f"/api/v1/conversations/{conversation_id}/messages"
    pending = next(item for item in api_payload(client.get(path)) if item["id"] == action_id)
    assert pending["device_action"]["status"] == "pending"
    assert "尚未创建" in pending["content"]
    if status == "rejected":
        assert client.post(f"/api/v1/device-actions/{action_id}/reject").status_code == 204
        assert client.post(f"/api/v1/device-actions/{action_id}/reject").status_code == 204
    else:
        assert client.post(f"/api/v1/device-actions/{action_id}/approve").status_code == 200
        body = {"status": status, "result": result}
        assert (
            client.post(f"/api/v1/device-actions/{action_id}/complete", json=body).status_code
            == 200
        )
        assert (
            client.post(f"/api/v1/device-actions/{action_id}/complete", json=body).status_code
            == 200
        )
    cards = [item for item in api_payload(client.get(path)) if item["id"] == action_id]
    assert len(cards) == 1
    assert cards[0]["device_action"]["status"] == status
    assert cards[0]["device_action"]["result"] == result
    assert expected in cards[0]["content"]
    if status != "failed":
        assert client.post(f"/api/v1/device-actions/{action_id}/approve").status_code == 409
    model.contexts.clear()
    client.post(
        "/api/v1/chat/stream", json={"conversation_id": conversation_id, "content": "闹钟怎么样了"}
    )
    assert any(expected in (content or "") for content in model.contexts[0])


@pytest.mark.asyncio
async def test_upgrade_old_device_action_database(tmp_path):
    from bingo.db.session import Database

    database = Database(f"sqlite+aiosqlite:///{tmp_path / 'old.db'}")
    await database.initialize()
    async with database.engine.begin() as connection:
        await connection.exec_driver_sql("DROP INDEX ix_device_actions_conversation_id")
        await connection.exec_driver_sql("ALTER TABLE device_actions DROP COLUMN conversation_id")
    await database.initialize()
    await database.initialize()
    async with database.engine.begin() as connection:
        columns = await connection.exec_driver_sql("PRAGMA table_info(device_actions)")
        assert "conversation_id" in {row[1] for row in columns}
    await database.dispose()
