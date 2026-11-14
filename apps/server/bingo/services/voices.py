import base64
import binascii
import secrets

from sqlalchemy import or_
from sqlmodel import select

from bingo.db.models import Role, RolePreference, Voice, VoiceJob
from bingo.db.repositories import RoleRepository
from bingo.db.seeds.voices import legacy_voice_id
from bingo.db.time import beijing_now
from bingo.roles.catalog import default_personality
from bingo.schemas.voices import VoicePayload
from bingo.services.exceptions import ServiceError
from bingo.services.voice_cloning import pcm_has_signal, pcm_wav


def voice_response(voice: Voice) -> dict:
    return {
        "id": voice.id,
        "name": voice.name,
        "description": voice.description,
        "gender": voice.gender,
        "scope": voice.scope,
        "status": voice.status,
        "editable": voice.owner_id is not None,
        "has_audio": bool(voice.provider_voice),
        "created_at": voice.created_at,
        "updated_at": voice.updated_at,
    }


async def legacy_asset(session, role, *, owned=False):
    """Translate old clients' role IDs once; the resulting asset outlives that role."""
    provider = role.owned_voice if owned else role.voice
    if not provider:
        return None
    public = (
        await session.exec(
            select(Voice).where(
                Voice.provider_voice == provider, Voice.owner_id.is_(None), Voice.deleted.is_(False)
            )
        )
    ).first()
    if public and not owned:
        return public
    identifier = legacy_voice_id(provider, role.owner_id)
    voice = await session.get(Voice, identifier)
    if voice is None:
        voice = Voice(
            id=identifier,
            name=f"{role.nickname}的声音",
            owner_id=role.owner_id,
            provider_voice=provider,
            status="ready",
            scope="private" if role.owner_id else "system",
        )
        session.add(voice)
        await session.flush()
    return voice


async def get_voice(session, user_id, identifier, *, owned=False, ready=False) -> Voice:
    voice = await session.get(Voice, identifier)
    if (
        not voice
        or voice.deleted
        or voice.owner_id not in {None, user_id}
        or (owned and voice.owner_id != user_id)
    ):
        raise ServiceError(404, "音色不存在")
    if ready and not voice.provider_voice:
        raise ServiceError(422, "音色尚未就绪，请等待复刻完成")
    return voice


async def list_voices(user, session, scope=None, gender=None) -> list[dict]:
    statement = select(Voice).where(
        Voice.deleted.is_(False), or_(Voice.owner_id.is_(None), Voice.owner_id == user.id)
    )
    if scope:
        statement = statement.where(Voice.scope == scope)
    if gender:
        statement = statement.where(Voice.gender == gender)
    rows = (await session.exec(statement.order_by(Voice.created_at, Voice.id))).all()
    return [voice_response(voice) for voice in rows]


async def create_voice(payload: VoicePayload, user, session):
    voice = Voice(
        owner_id=user.id, name=payload.name, description=payload.description, gender=payload.gender
    )
    session.add(voice)
    await session.commit()
    return voice_response(voice)


async def update_voice(identifier, payload: VoicePayload, user, session):
    voice = await get_voice(session, user.id, identifier, owned=True)
    voice.name, voice.description, voice.gender = payload.name, payload.description, payload.gender
    voice.updated_at = beijing_now()
    await session.commit()
    return voice_response(voice)


async def effective_role(session, user_id, role):
    """Return a detached view; never modify a shared official role for one user's choice."""
    if role is None:
        return None
    preference = await session.get(RolePreference, (user_id, role.id))
    identifier = (preference.voice_id if preference else None) or role.voice_id
    if not identifier:
        return role
    try:
        voice = await get_voice(session, user_id, identifier, ready=True)
    except ServiceError:
        return role.model_copy(update={"voice": ""})
    return role.model_copy(update={"voice": voice.provider_voice, "voice_id": voice.id})


async def assign_voice(role_id, voice_id, user, session):
    role = await session.get(Role, role_id)
    if not await RoleRepository(session).can_access(user, role):
        raise ServiceError(404, "角色不存在")
    voice = await get_voice(session, user.id, voice_id, ready=True)
    if role.owner_id == user.id:
        role.voice_id, role.voice = voice.id, voice.provider_voice
        role.voice_source_id = None
    else:
        preference = await session.get(RolePreference, (user.id, role.id))
        if preference is None:
            preference = RolePreference(
                user_id=user.id,
                role_id=role.id,
                personality=default_personality(role, user.personality)
                or role.speaking_style
                or "温柔体贴",
            )
            session.add(preference)
        preference.voice_id = voice.id
    await session.commit()
    return {"role_id": role.id, "voice_id": voice.id}


