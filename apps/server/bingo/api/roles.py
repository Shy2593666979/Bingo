import base64
import binascii
import json
import secrets
from datetime import timedelta

from fastapi import APIRouter, HTTPException, Request, Response
from pydantic import BaseModel, Field, field_validator
from sqlalchemy import func
from sqlmodel import select

from bingo.api.dependencies import CurrentUserDependency, SessionDependency
from bingo.db.models import CallInvitation, Conversation, Message, Role, User, VoiceJob, new_id
from bingo.db.repositories import ConversationRepository, RoleRepository
from bingo.db.time import beijing_now
from bingo.roles import role_id
from bingo.roles.traits import CATEGORIES, TRAITS
from bingo.schemas.avatar import validate_avatar
from bingo.schemas.chat import ConversationResponse
from bingo.services.voice_cloning import pcm_has_signal, pcm_wav

router = APIRouter(tags=["roles"])


def role_response(role: Role) -> dict:
    return {
        "id": role.id,
        "name": role.visible_name,
        "nickname": role.nickname,
        "role_type": role.name if role.owner_id is None else "自定义角色",
        "description": role.description,
        "prompt": role.prompt,
        "avatar_data": role.avatar_data,
        "builtin": role.owner_id is None,
        "enabled": role.enabled,
        "has_voice": bool(role.voice),
        "has_cloned_voice": bool(role.owned_voice),
        "voice_source_id": role.voice_source_id,
        "categories": json.loads(role.categories_json),
        "traits": json.loads(role.traits_json),
    }


class RolePayload(BaseModel):
    name: str = Field(min_length=1, max_length=30)
    prompt: str = Field(min_length=1, max_length=2000)
    avatar_data: str | None = Field(default=None, max_length=3_000_000)
    voice_source_id: str | None = Field(default=None, max_length=36)
    draft: bool = False
    categories: list[str] | None = Field(default=None, min_length=2, max_length=3)
    traits: list[str] | None = Field(default=None, min_length=2, max_length=3)

    @field_validator("categories", "traits")
    @classmethod
    def validate_labels(cls, value, info):
        if value is not None:
            allowed = CATEGORIES if info.field_name == "categories" else TRAITS
            if len(set(value)) != len(value) or any(item not in allowed for item in value):
                raise ValueError("请选择有效且不重复的分类和特征")
        return value

    @field_validator("name", "prompt")
    @classmethod
    def trim_text(cls, value: str) -> str:
        value = value.strip()
        if not value:
            raise ValueError("请输入角色名称和设定")
        return value

    @field_validator("avatar_data")
    @classmethod
    def check_avatar(cls, value: str | None) -> str | None:
        return validate_avatar(value)


class ClonePayload(BaseModel):
    audio: str = Field(min_length=1, max_length=2_560_000)
    consent: bool


async def owned_role(session, user, identifier: str) -> Role:
    role = await session.get(Role, identifier)
    if not role or role.deleted or role.owner_id != user.id:
        raise HTTPException(404, "角色不存在")
    return role


async def apply_payload(session, user, role: Role, payload: RolePayload) -> None:
    available = (
        await session.exec(
            select(Role).where(
                Role.deleted.is_(False),
                (Role.owner_id.is_(None)) | (Role.owner_id == user.id),
            )
        )
    ).all()
    if any(item.id != role.id and item.visible_name == payload.name for item in available):
        raise HTTPException(409, "已有同名角色，请换一个名称")
    source = await session.get(Role, payload.voice_source_id or role_id("girlfriend"))
    if payload.voice_source_id == role.id and role.owned_voice:
        role.voice = role.owned_voice
        role.voice_source_id = role.id
    elif source and source.enabled and not source.deleted and source.owner_id in {None, user.id}:
        role.voice = source.voice
        role.voice_source_id = source.voice_source_id or source.id
    else:
        raise HTTPException(422, "所选音色已失效，请重新选择")
    role.display_name = payload.name
    role.description = payload.prompt[:200]
    role.prompt = payload.prompt
    role.avatar_data = payload.avatar_data
    role.enabled = not payload.draft
    role.updated_at = beijing_now()
    if payload.categories is not None:
        role.categories_json = json.dumps(payload.categories, ensure_ascii=False)
    if payload.traits is not None:
        role.traits_json = json.dumps(payload.traits, ensure_ascii=False)


