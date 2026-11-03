from fastapi import APIRouter, Response
from fastapi.responses import FileResponse

from bingo.api.dependencies import CurrentUserDependency, SessionDependency
from bingo.api.response import EnvelopeRoute
from bingo.schemas.stickers import StickerUpload
from bingo.services import stickers as service

router = APIRouter(tags=["stickers"], route_class=EnvelopeRoute)


@router.get("/stickers")
async def list_stickers(user: CurrentUserDependency, session: SessionDependency) -> list[dict]:
    return await service.list_stickers(user, session)


@router.post("/stickers", status_code=201)
async def upload_sticker(
    payload: StickerUpload, user: CurrentUserDependency, session: SessionDependency
) -> dict:
    return await service.upload_sticker(payload, user, session)


@router.get("/stickers/{identifier}/image")
async def sticker_image(
    identifier: str, user: CurrentUserDependency, session: SessionDependency
) -> FileResponse:
    path, mime = await service.sticker_image(identifier, user, session)
    return FileResponse(path, media_type=mime, headers={"Cache-Control": "private, max-age=300"})


@router.delete("/stickers/{identifier}", status_code=204)
async def remove_sticker(
    identifier: str, user: CurrentUserDependency, session: SessionDependency
) -> Response:
    await service.remove_sticker(identifier, user, session)
    return Response(status_code=204)
