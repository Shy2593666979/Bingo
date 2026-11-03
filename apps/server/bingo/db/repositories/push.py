from datetime import datetime

from sqlmodel import select
from sqlmodel.ext.asyncio.session import AsyncSession

from bingo.db.models import (
    PushDevice,
    PushOutbox,
)
from bingo.db.time import beijing_now


class PushDeviceRepository:
    def __init__(self, session: AsyncSession) -> None:
        self._session = session

    async def upsert(
        self,
        *,
        user_id: str,
        installation_id: str,
        provider: str,
        client_id: str,
        manufacturer: str | None,
        model: str | None,
        app_version: str | None,
    ) -> PushDevice:
        device = (
            await self._session.exec(
                select(PushDevice).where(PushDevice.installation_id == installation_id)
            )
        ).first()
        now = beijing_now()
        if device is None:
            device = PushDevice(
                user_id=user_id,
                installation_id=installation_id,
                provider=provider,
                client_id=client_id,
                manufacturer=manufacturer,
                model=model,
                app_version=app_version,
            )
            self._session.add(device)
        else:
            device.user_id = user_id
            device.provider = provider
            device.client_id = client_id
            device.manufacturer = manufacturer
            device.model = model
            device.app_version = app_version
            device.active = True
            device.last_seen_at = now
        await self._session.commit()
        await self._session.refresh(device)
        return device

    async def deactivate(self, user_id: str, installation_id: str) -> None:
        device = (
            await self._session.exec(
                select(PushDevice).where(
                    PushDevice.user_id == user_id,
                    PushDevice.installation_id == installation_id,
                )
            )
        ).first()
        if device is not None:
            device.active = False
            await self._session.commit()


class PushOutboxRepository:
    def __init__(self, session: AsyncSession) -> None:
        self._session = session

    async def enqueue_for_user(
        self,
        *,
        user_id: str,
        proactive_message_id: str,
        title: str,
        body: str,
        payload_json: str,
    ) -> int:
        devices = list(
            (
                await self._session.exec(
                    select(PushDevice).where(
                        PushDevice.user_id == user_id,
                        PushDevice.active.is_(True),
                    )
                )
            ).all()
        )
        for device in devices:
            self._session.add(
                PushOutbox(
                    user_id=user_id,
                    device_id=device.id,
                    proactive_message_id=proactive_message_id,
                    title=title,
                    body=body,
                    payload_json=payload_json,
                )
            )
        await self._session.commit()
        return len(devices)

    async def next_due(self) -> tuple[PushOutbox, PushDevice] | None:
        statement = (
            select(PushOutbox, PushDevice)
            .join(PushDevice, PushDevice.id == PushOutbox.device_id)
            .where(
                PushOutbox.status == "pending",
                PushOutbox.next_attempt_at <= beijing_now(),
                PushDevice.active.is_(True),
            )
            .order_by(PushOutbox.next_attempt_at, PushOutbox.created_at)
            .limit(1)
        )
        return (await self._session.exec(statement)).first()

    async def mark_sent(self, outbox: PushOutbox, provider_message_id: str | None) -> None:
        outbox.status = "sent"
        outbox.provider_message_id = provider_message_id
        outbox.sent_at = beijing_now()
        outbox.last_error = None
        await self._session.commit()

    async def reschedule(
        self,
        outbox: PushOutbox,
        attempts: int,
        next_attempt_at: datetime,
        error: str,
    ) -> None:
        outbox.attempts = attempts
        outbox.next_attempt_at = next_attempt_at
        outbox.last_error = error[:2000]
        await self._session.commit()

    async def mark_failed(self, outbox: PushOutbox, attempts: int, error: str) -> None:
        outbox.status = "failed"
        outbox.attempts = attempts
        outbox.last_error = error[:2000]
        await self._session.commit()
