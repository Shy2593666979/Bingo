from fastapi import APIRouter, HTTPException, Request, Response, status

from bingo.api.dependencies import CurrentUserDependency, SessionDependency
from bingo.background import EngagementService
from bingo.db.repositories import ProactiveMessageRepository
from bingo.schemas.engagement import ProactiveMessageResponse, RecommendationsResponse

router = APIRouter(tags=["engagement"])


@router.get("/proactive/messages", response_model=list[ProactiveMessageResponse])
async def list_proactive_messages(
    session: SessionDependency,
    user: CurrentUserDependency,
) -> list[ProactiveMessageResponse]:
    rows = await ProactiveMessageRepository(session, user.id).list_pending()
    return [
        ProactiveMessageResponse(
            id=proactive.id,
            conversation_id=proactive.conversation_id,
            message_id=message.id,
            content=message.content,
            stage=proactive.stage,
            created_at=message.created_at,
            assistant_role=message.assistant_role,
        )
        for proactive, message in rows
    ]


@router.post("/proactive/messages/{message_id}/ack", status_code=status.HTTP_204_NO_CONTENT)
async def acknowledge_proactive_message(
    message_id: str,
    session: SessionDependency,
    user: CurrentUserDependency,
) -> Response:
    acknowledged = await ProactiveMessageRepository(session, user.id).acknowledge(message_id)
    if not acknowledged:
        raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail="主动消息不存在")
    return Response(status_code=status.HTTP_204_NO_CONTENT)


@router.get("/recommendations", response_model=RecommendationsResponse)
async def get_recommendations(
    request: Request,
    user: CurrentUserDependency,
) -> RecommendationsResponse:
    service: EngagementService | None = request.app.state.engagement
    items = [] if service is None else await service.recommendations_for_entry(user.id)
    return RecommendationsResponse(items=items)


@router.delete("/recommendations", status_code=status.HTTP_204_NO_CONTENT)
async def clear_recommendations(
    request: Request,
    user: CurrentUserDependency,
) -> Response:
    service: EngagementService | None = request.app.state.engagement
    if service is not None:
        await service.clear_recommendations(user.id)
    return Response(status_code=status.HTTP_204_NO_CONTENT)