@router.get("/roles")
async def list_roles(user: CurrentUserDependency, session: SessionDependency) -> list[dict]:
    responses = []
    for role in await RoleRepository(session).list_enabled(user.id):
        response = role_response(role)
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
        response["message_count"] = 0
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
                response["last_message"] = last_message.content[:80]
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


@router.post("/roles/{identifier}/conversation", response_model=ConversationResponse)
async def open_role_conversation(
    identifier: str, user: CurrentUserDependency, session: SessionDependency
) -> ConversationResponse:
    role = await session.get(Role, identifier)
    if not role or role.deleted or not role.enabled or role.owner_id not in {None, user.id}:
        raise HTTPException(404, "角色不存在")
    conversation = await ConversationRepository(session, user.id).get_or_create(None, role.id)
    conversation.last_read_at = beijing_now()
    user.role_id = role.id
    user.role = role.visible_name
    user.assistant_name = role.nickname
    await session.commit()
    return ConversationResponse.model_validate(conversation, from_attributes=True)


@router.post("/roles", status_code=201)
async def create_role(
    payload: RolePayload, user: CurrentUserDependency, session: SessionDependency
) -> dict:
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
    await session.commit()
    return role_response(role)


@router.put("/roles/{identifier}")
async def update_role(
    identifier: str, payload: RolePayload, user: CurrentUserDependency, session: SessionDependency
) -> dict:
    role = await owned_role(session, user, identifier)
    await apply_payload(session, user, role, payload)
    users = (await session.exec(select(User).where(User.role_id == role.id))).all()
    for selected_user in users:
        selected_user.role = role.visible_name
    await session.commit()
    return role_response(role)


@router.delete("/roles/{identifier}", status_code=204)
async def delete_role(
    identifier: str, user: CurrentUserDependency, session: SessionDependency, request: Request
) -> Response:
    role = await owned_role(session, user, identifier)
    fallback = await session.get(Role, role_id("girlfriend"))
    affected = (await session.exec(select(Role).where(Role.voice_source_id == role.id))).all()
    for dependent in affected:
        dependent.voice = fallback.voice
        dependent.voice_source_id = fallback.id
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
    cleanups = []
    if role.owned_voice:
        cleanups.append(
            VoiceJob(user_id=user.id, role_id=role.id, kind="delete", voice=role.owned_voice)
        )
    uncertain_jobs = (
        await session.exec(
            select(VoiceJob).where(
                VoiceJob.role_id == role.id,
                VoiceJob.kind == "clone",
                VoiceJob.status.in_(["failed", "pending", "processing"]),
            )
        )
    ).all()
    for job in uncertain_jobs:
        cleanups.append(
            VoiceJob(
                user_id=user.id,
                role_id=role.id,
                kind="delete_prefix",
                voice="u" + job.id.replace("-", "")[:9],
            )
        )
    for cleanup in cleanups:
        session.add(cleanup)
    role.deleted = True
    role.enabled = False
    role.voice = ""
    role.owned_voice = ""
    role.avatar_data = None
    await session.commit()
    for cleanup in cleanups:
        request.app.state.voice_cloning.schedule(cleanup.id)
    return Response(status_code=204)


