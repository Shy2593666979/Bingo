from bingo.agent.context import build_context
from bingo.db.repositories import (
    AuthSessionRepository,
    CallInvitationRepository,
    ConversationRepository,
    MemoryRepository,
    RoleRepository,
)
from bingo.services.exceptions import ServiceError
from bingo.tools.base import ToolContext


async def prepare_call(database, token: str, requested_conversation_id, requested_call_id):
    invitation = None
    async with database.session_factory() as session:
        user = await AuthSessionRepository(session).get_user(token)
        if user is None:
            raise ServiceError(401, "登录已失效")
        if requested_call_id:
            invitation_repository = CallInvitationRepository(session, user.id)
            invitation = await invitation_repository.get(requested_call_id)
            if invitation is None or invitation.status != "accepted":
                raise ServiceError(409, "来电邀请无效或尚未接受")
            await invitation_repository.set_status(invitation, "active")
            requested_conversation_id = invitation.conversation_id
        repository = ConversationRepository(session, user.id)
        try:
            user = await repository.context_user(user, requested_conversation_id)
            conversation = await repository.get_or_create(requested_conversation_id)
        except ServiceError:
            raise ServiceError(409, "角色或对话已失效") from None
        await repository.commit()
        history = await repository.list_messages(conversation.id, limit=40)
        memories = await MemoryRepository(session, user.id).list(role_id=user.role_id)
        role = await RoleRepository(session).get(invitation.role_id if invitation else user.role_id)
        if role and (role.deleted or not role.enabled or role.owner_id not in {None, user.id}):
            raise ServiceError(409, "角色已失效，请重新选择")

    return user, conversation, role, invitation, history, memories


async def persist_call(database, prepared, status: str, duration_seconds: int) -> None:
    user, conversation, role, invitation, history, memories = prepared
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


async def execute_tool(
    database, tool_registry, user, conversation, timezone, name: str, arguments: str
) -> tuple[str, dict[str, object] | None]:
    async with database.session_factory() as tool_session:
        result = await tool_registry.execute(
            name,
            arguments,
            ToolContext(
                session=tool_session,
                user=user,
                timezone=timezone,
                conversation_id=conversation.id,
            ),
        )
        return result.content, result.client_event


def build_call_prompt(settings, prepared, region):
    user, conversation, role, invitation, history, memories = prepared
    context = build_context(
        [],
        memories,
        username=user.username or "用户",
        assistant_name=user.assistant_name or settings.agent.assistant_name,
        personality=user.personality or settings.agent.assistant_persona,
        role=user.role or "朋友",
        timezone=settings.app.timezone,
        role_prompt=role.context_prompt if role else "",
        current_location=region["display"] if region else "",
    )
    prompt = context[0].content + "\n当前是实时语音通话，请使用自然、口语化、简短的表达。"
    if invitation is not None:
        prompt += (
            "\n这是你主动发起并且用户刚刚接受的电话。接通后由你先自然地开口问候，"
            f"不要等待用户先说话。来电原因：{invitation.reason}"
        )
    return prompt
