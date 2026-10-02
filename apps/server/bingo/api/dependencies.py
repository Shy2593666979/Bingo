from collections.abc import AsyncIterator
from dataclasses import replace
from typing import Annotated

from fastapi import Depends, HTTPException, Request, status
from fastapi.security import HTTPAuthorizationCredentials, HTTPBearer
from sqlmodel.ext.asyncio.session import AsyncSession

from bingo.db.models import User
from bingo.services.auth import require_user
from bingo.services.context import ServiceContext

bearer_scheme = HTTPBearer(auto_error=False)


def get_service_context(request: Request) -> ServiceContext:
    return replace(
        request.app.state.services,
        runtime=request.app.state.runtime,
        chat_runs=request.app.state.chat_runs,
        voice_cloning=request.app.state.voice_cloning,
        engagement=request.app.state.engagement,
        public_base_url=str(request.base_url).rstrip("/"),
        client_address=request.client.host if request.client else "unknown",
    )


async def get_session(request: Request) -> AsyncIterator[AsyncSession]:
    async with request.app.state.database.session_factory() as session:
        yield session


SessionDependency = Annotated[AsyncSession, Depends(get_session)]


async def get_access_token(
    credentials: Annotated[HTTPAuthorizationCredentials | None, Depends(bearer_scheme)],
) -> str:
    if credentials is None or credentials.scheme.lower() != "bearer":
        raise HTTPException(
            status_code=status.HTTP_401_UNAUTHORIZED,
            detail="请先登录",
            headers={"WWW-Authenticate": "Bearer"},
        )
    return credentials.credentials


AccessTokenDependency = Annotated[str, Depends(get_access_token)]


async def get_current_user(
    token: AccessTokenDependency,
    session: SessionDependency,
) -> User:
    return await require_user(session, token)


CurrentUserDependency = Annotated[User, Depends(get_current_user)]
