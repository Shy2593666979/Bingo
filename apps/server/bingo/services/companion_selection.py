"""Account-owned built-ins, chosen explicitly during modern registration."""

from sqlalchemy import update
from sqlmodel import select

from bingo.db.models import User, UserCompanion
from bingo.db.repositories import RoleRepository
from bingo.roles.catalog import default_personality
from bingo.services.auth import user_response
from bingo.services.companion_welcome import create_welcome_chats
from bingo.services.exceptions import ServiceError
from bingo.services.roles import response_for_user


async def candidates(user, session):
    return [
        await response_for_user(session, user, role)
        for role in await RoleRepository(session).list_enabled()
    ]


async def complete(user, session, ids):
    existing = set(
        (
            await session.exec(
                select(UserCompanion.role_id).where(UserCompanion.user_id == user.id)
            )
        ).all()
    )
    if user.companion_selection_complete:
        if user.selective_companions and existing == set(ids):
            return await user_response(user, session)
        raise ServiceError(409, "已完成搭子选择")
    if not user.onboarding_complete or not user.birthday:
        raise ServiceError(409, "请先完善个人资料")
    available = {role.id: role for role in await RoleRepository(session).list_enabled()}
    if any(identifier not in available for identifier in ids):
        raise ServiceError(422, "所选搭子不可用，请刷新后重试")
    first = available[ids[0]]
    changed = await session.exec(
        update(User)
        .where(
            User.id == user.id,
            User.companion_selection_complete.is_(False),
        )
        .values(
            companion_selection_complete=True,
            role_id=first.id,
            role=first.visible_name,
            assistant_name=first.nickname,
            personality=default_personality(first, user.personality),
        )
    )
    if changed.rowcount != 1:
        await session.rollback()
        raise ServiceError(409, "选择状态已更新，请刷新后重试")
    for identifier in ids:
        session.add(UserCompanion(user_id=user.id, role_id=identifier))
    await create_welcome_chats(user, session, [available[identifier] for identifier in ids])
    await session.commit()
    await session.refresh(user)
    return await user_response(user, session)
