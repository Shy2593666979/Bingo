from sqlalchemy import or_
from sqlmodel import select
from sqlmodel.ext.asyncio.session import AsyncSession

from bingo.db.models import (
    Role,
    User,
    UserCompanion,
)
from bingo.roles.catalog import BUILTIN_RELATION_ALIASES, BUILTIN_ROLES


class RoleRepository:
    def __init__(self, session: AsyncSession) -> None:
        self._session = session

    async def get_by_name(self, name: str) -> Role | None:
        code = BUILTIN_RELATION_ALIASES.get(name)
        if code:
            name = next(role.name for role in BUILTIN_ROLES if role.code == code)
        return (
            await self._session.exec(
                select(Role).where(
                    Role.name == name, Role.owner_id.is_(None), Role.deleted.is_(False)
                )
            )
        ).first()

    async def get(self, role_id: str | None) -> Role | None:
        if role_id is None:
            return None
        return await self._session.get(Role, role_id)

    async def list_enabled(self, user_id: str | None = None) -> list[Role]:
        statement = (
            select(Role)
            .where(
                Role.enabled.is_(True),
                Role.deleted.is_(False),
                or_(Role.owner_id.is_(None), Role.owner_id == user_id),
            )
            .order_by(Role.sort_order, Role.name)
        )
        user = await self._session.get(User, user_id) if user_id else None
        if user and user.selective_companions:
            statement = statement.where(
                or_(
                    Role.owner_id == user.id,
                    Role.id.in_(
                        select(UserCompanion.role_id).where(UserCompanion.user_id == user.id)
                    ),
                )
            )
        return list((await self._session.exec(statement)).all())

    async def can_access(self, user: User, role: Role | None) -> bool:
        if not role or role.deleted or not role.enabled or role.owner_id not in {None, user.id}:
            return False
        if role.owner_id == user.id or not user.selective_companions:
            return True
        return await self._session.get(UserCompanion, (user.id, role.id)) is not None
