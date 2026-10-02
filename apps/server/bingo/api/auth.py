import hmac
import logging
import secrets
import time

from fastapi import APIRouter, HTTPException, Request, status
from sqlalchemy import delete, update

from bingo.api.dependencies import (
    AccessTokenDependency,
    CurrentUserDependency,
    SessionDependency,
)
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
from bingo.services.logging import log_event
from bingo.services.security import hash_password, hash_token, verify_password

router = APIRouter(tags=["auth"])
logger = logging.getLogger(__name__)


@router.post("/me/password", status_code=204)
async def change_password(
    payload: ChangePassword, user: CurrentUserDependency, session: SessionDependency
) -> None:
    if not verify_password(payload.old_password, user.password_hash):
        raise HTTPException(400, "当前密码验证失败")
    user.password_hash = hash_password(payload.new_password)
    session.add(user)
    await session.exec(delete(AuthSession).where(AuthSession.user_id == user.id))
    await session.commit()


@router.post("/me/recovery-profile")
async def recovery_profile(
    payload: RecoveryProfile, user: CurrentUserDependency, session: SessionDependency
) -> dict:
    if user.recovery_hash:
        raise HTTPException(409, "已设置找回信息，不能覆盖恢复码")
    if not user.username:
        raise HTTPException(422, "请先设置用户名")
    code = secrets.token_urlsafe(24)
    changed = await session.exec(
        update(User)
        .where(User.id == user.id, User.recovery_hash.is_(None))
        .values(birthday=payload.birthday.isoformat(), recovery_hash=hash_token(code))
    )
    if changed.rowcount != 1:
        raise HTTPException(409, "已设置找回信息，不能覆盖恢复码")
    await session.commit()
    return {"recovery_code": code}


@router.post("/auth/reset-password")
async def reset_password(
    payload: ResetPassword, session: SessionDependency, request: Request
) -> dict:
    attempts = getattr(request.app.state, "password_reset_attempts", {})
    request.app.state.password_reset_attempts = attempts
    now = time.monotonic()
    for key in list(attempts):
        if now - attempts[key][0] > 900:
            del attempts[key]
    address = request.client.host if request.client else "unknown"
    for key in ("phone:" + hash_token(payload.phone), "ip:" + address):
        started, count = attempts.get(key, (now, 0))
        if count >= 10 or len(attempts) >= 10000:
            raise HTTPException(429, "尝试过于频繁，请稍后再试")
        attempts[key] = (started, count + 1)
    user = await UserRepository(session).get_by_phone(payload.phone)
    supplied_hash = hash_token(payload.recovery_code)
    valid_code = hmac.compare_digest(
        supplied_hash, user.recovery_hash or "0" * 64 if user else "0" * 64
    )
    if (
        not user
        or not valid_code
        or user.username != payload.username.strip()
        or user.birthday != payload.birthday.isoformat()
    ):
        raise HTTPException(400, "找回信息验证失败，请检查后重试")
    code = secrets.token_urlsafe(24)
    changed = await session.exec(
        update(User)
        .where(User.id == user.id, User.recovery_hash == supplied_hash)
        .values(password_hash=hash_password(payload.new_password), recovery_hash=hash_token(code))
    )
    if changed.rowcount != 1:
        raise HTTPException(400, "找回信息验证失败，请检查后重试")
    await session.exec(delete(AuthSession).where(AuthSession.user_id == user.id))
    await session.commit()
    return {"recovery_code": code}


async def user_response(user: User, session) -> UserProfileResponse:
    response = UserProfileResponse.model_validate(user, from_attributes=True)
    role = await RoleRepository(session).get(user.role_id)
    if role and not role.deleted:
        response.avatar_data = role.avatar_data
    return response


