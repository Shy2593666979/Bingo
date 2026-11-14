import base64
import json
from datetime import timedelta

from sqlalchemy import func
from sqlmodel import select
from sqlmodel.ext.asyncio.session import AsyncSession

from bingo.db.models import (
    CallInvitation,
    Conversation,
    Message,
    Role,
    RolePreference,
    User,
    Voice,
    VoiceJob,
    new_id,
)
from bingo.db.repositories import ConversationRepository, RoleRepository
from bingo.db.time import beijing_now
from bingo.roles import role_id
from bingo.roles.catalog import BUILTIN_NICKNAMES, default_personality
from bingo.roles.persona import speaking_style_for
from bingo.schemas.chat import ConversationResponse
from bingo.schemas.roles import ClonePayload, RolePayload
from bingo.services import voices as voice_assets
from bingo.services.companion_welcome import enqueue_role_welcome
from bingo.services.context import BinaryAsset, ServiceContext
from bingo.services.exceptions import ServiceError
from bingo.utils.stickers.content import preview_content


def role_response(
    role: Role, personality: str | None = None, speaking_style: str | None = None
) -> dict:
    return {
        "id": role.id,
        "name": role.visible_name,
        "nickname": role.nickname,
        "character_name": role.nickname,
        "relationship": role.relationship,
        "speaking_style": speaking_style or speaking_style_for(role, personality),
        "background": role.background if role.background is not None else role.prompt,
        "personality_tags": json.loads(role.traits_json),
        "role_type": role.relationship
        if role.role_type is not None or role.code in BUILTIN_NICKNAMES
        else "自定义角色",
        "personality": personality,
        "description": role.description,
        "opening_line": "",  # Legacy response key; greetings are generated as messages.
        "prompt": role.prompt,
        "avatar_data": role.avatar_data,
        "avatar_asset": role.avatar,
        "builtin": role.owner_id is None and role.code in BUILTIN_NICKNAMES,
        "identity_editable": role.owner_id is not None,
        "enabled": role.enabled,
        "has_voice": bool(role.voice),
        "has_cloned_voice": bool(role.owned_voice),
        "voice_source_id": role.voice_source_id,
        "voice_id": role.voice_id,
        "categories": json.loads(role.categories_json),
        "traits": json.loads(role.traits_json),
        "source_publication_id": role.source_publication_id,
    }


async def owned_role(session, user, identifier: str) -> Role:
    role = await session.get(Role, identifier)
    if not role or role.deleted or role.owner_id != user.id:
        raise ServiceError(404, "角色不存在")
    return role


async def apply_payload(session, user, role: Role, payload: RolePayload) -> None:
    background = payload.background if payload.background is not None else payload.prompt
    if background is None:
        background = role.background if role.background is not None else role.prompt
    if not background:
        raise ServiceError(422, "请填写人物背景")
    available = (
        await session.exec(
            select(Role).where(Role.deleted.is_(False), RoleRepository.scope(user.id))
        )
    ).all()
    if any(
        item.id != role.id and payload.name in {item.visible_name, item.nickname}
        for item in available
    ):
        raise ServiceError(409, "已有同名角色，请换一个名称")
    if payload.voice_id:
        asset = await voice_assets.get_voice(session, user.id, payload.voice_id, ready=True)
        role.voice_source_id = None
    elif role.voice_id and "voice_source_id" not in payload.model_fields_set:
        asset = await voice_assets.get_voice(session, user.id, role.voice_id, ready=True)
    else:
        source = await session.get(Role, payload.voice_source_id or role_id("girlfriend"))
        if payload.voice_source_id == role.id and role.owned_voice:
            asset = await voice_assets.legacy_asset(session, role, owned=True)
            role.voice_source_id = role.id
        elif (
            source and source.enabled and not source.deleted and source.owner_id in {None, user.id}
        ):
            asset = await voice_assets.legacy_asset(session, source)
            role.voice_source_id = source.voice_source_id or source.id
        elif role.voice_id and payload.voice_source_id == role.voice_source_id:
            asset = await voice_assets.get_voice(session, user.id, role.voice_id, ready=True)
        else:
            raise ServiceError(422, "所选音色已失效，请重新选择")
    if asset is None:
        raise ServiceError(422, "所选音色已失效，请重新选择")
    role.voice_id, role.voice = asset.id, asset.provider_voice
    role.display_name = payload.name
    role.description = payload.description if payload.description is not None else background[:200]
    role.background = background
    role.prompt = background  # Compatibility for older clients and community snapshots.
    if payload.speaking_style is not None:
        role.speaking_style = payload.speaking_style
    if payload.role_type is not None:
        role.role_type = payload.role_type
    role.avatar_data = payload.avatar_data
    role.enabled = not payload.draft
    role.updated_at = beijing_now()
    if payload.categories is not None:
        role.categories_json = json.dumps(payload.categories, ensure_ascii=False)
    if payload.traits is not None:
        role.traits_json = json.dumps(payload.traits, ensure_ascii=False)


