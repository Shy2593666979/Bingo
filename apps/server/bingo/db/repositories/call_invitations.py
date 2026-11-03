from datetime import timedelta

from sqlmodel import select
from sqlmodel.ext.asyncio.session import AsyncSession

from bingo.db.models import (
    CallInvitation,
)
from bingo.db.time import beijing_now


class CallInvitationRepository:
    def __init__(self, session: AsyncSession, user_id: str) -> None:
        self._session = session
        self._user_id = user_id

    async def create(
        self,
        *,
        conversation_id: str,
        role_id: str | None,
        caller_name: str,
        caller_role: str | None,
        reason: str,
        lifetime_seconds: int = 30,
        cooldown_seconds: int = 15,
    ) -> CallInvitation:
        now = beijing_now()
        latest = (
            await self._session.exec(
                select(CallInvitation)
                .where(CallInvitation.user_id == self._user_id)
                .order_by(CallInvitation.created_at.desc())
                .limit(1)
            )
        ).first()
        if latest is not None and latest.status == "ringing":
            if latest.expires_at > now:
                return latest
            latest.status = "missed"
            latest.ended_at = now
        if (
            latest is not None
            and latest.status != "ringing"
            and latest.created_at > now - timedelta(seconds=cooldown_seconds)
        ):
            raise ValueError("刚刚已经发起过来电，请稍后再试")

        invitation = CallInvitation(
            user_id=self._user_id,
            conversation_id=conversation_id,
            role_id=role_id,
            caller_name=caller_name,
            caller_role=caller_role,
            reason=reason,
            expires_at=now + timedelta(seconds=lifetime_seconds),
        )
        self._session.add(invitation)
        await self._session.commit()
        await self._session.refresh(invitation)
        return invitation

    async def get(self, invitation_id: str) -> CallInvitation | None:
        return (
            await self._session.exec(
                select(CallInvitation).where(
                    CallInvitation.id == invitation_id,
                    CallInvitation.user_id == self._user_id,
                )
            )
        ).first()

    async def pending(self) -> CallInvitation | None:
        invitation = (
            await self._session.exec(
                select(CallInvitation)
                .where(
                    CallInvitation.user_id == self._user_id,
                    CallInvitation.status == "ringing",
                )
                .order_by(CallInvitation.created_at.desc())
                .limit(1)
            )
        ).first()
        return await self._expire_if_needed(invitation)

    async def set_status(self, invitation: CallInvitation, status: str) -> CallInvitation:
        now = beijing_now()
        invitation.status = status
        if status == "accepted":
            invitation.answered_at = now
        if status in {"rejected", "missed", "cancelled", "ended", "failed"}:
            invitation.ended_at = now
        await self._session.commit()
        await self._session.refresh(invitation)
        return invitation

    async def _expire_if_needed(self, invitation: CallInvitation | None) -> CallInvitation | None:
        if (
            invitation is not None
            and invitation.status == "ringing"
            and invitation.expires_at <= beijing_now()
        ):
            return await self.set_status(invitation, "missed")
        return invitation
