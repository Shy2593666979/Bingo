from sqlmodel.ext.asyncio.session import AsyncSession

from bingo.db.models import User
from bingo.db.repositories import PushDeviceRepository
from bingo.schemas.push import PushDeviceRegistration, PushDeviceResponse


async def register_push_device(
    body: PushDeviceRegistration, session: AsyncSession, user: User
) -> PushDeviceResponse:
    device = await PushDeviceRepository(session).upsert(
        user_id=user.id,
        installation_id=body.installation_id,
        provider=body.provider,
        client_id=body.client_id,
        manufacturer=body.manufacturer,
        model=body.model,
        app_version=body.app_version,
    )
    return PushDeviceResponse.model_validate(device, from_attributes=True)


async def unregister_push_device(installation_id: str, session: AsyncSession, user: User) -> None:
    await PushDeviceRepository(session).deactivate(user.id, installation_id)
    return None
