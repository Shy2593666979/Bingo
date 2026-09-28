import logging
from collections.abc import AsyncIterator
from contextlib import asynccontextmanager

from fastapi import FastAPI
from fastapi.middleware.cors import CORSMiddleware

from bingo.agent.model_client import create_model_client
from bingo.agent.runtime import AgentRuntime
from bingo.api import (
    asr,
    auth,
    call_invitations,
    chat,
    conversations,
    device_actions,
    engagement,
    memories,
    push,
    realtime_calls,
)
from bingo.api.middleware import RequestLoggingMiddleware
from bingo.background import EngagementService
from bingo.config import Settings, get_settings
from bingo.db.session import Database
from bingo.push import PushService, create_push_provider
from bingo.services.chat_runs import ChatRunService
from bingo.services.logging import configure_logging, log_event
from bingo.tools import create_tool_registry

logger = logging.getLogger(__name__)


def create_app(settings: Settings | None = None) -> FastAPI:
    resolved_settings = settings or get_settings()
    if resolved_settings.app.environment != "test":
        configure_logging(resolved_settings.logging)
    database = Database(resolved_settings.database.url)
    model_client = create_model_client(resolved_settings)
    push_service = PushService(
        database.session_factory,
        create_push_provider(resolved_settings),
        poll_seconds=resolved_settings.push.worker_poll_seconds,
    )
    engagement_service = (
        None
        if resolved_settings.app.environment == "test"
        else EngagementService(
            database.session_factory,
            model_client,
            redis_url=resolved_settings.redis.url,
            follow_up_delays=resolved_settings.engagement.follow_up_delays_seconds,
            recommendation_delay=resolved_settings.engagement.recommendation_delay_seconds,
            poll_seconds=resolved_settings.engagement.worker_poll_seconds,
            push_service=push_service,
            timezone=resolved_settings.app.timezone,
        )
    )
    tool_registry = create_tool_registry()
    runtime = AgentRuntime(
        model_client,
        tool_registry,
        assistant_name=resolved_settings.agent.assistant_name,
        persona=resolved_settings.agent.assistant_persona,
        timezone=resolved_settings.app.timezone,
        engagement=engagement_service,
    )
    chat_runs = ChatRunService(database.session_factory, runtime)

    @asynccontextmanager
    async def lifespan(application: FastAPI) -> AsyncIterator[None]:
        await database.initialize()
        application.state.database = database
        application.state.runtime = runtime
        application.state.chat_runs = chat_runs
        application.state.tools = tool_registry
        application.state.engagement = engagement_service
        application.state.settings = resolved_settings
        application.state.push = push_service
        await push_service.start()
        if engagement_service is not None:
            await engagement_service.start()
        log_event(logger, logging.INFO, "application.started")
        yield
        await chat_runs.close()
        if engagement_service is not None:
            await engagement_service.close()
        await push_service.close()
        await database.dispose()
        log_event(logger, logging.INFO, "application.stopped")

    application = FastAPI(
        title=resolved_settings.app.name,
        version="0.1.0",
        lifespan=lifespan,
    )
    application.add_middleware(RequestLoggingMiddleware)
    application.add_middleware(
        CORSMiddleware,
        allow_origins=resolved_settings.server.cors_origins,
        allow_credentials=False,
        allow_methods=["*"],
        allow_headers=["*"],
    )

    @application.get(f"{resolved_settings.server.api_prefix}/health", tags=["system"])
    async def health() -> dict[str, str]:
        return {"status": "ok"}

    application.include_router(auth.router, prefix=resolved_settings.server.api_prefix)
    application.include_router(chat.router, prefix=resolved_settings.server.api_prefix)
    application.include_router(conversations.router, prefix=resolved_settings.server.api_prefix)
    application.include_router(memories.router, prefix=resolved_settings.server.api_prefix)
    application.include_router(device_actions.router, prefix=resolved_settings.server.api_prefix)
    application.include_router(call_invitations.router, prefix=resolved_settings.server.api_prefix)
    application.include_router(engagement.router, prefix=resolved_settings.server.api_prefix)
    application.include_router(push.router, prefix=resolved_settings.server.api_prefix)
    application.include_router(asr.router, prefix=resolved_settings.server.api_prefix)
    application.include_router(realtime_calls.router, prefix=resolved_settings.server.api_prefix)
    return application
