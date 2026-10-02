from fastapi import APIRouter, HTTPException, WebSocket

from bingo.agent.context import build_context
from bingo.db.repositories import (
    AuthSessionRepository,
    CallInvitationRepository,
    ConversationRepository,
    MemoryRepository,
    RoleRepository,
)
from bingo.services.realtime_call import RealtimeCallProxy, derive_realtime_url
from bingo.tools.base import ToolContext

router = APIRouter(tags=["realtime-calls"])


@router.websocket("/realtime/calls/stream")
async def realtime_call(websocket: WebSocket) -> None:
    authorization = websocket.headers.get("authorization", "")
    scheme, _, token = authorization.partition(" ")
    if scheme.lower() != "bearer" or not token:
        await websocket.close(code=4401, reason="请先登录")
        return

    database = websocket.app.state.database
    requested_conversation_id = websocket.query_params.get("conversation_id")
    requested_call_id = websocket.query_params.get("call_id")
    invitation = None
    async with database.session_factory() as session:
        user = await AuthSessionRepository(session).get_user(token)
        if user is None:
            await websocket.close(code=4401, reason="登录已失效")
            return
        if requested_call_id:
            invitation_repository = CallInvitationRepository(session, user.id)
            invitation = await invitation_repository.get(requested_call_id)
            if invitation is None or invitation.status != "accepted":
                await websocket.close(code=4409, reason="来电邀请无效或尚未接受")
                return
            await invitation_repository.set_status(invitation, "active")
            requested_conversation_id = invitation.conversation_id
        repository = ConversationRepository(session, user.id)
        try:
            user = await repository.context_user(user, requested_conversation_id)
            conversation = await repository.get_or_create(requested_conversation_id)
        except HTTPException:
            await websocket.close(code=4409, reason="角色或对话已失效")
            return
        await repository.commit()
        history = await repository.list_messages(conversation.id, limit=40)
        memories = await MemoryRepository(session, user.id).list(role_id=user.role_id)
        role = await RoleRepository(session).get(invitation.role_id if invitation else user.role_id)
        if role and (role.deleted or not role.enabled or role.owner_id not in {None, user.id}):
            await websocket.close(code=4409, reason="角色已失效，请重新选择")
            return

    settings = websocket.app.state.settings
    call_settings = settings.realtime_call
    if not call_settings.api_key:
        await websocket.close(code=1013, reason="后台未配置 realtime_call.api_key")
        return
    context = build_context(
        [],
        memories,
        username=user.username or "用户",
        assistant_name=user.assistant_name or settings.agent.assistant_name,
        personality=user.personality or settings.agent.assistant_persona,
        role=user.role or "朋友",
        timezone=settings.app.timezone,
        role_prompt=role.prompt if role else "",
    )
    prompt = context[0].content + "\n当前是实时语音通话，请使用自然、口语化、简短的表达。"
    if invitation is not None:
        prompt += (
            "\n这是你主动发起并且用户刚刚接受的电话。接通后由你先自然地开口问候，"
            f"不要等待用户先说话。来电原因：{invitation.reason}"
        )
    url = derive_realtime_url(call_settings.url, settings.asr.realtime.url)

    async def handle_transcript(message_role: str, content: str) -> None:
        # Realtime transcripts belong to the active call UI, not the chat timeline.
        return None

    async def persist_call(status: str, duration_seconds: int) -> None:
        async with database.session_factory() as call_session:
            if invitation is not None:
                invitation_repository = CallInvitationRepository(call_session, user.id)
                current_invitation = await invitation_repository.get(invitation.id)
                if current_invitation is not None and current_invitation.status == "active":
                    await invitation_repository.set_status(current_invitation, status)
            call_repository = ConversationRepository(call_session, user.id)
            target = await call_repository.get_or_create(conversation.id)
            if target.title == "New conversation":
                target.title = "语音通话"
            await call_repository.add_message(
                target.id,
                "assistant" if invitation else "user",
                "通话已结束" if status == "ended" else "通话异常结束",
                assistant_role=invitation.caller_role if invitation else None,
                role_id=invitation.role_id if invitation else user.role_id,
                message_type="call",
                call_status=status,
                call_duration_seconds=duration_seconds,
            )
            await call_repository.commit()

    tool_registry = websocket.app.state.tools
    tool_definitions = [
        definition
        for definition in tool_registry.definitions()
        if definition["function"]["name"] not in {"device_alarm_create", "assistant_call_invite"}
    ]

    async def execute_tool(name: str, arguments: str) -> tuple[str, dict[str, object] | None]:
        async with database.session_factory() as tool_session:
            result = await tool_registry.execute(
                name,
                arguments,
                ToolContext(
                    session=tool_session,
                    user=user,
                    timezone=settings.app.timezone,
                    conversation_id=conversation.id,
                ),
            )
            return result.content, result.client_event

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