async def preview_voice(identifier, user, session, context):
    voice = await get_voice(session, user.id, identifier, ready=True)
    provider = voice.provider_voice
    try:
        audio = await context.voice_cloning.preview(provider)
    except Exception as error:
        raise ServiceError(502, "试听生成失败，请稍后重试") from error
    await session.refresh(voice)
    if voice.deleted or voice.provider_voice != provider:
        raise ServiceError(404, "音色已失效")
    return {"audio": base64.b64encode(audio).decode(), "mime_type": "audio/wav"}


async def clone_voice(identifier, payload, user, session, context, *, legacy_role_id=""):
    voice = await get_voice(session, user.id, identifier, owned=True)
    if not payload.consent:
        raise ServiceError(422, "请确认录音为本人声音或已获得授权")
    try:
        audio = base64.b64decode(payload.audio, validate=True)
    except (ValueError, binascii.Error) as error:
        raise ServiceError(422, "录音格式无效") from error
    if len(audio) < 16000 * 2 * 15:
        raise ServiceError(422, "录音时间太短，请重新录制")
    if len(audio) > 16000 * 2 * 60 or len(audio) % 2:
        raise ServiceError(422, "请录制 15～60 秒的音频")
    if not pcm_has_signal(audio):
        raise ServiceError(422, "录音没有检测到声音，请检查麦克风后重新录制")
    settings = context.settings
    if not settings.realtime_call.api_key:
        raise ServiceError(503, "服务器尚未配置声音复刻")
    pending = (
        await session.exec(
            select(VoiceJob).where(
                VoiceJob.voice_id == voice.id,
                VoiceJob.kind == "clone",
                VoiceJob.status.in_(["pending", "processing"]),
            )
        )
    ).first()
    if pending:
        return {"id": pending.id, "voice_id": voice.id, "status": pending.status}
    # Reuse failed job identifiers so provider retries can find already-created voices.
    job = (
        await session.exec(
            select(VoiceJob)
            .where(
                VoiceJob.voice_id == voice.id,
                VoiceJob.kind == "clone",
                VoiceJob.status == "failed",
            )
            .order_by(VoiceJob.created_at.desc())
        )
    ).first()
    if job is None:
        job = VoiceJob(user_id=user.id, voice_id=voice.id, role_id=legacy_role_id)
    public_url = settings.voice_cloning.public_base_url.rstrip("/")
    job.public_base_url = public_url or (
        str(context.public_base_url).rstrip("/") + settings.server.api_prefix
    )
    job.status, job.error, job.created_at = "pending", None, beijing_now()
    job.sample = base64.b64encode(pcm_wav(audio)).decode()
    job.sample_token = secrets.token_urlsafe(32)
    voice.status, voice.updated_at = "processing", beijing_now()
    session.add(job)
    await session.commit()
    context.voice_cloning.schedule(job.id)
    return {"id": job.id, "voice_id": voice.id, "status": job.status}


async def delete_voice(identifier, user, session, context):
    voice = await get_voice(session, user.id, identifier, owned=True)
    used_role = (
        await session.exec(
            select(Role.id).where(Role.voice_id == voice.id, Role.deleted.is_(False))
        )
    ).first()
    used_preference = (
        await session.exec(
            select(RolePreference.role_id).where(RolePreference.voice_id == voice.id)
        )
    ).first()
    if used_role or used_preference:
        raise ServiceError(409, "仍有搭子在使用这个音色，请先为他们更换声音")
    voice.deleted = True
    voice.updated_at = beijing_now()
    jobs = (
        await session.exec(
            select(VoiceJob).where(VoiceJob.voice_id == voice.id, VoiceJob.kind == "clone")
        )
    ).all()
    cleanups = []
    for job in jobs:
        if job.status != "ready":
            cleanups.append(
                VoiceJob(
                    user_id=user.id,
                    voice_id=voice.id,
                    kind="delete_prefix",
                    voice="u" + job.id.replace("-", "")[:9],
                )
            )
        job.status, job.sample, job.sample_token = "cancelled", None, None
    shared = (
        await session.exec(
            select(Voice.id).where(
                Voice.id != voice.id,
                Voice.deleted.is_(False),
                Voice.provider_voice == voice.provider_voice,
            )
        )
    ).first()
    if voice.provider_voice and not shared:
        cleanups.append(
            VoiceJob(user_id=user.id, voice_id=voice.id, kind="delete", voice=voice.provider_voice)
        )
    for cleanup in cleanups:
        session.add(cleanup)
    await session.commit()
    for cleanup in cleanups:
        context.voice_cloning.schedule(cleanup.id)
