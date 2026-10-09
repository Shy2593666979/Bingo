import logging
import time

from sqlalchemy import delete, update
from sqlmodel.ext.asyncio.session import AsyncSession

from bingo.db.models import AuthSession, User
from bingo.db.repositories import AuthSessionRepository, RoleRepository, UserRepository
from bingo.schemas.auth import (
    AuthResponse,
    ChangePassword,
    Credentials,
    PersonalityUpdate,
    ProfileOptionsResponse,
    ProfileUpdate,
    RecoveryProfile,
    ResetPassword,
    UserDetailsUpdate,
    UserProfileResponse,
)
from bingo.services.context import ServiceContext
from bingo.services.exceptions import ServiceError
from bingo.services.logging import log_event
from bingo.services.security import hash_password, hash_token, verify_password

logger = logging.getLogger(__name__)


async def authenticated_user(database, token: str):
    async with database.session_factory() as session:
        return await AuthSessionRepository(session).get_user(token)


async def require_user(session: AsyncSession, token: str) -> User:
    user = await AuthSessionRepository(session).get_user(token)
    if user is None:
        raise ServiceError(401, "登录已失效，请重新登录", {"WWW-Authenticate": "Bearer"})
    return user


async def change_password(payload: ChangePassword, user: User, session: AsyncSession) -> None:
    if not verify_password(payload.old_password, user.password_hash):
        raise ServiceError(400, "当前密码验证失败")
    user.password_hash = hash_password(payload.new_password)
    session.add(user)
    await session.exec(delete(AuthSession).where(AuthSession.user_id == user.id))
    await session.commit()


async def recovery_profile(payload: RecoveryProfile, user: User, session: AsyncSession) -> dict:
    if user.birthday:
        raise ServiceError(409, "已设置找回生日，不能重复设置")
    if not user.username:
        raise ServiceError(422, "请先设置用户名")
    changed = await session.exec(
        update(User)
        .where(User.id == user.id, User.birthday.is_(None))
        .values(birthday=payload.birthday.isoformat(), recovery_hash=None)
    )
    if changed.rowcount != 1:
        raise ServiceError(409, "已设置找回生日，不能重复设置")
    await session.commit()
    return {}


async def reset_password(
    payload: ResetPassword, session: AsyncSession, context: ServiceContext
) -> dict:
    attempts = getattr(context, "password_reset_attempts", {})
    context.password_reset_attempts = attempts
    now = time.monotonic()
    for key in list(attempts):
        if now - attempts[key][0] > 900:
            del attempts[key]
    address = context.client_address
    for key in ("phone:" + hash_token(payload.phone), "ip:" + address):
        started, count = attempts.get(key, (now, 0))
        if count >= 10 or len(attempts) >= 10000:
            raise ServiceError(429, "尝试过于频繁，请稍后再试")
        attempts[key] = (started, count + 1)
    user = await UserRepository(session).get_by_phone(payload.phone)
    if (
        not user
        or user.username != payload.username.strip()
        or (user.birthday != payload.birthday.isoformat())
    ):
        raise ServiceError(400, "找回信息验证失败，请检查后重试")
    changed = await session.exec(
        update(User)
        .where(
            User.id == user.id,
            User.username == payload.username.strip(),
            User.birthday == payload.birthday.isoformat(),
            User.password_hash == user.password_hash,
        )
        .values(password_hash=hash_password(payload.new_password), recovery_hash=None)
    )
    if changed.rowcount != 1:
        raise ServiceError(400, "找回信息验证失败，请检查后重试")
    await session.exec(delete(AuthSession).where(AuthSession.user_id == user.id))
    await session.commit()
    return {}


async def user_response(user: User, session) -> UserProfileResponse:
    response = UserProfileResponse.model_validate(user, from_attributes=True)
    role = await RoleRepository(session).get(user.role_id)
    if role and (not role.deleted):
        response.avatar_data = role.avatar_data
    return response


async def register(payload: Credentials, session: AsyncSession) -> AuthResponse:
    users = UserRepository(session)
    if await users.get_by_phone(payload.phone):
        log_event(logger, logging.WARNING, "auth.registration_failed", error_type="PhoneExists")
        raise ServiceError(status_code=409, detail="该手机号已注册")
    user = await users.create(payload.phone, hash_password(payload.password))
    token = await AuthSessionRepository(session).create(user.id)
    log_event(logger, logging.INFO, "auth.registered", user_id=user.id)
    return AuthResponse(access_token=token, user=await user_response(user, session))


async def login(payload: Credentials, session: AsyncSession) -> AuthResponse:
    user = await UserRepository(session).get_by_phone(payload.phone)
    if user is None or not verify_password(payload.password, user.password_hash):
        log_event(logger, logging.WARNING, "auth.login_failed", error_type="InvalidCredentials")
        raise ServiceError(status_code=401, detail="手机号或密码错误")
    token = await AuthSessionRepository(session).create(user.id)
    log_event(logger, logging.INFO, "auth.login_succeeded", user_id=user.id)
    return AuthResponse(access_token=token, user=await user_response(user, session))


async def logout(token: str, session: AsyncSession) -> None:
    user = await AuthSessionRepository(session).get_user(token)
    await AuthSessionRepository(session).delete(token)
    log_event(logger, logging.INFO, "auth.logged_out", user_id=user.id if user else None)


async def get_profile(user: User, session: AsyncSession) -> UserProfileResponse:
    return await user_response(user, session)


async def update_profile(
    payload: ProfileUpdate, user: User, session: AsyncSession
) -> UserProfileResponse:
    try:
        updated = await UserRepository(session).update_profile(
            user,
            username=payload.username,
            assistant_name=payload.assistant_name,
            personality=payload.personality,
            role=payload.role,
        )
    except ValueError as error:
        raise ServiceError(status_code=422, detail="无效的助手角色") from error
    return await user_response(updated, session)


async def update_user_details(
    payload: UserDetailsUpdate, user: User, session: AsyncSession
) -> dict:
    if user.birthday and user.birthday != payload.birthday.isoformat():
        raise ServiceError(409, "生日已用于账号找回，不能在首次资料页面修改")
    values = {
        "username": payload.username,
        "gender": payload.gender,
        "user_avatar_data": payload.user_avatar_data,
        "birthday": payload.birthday.isoformat(),
        "onboarding_complete": True,
        "recovery_hash": None,
    }
    statement = update(User).where(User.id == user.id)
    statement = statement.where(User.birthday == user.birthday)
    changed = await session.exec(statement.values(**values))
    if changed.rowcount != 1:
        raise ServiceError(409, "资料已更新，请重新加载后再试")
    await session.commit()
    await session.refresh(user)
    return {
        "user": (await user_response(user, session)).model_dump(mode="json"),
    }


async def update_personality(
    payload: PersonalityUpdate, user: User, session: AsyncSession
) -> UserProfileResponse:
    user.personality = payload.personality
    session.add(user)
    await session.commit()
    await session.refresh(user)
    return await user_response(user, session)


async def profile_options(session: AsyncSession, user: User) -> ProfileOptionsResponse:
    from bingo.services.roles import response_for_user

    roles = await RoleRepository(session).list_enabled(user.id)
    return ProfileOptionsResponse(
        roles=tuple(role.visible_name for role in roles),
        role_details=[await response_for_user(session, user, role) for role in roles],
    )
