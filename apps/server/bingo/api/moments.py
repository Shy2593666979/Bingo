import json

from fastapi import APIRouter, Request
from fastapi.responses import StreamingResponse

from bingo.api.dependencies import CurrentUserDependency, SessionDependency, get_service_context
from bingo.api.response import EnvelopeRoute
from bingo.schemas.moments import MomentFinishRequest, MomentRequest
from bingo.services import moments as moment_service

router = APIRouter(tags=["moments"], route_class=EnvelopeRoute)


@router.post("/moments/finish")
async def finish_moment(
    payload: MomentFinishRequest,
    request: Request,
    session: SessionDependency,
    user: CurrentUserDependency,
):
    return await moment_service.finish_moment(payload, get_service_context(request), session, user)


@router.post("/moments/stream")
async def stream_moment(
    payload: MomentRequest,
    request: Request,
    session: SessionDependency,
    user: CurrentUserDependency,
) -> StreamingResponse:
    events = await moment_service.subscribe_moment(
        payload, get_service_context(request), session, user
    )

    async def event_stream():
        try:
            async for event in events:
                yield json.dumps(event, ensure_ascii=False) + "\n"
        finally:
            await events.aclose()

    return StreamingResponse(
        event_stream(),
        media_type="application/x-ndjson",
        headers={"Cache-Control": "no-cache, no-transform", "X-Accel-Buffering": "no"},
    )
