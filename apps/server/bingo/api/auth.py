from fastapi import APIRouter, Request, Response, status

from bingo.api.dependencies import (
    AccessTokenDependency,
    CurrentUserDependency,
    SessionDependency,
    get_service_context,
)
from bingo.api.response import EnvelopeRoute
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
from bingo.services import auth as auth_service

router = APIRouter(tags=["auth"], route_class=EnvelopeRoute)


@router.post("/me/password", status_code=204)
async def change_password(
    payload: ChangePassword, user: CurrentUserDependency, session: SessionDependency
) -> None:
    await auth_service.change_password(payload=payload, user=user, session=session)
    return Response(status_code=204)


@router.post("/me/recovery-profile")
async def recovery_profile(
    payload: RecoveryProfile, user: CurrentUserDependency, session: SessionDependency
) -> dict:
    return await auth_service.recovery_profile(payload=payload, user=user, session=session)


@router.post("/auth/reset-password")
async def reset_password(
    payload: ResetPassword, session: SessionDependency, request: Request
) -> dict:
    return await auth_service.reset_password(
        payload=payload, session=session, context=get_service_context(request)
    )


@router.post("/auth/register", response_model=AuthResponse, status_code=status.HTTP_201_CREATED)
async def register(payload: Credentials, session: SessionDependency) -> AuthResponse:
    return await auth_service.register(payload=payload, session=session)


@router.post("/auth/login", response_model=AuthResponse)
async def login(payload: Credentials, session: SessionDependency) -> AuthResponse:
    return await auth_service.login(payload=payload, session=session)


@router.post("/auth/logout", status_code=status.HTTP_204_NO_CONTENT)
async def logout(token: AccessTokenDependency, session: SessionDependency) -> None:
    await auth_service.logout(token=token, session=session)
    return Response(status_code=204)


@router.get("/me", response_model=UserProfileResponse)
async def get_profile(
    user: CurrentUserDependency, session: SessionDependency
) -> UserProfileResponse:
    return await auth_service.get_profile(user=user, session=session)


@router.put("/me/profile", response_model=UserProfileResponse)
async def update_profile(
    payload: ProfileUpdate, user: CurrentUserDependency, session: SessionDependency
) -> UserProfileResponse:
    return await auth_service.update_profile(payload=payload, user=user, session=session)


@router.put("/me/user-profile")
async def update_user_details(
    payload: UserDetailsUpdate, user: CurrentUserDependency, session: SessionDependency
) -> dict:
    return await auth_service.update_user_details(payload=payload, user=user, session=session)


@router.put("/me/personality", response_model=UserProfileResponse)
async def update_personality(
    payload: PersonalityUpdate, user: CurrentUserDependency, session: SessionDependency
) -> UserProfileResponse:
    return await auth_service.update_personality(payload=payload, user=user, session=session)


@router.get("/profile/options", response_model=ProfileOptionsResponse)
async def profile_options(
    session: SessionDependency, user: CurrentUserDependency
) -> ProfileOptionsResponse:
    return await auth_service.profile_options(session=session, user=user)
