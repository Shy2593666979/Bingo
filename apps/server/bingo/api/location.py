from fastapi import APIRouter, Request, Response

from bingo.api.dependencies import CurrentUserDependency
from bingo.api.response import EnvelopeRoute
from bingo.schemas.location import RegionLocation

router = APIRouter(tags=["location"], route_class=EnvelopeRoute)


@router.get("/me/location")
async def current_location(request: Request, user: CurrentUserDependency) -> dict | None:
    return await request.app.state.location.current(user.id)


@router.put("/me/location")
async def update_location(
    payload: RegionLocation, request: Request, user: CurrentUserDependency
) -> dict:
    return await request.app.state.location.update(user.id, payload)


@router.delete("/me/location", status_code=204)
async def clear_location(request: Request, user: CurrentUserDependency) -> Response:
    await request.app.state.location.clear(user.id)
    return Response(status_code=204)
