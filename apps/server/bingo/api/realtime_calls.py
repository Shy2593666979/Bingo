from fastapi import APIRouter, WebSocket

from bingo.services import realtime_session as session_service
from bingo.services.exceptions import ServiceError
from bingo.services.realtime_call import RealtimeCallProxy, derive_realtime_url

router = APIRouter(tags=["realtime-calls"])


@router.websocket("/realtime/calls/stream")
async def realtime_call(websocket: WebSocket) -> None:
    authorization = websocket.headers.get("authorization", "")
    scheme, _, token = authorization.partition(" ")
    if scheme.lower() != "bearer" or not token:
        await websocket.close(code=4401, reason="请先登录")
        return

    database = websocket.app.state.database
    try:
        prepared = await session_service.prepare_call(
            database,
            token,
            websocket.query_params.get("conversation_id"),
            websocket.query_params.get("call_id"),
        )
    except ServiceError as error:
        await websocket.close(code=4401 if error.status_code == 401 else 4409, reason=error.message)
        return
    user, conversation, role, invitation, history, memories = prepared

    settings = websocket.app.state.settings
    call_settings = settings.realtime_call
    if not call_settings.api_key:
        await websocket.close(code=1013, reason="后台未配置 realtime_call.api_key")
        return
    region = await websocket.app.state.location.current(user.id)
    prompt = session_service.build_call_prompt(settings, prepared, region)
    url = derive_realtime_url(call_settings.url, settings.asr.realtime.url)

    async def handle_transcript(message_role: str, content: str) -> None:
        return None

    async def persist_call(status: str, duration_seconds: int) -> None:
        await session_service.persist_call(database, prepared, status, duration_seconds)

    tool_registry = websocket.app.state.tools
    tool_definitions = [
        definition
        for definition in tool_registry.definitions()
        if definition["function"]["name"] not in {"device_alarm_create", "assistant_call_invite"}
    ]

    async def execute_tool(name: str, arguments: str) -> tuple[str, dict[str, object] | None]:
        return await session_service.execute_tool(
            database, tool_registry, user, conversation, settings.app.timezone, name, arguments
        )

    await websocket.accept()
    proxy = RealtimeCallProxy(
        api_key=call_settings.api_key,
        url=url,
        model=call_settings.model,
        voice=(role.voice.strip() if role and role.voice.strip() else call_settings.voice),
        instructions=prompt,
        history=[
            (message.role, message.content) for message in history if message.message_type == "chat"
        ],
        tools=tool_definitions,
        turn_detection=call_settings.turn_detection,
        max_history_turns=call_settings.max_history_turns,
        timeout_seconds=call_settings.timeout_seconds,
        start_with_response=invitation is not None,
    )
    await proxy.run(
        websocket,
        user_id=user.id,
        conversation_id=conversation.id,
        on_transcript=handle_transcript,
        on_tool_call=execute_tool,
        on_finished=persist_call,
    )
