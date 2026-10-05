from typing import Literal

from fastapi import APIRouter, Query, Request
from fastapi.responses import Response

from bingo.api.dependencies import CurrentUserDependency, get_service_context
from bingo.api.response import EnvelopeRoute
from bingo.schemas.maps import LocationResults

router = APIRouter(tags=["maps"], route_class=EnvelopeRoute)


@router.get("/locations/search")
async def search_locations(
    request: Request,
    user: CurrentUserDependency,
    keywords: str = Query(min_length=1, max_length=80),
    city: str = Query(default="", max_length=60),
) -> LocationResults:
    return await get_service_context(request).maps.search(user.id, keywords.strip(), city.strip())


@router.get("/locations/reverse")
async def reverse_location(
    request: Request,
    user: CurrentUserDependency,
    longitude: float = Query(ge=-180, le=180, allow_inf_nan=False),
    latitude: float = Query(ge=-85, le=85, allow_inf_nan=False),
    coordinate_system: Literal["GCJ-02", "WGS84"] = "GCJ-02",
) -> LocationResults:
    return await get_service_context(request).maps.reverse(
        user.id, longitude, latitude, coordinate_system
    )


@router.get("/locations/map")
async def location_map(
    request: Request,
    user: CurrentUserDependency,
    longitude: float = Query(ge=-180, le=180, allow_inf_nan=False),
    latitude: float = Query(ge=-85, le=85, allow_inf_nan=False),
    zoom: int = Query(default=15, ge=3, le=18),
    height: int = Query(default=220, ge=220, le=640),
    marker: bool = True,
) -> Response:
    data = await get_service_context(request).maps.map_image(
        user.id, longitude, latitude, zoom, height, marker
    )
    return Response(data, media_type="image/png", headers={"Cache-Control": "private, max-age=600"})
