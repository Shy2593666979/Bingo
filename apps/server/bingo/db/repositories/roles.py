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

    @staticmethod
    def scope(user_id: str | None):
        """Only the twelve defaults are public companions; community templates are not."""
        default = Role.owner_id.is_(None) & Role.code.in_([role.code for role in BUILTIN_ROLES])
        if user_id is None:
            return default
        granted = Role.owner_id.is_(None) & Role.id.in_(
            select(UserCompanion.role_id).where(UserCompanion.user_id == user_id)
        )
        return or_(default, Role.owner_id == user_id, granted)

    async def get_by_name(self, name: str) -> Role | None:
        code = BUILTIN_RELATION_ALIASES.get(name)
        if code:
            name = next(role.relationship for role in BUILTIN_ROLES if role.code == code)
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
                self.scope(user_id),
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
        if role.owner_id == user.id:
            return True
        if not user.selective_companions and role.code in {item.code for item in BUILTIN_ROLES}:
            return True
        return await self._session.get(UserCompanion, (user.id, role.id)) is not None
