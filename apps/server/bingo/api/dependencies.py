from collections.abc import AsyncIterator
from typing import Annotated

from fastapi import Depends, HTTPException, Request, status
from fastapi.security import HTTPAuthorizationCredentials, HTTPBearer
from sqlmodel.ext.asyncio.session import AsyncSession

from bingo.db.models import User
from bingo.db.repositories import AuthSessionRepository

bearer_scheme = HTTPBearer(auto_error=False)


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
    user = await AuthSessionRepository(session).get_user(token)
    if user is None:
        raise HTTPException(
            status_code=status.HTTP_401_UNAUTHORIZED,
            detail="登录已失效，请重新登录",
            headers={"WWW-Authenticate": "Bearer"},
        )
    return user


CurrentUserDependency = Annotated[User, Depends(get_current_user)]
