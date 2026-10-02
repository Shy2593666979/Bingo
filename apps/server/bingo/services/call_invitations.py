from sqlmodel import select
from sqlmodel.ext.asyncio.session import AsyncSession

from bingo.db.models import CallInvitation, Message, User
from bingo.db.repositories import CallInvitationRepository, ConversationRepository
from bingo.db.time import beijing_now
from bingo.schemas.call_invitation import CallInvitationResponse
from bingo.services.exceptions import ServiceError


def _response(invitation: CallInvitation) -> CallInvitationResponse:
    return CallInvitationResponse.model_validate(invitation, from_attributes=True)


async def _ensure_call_record(
    session: AsyncSession, user_id: str, invitation: CallInvitation, call_status: str
) -> None:
    run_id = f"incoming-call:{invitation.id}"
    existing = (await session.exec(select(Message).where(Message.run_id == run_id))).first()
    if existing is not None:
        return
    conversation = ConversationRepository(session, user_id)
    await conversation.add_message(
        invitation.conversation_id,
        "assistant",
        "未接来电",
        assistant_role=invitation.caller_role,
        role_id=invitation.role_id,
        run_id=run_id,
        message_type="call",
        call_status=call_status,
        call_duration_seconds=0,
    )
    await conversation.commit()


async def pending_call_invitation(
    session: AsyncSession, user: User
) -> CallInvitationResponse | None:
    invitation = await CallInvitationRepository(session, user.id).pending()
    if invitation is None:
        return None
    if invitation.status == "missed":
        await _ensure_call_record(session, user.id, invitation, "missed")
        return None
    if invitation.status != "ringing":
        return None
    return _response(invitation)


async def accept_call_invitation(
    invitation_id: str, session: AsyncSession, user: User
) -> CallInvitationResponse:
    repository = CallInvitationRepository(session, user.id)
    invitation = await repository.get(invitation_id)
    if invitation is None:
        raise ServiceError(status_code=404, detail="来电邀请不存在")
    if invitation.status == "accepted":
        return _response(invitation)
    if invitation.status != "ringing":
        raise ServiceError(status_code=409, detail="来电邀请已失效")
    if invitation.expires_at <= beijing_now():
        invitation = await repository.set_status(invitation, "missed")
        await _ensure_call_record(session, user.id, invitation, "missed")
        raise ServiceError(status_code=409, detail="来电邀请已超时")
    return _response(await repository.set_status(invitation, "accepted"))


async def reject_call_invitation(invitation_id: str, session: AsyncSession, user: User) -> None:
    repository = CallInvitationRepository(session, user.id)
    invitation = await repository.get(invitation_id)
    if invitation is None:
        raise ServiceError(status_code=404, detail="来电邀请不存在")
    if invitation.status == "ringing" and invitation.expires_at <= beijing_now():
        invitation = await repository.set_status(invitation, "missed")
        await _ensure_call_record(session, user.id, invitation, "missed")
    elif invitation.status == "ringing":
        invitation = await repository.set_status(invitation, "rejected")
        await _ensure_call_record(session, user.id, invitation, "rejected")
    return None


async def miss_call_invitation(invitation_id: str, session: AsyncSession, user: User) -> None:
    repository = CallInvitationRepository(session, user.id)
    invitation = await repository.get(invitation_id)
    if invitation is None:
        raise ServiceError(status_code=404, detail="来电邀请不存在")
    if invitation.status == "ringing":
        invitation = await repository.set_status(invitation, "missed")
    if invitation.status == "missed":
        await _ensure_call_record(session, user.id, invitation, "missed")
    return None
