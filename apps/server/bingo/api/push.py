from fastapi import APIRouter, Response, status

from bingo.api.dependencies import CurrentUserDependency, SessionDependency
from bingo.db.repositories import PushDeviceRepository
from bingo.schemas.push import PushDeviceRegistration, PushDeviceResponse

router = APIRouter(prefix="/push", tags=["push"])


@router.put("/devices", response_model=PushDeviceResponse)
async def register_push_device(
    body: PushDeviceRegistration,
    session: SessionDependency,
    user: CurrentUserDependency,
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


@router.delete("/devices/{installation_id}", status_code=status.HTTP_204_NO_CONTENT)
async def unregister_push_device(
    installation_id: str,
    session: SessionDependency,
    user: CurrentUserDependency,
) -> Response:
    await PushDeviceRepository(session).deactivate(user.id, installation_id)
    return Response(status_code=status.HTTP_204_NO_CONTENT)