@router.post("/auth/register", response_model=AuthResponse, status_code=status.HTTP_201_CREATED)
async def register(payload: Credentials, session: SessionDependency) -> AuthResponse:
    users = UserRepository(session)
    if await users.get_by_phone(payload.phone):
        log_event(logger, logging.WARNING, "auth.registration_failed", error_type="PhoneExists")
        raise HTTPException(status_code=status.HTTP_409_CONFLICT, detail="该手机号已注册")
    user = await users.create(payload.phone, hash_password(payload.password))
    token = await AuthSessionRepository(session).create(user.id)
    log_event(logger, logging.INFO, "auth.registered", user_id=user.id)
    return AuthResponse(access_token=token, user=await user_response(user, session))


@router.post("/auth/login", response_model=AuthResponse)
async def login(payload: Credentials, session: SessionDependency) -> AuthResponse:
    user = await UserRepository(session).get_by_phone(payload.phone)
    if user is None or not verify_password(payload.password, user.password_hash):
        log_event(logger, logging.WARNING, "auth.login_failed", error_type="InvalidCredentials")
        raise HTTPException(
            status_code=status.HTTP_401_UNAUTHORIZED,
            detail="手机号或密码错误",
        )
    token = await AuthSessionRepository(session).create(user.id)
    log_event(logger, logging.INFO, "auth.login_succeeded", user_id=user.id)
    return AuthResponse(access_token=token, user=await user_response(user, session))


@router.post("/auth/logout", status_code=status.HTTP_204_NO_CONTENT)
async def logout(token: AccessTokenDependency, session: SessionDependency) -> None:
    user = await AuthSessionRepository(session).get_user(token)
    await AuthSessionRepository(session).delete(token)
    log_event(logger, logging.INFO, "auth.logged_out", user_id=user.id if user else None)


@router.get("/me", response_model=UserProfileResponse)
async def get_profile(
    user: CurrentUserDependency,
    session: SessionDependency,
) -> UserProfileResponse:
    return await user_response(user, session)


@router.put("/me/profile", response_model=UserProfileResponse)
async def update_profile(
    payload: ProfileUpdate,
    user: CurrentUserDependency,
    session: SessionDependency,
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
        raise HTTPException(
            status_code=status.HTTP_422_UNPROCESSABLE_CONTENT,
            detail="无效的助手角色",
        ) from error
    return await user_response(updated, session)


@router.put("/me/user-profile")
async def update_user_details(
    payload: UserDetailsUpdate, user: CurrentUserDependency, session: SessionDependency
) -> dict:
    if user.recovery_hash and user.birthday != payload.birthday.isoformat():
        raise HTTPException(409, "生日已用于账号找回，不能在首次资料页面修改")
    code = None if user.recovery_hash else secrets.token_urlsafe(24)
    values = {
        "username": payload.username,
        "gender": payload.gender,
        "user_avatar_data": payload.user_avatar_data,
        "birthday": payload.birthday.isoformat(),
        "onboarding_complete": True,
    }
    if code:
        values["recovery_hash"] = hash_token(code)
    statement = update(User).where(User.id == user.id)
    if code:
        statement = statement.where(User.recovery_hash.is_(None))
    changed = await session.exec(statement.values(**values))
    if changed.rowcount != 1:
        raise HTTPException(409, "资料已更新，请重新加载后再试")
    await session.commit()
    await session.refresh(user)
    return {
        "user": (await user_response(user, session)).model_dump(mode="json"),
        "recovery_code": code,
    }


@router.put("/me/personality", response_model=UserProfileResponse)
async def update_personality(
    payload: PersonalityUpdate, user: CurrentUserDependency, session: SessionDependency
) -> UserProfileResponse:
    user.personality = payload.personality
    session.add(user)
    await session.commit()
    await session.refresh(user)
    return await user_response(user, session)


@router.get("/profile/options", response_model=ProfileOptionsResponse)
async def profile_options(
    session: SessionDependency,
    user: CurrentUserDependency,
) -> ProfileOptionsResponse:
    from bingo.api.roles import role_response

    roles = await RoleRepository(session).list_enabled(user.id)
    return ProfileOptionsResponse(
        roles=tuple(role.visible_name for role in roles),
        role_details=[role_response(role) for role in roles],
    )