@router.post("/roles/{identifier}/voice-clone", status_code=202)
async def clone_voice(
    identifier: str,
    payload: ClonePayload,
    user: CurrentUserDependency,
    session: SessionDependency,
    request: Request,
) -> dict:
    await owned_role(session, user, identifier)
    if not payload.consent:
        raise HTTPException(422, "请确认录音为本人声音或已获得授权")
    try:
        audio = base64.b64decode(payload.audio, validate=True)
    except (ValueError, binascii.Error) as error:
        raise HTTPException(422, "录音格式无效") from error
    if len(audio) < 16000 * 2 * 15:
        raise HTTPException(422, "录音时间太短，请重新录制")
    if len(audio) > 16000 * 2 * 60 or len(audio) % 2:
        raise HTTPException(422, "请录制 15～60 秒的音频")
    if not pcm_has_signal(audio):
        raise HTTPException(422, "录音没有检测到声音，请检查麦克风后重新录制")
    settings = request.app.state.settings
    if not settings.realtime_call.api_key:
        raise HTTPException(503, "服务器尚未配置声音复刻")
    pending = (
        await session.exec(
            select(VoiceJob).where(
                VoiceJob.role_id == identifier,
                VoiceJob.kind == "clone",
                VoiceJob.status.in_(["pending", "processing"]),
            )
        )
    ).first()
    if pending:
        return {"id": pending.id, "status": pending.status}
    public_url = settings.voice_cloning.public_base_url.rstrip("/")
    if not public_url:
        public_url = str(request.base_url).rstrip("/") + settings.server.api_prefix
    job = (
        await session.exec(
            select(VoiceJob)
            .where(
                VoiceJob.role_id == identifier,
                VoiceJob.kind == "clone",
                VoiceJob.status == "failed",
            )
            .order_by(VoiceJob.created_at.desc())
        )
    ).first()
    if job is None:
        job = VoiceJob(user_id=user.id, role_id=identifier)
    job.status = "pending"
    job.error = None
    job.created_at = beijing_now()
    job.sample = base64.b64encode(pcm_wav(audio)).decode()
    job.sample_token = secrets.token_urlsafe(32)
    job.public_base_url = public_url
    session.add(job)
    await session.commit()
    request.app.state.voice_cloning.schedule(job.id)
    return {"id": job.id, "status": job.status}


@router.get("/voice-jobs/{identifier}")
async def voice_job(
    identifier: str, user: CurrentUserDependency, session: SessionDependency, request: Request
) -> dict:
    job = await session.get(VoiceJob, identifier)
    if not job or job.user_id != user.id or job.kind != "clone":
        raise HTTPException(404, "复刻任务不存在")
    return {
        "id": job.id,
        "status": job.status,
        "error": job.error,
        "stage": request.app.state.voice_cloning.stages.get(job.id, job.status),
    }


@router.get("/role-voice-samples/{token}")
async def voice_sample(token: str, session: SessionDependency) -> Response:
    job = (await session.exec(select(VoiceJob).where(VoiceJob.sample_token == token))).first()
    if (
        not job
        or not job.sample
        or job.status not in {"pending", "processing"}
        or job.created_at < beijing_now() - timedelta(minutes=10)
    ):
        raise HTTPException(404, "录音不存在或已过期")
    role = await session.get(Role, job.role_id)
    if not role or role.deleted:
        raise HTTPException(404, "录音不存在或已过期")
    return Response(
        base64.b64decode(job.sample), media_type="audio/wav", headers={"Cache-Control": "no-store"}
    )


@router.post("/roles/{identifier}/voice-preview")
async def preview_voice(
    identifier: str, user: CurrentUserDependency, session: SessionDependency, request: Request
) -> dict:
    role = await session.get(Role, identifier)
    if not role or role.deleted or role.owner_id not in {None, user.id} or not role.voice:
        raise HTTPException(404, "音色不存在或已失效")
    try:
        voice = role.voice
        audio = await request.app.state.voice_cloning.preview(voice)
    except Exception as error:
        raise HTTPException(502, "试听生成失败，请稍后重试") from error
    await session.refresh(role)
    if role.deleted or role.voice != voice:
        raise HTTPException(404, "音色已失效")
    return {"audio": base64.b64encode(audio).decode(), "mime_type": "audio/wav"}
