from typing import Literal

from fastapi import APIRouter, Path, Query, Response

from bingo.api.dependencies import CurrentUserDependency, SessionDependency
from bingo.api.response import EnvelopeRoute
from bingo.schemas.community import (
    CommentCreate,
    FavoriteUpdate,
    LikeUpdate,
    ReportCreate,
    ShareCreate,
)
from bingo.services import community as service

router = APIRouter(tags=["community"], route_class=EnvelopeRoute)


@router.put("/community/characters/{identifier}/like")
async def like_character(
    identifier: str, payload: LikeUpdate, user: CurrentUserDependency, session: SessionDependency
) -> dict:
    return await service.set_like(session, user, identifier, payload.liked)


@router.get("/community/characters/{identifier}/comments")
async def comments(
    identifier: str,
    user: CurrentUserDependency,
    session: SessionDependency,
    offset: int = Query(default=0, ge=0),
    limit: int = Query(default=20, ge=1, le=50),
) -> dict:
    return await service.list_comments(session, user, identifier, offset, limit)


@router.post("/community/characters/{identifier}/comments", status_code=201)
async def add_comment(
    identifier: str, payload: CommentCreate, user: CurrentUserDependency, session: SessionDependency
) -> dict:
    return await service.add_comment(session, user, identifier, payload)


@router.delete("/community/characters/{identifier}/comments/{comment_id}", status_code=204)
async def delete_comment(
    identifier: str, comment_id: str, user: CurrentUserDependency, session: SessionDependency
) -> Response:
    await service.delete_comment(session, user, identifier, comment_id)
    return Response(status_code=204)


@router.get("/community/characters")
async def list_characters(
    user: CurrentUserDependency,
    session: SessionDependency,
    q: str = Query(default="", max_length=100),
    scope: Literal["all", "mine", "favorites", "recommended"] = "all",
    sort: Literal["latest", "popular"] = "latest",
    offset: int = Query(default=0, ge=0),
    limit: int = Query(default=20, ge=1, le=40),
) -> dict:
    return await service.list_shares(
        session, user, query=q, scope=scope, sort=sort, offset=offset, limit=limit
    )


@router.post("/community/characters", status_code=201)
async def publish_character(
    payload: ShareCreate, user: CurrentUserDependency, session: SessionDependency
) -> dict:
    return await service.publish(session, user, payload)


@router.get("/community/characters/{identifier}")
async def character_detail(
    identifier: str, user: CurrentUserDependency, session: SessionDependency
) -> dict:
    return await service.get_share(session, user, identifier)


@router.get("/community/characters/{identifier}/avatar")
async def character_avatar(
    identifier: str, user: CurrentUserDependency, session: SessionDependency
) -> Response:
    asset = await service.avatar(session, user, identifier)
    return Response(asset.data, media_type=asset.media_type, headers=asset.headers)


@router.get("/community/characters/{identifier}/images/{index}")
async def character_image(
    identifier: str,
    user: CurrentUserDependency,
    session: SessionDependency,
    index: int = Path(ge=0, le=2),
) -> Response:
    asset = await service.image(session, user, identifier, index)
    return Response(asset.data, media_type=asset.media_type, headers=asset.headers)


@router.post("/community/characters/{identifier}/install")
async def install_character(
    identifier: str, user: CurrentUserDependency, session: SessionDependency
) -> dict:
    return await service.install(session, user, identifier)


@router.put("/community/characters/{identifier}/favorite")
async def favorite_character(
    identifier: str,
    payload: FavoriteUpdate,
    user: CurrentUserDependency,
    session: SessionDependency,
) -> dict:
    return await service.set_favorite(session, user, identifier, payload.favorite)


@router.delete("/community/characters/{identifier}", status_code=204)
async def withdraw_character(
    identifier: str, user: CurrentUserDependency, session: SessionDependency
) -> Response:
    await service.withdraw(session, user, identifier)
    return Response(status_code=204)


@router.post("/community/characters/{identifier}/reports", status_code=204)
async def report_character(
    identifier: str, payload: ReportCreate, user: CurrentUserDependency, session: SessionDependency
) -> Response:
    await service.report(session, user, identifier, payload.reason)
    return Response(status_code=204)
