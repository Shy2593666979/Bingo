import asyncio
import json
from contextlib import aclosing

from fastapi import APIRouter, Query, Request, Response
from fastapi.responses import FileResponse, StreamingResponse

from bingo.api.dependencies import CurrentUserDependency, get_service_context
from bingo.api.response import EnvelopeRoute
from bingo.schemas.group_chat import GroupCreate, GroupSend, GroupUpdate, MemberAdd
from bingo.services import group_chat as service

router = APIRouter(tags=["group_chat"], route_class=EnvelopeRoute)


def engine(request):
    return get_service_context(request).group_chat


@router.get("/groups/{identifier}/messages/{message_id}/image")
async def group_image(
    identifier: str, message_id: str, request: Request, user: CurrentUserDependency
) -> FileResponse:
    path, mime_type = await engine(request).image_source(identifier, message_id, user.id)
    return FileResponse(path, media_type=mime_type)


@router.post("/groups", status_code=201)
async def create_group(payload: GroupCreate, request: Request, user: CurrentUserDependency) -> dict:
    return await engine(request).create(user, payload)


@router.get("/groups")
async def list_groups(request: Request, user: CurrentUserDependency) -> list[dict]:
    return await engine(request).list(user.id)


@router.get("/groups/{identifier}")
async def get_group(identifier: str, request: Request, user: CurrentUserDependency) -> dict:
    return await engine(request).get(identifier, user.id)


@router.patch("/groups/{identifier}")
async def update_group(
    identifier: str, payload: GroupUpdate, request: Request, user: CurrentUserDependency
) -> dict:
    return await engine(request).update(identifier, user.id, payload)


@router.post("/groups/{identifier}/members")
async def add_members(
    identifier: str, payload: MemberAdd, request: Request, user: CurrentUserDependency
) -> dict:
    return await engine(request).members(identifier, user.id, payload.role_ids)


@router.delete("/groups/{identifier}/members/{role_id}")
async def remove_member(
    identifier: str, role_id: str, request: Request, user: CurrentUserDependency
) -> dict:
    return await engine(request).members(identifier, user.id, remove=role_id)


@router.get("/groups/{identifier}/messages")
async def messages(
    identifier: str,
    request: Request,
    user: CurrentUserDependency,
    before_seq: int | None = Query(default=None, ge=1),
    limit: int = Query(default=100, ge=1, le=200),
) -> list[dict]:
    return await engine(request).messages(identifier, user.id, before_seq, limit)


@router.post("/groups/{identifier}/read", status_code=204)
async def read_group(
    identifier: str, request: Request, user: CurrentUserDependency, seq: int = Query(ge=0)
) -> Response:
    await engine(request).read(identifier, user.id, seq)
    return Response(status_code=204)


@router.get("/groups/{identifier}/messages/{message_id}/context")
async def message_context(
    identifier: str, message_id: str, request: Request, user: CurrentUserDependency
) -> list[dict]:
    return await engine(request).message_context(identifier, message_id, user.id)


@router.post("/groups/{identifier}/chat")
async def send_group(
    identifier: str, payload: GroupSend, request: Request, user: CurrentUserDependency
) -> dict:
    return await engine(request).begin(identifier, user, payload)


@router.post("/groups/{identifier}/messages/{message_id}/speech")
async def message_speech(
    identifier: str, message_id: str, request: Request, user: CurrentUserDependency
):
    context = get_service_context(request)
    text, voice = await engine(request).speech_source(identifier, message_id, user.id)
    voice = voice or context.settings.realtime_call.voice

    async def stream():
        async with aclosing(context.chat_speech.message_events(text, voice)) as events:
            async for item in events:
                yield json.dumps(item, ensure_ascii=False) + "\n"

    return StreamingResponse(
        stream(),
        media_type="application/x-ndjson",
        headers={"Cache-Control": "no-store", "X-Accel-Buffering": "no"},
    )


@router.get("/groups/{identifier}/runs/{run_id}/events")
async def events(
    identifier: str,
    run_id: str,
    request: Request,
    user: CurrentUserDependency,
    after_event_seq: int = Query(default=0, ge=0),
) -> dict:
    return await engine(request).events(identifier, run_id, user.id, after_event_seq)


@router.post("/groups/{identifier}/runs/{run_id}/cancel", status_code=204)
async def cancel(
    identifier: str, run_id: str, request: Request, user: CurrentUserDependency
) -> Response:
    await engine(request).cancel(identifier, user.id, run_id)
    return Response(status_code=204)


@router.post("/groups/{identifier}/chat/stream")
async def stream(
    identifier: str, payload: GroupSend, request: Request, user: CurrentUserDependency
) -> StreamingResponse:
    run = await engine(request).begin(identifier, user, payload)

    async def stream_events():
        cursor = 0
        while True:
            batch = await engine(request).events(identifier, run["run_id"], user.id, cursor)
            for item in batch["events"]:
                yield json.dumps(item, ensure_ascii=False) + "\n"
                cursor = item["event_seq"]
            if batch["status"] in service.TERMINAL and not batch.get("has_more"):
                break
            await asyncio.sleep(0.15)

    return StreamingResponse(
        stream_events(), media_type="application/x-ndjson", headers={"Cache-Control": "no-cache"}
    )


@router.delete("/groups/{identifier}/messages", status_code=204)
async def clear(identifier: str, request: Request, user: CurrentUserDependency) -> Response:
    await engine(request).clear(identifier, user.id)
    return Response(status_code=204)


@router.delete("/groups/{identifier}", status_code=204)
async def destroy(identifier: str, request: Request, user: CurrentUserDependency) -> Response:
    await engine(request).clear(identifier, user.id, destroy=True)
    return Response(status_code=204)