async def save_personality(session, user, role, personality, speaking_style=None):
    if personality is None and speaking_style is None:
        return
    preference = await session.get(RolePreference, (user.id, role.id))
    if preference is None:
        preference = RolePreference(
            user_id=user.id,
            role_id=role.id,
            personality=personality or "温柔体贴",
            speaking_style=speaking_style,
        )
        session.add(preference)
    else:
        if personality is not None:
            preference.personality = personality
        preference.speaking_style = speaking_style


async def response_for_user(session, user, role):
    preference = await session.get(RolePreference, (user.id, role.id))
    effective = await voice_assets.effective_role(session, user.id, role)
    response = role_response(
        effective,
        preference.personality if preference else default_personality(role, user.personality),
        speaking_style_for(role, user.personality, preference),
    )
    asset = await session.get(Voice, effective.voice_id) if effective.voice_id else None
    response["voice_name"] = asset.name if asset and not asset.deleted else None
    return response


async def list_roles(user: User, session: AsyncSession) -> list[dict]:
    responses = []
    for role in await RoleRepository(session).list_enabled(user.id):
        response = await response_for_user(session, user, role)
        conversation = (
            await session.exec(
                select(Conversation)
                .where(Conversation.user_id == user.id, Conversation.role_id == role.id)
                .order_by(Conversation.created_at.desc())
                .limit(1)
            )
        ).first()
        response["unread_count"] = 0
        response["last_message"] = None
        response["last_message_at"] = None
        response["message_count"] = 0
        response["pinned"] = bool(conversation and conversation.pinned)
        response["archived"] = bool(conversation and conversation.archived)
        response["muted"] = bool(conversation and conversation.muted)
        if conversation:
            response["message_count"] = (
                await session.exec(
                    select(func.count(Message.id)).where(
                        Message.conversation_id == conversation.id, Message.status != "streaming"
                    )
                )
            ).one()
            last_message = (
                await session.exec(
                    select(Message)
                    .where(Message.conversation_id == conversation.id)
                    .order_by(Message.created_at.desc(), Message.id.desc())
                    .limit(1)
                )
            ).first()
            response["conversation_id"] = conversation.id
            if last_message:
                response["last_message"] = preview_content(last_message.content)[:80]
                response["last_message_at"] = last_message.created_at.isoformat()
            statement = select(func.count(Message.id)).where(
                Message.conversation_id == conversation.id,
                Message.role == "assistant",
                Message.status != "streaming",
            )
            if conversation.last_read_at:
                statement = statement.where(Message.created_at > conversation.last_read_at)
            response["unread_count"] = (await session.exec(statement)).one()
        responses.append(response)
    return responses


async def open_role_conversation(
    identifier: str, user: User, session: AsyncSession
) -> ConversationResponse:
    role = await session.get(Role, identifier)
    if not await RoleRepository(session).can_access(user, role):
        raise ServiceError(404, "角色不存在")
    conversation = await ConversationRepository(session, user.id).get_or_create(None, role.id)
    welcome = (
        await session.exec(
            select(Message)
            .where(
                Message.conversation_id == conversation.id, Message.run_id.startswith("welcome-")
            )
            .order_by(Message.created_at.desc())
            .limit(1)
        )
    ).first()
    welcome_unread = bool(
        welcome
        and (
            welcome.status == "streaming"
            or conversation.last_read_at is None
            or welcome.created_at > conversation.last_read_at
        )
    )
    conversation.last_read_at = beijing_now()
    user.role_id = role.id
    user.role = role.visible_name
    user.assistant_name = role.nickname
    await session.commit()
    return ConversationResponse.model_validate(conversation, from_attributes=True).model_copy(
        update={"welcome_unread": welcome_unread}
    )


async def create_role(payload: RolePayload, user: User, session: AsyncSession) -> dict:
    identifier = new_id()
    role = Role(
        id=identifier,
        code=identifier,
        name=identifier.replace("-", "")[:30],
        owner_id=user.id,
        avatar="bingo_logo.png",
        sort_order=100,
    )
    await apply_payload(session, user, role, payload)
    session.add(role)
    await save_personality(session, user, role, payload.personality, payload.speaking_style)
    if role.enabled:
        await enqueue_role_welcome(user, session, role)
    await session.commit()
    return await response_for_user(session, user, role)


async def update_role(
    identifier: str, payload: RolePayload, user: User, session: AsyncSession
) -> dict:
    role = await session.get(Role, identifier)
    if (
        not role
        or role.deleted
        or role.owner_id not in {None, user.id}
        or (role.owner_id is None and not await RoleRepository(session).can_access(user, role))
    ):
        raise ServiceError(404, "角色不存在")
    if role.owner_id is None:
        if not role.enabled:
            raise ServiceError(404, "角色不存在")
        if payload.personality is None and payload.speaking_style is None and not payload.voice_id:
            raise ServiceError(422, "请填写说话风格")
        await save_personality(session, user, role, payload.personality, payload.speaking_style)
        if payload.voice_id:
            await voice_assets.assign_voice(role.id, payload.voice_id, user, session)
        await session.commit()
        return await response_for_user(session, user, role)
    was_draft = not role.enabled
    await apply_payload(session, user, role, payload)
    await save_personality(session, user, role, payload.personality, payload.speaking_style)
    users = (await session.exec(select(User).where(User.role_id == role.id))).all()
    for selected_user in users:
        selected_user.role = role.visible_name
    if was_draft and role.enabled:
        await enqueue_role_welcome(user, session, role)
    await session.commit()
    return await response_for_user(session, user, role)


