from sqlmodel.ext.asyncio.session import AsyncSession

from bingo.background import EngagementService
from bingo.db.models import User
from bingo.db.repositories import ProactiveMessageRepository
from bingo.schemas.engagement import ProactiveMessageResponse, RecommendationsResponse
from bingo.services.context import ServiceContext
from bingo.services.exceptions import ServiceError


async def list_proactive_messages(
    session: AsyncSession, user: User
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


async def acknowledge_proactive_message(message_id: str, session: AsyncSession, user: User) -> None:
    acknowledged = await ProactiveMessageRepository(session, user.id).acknowledge(message_id)
    if not acknowledged:
        raise ServiceError(status_code=404, detail="主动消息不存在")
    return None


async def get_recommendations(
    context: ServiceContext, user: User, conversation_id: str | None = None
) -> RecommendationsResponse:
    service: EngagementService | None = context.engagement
    items = (
        [] if service is None else await service.recommendations_for_entry(user.id, conversation_id)
    )
    return RecommendationsResponse(items=items)


async def clear_recommendations(
    context: ServiceContext, user: User, conversation_id: str | None = None
) -> None:
    service: EngagementService | None = context.engagement
    if service is not None:
        await service.clear_recommendations(user.id, conversation_id)
    return None
