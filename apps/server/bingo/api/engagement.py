from fastapi import APIRouter, Request, Response, status

from bingo.api.dependencies import CurrentUserDependency, SessionDependency, get_service_context
from bingo.api.response import EnvelopeRoute
from bingo.schemas.engagement import ProactiveMessageResponse, RecommendationsResponse
from bingo.services import engagement as engagement_service

router = APIRouter(tags=["engagement"], route_class=EnvelopeRoute)


@router.get("/proactive/messages", response_model=list[ProactiveMessageResponse])
async def list_proactive_messages(
    session: SessionDependency, user: CurrentUserDependency
) -> list[ProactiveMessageResponse]:
    return await engagement_service.list_proactive_messages(session=session, user=user)


@router.post("/proactive/messages/{message_id}/ack", status_code=status.HTTP_204_NO_CONTENT)
async def acknowledge_proactive_message(
    message_id: str, session: SessionDependency, user: CurrentUserDependency
) -> Response:
    await engagement_service.acknowledge_proactive_message(
        message_id=message_id, session=session, user=user
    )
    return Response(status_code=204)


@router.get("/recommendations", response_model=RecommendationsResponse)
async def get_recommendations(
    request: Request, user: CurrentUserDependency, conversation_id: str | None = None
) -> RecommendationsResponse:
    return await engagement_service.get_recommendations(
        context=get_service_context(request), user=user, conversation_id=conversation_id
    )


@router.delete("/recommendations", status_code=status.HTTP_204_NO_CONTENT)
async def clear_recommendations(
    request: Request, user: CurrentUserDependency, conversation_id: str | None = None
) -> Response:
    await engagement_service.clear_recommendations(
        context=get_service_context(request), user=user, conversation_id=conversation_id
    )
    return Response(status_code=204)