async def delete_role(
    identifier: str, user: User, session: AsyncSession, context: ServiceContext
) -> None:
    role = await owned_role(session, user, identifier)
    fallback = await session.get(Role, role_id("girlfriend"))
    # Keep independently owned sounds even when their original companion is removed.
    if role.owned_voice:
        await voice_assets.legacy_asset(session, role, owned=True)
    selected = (await session.exec(select(User).where(User.role_id == role.id))).all()
    for selected_user in selected:
        selected_user.role_id = fallback.id
        selected_user.role = fallback.name
        selected_user.role_changed_at = beijing_now()
    invitations = (
        await session.exec(
            select(CallInvitation).where(
                CallInvitation.role_id == role.id,
                CallInvitation.status.in_(["ringing", "accepted"]),
            )
        )
    ).all()
    for invitation in invitations:
        invitation.status = "cancelled"
    role.deleted = True
    role.enabled = False
    role.voice = ""
    role.owned_voice = ""
    role.avatar_data = None
    await session.commit()
    return None


async def clone_voice(
    identifier: str,
    payload: ClonePayload,
    user: User,
    session: AsyncSession,
    context: ServiceContext,
) -> dict:
    role = await owned_role(session, user, identifier)
    # Compatibility endpoint: cloning still creates a reusable asset, never a role-owned voice.
    previous_job = (
        await session.exec(
            select(VoiceJob)
            .where(
                VoiceJob.role_id == role.id,
                VoiceJob.user_id == user.id,
                VoiceJob.kind == "clone",
                VoiceJob.voice_id.is_not(None),
            )
            .order_by(VoiceJob.created_at.desc())
        )
    ).first()
    asset = await session.get(Voice, previous_job.voice_id) if previous_job else None
    if asset is None or asset.deleted or asset.owner_id != user.id:
        asset = await voice_assets.legacy_asset(session, role, owned=True)
    if asset is None:
        asset = Voice(name=f"{role.nickname}的声音", owner_id=user.id)
        session.add(asset)
        await session.flush()
    return await voice_assets.clone_voice(
        asset.id, payload, user, session, context, legacy_role_id=role.id
    )


async def voice_job(
    identifier: str, user: User, session: AsyncSession, context: ServiceContext
) -> dict:
    job = await session.get(VoiceJob, identifier)
    if not job or job.user_id != user.id or job.kind != "clone":
        raise ServiceError(404, "复刻任务不存在")
    return {
        "id": job.id,
        "status": job.status,
        "error": job.error,
        "stage": context.voice_cloning.stages.get(job.id, job.status),
        "voice_id": job.voice_id,
    }


async def voice_sample(token: str, session: AsyncSession) -> BinaryAsset:
    job = (await session.exec(select(VoiceJob).where(VoiceJob.sample_token == token))).first()
    if (
        not job
        or not job.sample
        or job.status not in {"pending", "processing"}
        or (job.created_at < beijing_now() - timedelta(minutes=10))
    ):
        raise ServiceError(404, "录音不存在或已过期")
    if job.voice_id:
        asset = await session.get(Voice, job.voice_id)
        if not asset or asset.deleted or asset.owner_id != job.user_id:
            raise ServiceError(404, "录音不存在或已过期")
    else:
        role = await session.get(Role, job.role_id)
        if not role or role.deleted:
            raise ServiceError(404, "录音不存在或已过期")
    return BinaryAsset(
        data=base64.b64decode(job.sample),
        media_type="audio/wav",
        headers={"Cache-Control": "no-store"},
    )


async def preview_voice(
    identifier: str, user: User, session: AsyncSession, context: ServiceContext
) -> dict:
    role = await session.get(Role, identifier)
    if not role or role.deleted or role.owner_id not in {None, user.id} or (not role.voice):
        raise ServiceError(404, "音色不存在或已失效")
    effective = await voice_assets.effective_role(session, user.id, role)
    if effective.voice_id:
        return await voice_assets.preview_voice(effective.voice_id, user, session, context)
    try:
        voice = role.voice
        audio = await context.voice_cloning.preview(voice)
    except Exception as error:
        raise ServiceError(502, "试听生成失败，请稍后重试") from error
    await session.refresh(role)
    if role.deleted or role.voice != voice:
        raise ServiceError(404, "音色已失效")
    return {"audio": base64.b64encode(audio).decode(), "mime_type": "audio/wav"}
