from datetime import timedelta

from sqlalchemy import delete
from sqlmodel import select
from sqlmodel.ext.asyncio.session import AsyncSession

from bingo.db.models import (
    AuthSession,
    User,
)
from bingo.db.time import beijing_now
from bingo.services.security import hash_token, new_access_token

from .roles import RoleRepository


class UserRepository:
    def __init__(self, session: AsyncSession) -> None:
        self._session = session

    async def get_by_phone(self, phone: str) -> User | None:
        return (await self._session.exec(select(User).where(User.phone == phone))).first()

    async def get(self, user_id: str) -> User | None:
        return await self._session.get(User, user_id)

    async def create(
        self, phone: str, password_hash: str, *, selective_companions: bool = False
    ) -> User:
        user = User(
            phone=phone,
            password_hash=password_hash,
            selective_companions=selective_companions,
            companion_selection_complete=not selective_companions,
        )
        self._session.add(user)
        await self._session.commit()
        await self._session.refresh(user)
        return user

    async def update_profile(
        self,
        user: User,
        *,
        username: str,
        assistant_name: str,
        personality: str,
        role: str,
    ) -> User:
        roles = RoleRepository(self._session)
        selected_role = await roles.get(role) or await roles.get_by_name(role)
        if (
            selected_role is None
            or not selected_role.enabled
            or selected_role.deleted
            or not await roles.can_access(user, selected_role)
        ):
            raise ValueError("Invalid assistant role")
        if user.role_id != selected_role.id:
            user.role_changed_at = beijing_now()
        user.role_id = selected_role.id
        user.username = username
        user.assistant_name = assistant_name
        user.personality = personality
        user.role = selected_role.visible_name
        user.onboarding_complete = True
        await self._session.commit()
        await self._session.refresh(user)
        return user


class AuthSessionRepository:
    def __init__(self, session: AsyncSession) -> None:
        self._session = session

    async def create(self, user_id: str, lifetime_days: int = 90) -> str:
        token = new_access_token()
        auth_session = AuthSession(
            user_id=user_id,
            token_hash=hash_token(token),
            expires_at=beijing_now() + timedelta(days=lifetime_days),
        )
        self._session.add(auth_session)
        await self._session.commit()
        return token

    async def get_user(self, token: str) -> User | None:
        statement = (
            select(User)
            .join(AuthSession, AuthSession.user_id == User.id)
            .where(
                AuthSession.token_hash == hash_token(token),
                AuthSession.expires_at > beijing_now(),
            )
        )
        return (await self._session.exec(statement)).first()

    async def delete(self, token: str) -> None:
        await self._session.exec(
            delete(AuthSession).where(AuthSession.token_hash == hash_token(token))
        )
        await self._session.commit()
