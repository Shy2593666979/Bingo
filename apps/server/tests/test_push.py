import json
from pathlib import Path

import pytest
from sqlmodel import select

from bingo.db.models import Conversation, PushOutbox, User
from bingo.db.repositories import ProactiveMessageRepository, PushDeviceRepository
from bingo.db.session import Database
from bingo.push.provider import PushDelivery
from bingo.push.service import PushService


class RecordingPushProvider:
    def __init__(self) -> None:
        self.deliveries: list[PushDelivery] = []

    @property
    def enabled(self) -> bool:
        return True

    async def send(self, delivery: PushDelivery) -> str:
        self.deliveries.append(delivery)
        return "provider-task-1"

    async def close(self) -> None:
        return None


@pytest.mark.asyncio
async def test_proactive_message_is_delivered_through_outbox(tmp_path: Path) -> None:
    database = Database(f"sqlite+aiosqlite:///{tmp_path / 'push.db'}")
    await database.initialize()
    provider = RecordingPushProvider()
    service = PushService(database.session_factory, provider, poll_seconds=0.01)
    try:
        async with database.session_factory() as session:
            user = User(phone="13800138003", password_hash="hash", assistant_name="Bingo")
            session.add(user)
            await session.flush()
            conversation = Conversation(user_id=user.id, title="问候")
            session.add(conversation)
            await session.commit()
            await PushDeviceRepository(session).upsert(
                user_id=user.id,
                installation_id="installation-001",
                provider="getui",
                client_id="getui-client-001",
                manufacturer="Xiaomi",
                model="test-device",
                app_version="0.1.0",
            )
            proactive = await ProactiveMessageRepository(session, user.id).create(
                conversation.id,
                "早上好，今天想先做什么？",
                1,
            )

        assert await service.enqueue(proactive, "Bingo", "早上好，今天想先做什么？") == 1
        assert await service._deliver_one()

        assert len(provider.deliveries) == 1
        assert provider.deliveries[0].client_id == "getui-client-001"
        assert provider.deliveries[0].payload["message_id"] == proactive.message_id

        async with database.session_factory() as session:
            outbox = (await session.exec(select(PushOutbox))).one()
            assert outbox.status == "sent"
            assert outbox.provider_message_id == "provider-task-1"
            assert json.loads(outbox.payload_json)["type"] == "proactive_message"
    finally:
        await service.close()
        await database.dispose()
