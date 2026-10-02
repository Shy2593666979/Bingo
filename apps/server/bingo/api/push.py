from fastapi import APIRouter, Response, status

from bingo.api.dependencies import CurrentUserDependency, SessionDependency
from bingo.api.response import EnvelopeRoute
from bingo.schemas.push import PushDeviceRegistration, PushDeviceResponse
from bingo.services import push as push_service

router = APIRouter(prefix="/push", tags=["push"], route_class=EnvelopeRoute)


@router.put("/devices", response_model=PushDeviceResponse)
async def register_push_device(
    body: PushDeviceRegistration, session: SessionDependency, user: CurrentUserDependency
) -> PushDeviceResponse:
    return await push_service.register_push_device(body=body, session=session, user=user)


@router.delete("/devices/{installation_id}", status_code=status.HTTP_204_NO_CONTENT)
async def unregister_push_device(
    installation_id: str, session: SessionDependency, user: CurrentUserDependency
) -> Response:
    await push_service.unregister_push_device(
        installation_id=installation_id, session=session, user=user
    )
    return Response(status_code=204)
