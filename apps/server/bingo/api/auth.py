import logging

from fastapi import APIRouter, HTTPException, status

from bingo.api.dependencies import (
    AccessTokenDependency,
    CurrentUserDependency,
    SessionDependency,
)
from bingo.db.models import User
from bingo.db.repositories import AuthSessionRepository, RoleRepository, UserRepository
from bingo.schemas.auth import (
    AuthResponse,
    Credentials,
    ProfileOptionsResponse,
    ProfileUpdate,
    UserProfileResponse,
)
from bingo.services.logging import log_event
from bingo.services.security import hash_password, verify_password

router = APIRouter(tags=["auth"])
logger = logging.getLogger(__name__)


def user_response(user: User) -> UserProfileResponse:
    return UserProfileResponse.model_validate(user, from_attributes=True)


@router.post("/auth/register", response_model=AuthResponse, status_code=status.HTTP_201_CREATED)
async def register(payload: Credentials, session: SessionDependency) -> AuthResponse:
    users = UserRepository(session)
    if await users.get_by_phone(payload.phone):
        log_event(logger, logging.WARNING, "auth.registration_failed", error_type="PhoneExists")
        raise HTTPException(status_code=status.HTTP_409_CONFLICT, detail="该手机号已注册")
    user = await users.create(payload.phone, hash_password(payload.password))
    token = await AuthSessionRepository(session).create(user.id)
    log_event(logger, logging.INFO, "auth.registered", user_id=user.id)
    return AuthResponse(access_token=token, user=user_response(user))


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
    return AuthResponse(access_token=token, user=user_response(user))


@router.post("/auth/logout", status_code=status.HTTP_204_NO_CONTENT)
async def logout(token: AccessTokenDependency, session: SessionDependency) -> None:
    user = await AuthSessionRepository(session).get_user(token)
    await AuthSessionRepository(session).delete(token)
    log_event(logger, logging.INFO, "auth.logged_out", user_id=user.id if user else None)


@router.get("/me", response_model=UserProfileResponse)
async def get_profile(user: CurrentUserDependency) -> UserProfileResponse:
    return user_response(user)


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
    return user_response(updated)


@router.get("/profile/options", response_model=ProfileOptionsResponse)
async def profile_options(session: SessionDependency) -> ProfileOptionsResponse:
    roles = await RoleRepository(session).list_enabled()
    return ProfileOptionsResponse(roles=tuple(role.name for role in roles))
